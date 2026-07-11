import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../constants/app_colors.dart';

/// Mirrors iOS `HostCalendarView` — monthly calendar with booking overlay and
/// date-blocking functionality.
class HostCalendarScreen extends StatefulWidget {
  const HostCalendarScreen({super.key, required this.hostId});

  final String hostId;

  @override
  State<HostCalendarScreen> createState() => _HostCalendarScreenState();
}

class _HostCalendarScreenState extends State<HostCalendarScreen> {
  DateTime _focusedMonth = DateTime(
      DateTime.now().year, DateTime.now().month, 1);
  DateTime _selectedDay = DateTime.now();
  List<_CalendarBooking> _bookings = [];
  Set<String> _blockedDates = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _key(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final snap = await FirebaseFirestore.instance
          .collection('bookings')
          .where('hostId', isEqualTo: widget.hostId)
          .where('status', whereIn: ['confirmed', 'pending'])
          .get();

      final bookings = <_CalendarBooking>[];
      for (final doc in snap.docs) {
        final m = doc.data();
        final checkIn = (m['checkInDate'] as Timestamp?)?.toDate();
        final checkOut = (m['checkOutDate'] as Timestamp?)?.toDate();
        if (checkIn != null && checkOut != null) {
          bookings.add(_CalendarBooking(
            id: doc.id,
            propertyTitle: m['propertyTitle'] as String? ?? 'Property',
            guestName: m['guestName'] as String? ?? '—',
            checkIn: checkIn,
            checkOut: checkOut,
            status: m['status'] as String? ?? 'confirmed',
          ));
        }
      }

      final blockedSnap = await FirebaseFirestore.instance
          .collection('hostBlockedDates')
          .where('hostId', isEqualTo: widget.hostId)
          .get();
      final blocked = <String>{};
      for (final doc in blockedSnap.docs) {
        final date = doc.data()['date'] as String?;
        if (date != null) blocked.add(date);
      }

      if (!mounted) return;
      setState(() {
        _bookings = bookings;
        _blockedDates = blocked;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  bool _isBooked(DateTime day) => _bookings.any(
      (b) => !day.isBefore(b.checkIn) && day.isBefore(b.checkOut));

  bool _isBlocked(DateTime day) =>
      _blockedDates.contains(_key(day));

  List<_CalendarBooking> _bookingsOn(DateTime day) => _bookings
      .where((b) => !day.isBefore(b.checkIn) && day.isBefore(b.checkOut))
      .toList();

  Future<void> _toggleBlock(DateTime day) async {
    final k = _key(day);
    try {
      if (_isBlocked(day)) {
        final snap = await FirebaseFirestore.instance
            .collection('hostBlockedDates')
            .where('hostId', isEqualTo: widget.hostId)
            .where('date', isEqualTo: k)
            .get();
        for (final doc in snap.docs) {
          await doc.reference.delete();
        }
        if (!mounted) return;
        setState(() => _blockedDates.remove(k));
      } else {
        await FirebaseFirestore.instance
            .collection('hostBlockedDates')
            .add({'hostId': widget.hostId, 'date': k});
        if (!mounted) return;
        setState(() => _blockedDates.add(k));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedBookings = _bookingsOn(_selectedDay);
    final isSelectedBlocked = _isBlocked(_selectedDay);
    final isSelectedBooked = _isBooked(_selectedDay);
    final fmt = DateFormat.yMMMd();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Host Calendar'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                children: [
                  _MonthCalendar(
                    focusedMonth: _focusedMonth,
                    selectedDay: _selectedDay,
                    isBooked: _isBooked,
                    isBlocked: _isBlocked,
                    onDaySelected: (day) =>
                        setState(() => _selectedDay = day),
                    onMonthChanged: (month) =>
                        setState(() => _focusedMonth = month),
                  ),
                  // Legend
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        _LegendDot(
                            color: Colors.green.withOpacity(0.4),
                            label: 'Booked'),
                        const SizedBox(width: 16),
                        _LegendDot(
                            color: Colors.red.withOpacity(0.3),
                            label: 'Blocked'),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Reservations on ${fmt.format(_selectedDay)}',
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 12),
                        if (selectedBookings.isEmpty) ...[
                          Text(
                            isSelectedBlocked
                                ? 'This date is blocked from new reservations.'
                                : 'No reservations. This date is available.',
                            style: TextStyle(
                                color: AppColors.textSecondary),
                          ),
                          const SizedBox(height: 12),
                          if (!isSelectedBooked)
                            OutlinedButton.icon(
                              onPressed: () =>
                                  _toggleBlock(_selectedDay),
                              icon: Icon(isSelectedBlocked
                                  ? Icons.event_available
                                  : Icons.event_busy),
                              label: Text(isSelectedBlocked
                                  ? 'Unblock this date'
                                  : 'Block this date'),
                            ),
                        ] else
                          ...selectedBookings.map(
                            (b) => _BookingCard(
                                booking: b, fmt: fmt),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

// ─── Custom month calendar ────────────────────────────────────────────────────

class _MonthCalendar extends StatelessWidget {
  const _MonthCalendar({
    required this.focusedMonth,
    required this.selectedDay,
    required this.isBooked,
    required this.isBlocked,
    required this.onDaySelected,
    required this.onMonthChanged,
  });

  final DateTime focusedMonth;
  final DateTime selectedDay;
  final bool Function(DateTime) isBooked;
  final bool Function(DateTime) isBlocked;
  final void Function(DateTime) onDaySelected;
  final void Function(DateTime) onMonthChanged;

  List<DateTime?> _daysInGrid() {
    final first = DateTime(focusedMonth.year, focusedMonth.month, 1);
    final last = DateTime(focusedMonth.year, focusedMonth.month + 1, 0);
    final startOffset = first.weekday % 7; // Sunday=0
    final days = <DateTime?>[];
    for (int i = 0; i < startOffset; i++) {
      days.add(null);
    }
    for (int d = 1; d <= last.day; d++) {
      days.add(DateTime(focusedMonth.year, focusedMonth.month, d));
    }
    return days;
  }

  @override
  Widget build(BuildContext context) {
    final grid = _daysInGrid();
    final monthLabel =
        DateFormat('MMMM yyyy').format(focusedMonth);
    const dayLabels = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

    return Column(
      children: [
        // Month header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: () => onMonthChanged(DateTime(
                    focusedMonth.year, focusedMonth.month - 1, 1)),
              ),
              Expanded(
                child: Text(monthLabel,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: () => onMonthChanged(DateTime(
                    focusedMonth.year, focusedMonth.month + 1, 1)),
              ),
            ],
          ),
        ),
        // Day headers
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: dayLabels
                .map(
                  (d) => Expanded(
                    child: Text(d,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w600)),
                  ),
                )
                .toList(),
          ),
        ),
        const SizedBox(height: 4),
        // Day grid
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
            ),
            itemCount: grid.length,
            itemBuilder: (ctx, i) {
              final day = grid[i];
              if (day == null) return const SizedBox.shrink();
              final booked = isBooked(day);
              final blocked = isBlocked(day);
              final isSelected = day.year == selectedDay.year &&
                  day.month == selectedDay.month &&
                  day.day == selectedDay.day;
              final isToday = day.year == DateTime.now().year &&
                  day.month == DateTime.now().month &&
                  day.day == DateTime.now().day;

              Color? bgColor;
              if (isSelected) {
                bgColor = AppColors.primary;
              } else if (blocked) {
                bgColor = Colors.red.withOpacity(0.15);
              } else if (booked) {
                bgColor = Colors.green.withOpacity(0.2);
              } else if (isToday) {
                bgColor = AppColors.primary.withOpacity(0.15);
              }

              return GestureDetector(
                onTap: () => onDaySelected(day),
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: bgColor,
                  ),
                  child: Center(
                    child: Text(
                      '${day.day}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: isSelected || isToday
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: isSelected
                            ? Colors.white
                            : blocked
                                ? Colors.red
                                : booked
                                    ? Colors.green
                                    : null,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
                shape: BoxShape.circle, color: color)),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}

class _BookingCard extends StatelessWidget {
  const _BookingCard({required this.booking, required this.fmt});
  final _CalendarBooking booking;
  final DateFormat fmt;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 4),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(booking.propertyTitle,
              style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('Guest: ${booking.guestName}',
              style: TextStyle(
                  fontSize: 13, color: AppColors.textSecondary)),
          Text(
              '${fmt.format(booking.checkIn)} – ${fmt.format(booking.checkOut)}',
              style: TextStyle(
                  fontSize: 12, color: AppColors.textSecondary)),
          const SizedBox(height: 4),
          _StatusChip(status: booking.status),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final color = status == 'confirmed'
        ? Colors.green
        : status == 'pending'
            ? Colors.orange
            : AppColors.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        status[0].toUpperCase() + status.substring(1),
        style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: color),
      ),
    );
  }
}

class _CalendarBooking {
  const _CalendarBooking({
    required this.id,
    required this.propertyTitle,
    required this.guestName,
    required this.checkIn,
    required this.checkOut,
    required this.status,
  });
  final String id;
  final String propertyTitle;
  final String guestName;
  final DateTime checkIn;
  final DateTime checkOut;
  final String status;
}
