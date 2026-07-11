import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../constants/app_colors.dart';
import '../../models/host_booking_row.dart';
import '../../repositories/user_profile_repository.dart';
import '../../services/guest_stays_privacy_store.dart';
import 'profile_subscreen_widgets.dart';

/// Guest bookings list — parity with iOS [GuestBookingsView].
class MyStaysScreen extends StatefulWidget {
  const MyStaysScreen({super.key, required this.userId});

  final String userId;

  @override
  State<MyStaysScreen> createState() => _MyStaysScreenState();
}

class _MyStaysScreenState extends State<MyStaysScreen> {
  Future<List<HostBookingRow>>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= _fetch();
  }

  Future<List<HostBookingRow>> _fetch() {
    return context.read<UserProfileRepository>().getMyStays(widget.userId);
  }

  Future<void> _onRefresh() async {
    setState(() {
      _future = _fetch();
    });
    await _future;
  }

  static String _money(HostBookingRow row) {
    final amt = row.totalAmount;
    if (amt == null) return '';
    final code = row.currencyCode ?? 'USD';
    try {
      return NumberFormat.simpleCurrency(name: code).format(amt);
    } catch (_) {
      return '$code ${amt.toStringAsFixed(2)}';
    }
  }

  static String _paymentLabel(String? raw) {
    switch ((raw ?? '').toLowerCase()) {
      case 'paid':
        return 'Paid';
      case 'unpaid':
      case 'requires_payment':
      case '':
        return 'Unpaid';
      case 'processing':
        return 'Processing';
      case 'failed':
        return 'Payment failed';
      default:
        final s = (raw ?? '').replaceAll('_', ' ');
        if (s.isEmpty) return 'Unpaid';
        return s.split(' ').map((w) {
          if (w.isEmpty) return w;
          return '${w[0].toUpperCase()}${w.length > 1 ? w.substring(1) : ''}';
        }).join(' ');
    }
  }

  static String _dateRangeMedium(HostBookingRow row) {
    final fmt = DateFormat.yMMMd();
    if (!row.hasDates) return 'Dates TBD';
    final a = fmt.format(row.checkIn!);
    final b = fmt.format(row.checkOut!);
    return '$a – $b';
  }

  Future<void> _openStay(HostBookingRow stay) async {
    await context.push('/profile/my-stays/detail', extra: stay);
    if (!mounted) return;
    setState(() => _future = _fetch());
  }

  Future<void> _confirmRemoveFromMyStays(HostBookingRow stay) async {
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
      bookingId: stay.id,
      guestId: widget.userId,
    );
    if (!mounted) return;
    setState(() => _future = _fetch());
  }

  @override
  Widget build(BuildContext context) {
    if (widget.userId.isEmpty) {
      return ProfileGroupedScaffold(
        title: 'My Stays',
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Sign in to see your stays.',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: AppColors.textSecondary,
                  ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return ProfileGroupedScaffold(
      title: 'My Stays',
      child: FutureBuilder<List<HostBookingRow>>(
        future: _future,
        builder: (context, snapshot) {
          final loadingFirst =
              snapshot.connectionState != ConnectionState.done &&
                  !snapshot.hasData;

          if (snapshot.hasError) {
            return ProfileErrorState(
              message: snapshot.error.toString(),
              onRetry: _onRefresh,
            );
          }

          final stays = snapshot.data ?? const [];

          if (loadingFirst) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 12),
                  Text(
                    'Loading…',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: _onRefresh,
            color: AppColors.primary,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                if (stays.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: ProfileEmptyState(
                      icon: Icons.luggage_outlined,
                      title: 'No stays found yet.',
                      subtitle:
                          'When you book a hosted stay, reservations appear here.',
                    ),
                  )
                else ...[
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    sliver: SliverToBoxAdapter(
                      child: Text(
                        '${stays.length} stay${stays.length == 1 ? '' : 's'}',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final stay = stays[index];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _GuestStayCard(
                              stay: stay,
                              dateLabel: _dateRangeMedium(stay),
                              amountLabel: _money(stay),
                              paymentLabel: _paymentLabel(stay.paymentStatus),
                              onTap: () => _openStay(stay),
                              onLongPress: () =>
                                  _confirmRemoveFromMyStays(stay),
                            ),
                          );
                        },
                        childCount: stays.length,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _GuestStayCard extends StatelessWidget {
  const _GuestStayCard({
    required this.stay,
    required this.dateLabel,
    required this.amountLabel,
    required this.paymentLabel,
    required this.onTap,
    required this.onLongPress,
  });

  final HostBookingRow stay;
  final String dateLabel;
  final String amountLabel;
  final String paymentLabel;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  Color _statusColor(BuildContext context) {
    final status = stay.statusLabel?.toLowerCase();
    switch (status) {
      case 'confirmed':
        return AppColors.success;
      case 'cancelled':
      case 'declined':
        return AppColors.error;
      case 'completed':
        return AppColors.primary;
      default:
        return AppColors.warning;
    }
  }

  @override
  Widget build(BuildContext context) {
    final chip = _statusColor(context);

    return Material(
      elevation: 2,
      shadowColor: Colors.black.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(14),
      color: Theme.of(context).colorScheme.surface,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _StayThumb(url: stay.propertyImageUrl),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          stay.headline,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          dateLabel,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: AppColors.textSecondary,
                                  ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: chip.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                stay.statusLabel ?? '—',
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(
                                      color: chip,
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                            ),
                            Text(
                              paymentLabel,
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(
                                    color: AppColors.textSecondary,
                                  ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (stay.propertyAddress?.trim().isNotEmpty == true) ...[
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.place_outlined,
                      size: 16,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        stay.propertyAddress!.trim(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
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
                  Expanded(
                    child: Text(
                      '${stay.numberOfNights} night${stay.numberOfNights == 1 ? '' : 's'} · '
                      '${stay.numberOfGuests ?? 1} guest${(stay.numberOfGuests ?? 1) == 1 ? '' : 's'}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                    ),
                  ),
                  if (amountLabel.isNotEmpty)
                    Text(
                      amountLabel,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StayThumb extends StatelessWidget {
  const _StayThumb({this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    const size = 72.0;
    if (url != null && url!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: CachedNetworkImage(
          imageUrl: url!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          placeholder: (_, __) => Container(
            width: size,
            height: size,
            color: AppColors.surfaceVariant,
            child: const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
          errorWidget: (_, __, ___) => _placeholder(size),
        ),
      );
    }
    return _placeholder(size);
  }

  Widget _placeholder(double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Icon(Icons.hotel, color: AppColors.textTertiary),
    );
  }
}
