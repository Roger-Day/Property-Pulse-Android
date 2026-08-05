import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../constants/app_colors.dart';
import '../../models/appointment_row.dart';
import '../../providers/auth_provider.dart';
import '../../repositories/user_profile_repository.dart';

/// Mirrors iOS `AppointmentManagementView` — lister/realtor view with
/// Pending / Upcoming / Past tabs and approve/reject controls.
class AppointmentManagementScreen extends StatefulWidget {
  const AppointmentManagementScreen({super.key, required this.userId});

  final String userId;

  @override
  State<AppointmentManagementScreen> createState() =>
      _AppointmentManagementScreenState();
}

enum _ApptTab { pending, upcoming, past }

class _AppointmentManagementScreenState
    extends State<AppointmentManagementScreen> {
  _ApptTab _tab = _ApptTab.pending;
  Future<List<AppointmentRow>>? _future;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    setState(() {
      _future = context
          .read<UserProfileRepository>()
          .getMyAppointments(widget.userId);
    });
  }

  List<AppointmentRow> _filterTab(
      List<AppointmentRow> all, _ApptTab tab) {
    switch (tab) {
      case _ApptTab.pending:
        // Expired-but-unactioned requests move to Past (mirrors iOS
        // `effectiveStatus`/isExpired — they can no longer be approved).
        return all
            .where((a) =>
                !a.isExpired &&
                (a.status.toLowerCase() == 'requested' ||
                    a.status.toLowerCase() == 'pending'))
            .toList();
      case _ApptTab.upcoming:
        return all.where((a) {
          final s = a.status.toLowerCase();
          return (s == 'approved' || s == 'confirmed') &&
              !a.isPast &&
              !a.isExpired;
        }).toList();
      case _ApptTab.past:
        return all.where((a) => a.isPast || a.isExpired).toList();
    }
  }

  // Status values must match iOS `AppointmentStatus` raw values exactly
  // ("Approved"/"Rejected", not lowercase) — a prior lowercase write here
  // would silently fail to decode on iOS.
  Future<void> _updateStatus(AppointmentRow appt, String status,
      {String? rejectionReason}) async {
    try {
      await context.read<UserProfileRepository>().updateAppointmentStatus(
            appointmentId: appt.id,
            status: status,
            rejectionReason: rejectionReason,
          );
      _refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(status == 'Approved'
                ? 'Appointment approved'
                : 'Appointment rejected')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _showRejectDialog(AppointmentRow appt) async {
    String reason = '';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject Appointment'),
        content: TextField(
          decoration: const InputDecoration(
              labelText: 'Reason (optional)',
              border: OutlineInputBorder()),
          onChanged: (v) => reason = v,
          maxLines: 2,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
                backgroundColor: Colors.red),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _updateStatus(appt, 'Rejected', rejectionReason: reason);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Appointment Management'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh appointments',
            onPressed: _refresh,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: SegmentedButton<_ApptTab>(
              segments: const [
                ButtonSegment(
                    value: _ApptTab.pending, label: Text('Pending')),
                ButtonSegment(
                    value: _ApptTab.upcoming, label: Text('Upcoming')),
                ButtonSegment(
                    value: _ApptTab.past, label: Text('Past')),
              ],
              selected: {_tab},
              onSelectionChanged: (s) =>
                  setState(() => _tab = s.first),
              style: const ButtonStyle(
                  visualDensity: VisualDensity.compact),
            ),
          ),
          const SizedBox(height: 4),
          const Divider(height: 1),
          Expanded(
            child: FutureBuilder<List<AppointmentRow>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Center(
                      child: CircularProgressIndicator());
                }
                final all = snap.data ?? [];
                final filtered = _filterTab(all, _tab);

                if (filtered.isEmpty) {
                  return _EmptyState(tab: _tab);
                }

                return RefreshIndicator(
                  onRefresh: () async => _refresh(),
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: 10),
                    itemBuilder: (ctx, i) {
                      final appt = filtered[i];
                      return _AppointmentManagementCard(
                        appointment: appt,
                        tab: _tab,
                        onApprove: _tab == _ApptTab.pending
                            ? () =>
                                _updateStatus(appt, 'Approved')
                            : null,
                        onReject: _tab == _ApptTab.pending
                            ? () => _showRejectDialog(appt)
                            : null,
                        onViewProperty: () =>
                            context.push('/property/${appt.propertyId}'),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.tab});
  final _ApptTab tab;

  @override
  Widget build(BuildContext context) {
    final (icon, msg) = switch (tab) {
      _ApptTab.pending => (
          Icons.pending_actions,
          'No pending appointment requests'
        ),
      _ApptTab.upcoming => (
          Icons.calendar_today,
          'No upcoming appointments'
        ),
      _ApptTab.past => (Icons.history, 'No past appointments'),
    };

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            Text(msg,
                style:
                    TextStyle(color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }
}

class _AppointmentManagementCard extends StatelessWidget {
  const _AppointmentManagementCard({
    required this.appointment,
    required this.tab,
    required this.onApprove,
    required this.onReject,
    required this.onViewProperty,
  });

  final AppointmentRow appointment;
  final _ApptTab tab;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;
  final VoidCallback onViewProperty;

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('EEE, MMM d · h:mm a');
    final statusColor = appointment.isExpired
        ? Colors.grey
        : switch (appointment.status.toLowerCase()) {
            'approved' || 'confirmed' => Colors.green,
            'rejected' || 'cancelled' || 'canceled' => Colors.red,
            'completed' => Colors.grey,
            _ => Colors.orange,
          };

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
                child: Text(
                  appointment.propertyTitle,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  appointment.displayStatus,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: statusColor),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (appointment.userName.isNotEmpty)
            _InfoRow(
                icon: Icons.person,
                label: 'Client: ${appointment.userName}'),
          _InfoRow(
              icon: Icons.access_time,
              label: fmt.format(appointment.date)),
          if (appointment.appointmentType.isNotEmpty)
            _InfoRow(
                icon: Icons.category_outlined,
                label: appointment.appointmentType),
          if (appointment.notes.isNotEmpty)
            _InfoRow(
                icon: Icons.notes,
                label: appointment.notes,
                maxLines: 2),
          const SizedBox(height: 8),
          Row(
            children: [
              TextButton(
                onPressed: onViewProperty,
                style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4)),
                child: const Text('View Property'),
              ),
              const Spacer(),
              if (onReject != null)
                TextButton(
                  onPressed: onReject,
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.red,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                  ),
                  child: const Text('Reject'),
                ),
              if (onApprove != null)
                const SizedBox(width: 6),
              if (onApprove != null)
                FilledButton(
                  onPressed: onApprove,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.green,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 6),
                    textStyle: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  child: const Text('Approve'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(
      {required this.icon, required this.label, this.maxLines = 1});
  final IconData icon;
  final String label;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: AppColors.textSecondary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                  fontSize: 13, color: AppColors.textSecondary),
              maxLines: maxLines,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
