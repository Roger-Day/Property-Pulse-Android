import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../constants/app_colors.dart';
import '../../models/host_booking_row.dart';
import '../../models/user_profile_doc.dart';
import '../../providers/auth_provider.dart';
import '../../repositories/property_repository.dart';
import '../../repositories/user_profile_repository.dart';
import '../../services/analytics_service.dart';
import '../../utils/responsive.dart';

class HostDashboardScreen extends StatefulWidget {
  const HostDashboardScreen({super.key});

  @override
  State<HostDashboardScreen> createState() => _HostDashboardScreenState();
}

class _HostDashboardScreenState extends State<HostDashboardScreen> {
  int _refreshKey = 0;
  bool _actionBusy = false;

  // Firestore-backed name, same source home_screen.dart's greeting uses —
  // FirebaseAuth's own displayName is frequently unset (email/password
  // accounts) and was leaving "Welcome back, Host" instead of the real name.
  String? _profileFullName;
  // Also carried by this same subscription (one users/{uid} listener
  // instead of two) — drives the "Payouts not set up" banner.
  String? _profileStripeAccountId;
  bool _profileLoaded = false;
  StreamSubscription<UserProfileDoc?>? _profileSub;

  @override
  void initState() {
    super.initState();
    AnalyticsService.logDashboardView('host');
    _watchProfileName();
  }

  void _watchProfileName() {
    final uid = context.read<AuthProvider>().user?.uid;
    if (uid == null) return;
    _profileSub = context
        .read<UserProfileRepository>()
        .watchUserProfile(uid)
        .listen((doc) {
      if (!mounted) return;
      setState(() {
        _profileFullName = doc?.fullName;
        _profileStripeAccountId = doc?.stripeAccountId;
        _profileLoaded = true;
      });
    });
  }

  @override
  void dispose() {
    _profileSub?.cancel();
    super.dispose();
  }

  Future<void> _onRefresh() async {
    HapticFeedback.lightImpact();
    setState(() => _refreshKey++);
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final uid = auth.user?.uid;
    if (uid == null || uid.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Host Dashboard')),
        body: const Center(child: Text('Sign in to manage hosting.')),
      );
    }

    final repo = context.read<PropertyRepository>();
    final stripeAccountId = _profileStripeAccountId;

    return StreamBuilder<int>(
      stream: repo.watchHostListingsCount(uid),
      builder: (context, listingsSnap) {
        final totalListings = listingsSnap.data ?? 0;
        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            title: const Text('Host Dashboard'),
            backgroundColor: AppColors.surface,
            actions: [
              IconButton(
                onPressed: () => _showEarningsDialog(context),
                tooltip: 'Earnings',
                icon: const Icon(Icons.attach_money_rounded),
              ),
            ],
          ),
          body: StreamBuilder<List<Map<String, dynamic>>>(
            key: ValueKey(_refreshKey),
            stream: repo.watchHostBookings(uid),
            builder: (context, snap) {
              if (snap.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Could not load bookings.\n${snap.error}',
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final rows = snap.data!
                  .map((m) => HostBookingRow.fromDoc('${m['id']}', m))
                  .toList();
              final earnings = _sumEarnings(rows);
              var currency = 'USD';
              for (final r in rows) {
                final c = r.currencyCode?.trim();
                if (c != null && c.isNotEmpty) {
                  currency = c;
                  break;
                }
              }
              final upcoming = rows.where((r) {
                if (r.checkIn == null) return false;
                return !r.checkIn!.isBefore(
                  DateTime.now().subtract(const Duration(days: 1)),
                );
              }).toList()
                ..sort((a, b) => (a.checkIn ?? DateTime(0))
                    .compareTo(b.checkIn ?? DateTime(0)));
              final byDay = <String, List<HostBookingRow>>{};
              for (final r in upcoming) {
                final d = r.checkIn!;
                final key = DateFormat.yMMMEd().format(d);
                byDay.putIfAbsent(key, () => []).add(r);
              }
              final pendingCount =
                  rows.where((r) => r.statusLabel == 'Pending').length;
              final hostName = (_profileFullName?.trim().isNotEmpty ?? false)
                  ? _profileFullName!.trim()
                  : (auth.user?.displayName?.trim().isNotEmpty ?? false)
                      ? auth.user!.displayName!.trim()
                      : 'Host';

              return RefreshIndicator(
                onRefresh: _onRefresh,
                child: ListView(
                  padding: Responsive.hPadding(context, top: 20, bottom: 20),
                  children: [
                    Text(
                      'Host Dashboard',
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Welcome back, $hostName',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                    ),
                    if (_profileLoaded &&
                        (stripeAccountId == null ||
                            stripeAccountId.isEmpty)) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.warning_amber_rounded,
                              color: Colors.orange,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Payouts not set up',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(color: AppColors.textSecondary),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: 1.7,
                      children: [
                        _StatCard(
                          title: 'Total Listings',
                          value: '$totalListings',
                          icon: Icons.home_rounded,
                          tint: Colors.blue,
                        ),
                        _StatCard(
                          title: 'Upcoming Reservations',
                          value: '${upcoming.length}',
                          icon: Icons.calendar_month_rounded,
                          tint: Colors.green,
                        ),
                        _StatCard(
                          title: 'Pending Requests',
                          value: '$pendingCount',
                          icon: Icons.pending_actions_rounded,
                          tint: Colors.orange,
                        ),
                        _StatCard(
                          title: 'Total Earnings',
                          value: earnings == null
                              ? '—'
                              : NumberFormat.compactSimpleCurrency(
                                  name: currency,
                                ).format(earnings),
                          icon: Icons.paid_rounded,
                          tint: Colors.purple,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Quick Actions',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _HostQuickActionButton(
                            title: 'Add Property',
                            icon: Icons.add_rounded,
                            tint: Colors.blue,
                            onPressed: () =>
                                context.push('/profile/add-listing'),
                          ),
                        ),
                        Expanded(
                          child: _HostQuickActionButton(
                            title: 'Reservations',
                            icon: Icons.checklist_rounded,
                            tint: Colors.green,
                            onPressed: () => _showReservationsSheet(rows),
                          ),
                        ),
                        Expanded(
                          child: _HostQuickActionButton(
                            title: 'Calendar',
                            icon: Icons.calendar_today_rounded,
                            tint: Colors.orange,
                            onPressed: () => _showCalendarSheet(byDay),
                          ),
                        ),
                        Expanded(
                          child: _HostQuickActionButton(
                            title: 'Listings',
                            icon: Icons.home_work_outlined,
                            tint: Colors.purple,
                            onPressed: () =>
                                context.push('/profile/my-listings'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Recent Bookings',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 8),
                    if (rows.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Text(
                          'No recent bookings yet.',
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: AppColors.textSecondary),
                        ),
                      )
                    else
                      ...rows.take(10).map(
                            (b) => _BookingCard(
                              row: b,
                              busy: _actionBusy,
                              onAccept: () => _updateStatus(
                                bookingId: b.id,
                                status: 'confirmed',
                                success: 'Reservation accepted',
                              ),
                              onDecline: () => _updateStatus(
                                bookingId: b.id,
                                status: 'declined',
                                success: 'Reservation declined',
                              ),
                              onMessageGuest: () => _startGuestChat(b),
                            ),
                          ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  // Mirrors iOS `HostDashboardView.startGuestChat(for:)`: open the specific
  // guest conversation, not just the generic messages list.
  Future<void> _startGuestChat(HostBookingRow row) async {
    final guestId = row.guestId?.trim();
    if (guestId == null || guestId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Missing guest id for this booking.')),
      );
      return;
    }
    final uid = context.read<AuthProvider>().user?.uid;
    if (uid == null || uid.isEmpty) return;

    try {
      final threadId =
          await context.read<PropertyRepository>().ensureDirectConversation(
                currentUserId: uid,
                otherUserId: guestId,
              );
      if (!mounted) return;
      await context.push('/messages/thread/$threadId');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open chat: $e')),
      );
    }
  }

  Future<void> _updateStatus({
    required String bookingId,
    required String status,
    required String success,
  }) async {
    if (_actionBusy) return;
    setState(() => _actionBusy = true);
    try {
      await context
          .read<PropertyRepository>()
          .updateBookingStatus(bookingId, status);
      if (status == 'accepted') {
        unawaited(AnalyticsService.logBookingAccepted(bookingId));
      } else if (status == 'declined') {
        unawaited(AnalyticsService.logBookingDeclined(bookingId));
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(success)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update booking: $e')),
      );
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  Future<void> _showEarningsDialog(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Earnings'),
        content: const Text(
          'Total earnings are shown on the dashboard cards. Detailed payouts are coming soon.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _showReservationsSheet(List<HostBookingRow> rows) async {
    final pending = rows.where((e) => e.statusLabel == 'Pending').toList();
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Reservations',
              style: Theme.of(ctx)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            if (pending.isEmpty)
              const ListTile(title: Text('No pending reservations'))
            else
              ...pending.map((b) => _BookingTile(row: b)),
          ],
        ),
      ),
    );
  }

  Future<void> _showCalendarSheet(
      Map<String, List<HostBookingRow>> byDay) async {
    final dayKeys = byDay.keys.toList();
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Calendar',
              style: Theme.of(ctx)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            if (dayKeys.isEmpty)
              const ListTile(title: Text('No upcoming check-ins'))
            else
              ...dayKeys.map((day) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 10, bottom: 6),
                        child: Text(
                          day,
                          style: Theme.of(ctx).textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: AppColors.primary,
                              ),
                        ),
                      ),
                      ...byDay[day]!.map((b) => _BookingTile(row: b)),
                    ],
                  )),
          ],
        ),
      ),
    );
  }

  static double? _sumEarnings(List<HostBookingRow> rows) {
    double sum = 0;
    var any = false;
    for (final r in rows) {
      final s = (r.statusLabel ?? '').toLowerCase();
      if (s != 'confirmed' && s != 'completed') continue;
      final amt = r.totalAmount;
      if (amt == null || amt <= 0) continue;
      sum += amt;
      any = true;
    }
    return any ? sum : null;
  }
}

/// Mirrors iOS `DashboardStatCard` (HostReusableComponents.swift): borderless
/// white card with a drop shadow, snug top-aligned icon/value/title layout.
class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.tint,
  });

  final String title;
  final String value;
  final IconData icon;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: tint),
          const SizedBox(height: 10),
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 2),
          Text(
            title,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
        ],
      ),
    );
  }
}

/// Mirrors iOS `HostQuickActionButton`: a circular tinted icon with a
/// caption label below, not a rectangular outlined button.
class _HostQuickActionButton extends StatelessWidget {
  const _HostQuickActionButton({
    required this.title,
    required this.icon,
    required this.tint,
    required this.onPressed,
  });

  final String title;
  final IconData icon;
  final Color tint;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
              child: Icon(icon, color: Colors.white, size: 20),
            ),
            const SizedBox(height: 8),
            Text(
              title,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Status pill color — mirrors iOS `BookingCard.statusColor`.
Color _bookingStatusColor(String? label) {
  switch (label) {
    case 'Pending':
      return Colors.orange;
    case 'Confirmed':
      return Colors.green;
    case 'Cancelled':
    case 'Declined':
      return AppColors.error;
    case 'Completed':
      return Colors.blue;
    default:
      return AppColors.textSecondary;
  }
}

/// Mirrors iOS `hostPaymentStatusLabel`.
String _paymentStatusLabel(String? raw) {
  switch ((raw ?? '').toLowerCase()) {
    case 'paid':
      return 'Paid';
    case 'processing':
      return 'Processing';
    case 'failed':
      return 'Failed';
    case 'unpaid':
    case 'requires_payment':
    case '':
      return 'Unpaid';
    default:
      return raw!
          .replaceAll('_', ' ')
          .split(' ')
          .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
          .join(' ');
  }
}

/// Rich booking card matching iOS `BookingCard` (HostReusableComponents.swift):
/// property thumbnail, guest name + date range, a colored status pill (not
/// inline text), optional address, nights/guests + price row, payment-status
/// caption, and compact (not full-width) action buttons.
class _BookingCard extends StatelessWidget {
  const _BookingCard({
    required this.row,
    required this.busy,
    required this.onAccept,
    required this.onDecline,
    required this.onMessageGuest,
  });

  final HostBookingRow row;
  final bool busy;
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  final VoidCallback onMessageGuest;

  @override
  Widget build(BuildContext context) {
    final isPending = row.statusLabel == 'Pending';
    final statusColor = _bookingStatusColor(row.statusLabel);
    final dateText = row.hasDates
        ? '${DateFormat.yMMMd().format(row.checkIn!)} - ${DateFormat.yMMMd().format(row.checkOut!)}'
        : null;
    final nights = row.numberOfNights;
    final guests = row.numberOfGuests ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: (row.propertyImageUrl?.trim().isNotEmpty ?? false)
                    ? CachedNetworkImage(
                        imageUrl: row.propertyImageUrl!.trim(),
                        width: 72,
                        height: 72,
                        fit: BoxFit.cover,
                        errorWidget: (context, url, error) => _thumbFallback(),
                      )
                    : _thumbFallback(),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.headline,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Guest: ${row.guestName?.trim().isNotEmpty == true ? row.guestName!.trim() : '—'}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                    ),
                    if (dateText != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        dateText,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: AppColors.textSecondary,
                            ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  row.statusLabel ?? '—',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: statusColor,
                      ),
                ),
              ),
            ],
          ),
          if (row.propertyAddress?.trim().isNotEmpty ?? false) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.location_on_outlined,
                    size: 14, color: AppColors.textSecondary),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    row.propertyAddress!.trim(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                '$nights night${nights == 1 ? '' : 's'} · $guests guest${guests == 1 ? '' : 's'}',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
              const Spacer(),
              if (row.totalAmount != null)
                Text(
                  NumberFormat.simpleCurrency(name: row.currencyCode ?? 'USD')
                      .format(row.totalAmount),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            'Payment: ${_paymentStatusLabel(row.paymentStatus)}',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (isPending) ...[
                FilledButton(
                  onPressed: busy ? null : onAccept,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.green,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Accept Booking'),
                ),
                OutlinedButton(
                  onPressed: busy ? null : onDecline,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.error,
                    side: const BorderSide(color: AppColors.error),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Decline Booking'),
                ),
              ],
              OutlinedButton(
                onPressed: busy ? null : onMessageGuest,
                style: OutlinedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Message Guest'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _thumbFallback() {
    return Container(
      width: 72,
      height: 72,
      color: AppColors.surfaceVariant,
      child: const Icon(Icons.home_rounded, color: AppColors.textTertiary),
    );
  }
}

class _BookingTile extends StatelessWidget {
  const _BookingTile({required this.row});

  final HostBookingRow row;

  @override
  Widget build(BuildContext context) {
    final subtitle = StringBuffer();
    if (row.hasDates) {
      subtitle.write(
        '${DateFormat.MMMd().format(row.checkIn!)} – ${DateFormat.MMMd().format(row.checkOut!)}',
      );
    }
    if (row.numberOfGuests != null) {
      if (subtitle.isNotEmpty) subtitle.write(' · ');
      subtitle.write('${row.numberOfGuests} guests');
    }

    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(row.headline),
      subtitle: Text(
        '${row.statusLabel ?? '—'}${subtitle.isNotEmpty ? '\n$subtitle' : ''}',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      trailing: row.totalAmount != null
          ? Text(
              NumberFormat.compactSimpleCurrency(
                name: row.currencyCode ?? 'USD',
              ).format(row.totalAmount),
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            )
          : null,
      isThreeLine: subtitle.isNotEmpty,
      onTap: row.propertyId.isEmpty
          ? null
          : () => context.push('/property/${row.propertyId}'),
    );
  }
}
