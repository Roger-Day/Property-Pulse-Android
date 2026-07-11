import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../constants/app_colors.dart';
import '../../models/appointment_row.dart';
import '../../models/user_profile_doc.dart';
import '../../providers/auth_provider.dart';
import '../../repositories/property_repository.dart';
import '../../repositories/user_profile_repository.dart';
import 'appointment_management_screen.dart';
import 'profile_subscreen_widgets.dart';

/// Entry point for `/profile/appointments` — mirrors iOS `MainTabView`'s
/// role switch (realtors/owners/admins get `AppointmentManagementView`,
/// everyone else gets `SeekerAppointmentsView`), just triggered from the
/// Profile menu instead of a bottom tab since Android has no Appointments tab.
class AppointmentsRoleRouter extends StatelessWidget {
  const AppointmentsRoleRouter({
    super.key,
    required this.userId,
    this.initialAppointmentId,
  });

  final String userId;

  /// Set when reached via the `propertypulse://appointment/{id}` deep link
  /// (or an "appointment"-typed push) — opens that appointment's detail
  /// page as soon as the list loads.
  final String? initialAppointmentId;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<UserProfileDoc?>(
      stream: context.read<UserProfileRepository>().watchUserProfile(userId),
      builder: (context, snap) {
        final doc = snap.data;
        final isRealtorOrOwner =
            (doc?.isRealtor ?? false) || (doc?.isOwner ?? false) || (doc?.isAdmin ?? false);
        if (!snap.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return isRealtorOrOwner
            ? AppointmentManagementScreen(userId: userId)
            : AppointmentsScreen(
                userId: userId,
                initialAppointmentId: initialAppointmentId,
              );
      },
    );
  }
}

/// Mirrors iOS `AppointmentDetailView` / seeker list — chat only after approval flow.
bool _appointmentParityChatEligible(AppointmentRow a) {
  final s = a.status.toLowerCase();
  return s == 'approved' || s == 'confirmed';
}

// Mirrors iOS `AppointmentType.icon` — one icon per canonical type.
IconData _appointmentTypeIcon(String type) {
  switch (type) {
    case 'Property Viewing':
      return Icons.home_outlined;
    case 'Consultation':
      return Icons.people_outline;
    case 'Open House':
      return Icons.meeting_room_outlined;
    case 'Virtual Tour':
      return Icons.videocam_outlined;
    case 'Contract Signing':
      return Icons.description_outlined;
    case 'Inspection':
      return Icons.search;
    default:
      return Icons.calendar_today_outlined;
  }
}

class AppointmentsScreen extends StatefulWidget {
  const AppointmentsScreen({
    super.key,
    required this.userId,
    this.initialAppointmentId,
  });

  final String userId;

  /// Deep-link/push target — opened automatically once the list loads.
  final String? initialAppointmentId;

  @override
  State<AppointmentsScreen> createState() => _AppointmentsScreenState();
}

class _AppointmentsScreenState extends State<AppointmentsScreen> {
  Future<List<AppointmentRow>>? _future;
  bool _didAutoOpenDeepLink = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= _fetch();
  }

  void _maybeAutoOpenDeepLink(
    List<AppointmentRow> all,
    Map<String, String> imageByPropertyId,
  ) {
    if (_didAutoOpenDeepLink) return;
    final targetId = widget.initialAppointmentId;
    if (targetId == null || targetId.isEmpty) return;
    final match = all.where((a) => a.id == targetId).toList();
    if (match.isEmpty) return;
    _didAutoOpenDeepLink = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _showDetails(match.first, imageByPropertyId[match.first.propertyId]);
    });
  }

  Future<List<AppointmentRow>> _fetch() {
    return context.read<UserProfileRepository>().getMyAppointments(widget.userId);
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _fetch();
    });
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return ProfileGroupedScaffold(
      title: 'My Appointments',
      actions: [
        IconButton(
          tooltip: 'Schedule appointment',
          onPressed: () => _openScheduleFlow(context),
          icon: const Icon(Icons.add),
        ),
      ],
      child: FutureBuilder<List<AppointmentRow>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done &&
              !snapshot.hasData) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 14),
                  Text(
                    'Loading appointments...',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                  ),
                ],
              ),
            );
          }
          if (snapshot.hasError) {
            return ProfileErrorState(
              message: snapshot.error.toString(),
              onRetry: _refresh,
            );
          }
          final all = snapshot.data ?? const <AppointmentRow>[];
          final upcoming = all.where((a) => !a.isPast).toList();
          final past = all.where((a) => a.isPast).toList();
          final shown = [...upcoming, ...past];
          final propertyIds =
              shown.map((a) => a.propertyId).where((e) => e.isNotEmpty).toList();

          return FutureBuilder<Map<String, String>>(
            future: context
                .read<UserProfileRepository>()
                .getPropertyImageUrls(propertyIds),
            builder: (context, imageSnap) {
              final imageByPropertyId = imageSnap.data ?? const {};
              _maybeAutoOpenDeepLink(all, imageByPropertyId);
              return RefreshIndicator(
                onRefresh: _refresh,
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                if (shown.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _SeekerAppointmentsEmptyState(
                      onSchedule: () => _openScheduleFlow(context),
                      onBrowseProperties: () => context.go('/home'),
                    ),
                  )
                else
                  SliverList(
                    delegate: SliverChildListDelegate.fixed([
                      if (upcoming.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                          child: ProfileSectionHeader(
                            'Upcoming (${upcoming.length})',
                          ),
                        ),
                      if (upcoming.isNotEmpty)
                        ...upcoming.map(
                          (appt) => Padding(
                            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                            child: _AppointmentCard(
                              appt: appt,
                              imageUrl: imageByPropertyId[appt.propertyId],
                              onTap: () => _showDetails(
                                    appt,
                                    imageByPropertyId[appt.propertyId],
                                  ),
                            ),
                          ),
                        ),
                      if (past.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
                          child: ProfileSectionHeader('Past (${past.length})'),
                        ),
                      if (past.isNotEmpty)
                        ...past.map(
                          (appt) => Padding(
                            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                            child: _AppointmentCard(
                              appt: appt,
                              imageUrl: imageByPropertyId[appt.propertyId],
                              onTap: () => _showDetails(
                                    appt,
                                    imageByPropertyId[appt.propertyId],
                                  ),
                            ),
                          ),
                        ),
                      const SizedBox(height: 20),
                    ]),
                  ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  bool _canCancel(AppointmentRow a, String currentUserId) {
    final isSeeker = a.userId == currentUserId;
    final isRealtor = a.realtorId == currentUserId;
    if (!isSeeker && !isRealtor) return false;
    final s = a.status.toLowerCase();
    return !a.isPast && (s == 'requested' || s == 'approved' || s == 'confirmed');
  }

  // Mirrors iOS `AppointmentDetailView.actionsSection`: approve/reject are
  // realtor-only and blocked once the slot has expired unactioned.
  bool _canApprove(AppointmentRow a, String currentUserId) {
    if (a.realtorId != currentUserId || a.isPast || a.isExpired) return false;
    return a.status.toLowerCase() == 'requested';
  }

  bool _canReject(AppointmentRow a, String currentUserId) {
    if (a.realtorId != currentUserId || a.isPast || a.isExpired) return false;
    return a.status.toLowerCase() == 'requested';
  }

  Future<void> _cancel(String appointmentId) async {
    await context.read<UserProfileRepository>().updateAppointmentStatus(
          appointmentId: appointmentId,
          status: 'Cancelled',
        );
    await _refresh();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Appointment cancelled')),
    );
  }

  Future<void> _updateStatus({
    required String appointmentId,
    required String status,
    required String successMessage,
  }) async {
    await context.read<UserProfileRepository>().updateAppointmentStatus(
          appointmentId: appointmentId,
          status: status,
        );
    await _refresh();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(successMessage)),
    );
  }

  Future<void> _confirmAndRun({
    required String title,
    required String message,
    required Future<void> Function() action,
  }) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Keep'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Confirm'),
              ),
            ],
          ),
        ) ??
        false;
    if (confirmed) {
      HapticFeedback.mediumImpact();
      await action();
    }
  }

  void _showDetails(AppointmentRow a, String? propertyImageUrl) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _AppointmentDetailPage(
          appointment: a,
          propertyImageUrl: propertyImageUrl,
          onOpenProperty: a.propertyId.isNotEmpty
              ? () => context.push('/property/${a.propertyId}')
              : null,
          onCancel: _canCancel(a, widget.userId) ? () => _cancel(a.id) : null,
          onApprove: _canApprove(a, widget.userId)
              ? () => _updateStatus(
                    appointmentId: a.id,
                    status: 'Approved',
                    successMessage: 'Appointment approved',
                  )
              : null,
          onReject: _canReject(a, widget.userId)
              ? () => _updateStatus(
                    appointmentId: a.id,
                    status: 'Rejected',
                    successMessage: 'Appointment rejected',
                  )
              : null,
          onConfirmAction: _confirmAndRun,
        ),
        fullscreenDialog: true,
      ),
    );
  }

  void _openScheduleFlow(BuildContext context) {
    context.push('/profile/appointments/schedule').then((_) {
      if (mounted) _refresh();
    });
  }

}

/// iOS [AppointmentsEmptyState]: primary schedule + secondary browse.
class _SeekerAppointmentsEmptyState extends StatelessWidget {
  const _SeekerAppointmentsEmptyState({
    required this.onSchedule,
    required this.onBrowseProperties,
  });

  final VoidCallback onSchedule;
  final VoidCallback onBrowseProperties;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.calendar_month_rounded,
            size: 60,
            color: AppColors.textSecondary.withValues(alpha: 0.9),
          ),
          const SizedBox(height: 18),
          Text(
            'No Appointments',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          Text(
            'Schedule viewings and appointments with property owners or agents.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
          ),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onSchedule,
              icon: const Icon(Icons.calendar_month_outlined),
              label: const Text('Schedule Appointment'),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onBrowseProperties,
              icon: const Icon(Icons.home_outlined),
              label: const Text('Browse Properties'),
            ),
          ),
        ],
      ),
    );
  }
}

class _AppointmentCard extends StatelessWidget {
  const _AppointmentCard({
    required this.appt,
    required this.imageUrl,
    required this.onTap,
  });

  final AppointmentRow appt;
  final String? imageUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final when = DateFormat.MMMd().add_jm().format(appt.date);
    final chip = _statusColor(appt);
    final icon = _appointmentTypeIcon(appt.appointmentType);
    return ProfileGroupedCard(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(ProfileTokens.radiusCard),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 360;
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Stack(
                        children: [
                          _AppointmentThumb(imageUrl: imageUrl),
                          Positioned(
                            right: -2,
                            bottom: -2,
                            child: Container(
                              width: 20,
                              height: 20,
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.surface,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                icon,
                                size: 12,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              appt.propertyTitle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: chip.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(
                                  ProfileTokens.radiusChip,
                                ),
                              ),
                              child: Text(
                                appt.displayStatus,
                                style: TextStyle(
                                  color: chip,
                                  fontSize: compact ? 10 : 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 6),
              Text(
                when,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                '${appt.appointmentType} • ${appt.duration} min',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textTertiary,
                    ),
              ),
              if (appt.propertyAddress.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  appt.propertyAddress,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                ),
              ],
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(
                    Icons.person_outline,
                    size: 14,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      appt.userName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                    ),
                  ),
                  if (appt.chatEnabled)
                    const Icon(
                      Icons.chat_bubble_outline,
                      size: 14,
                      color: AppColors.primary,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Mirrors iOS `AppointmentStatus.color`, substituting gray for expired
  // (iOS `effectiveStatus`) before falling back to the raw status.
  Color _statusColor(AppointmentRow appt) {
    if (appt.isExpired) return AppColors.textSecondary;
    switch (appt.status.toLowerCase()) {
      case 'approved':
        return AppColors.success;
      case 'confirmed':
        return AppColors.primary;
      case 'rejected':
      case 'cancelled':
      case 'canceled':
        return AppColors.error;
      case 'completed':
        return AppColors.textSecondary;
      default:
        return AppColors.warning;
    }
  }

}

class _AppointmentDetailPage extends StatelessWidget {
  const _AppointmentDetailPage({
    required this.appointment,
    this.propertyImageUrl,
    required this.onConfirmAction,
    this.onOpenProperty,
    this.onCancel,
    this.onApprove,
    this.onReject,
  });

  final AppointmentRow appointment;
  final String? propertyImageUrl;
  final VoidCallback? onOpenProperty;
  final Future<void> Function()? onCancel;
  final Future<void> Function()? onApprove;
  final Future<void> Function()? onReject;
  final Future<void> Function({
    required String title,
    required String message,
    required Future<void> Function() action,
  }) onConfirmAction;

  Future<void> _startChat(BuildContext context) async {
    final rawUid = context.read<AuthProvider>().user?.uid;
    final uid = rawUid?.trim() ?? '';
    if (uid.isEmpty) return;

    final realtor = appointment.realtorId.trim();
    final client = appointment.userId.trim();
    final other = uid == client ? realtor : client;
    if (other.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Missing participant for chat.')),
      );
      return;
    }

    try {
      final tid = await context.read<PropertyRepository>().ensureDirectConversation(
            currentUserId: uid,
            otherUserId: other,
          );
      if (!context.mounted) return;
      await context.push('/messages/thread/$tid');
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open chat: $e')),
      );
    }
  }

  // Mirrors iOS `AppointmentStatus.color`, substituting gray for expired
  // (iOS `effectiveStatus`) before falling back to the raw status.
  Color _statusColor(AppointmentRow appt) {
    if (appt.isExpired) return AppColors.textSecondary;
    switch (appt.status.toLowerCase()) {
      case 'approved':
        return AppColors.success;
      case 'confirmed':
        return AppColors.primary;
      case 'rejected':
      case 'cancelled':
      case 'canceled':
        return AppColors.error;
      case 'completed':
        return AppColors.textSecondary;
      default:
        return AppColors.warning;
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusBackground = _statusColor(appointment);
    final dateOnly = DateFormat.yMMMMd().format(appointment.date);
    final timeOnly = DateFormat.jm().format(appointment.date);
    final created = appointment.createdAt == null
        ? 'Unknown'
        : DateFormat.yMMMd().add_jm().format(appointment.createdAt!);
    final typeIcon = _appointmentTypeIcon(appointment.appointmentType);

    return ProfileGroupedScaffold(
      title: 'Appointment Details',
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
        children: [
          // Header — iOS AppointmentDetailView headerSection
          Column(
            children: [
              Icon(typeIcon, size: 48, color: AppColors.primary),
              const SizedBox(height: 10),
              Text(
                appointment.appointmentType,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: statusBackground,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  appointment.displayStatus,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          // Property — iOS propertySection
          _IosGraySection(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Property',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _DetailPropertyThumb(url: propertyImageUrl),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            appointment.propertyTitle,
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            appointment.propertyAddress,
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: AppColors.textSecondary,
                                    ),
                          ),
                          if (appointment.chatEnabled) ...[
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                const Icon(
                                  Icons.chat_rounded,
                                  size: 14,
                                  color: AppColors.primary,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Chat Enabled',
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelSmall
                                      ?.copyWith(color: AppColors.primary),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _IosGraySection(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Appointment Details',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 10),
                _detailRow(context, Icons.calendar_today_outlined, 'Date', dateOnly),
                _detailRow(context, Icons.schedule_outlined, 'Time', timeOnly),
                _detailRow(
                  context,
                  Icons.timer_outlined,
                  'Duration',
                  '${appointment.duration} minutes',
                ),
                _detailRow(
                  context,
                  Icons.event_available_outlined,
                  'Created',
                  created,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _IosGraySection(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Client',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 10),
                _detailLine('Name', appointment.userName),
                _detailLine('Email', appointment.userEmail),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _IosGraySection(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Agent',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 10),
                _detailLine('Name', appointment.realtorName),
                _detailLine('Email', appointment.realtorEmail),
              ],
            ),
          ),
          if (appointment.notes.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            _IosGraySection(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Notes',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    appointment.notes,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 18),
          if (_appointmentParityChatEligible(appointment))
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => _startChat(context),
                icon: const Icon(Icons.chat_bubble_outline),
                label: const Text('Start Chat'),
              ),
            ),
          if (_appointmentParityChatEligible(appointment))
            const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.start,
            children: [
              if (onOpenProperty != null)
                OutlinedButton.icon(
                  onPressed: onOpenProperty,
                  icon: const Icon(Icons.home_outlined, size: 18),
                  label: const Text('View Property'),
                ),
              if (onApprove != null)
                FilledButton.icon(
                  onPressed: onApprove,
                  icon: const Icon(Icons.check_circle_outline, size: 18),
                  label: const Text('Approve'),
                ),
              if (onReject != null)
                OutlinedButton.icon(
                  onPressed: () => onConfirmAction(
                    title: 'Reject Appointment Request',
                    message:
                        'Please confirm — this will mark the appointment as rejected.',
                    action: onReject!,
                  ),
                  icon: const Icon(Icons.close, size: 18),
                  label: const Text('Reject'),
                ),
              if (onCancel != null)
                TextButton.icon(
                  onPressed: () => onConfirmAction(
                    title: 'Cancel Appointment?',
                    message:
                        'This appointment will be marked as cancelled. The other party will no longer see it as scheduled.',
                    action: onCancel!,
                  ),
                  icon: const Icon(Icons.cancel_outlined, size: 18),
                  label: const Text('Cancel Appointment'),
                  style: TextButton.styleFrom(foregroundColor: AppColors.error),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _detailLine(String title, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              title,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  Widget _detailRow(
    BuildContext context,
    IconData icon,
    String title,
    String value,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                ),
                const SizedBox(height: 2),
                Text(value, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Light grouped panel — iOS gray.opacity(0.1) cards.
class _IosGraySection extends StatelessWidget {
  const _IosGraySection({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
    );
  }
}

class _DetailPropertyThumb extends StatelessWidget {
  const _DetailPropertyThumb({this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    const size = 80.0;
    final u = url?.trim();
    if (u != null && u.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: CachedNetworkImage(
          imageUrl: u,
          width: size,
          height: size,
          fit: BoxFit.cover,
          memCacheWidth: 160,
          memCacheHeight: 160,
          placeholder: (_, __) => Container(
            width: size,
            height: size,
            color: AppColors.surfaceVariant,
            child: const Center(
              child: SizedBox(
                width: 18,
                height: 18,
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
      child: const Icon(Icons.home_rounded, color: AppColors.textTertiary),
    );
  }
}


class _AppointmentThumb extends StatelessWidget {
  const _AppointmentThumb({required this.imageUrl});

  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    const size = 52.0;
    if (imageUrl != null && imageUrl!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(ProfileTokens.radiusThumb),
        child: CachedNetworkImage(
          imageUrl: imageUrl!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          // 52dp × 2× density = 104px decoded cap.
          memCacheWidth: 104,
          memCacheHeight: 104,
          placeholder: (_, __) => Container(
            width: size,
            height: size,
            color: AppColors.surfaceVariant,
            child: const Center(
              child: SizedBox(
                width: 16,
                height: 16,
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
        borderRadius: BorderRadius.circular(ProfileTokens.radiusThumb),
      ),
      child: const Icon(
        Icons.home_outlined,
        color: AppColors.textTertiary,
        size: 20,
      ),
    );
  }
}
