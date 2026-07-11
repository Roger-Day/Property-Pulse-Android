import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../constants/app_colors.dart';
import '../../constants/app_constants.dart';
import '../../models/host_booking_row.dart';
import '../../providers/auth_provider.dart';
import '../../repositories/property_repository.dart';
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

  @override
  void initState() {
    super.initState();
    AnalyticsService.logDashboardView('host');
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

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection(AppConstants.usersCollection)
          .doc(uid)
          .snapshots(),
      builder: (context, userSnap) {
        final stripeAccountId = userSnap.data?.data()?['stripeAccountId'] as String?;
        return StreamBuilder<int>(
          stream: _watchHostListingsCount(uid),
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
                  final hostName =
                      (auth.user?.displayName?.trim().isNotEmpty ?? false)
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
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: AppColors.textSecondary,
                                  ),
                        ),
                        if (userSnap.hasData &&
                            (stripeAccountId == null || stripeAccountId.isEmpty)) ...[
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
                          childAspectRatio: 1.9,
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
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                        const SizedBox(height: 8),
                        GridView.count(
                          crossAxisCount: Responsive.gridColumns(
                            context,
                            phone: 2,
                            tablet: 4,
                            desktop: 4,
                          ),
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          mainAxisSpacing: 10,
                          crossAxisSpacing: 10,
                          childAspectRatio: Responsive.isWide(context) ? 2.2 : 2.6,
                          children: [
                            _QuickActionButton(
                              title: 'Add Property',
                              icon: Icons.add_home_outlined,
                              tint: Colors.blue,
                              onPressed: () => context.push('/profile/add-listing'),
                            ),
                            _QuickActionButton(
                              title: 'Reservations',
                              icon: Icons.checklist_rounded,
                              tint: Colors.green,
                              onPressed: () => _showReservationsSheet(rows),
                            ),
                            _QuickActionButton(
                              title: 'Calendar',
                              icon: Icons.calendar_today_rounded,
                              tint: Colors.orange,
                              onPressed: () => _showCalendarSheet(byDay),
                            ),
                            _QuickActionButton(
                              title: 'Listings',
                              icon: Icons.home_work_outlined,
                              tint: Colors.purple,
                              onPressed: () => context.push('/profile/my-listings'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'Recent Bookings',
                          style:
                              Theme.of(context).textTheme.titleLarge?.copyWith(
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
                                  onMessageGuest: () => context.go('/messages'),
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
      },
    );
  }

  Future<void> _updateStatus({
    required String bookingId,
    required String status,
    required String success,
  }) async {
    if (_actionBusy) return;
    setState(() => _actionBusy = true);
    try {
      await context.read<PropertyRepository>().updateBookingStatus(bookingId, status);
      if (status == 'accepted') {
        unawaited(AnalyticsService.logBookingAccepted(bookingId));
      } else if (status == 'declined') {
        unawaited(AnalyticsService.logBookingDeclined(bookingId));
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(success)));
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
              style:
                  Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
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

  Future<void> _showCalendarSheet(Map<String, List<HostBookingRow>> byDay) async {
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
              style:
                  Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
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

  Stream<int> _watchHostListingsCount(String uid) {
    final controller = StreamController<int>.broadcast();
    final latest = <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
    final subs = <StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>[];

    void emit() {
      final byId = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
      for (final docs in latest.values) {
        for (final d in docs) {
          byId[d.id] = d;
        }
      }
      final count = byId.values
          .where((d) => (d.data()['deleted'] as bool?) != true)
          .length;
      controller.add(count);
    }

    void attach(String key, Query<Map<String, dynamic>> q) {
      final sub = q.snapshots().listen(
        (snap) {
          latest[key] = snap.docs;
          emit();
        },
        onError: (_) {
          latest[key] = const [];
          emit();
        },
      );
      subs.add(sub);
    }

    final col = FirebaseFirestore.instance.collection(AppConstants.propertiesCollection);
    attach('hostId', col.where('hostId', isEqualTo: uid).limit(120));
    attach('realtorId', col.where('realtorId', isEqualTo: uid).limit(120));
    attach('ownerId', col.where('ownerId', isEqualTo: uid).limit(120));

    controller.onCancel = () async {
      for (final s in subs) {
        await s.cancel();
      }
    };
    return controller.stream;
  }
}

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
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: tint),
          const Spacer(),
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

class _QuickActionButton extends StatelessWidget {
  const _QuickActionButton({
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
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(46),
        side: BorderSide.none,
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 16, color: tint),
          const SizedBox(width: 6),
          Flexible(child: Text(title, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }
}

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
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _BookingTile(row: row),
            const SizedBox(height: 8),
            Row(
              children: [
                if (isPending) ...[
                  Expanded(
                    child: FilledButton(
                      onPressed: busy ? null : onAccept,
                      child: const Text('Accept'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: busy ? null : onDecline,
                      child: const Text('Decline'),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onMessageGuest,
                    icon: const Icon(Icons.chat_bubble_outline, size: 16),
                    label: const Text('Message'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
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
      onTap: row.propertyId.isEmpty ? null : () => context.push('/property/${row.propertyId}'),
    );
  }
}
