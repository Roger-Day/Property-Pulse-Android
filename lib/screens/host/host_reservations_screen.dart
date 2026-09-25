import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../constants/app_colors.dart';
import 'cancellation_flow_screen.dart';
import 'dispute_flow_screen.dart';

/// Mirrors iOS `ReservationsManagementView` — full reservation lifecycle view.
class HostReservationsScreen extends StatefulWidget {
  const HostReservationsScreen({super.key, required this.hostId});

  final String hostId;

  @override
  State<HostReservationsScreen> createState() =>
      _HostReservationsScreenState();
}

enum _ReservationTab { upcoming, active, completed, cancelled }

class _HostReservationsScreenState extends State<HostReservationsScreen> {
  _ReservationTab _tab = _ReservationTab.upcoming;
  Future<List<_Reservation>>? _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<_Reservation>> _load() async {
    final snap = await FirebaseFirestore.instance
        .collection('bookings')
        .where('hostId', isEqualTo: widget.hostId)
        .orderBy('checkInDate', descending: false)
        .get();

    return snap.docs.map((doc) {
      final m = doc.data();
      return _Reservation(
        id: doc.id,
        propertyTitle: m['propertyTitle'] as String? ?? 'Property',
        guestName: m['guestName'] as String? ?? '—',
        guestId: m['guestId'] as String? ?? '',
        checkIn: (m['checkInDate'] as Timestamp?)?.toDate(),
        checkOut: (m['checkOutDate'] as Timestamp?)?.toDate(),
        status: m['status'] as String? ?? 'pending',
        totalPrice: (m['totalPrice'] as num?)?.toDouble() ?? 0,
        nightsCount: (m['nightsCount'] as num?)?.toInt() ?? 1,
        cancellationPolicyId: m['cancellationPolicyId'] as String?,
      );
    }).toList();
  }

  List<_Reservation> _filtered(List<_Reservation> all) {
    final now = DateTime.now();
    switch (_tab) {
      case _ReservationTab.upcoming:
        return all.where((r) {
          if (r.checkIn == null) return false;
          return r.checkIn!.isAfter(now) &&
              (r.status == 'confirmed' || r.status == 'pending');
        }).toList();
      case _ReservationTab.active:
        return all.where((r) {
          if (r.checkIn == null || r.checkOut == null) return false;
          return !r.checkIn!.isAfter(now) &&
              r.checkOut!.isAfter(now) &&
              r.status == 'confirmed';
        }).toList();
      case _ReservationTab.completed:
        return all.where((r) => r.status == 'completed').toList();
      case _ReservationTab.cancelled:
        // cancelBooking (Cloud Function) writes the more specific
        // cancelled_by_guest/cancelled_by_host/cancelled_by_admin rather
        // than a bare 'cancelled' — those matched none of this screen's
        // four tab filters, so a cancelled reservation just vanished from
        // the host's Reservations screen entirely.
        return all
            .where((r) => r.status == 'cancelled' ||
                r.status.startsWith('cancelled_by_'))
            .toList();
    }
  }

  Future<void> _approve(String id) async {
    await FirebaseFirestore.instance
        .collection('bookings')
        .doc(id)
        .update({'status': 'confirmed'});
    setState(() => _future = _load());
  }

  Future<void> _decline(String id) async {
    await FirebaseFirestore.instance
        .collection('bookings')
        .doc(id)
        .update({'status': 'cancelled'});
    setState(() => _future = _load());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reservations')),
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: _ReservationTab.values.map((t) {
                final selected = _tab == t;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(_tabLabel(t)),
                    selected: selected,
                    onSelected: (_) => setState(() => _tab = t),
                    selectedColor: AppColors.primary.withOpacity(0.15),
                    checkmarkColor: AppColors.primary,
                    labelStyle: TextStyle(
                        color: selected
                            ? AppColors.primary
                            : AppColors.textSecondary,
                        fontWeight: selected
                            ? FontWeight.bold
                            : FontWeight.normal),
                  ),
                );
              }).toList(),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: FutureBuilder<List<_Reservation>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.cloud_off_outlined,
                            size: 48, color: Colors.grey),
                        const SizedBox(height: 12),
                        Text(
                          'Could not load reservations',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton(
                          onPressed: () =>
                              setState(() => _future = _load()),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  );
                }
                final all = snap.data ?? [];
                final filtered = _filtered(all);
                if (filtered.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.calendar_today,
                            size: 48, color: Colors.grey),
                        const SizedBox(height: 12),
                        Text(
                          'No ${_tabLabel(_tab).toLowerCase()} reservations',
                          style: TextStyle(
                              color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async =>
                      setState(() => _future = _load()),
                  child: ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: 8),
                    itemBuilder: (ctx, i) =>
                        _ReservationCard(
                      reservation: filtered[i],
                      onApprove: filtered[i].status == 'pending'
                          ? () => _approve(filtered[i].id)
                          : null,
                      onDecline: filtered[i].status == 'pending'
                          ? () => _decline(filtered[i].id)
                          : null,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _tabLabel(_ReservationTab t) {
    switch (t) {
      case _ReservationTab.upcoming:
        return 'Upcoming';
      case _ReservationTab.active:
        return 'Active';
      case _ReservationTab.completed:
        return 'Completed';
      case _ReservationTab.cancelled:
        return 'Cancelled';
    }
  }
}

class _ReservationCard extends StatelessWidget {
  const _ReservationCard({
    required this.reservation,
    required this.onApprove,
    required this.onDecline,
  });
  final _Reservation reservation;
  final VoidCallback? onApprove;
  final VoidCallback? onDecline;

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat.yMMMd();
    final statusColor = reservation.status == 'confirmed'
        ? Colors.green
        : reservation.status == 'pending'
            ? Colors.orange
            : reservation.status == 'completed'
                ? Colors.blue
                : Colors.red;

    return Container(
      padding: const EdgeInsets.all(14),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(reservation.propertyTitle,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  _capitalise(reservation.status),
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: statusColor),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text('Guest: ${reservation.guestName}',
              style: TextStyle(
                  fontSize: 13, color: AppColors.textSecondary)),
          if (reservation.checkIn != null && reservation.checkOut != null)
            Text(
              '${fmt.format(reservation.checkIn!)} – ${fmt.format(reservation.checkOut!)} (${reservation.nightsCount} nights)',
              style: TextStyle(
                  fontSize: 12, color: AppColors.textSecondary),
            ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(
                '\$${reservation.totalPrice.toStringAsFixed(0)}',
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 15),
              ),
              const Spacer(),
              if (onApprove != null || onDecline != null) ...[
                if (onDecline != null)
                  TextButton(
                    onPressed: onDecline,
                    style: TextButton.styleFrom(
                        foregroundColor: Colors.red,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6)),
                    child: const Text('Decline'),
                  ),
                if (onApprove != null)
                  FilledButton(
                    onPressed: onApprove,
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.green,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                    ),
                    child: const Text('Approve'),
                  ),
              ],
              // Cancel / Dispute for confirmed bookings
              if (reservation.status == 'confirmed') ...[
                TextButton(
                  onPressed: () => showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    useSafeArea: true,
                    builder: (_) => CancellationFlowScreen(
                      bookingId: reservation.id,
                      propertyTitle: reservation.propertyTitle,
                      guestName: reservation.guestName,
                      totalPrice: reservation.totalPrice,
                      checkIn: reservation.checkIn,
                      cancellationPolicyId: reservation.cancellationPolicyId,
                      role: 'host',
                    ),
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.red,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                  ),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    useSafeArea: true,
                    builder: (_) => DisputeFlowScreen(
                      bookingId: reservation.id,
                      propertyTitle: reservation.propertyTitle,
                    ),
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.orange,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                  ),
                  child: const Text('Dispute'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  String _capitalise(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

class _Reservation {
  const _Reservation({
    required this.id,
    required this.propertyTitle,
    required this.guestName,
    required this.guestId,
    required this.checkIn,
    required this.checkOut,
    required this.status,
    required this.totalPrice,
    required this.nightsCount,
    this.cancellationPolicyId,
  });
  final String id;
  final String propertyTitle;
  final String guestName;
  final String guestId;
  final DateTime? checkIn;
  final DateTime? checkOut;
  final String status;
  final double totalPrice;
  final int nightsCount;
  final String? cancellationPolicyId;
}
