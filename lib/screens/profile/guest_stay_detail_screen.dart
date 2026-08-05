import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../constants/app_colors.dart';
import '../../models/host_booking_row.dart';
import '../../models/property_model.dart';
import '../../providers/auth_provider.dart';
import '../../repositories/property_repository.dart';
import '../../services/guest_stays_privacy_store.dart';
import '../../services/stripe_service.dart';
import '../host/cancellation_flow_screen.dart';

/// Guest stay details — parity with iOS [GuestStayDetailView].
class GuestStayDetailScreen extends StatefulWidget {
  const GuestStayDetailScreen({super.key, required this.booking});

  final HostBookingRow booking;

  @override
  State<GuestStayDetailScreen> createState() => _GuestStayDetailScreenState();
}

class _GuestStayDetailScreenState extends State<GuestStayDetailScreen> {
  late HostBookingRow _live;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;

  String? _resolvedAddress;
  bool _loadingAddress = false;
  bool _paying = false;
  String? _paymentMessage;

  static final _mediumFmt = DateFormat.yMMMd();

  @override
  void initState() {
    super.initState();
    _live = widget.booking;
    _listenBooking();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _bootstrapAddress();
    });
  }

  void _listenBooking() {
    final path = _live.firestoreCollection.collectionId;
    _sub = FirebaseFirestore.instance
        .collection(path)
        .doc(_live.id)
        .snapshots()
        .listen((snap) {
      if (!snap.exists || !mounted) return;
      final next = HostBookingRow.fromDoc(
        snap.id,
        snap.data()!,
        firestoreCollection: _live.firestoreCollection,
      );
      setState(() => _live = next);
    });
  }

  Future<void> _bootstrapAddress() async {
    final snap = widget.booking.propertyAddress?.trim();
    if (snap != null && snap.isNotEmpty) {
      setState(() => _resolvedAddress = snap);
      return;
    }
    final pid = widget.booking.propertyId.trim();
    if (pid.isEmpty) return;

    setState(() => _loadingAddress = true);
    try {
      final repo = context.read<PropertyRepository>();
      final p = await repo.fetchPropertyById(pid);
      if (!mounted) return;
      final addr = p?.fullAddress.trim();
      if (addr != null && addr.isNotEmpty) {
        setState(() => _resolvedAddress = addr);
      }
    } finally {
      if (mounted) setState(() => _loadingAddress = false);
    }
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    super.dispose();
  }

  String _formatMoney(HostBookingRow row) {
    final amt = row.totalAmount;
    if (amt == null) return '';
    final code = row.currencyCode ?? 'USD';
    try {
      return NumberFormat.simpleCurrency(name: code).format(amt);
    } catch (_) {
      return '$code ${amt.toStringAsFixed(2)}';
    }
  }

  Future<void> _messageHost(BuildContext context) async {
    final hostId = _live.hostId?.trim() ?? '';
    if (hostId.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Missing host id for this booking.')),
      );
      return;
    }
    final auth = context.read<AuthProvider>();
    final repo = context.read<PropertyRepository>();
    final uid = auth.user?.uid;
    if (uid == null) return;

    try {
      final prop =
          await repo.fetchPropertyById(_live.propertyId.trim()) ??
              _minimalProperty();
      final threadId = await repo.ensureConversationForProperty(
        currentUserId: uid,
        property: prop,
      );
      if (!mounted || !context.mounted) return;
      await context.push('/messages/thread/$threadId');
    } catch (e) {
      if (!mounted || !context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open chat: $e')),
      );
    }
  }

  /// Minimal listing shell when Firestore no longer has the property doc.
  PropertyModel _minimalProperty() {
    final id = _live.propertyId.trim().isEmpty ? 'unknown' : _live.propertyId.trim();
    return PropertyModel(
      id: id,
      title: _live.headline,
      description: '',
      price: 0,
      currencyCode: _live.currencyCode ?? 'USD',
      street: '',
      city: '',
      state: '',
      zipCode: '',
      bedrooms: 0,
      bathrooms: 0,
      squareFootage: 0,
      deleted: false,
      heroImageUrl: _live.propertyImageUrl,
      imageUrls: const [],
      features: const [],
      propertyType: '',
      realtorName: null,
      realtorEmail: null,
      realtorPhone: null,
      hostUserId: _live.hostId,
    );
  }

  Future<void> _payNow(BuildContext context) async {
    if (_paying) return;
    final stripe = context.read<StripeService>();
    setState(() {
      _paying = true;
      _paymentMessage = null;
    });
    try {
      // Bookings now live in `host_bookings` (iOS-parity schema) — the
      // Cloud Function resolves the id there directly.
      await stripe.presentConfirmedBookingPaymentSheet(bookingId: _live.id);
      if (!mounted) return;
      setState(() {
        _paymentMessage =
            'Payment submitted. Final status will update shortly.';
      });
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString();
      setState(() {
        _paymentMessage =
            msg.contains('canceled') || msg.contains('cancel')
                ? 'Payment canceled.'
                : 'Payment failed: $msg';
      });
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  Future<void> _openCancelFlow(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => CancellationFlowScreen(
        bookingId: _live.id,
        propertyTitle: _live.headline,
        totalPrice: _live.totalAmount ?? 0,
        checkIn: _live.checkIn,
        cancellationPolicyId: _live.cancellationPolicyId,
        role: 'guest',
        onDismiss: () => Navigator.of(context).maybePop(),
      ),
    );
    // The booking-detail listener (`_listenBooking`) picks up the status
    // change in real time, so no manual refresh is needed here.
  }

  Future<void> _confirmRemoveFromMyStays(BuildContext context) async {
    final uid = context.read<AuthProvider>().user?.uid ?? '';
    if (uid.isEmpty) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove from My Stays?'),
        content: const Text(
          'This hides the stay on this device only. It does not cancel a '
          'reservation or remove the booking for the host.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              foregroundColor: Colors.white,
              backgroundColor: AppColors.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    await GuestStaysPrivacyStore.hideBooking(
      bookingId: _live.id,
      guestId: uid,
    );
    if (!mounted || !context.mounted) return;
    context.pop(true);
  }

  Widget _paymentSection(BuildContext context, HostBookingRow row) {
    final ps = (row.paymentStatus ?? '').toLowerCase();

    if (!_live.isConfirmedStay) {
      return const SizedBox.shrink();
    }

    if (_paying) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Text('Processing…'),
          ],
        ),
      );
    }

    switch (ps) {
      case 'requires_payment':
      case 'unpaid':
      case '':
        return FilledButton.icon(
          onPressed: () => _payNow(context),
          icon: const Icon(Icons.credit_card_rounded),
          label: const Text('Pay Now'),
        );
      case 'processing':
        return OutlinedButton.icon(
          onPressed: null,
          icon: const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          label: const Text('Processing…'),
        );
      case 'paid':
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: AppColors.success),
              const SizedBox(width: 10),
              Text(
                'Payment received',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
            ],
          ),
        );
      case 'failed':
        return OutlinedButton.icon(
          onPressed: () => _payNow(context),
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Retry payment'),
        );
      default:
        return Text(
          'Payment status: ${row.paymentStatus}',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final row = _live;
    final hero = MediaQuery.sizeOf(context).width - 40;
    final targetW = hero < 320 ? 320.0 : hero;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Stay details'),
        backgroundColor: AppColors.surface,
        actions: [
          IconButton(
            tooltip: 'Remove from My Stays',
            icon: const Icon(Icons.visibility_off_rounded),
            onPressed: () => _confirmRemoveFromMyStays(context),
          ),
          if (row.propertyId.trim().isNotEmpty)
            IconButton(
              tooltip: 'Open listing',
              icon: const Icon(Icons.open_in_new_rounded),
              onPressed: () =>
                  context.push('/property/${row.propertyId.trim()}'),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SizedBox(
                height: 200,
                width: double.infinity,
                child: _HeroImage(url: row.propertyImageUrl, widthHint: targetW),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              row.headline,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              row.statusLabel ?? '—',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const Divider(height: 28),
            Text(
              'Check-in',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              row.hasDates ? _mediumFmt.format(row.checkIn!) : '—',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 14),
            Text(
              'Check-out',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              row.hasDates ? _mediumFmt.format(row.checkOut!) : '—',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
            Text(
              '${row.numberOfNights} night${row.numberOfNights == 1 ? '' : 's'} · '
              '${row.numberOfGuests ?? 1} guest${(row.numberOfGuests ?? 1) == 1 ? '' : 's'} · '
              '${_formatMoney(row)} total',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
            const SizedBox(height: 16),
            if (_loadingAddress)
              Row(
                children: [
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Loading address…',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                  ),
                ],
              )
            else if (_resolvedAddress != null &&
                _resolvedAddress!.trim().isNotEmpty) ...[
              Text(
                'Address',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
              const SizedBox(height: 6),
              Text(_resolvedAddress!, style: Theme.of(context).textTheme.bodyLarge),
            ],
            const Divider(height: 28),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => _messageHost(context),
                icon: const Icon(Icons.message_rounded),
                label: const Text('Message Host'),
              ),
            ),
            if (row.canGuestCancelReservation) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.error,
                  ),
                  onPressed: () => _openCancelFlow(context),
                  child: const Text('Cancel reservation'),
                ),
              ),
            ],
            if (_live.isConfirmedStay) ...[
              const SizedBox(height: 12),
              _paymentSection(context, row),
            ],
            if (_paymentMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                _paymentMessage!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
            ],
            const SizedBox(height: 24),
            Text(
              'Booking ID',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
            const SizedBox(height: 4),
            SelectableText(
              row.id,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroImage extends StatelessWidget {
  const _HeroImage({this.url, required this.widthHint});

  final String? url;
  final double widthHint;

  @override
  Widget build(BuildContext context) {
    final u = url?.trim();
    if (u != null && u.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: u,
        width: widthHint,
        height: 200,
        fit: BoxFit.cover,
        placeholder: (_, __) => Container(
          color: AppColors.surfaceVariant,
          alignment: Alignment.center,
          child: const CircularProgressIndicator(strokeWidth: 2),
        ),
        errorWidget: (_, __, ___) =>
            Container(color: AppColors.surfaceVariant, child: _fallback()),
      );
    }
    return Container(
      color: AppColors.surfaceVariant,
      child: _fallback(),
    );
  }

  Widget _fallback() {
    return const Center(
      child: Icon(Icons.hotel_rounded, size: 48, color: AppColors.textTertiary),
    );
  }
}
