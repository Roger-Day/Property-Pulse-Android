import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../constants/app_colors.dart';

/// Mirrors iOS `HostEarningsView` — earnings dashboard with total, monthly, and payout data.
class HostEarningsScreen extends StatefulWidget {
  const HostEarningsScreen({super.key, required this.hostId});

  final String hostId;

  @override
  State<HostEarningsScreen> createState() => _HostEarningsScreenState();
}

class _HostEarningsScreenState extends State<HostEarningsScreen> {
  Future<_EarningsData>? _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_EarningsData> _load() async {
    try {
      // Completed bookings for this host
      final snap = await FirebaseFirestore.instance
          .collection('bookings')
          .where('hostId', isEqualTo: widget.hostId)
          .where('status', isEqualTo: 'completed')
          .orderBy('checkOutDate', descending: true)
          .get();

      double total = 0;
      double thisMonth = 0;
      final bookings = <_BookingEarning>[];
      final now = DateTime.now();

      for (final doc in snap.docs) {
        final m = doc.data();
        final amount = (m['earningsAmount'] as num?)?.toDouble() ??
            (m['totalPrice'] as num?)?.toDouble() ??
            0.0;
        total += amount;
        final checkOut = (m['checkOutDate'] as Timestamp?)?.toDate();
        if (checkOut != null &&
            checkOut.year == now.year &&
            checkOut.month == now.month) {
          thisMonth += amount;
        }
        bookings.add(_BookingEarning(
          propertyTitle: m['propertyTitle'] as String? ?? 'Property',
          guestName: m['guestName'] as String? ?? '—',
          checkIn: (m['checkInDate'] as Timestamp?)?.toDate(),
          checkOut: checkOut,
          amount: amount,
        ));
      }

      // Upcoming payout (simplified: next 30-day rolling total of confirmed bookings)
      final upcomingSnap = await FirebaseFirestore.instance
          .collection('bookings')
          .where('hostId', isEqualTo: widget.hostId)
          .where('status', isEqualTo: 'confirmed')
          .get();
      double upcoming = 0;
      final upcoming7Days = now.add(const Duration(days: 7));
      for (final doc in upcomingSnap.docs) {
        final m = doc.data();
        final checkOut = (m['checkOutDate'] as Timestamp?)?.toDate();
        if (checkOut != null && checkOut.isBefore(upcoming7Days)) {
          upcoming +=
              (m['earningsAmount'] as num?)?.toDouble() ?? 0.0;
        }
      }

      return _EarningsData(
        totalEarnings: total,
        thisMonth: thisMonth,
        upcomingPayout: upcoming,
        completedBookings: bookings,
      );
    } catch (_) {
      return const _EarningsData(
          totalEarnings: 0,
          thisMonth: 0,
          upcomingPayout: 0,
          completedBookings: []);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Earnings')),
      body: FutureBuilder<_EarningsData>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snap.data ??
              const _EarningsData(
                  totalEarnings: 0,
                  thisMonth: 0,
                  upcomingPayout: 0,
                  completedBookings: []);
          return RefreshIndicator(
            onRefresh: () async {
              setState(() => _future = _load());
            },
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _StatCard(
                  title: 'Total Earnings',
                  value: _fmt(data.totalEarnings),
                  icon: Icons.monetization_on,
                  color: Colors.green,
                ),
                const SizedBox(height: 12),
                _StatCard(
                  title: 'Earnings This Month',
                  value: _fmt(data.thisMonth),
                  icon: Icons.calendar_month,
                  color: Colors.blue,
                ),
                const SizedBox(height: 12),
                _StatCard(
                  title: 'Upcoming Payouts',
                  value: _fmt(data.upcomingPayout),
                  icon: Icons.credit_card,
                  color: Colors.purple,
                ),
                const SizedBox(height: 20),
                if (data.completedBookings.isNotEmpty) ...[
                  const Text('Completed Bookings',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  ...data.completedBookings.map(
                    (b) => _BookingEarningTile(booking: b),
                  ),
                ] else
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        children: [
                          const Icon(Icons.receipt_long,
                              size: 48, color: Colors.grey),
                          const SizedBox(height: 12),
                          Text(
                            'No completed bookings yet',
                            style: TextStyle(
                                color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  static String _fmt(double v) =>
      NumberFormat.currency(symbol: '\$', decimalDigits: 0).format(v);
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: TextStyle(
                      fontSize: 13, color: AppColors.textSecondary)),
              Text(value,
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }
}

class _BookingEarningTile extends StatelessWidget {
  const _BookingEarningTile({required this.booking});
  final _BookingEarning booking;

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat.yMMMd();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(booking.propertyTitle,
                    style:
                        const TextStyle(fontWeight: FontWeight.w600)),
                if (booking.checkIn != null && booking.checkOut != null)
                  Text(
                    '${fmt.format(booking.checkIn!)} – ${fmt.format(booking.checkOut!)}',
                    style: TextStyle(
                        fontSize: 12, color: AppColors.textSecondary),
                  ),
              ],
            ),
          ),
          Text(
            NumberFormat.currency(symbol: '\$', decimalDigits: 0)
                .format(booking.amount),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

class _EarningsData {
  const _EarningsData({
    required this.totalEarnings,
    required this.thisMonth,
    required this.upcomingPayout,
    required this.completedBookings,
  });
  final double totalEarnings;
  final double thisMonth;
  final double upcomingPayout;
  final List<_BookingEarning> completedBookings;
}

class _BookingEarning {
  const _BookingEarning({
    required this.propertyTitle,
    required this.guestName,
    required this.checkIn,
    required this.checkOut,
    required this.amount,
  });
  final String propertyTitle;
  final String guestName;
  final DateTime? checkIn;
  final DateTime? checkOut;
  final double amount;
}
