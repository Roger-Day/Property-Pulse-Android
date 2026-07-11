import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../constants/app_colors.dart';
import '../../models/user_data_export_snapshot.dart';
import '../../repositories/user_profile_repository.dart';
import 'profile_subscreen_widgets.dart';

/// Mirrors iOS `DataExportView`: summary, section previews (first 5 each),
/// and Share for UTF-8 CSV (`UserDataExportSnapshot.csvDocument`).
class DataExportScreen extends StatefulWidget {
  const DataExportScreen({super.key, required this.userId});

  final String userId;

  @override
  State<DataExportScreen> createState() => _DataExportScreenState();
}

class _DataExportScreenState extends State<DataExportScreen> {
  Future<UserDataExportSnapshot>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= context
        .read<UserProfileRepository>()
        .exportUserDataSnapshot(widget.userId);
  }

  Future<void> _reload() async {
    setState(() {
      _future = context
          .read<UserProfileRepository>()
          .exportUserDataSnapshot(widget.userId);
    });
    await _future;
  }

  Future<void> _share(UserDataExportSnapshot data) async {
    await Share.share(
      data.csvDocument,
      subject: 'Property Pulse data export',
    );
  }

  @override
  Widget build(BuildContext context) {
    return ProfileGroupedScaffold(
      title: 'Data Export',
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).maybePop(),
          child: const Text('Done'),
        ),
      ],
      child: FutureBuilder<UserDataExportSnapshot>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return ProfileErrorState(
              message: snapshot.error.toString(),
              onRetry: _reload,
            );
          }
          final data = snapshot.data!;
          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: ProfileLayout.pagePadding,
              children: [
                _ExportSummaryCard(data: data),
                const SizedBox(height: ProfileLayout.sectionGap),
                _DataSectionCard(
                  title: 'User Information',
                  icon: Icons.person_rounded,
                  iconColor: AppColors.primary,
                  child: _UserInfoSection(data: data),
                ),
                const SizedBox(height: ProfileLayout.sectionGap),
                _DataSectionCard(
                  title: 'Saved Properties',
                  icon: Icons.bookmark_rounded,
                  iconColor: AppColors.secondary,
                  child: _SavedPropertiesSection(rows: data.savedProperties),
                ),
                const SizedBox(height: ProfileLayout.sectionGap),
                _DataSectionCard(
                  title: 'Messages',
                  icon: Icons.chat_bubble_rounded,
                  iconColor: AppColors.warning,
                  child: _MessagesSection(rows: data.messages),
                ),
                const SizedBox(height: ProfileLayout.sectionGap),
                _DataSectionCard(
                  title: 'Appointments',
                  icon: Icons.calendar_month_rounded,
                  iconColor: AppColors.error,
                  child: _AppointmentsSection(rows: data.appointments),
                ),
                const SizedBox(height: ProfileLayout.sectionGap),
                ProfilePrimaryButton(
                  label: 'Share Data Export',
                  icon: Icons.share_rounded,
                  onPressed: () => _share(data),
                ),
                const SizedBox(height: 24),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ExportSummaryCard extends StatelessWidget {
  const _ExportSummaryCard({required this.data});

  final UserDataExportSnapshot data;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return ProfileGroupedCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Export Summary',
            style: t.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          _SummaryRow(
            icon: Icons.calendar_today_outlined,
            label: 'Export Date',
            value: UserDataExportSnapshot.formatMedium(data.exportDate),
          ),
          _SummaryRow(
            icon: Icons.bookmark_outline,
            label: 'Saved Properties',
            value: '${data.savedProperties.length}',
          ),
          _SummaryRow(
            icon: Icons.chat_bubble_outline,
            label: 'Messages',
            value: '${data.messages.length}',
          ),
          _SummaryRow(
            icon: Icons.event_outlined,
            label: 'Appointments',
            value: '${data.appointments.length}',
          ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.textSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: t.bodyMedium?.copyWith(color: AppColors.textSecondary),
            ),
          ),
          Text(
            value,
            style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

class _DataSectionCard extends StatelessWidget {
  const _DataSectionCard({
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Color iconColor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return ProfileGroupedCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor, size: 26),
              const SizedBox(width: 10),
              Text(
                title,
                style: t.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _UserInfoSection extends StatelessWidget {
  const _UserInfoSection({required this.data});

  final UserDataExportSnapshot data;

  @override
  Widget build(BuildContext context) {
    final rows = <MapEntry<String, String>>[
      MapEntry('Name', data.fullName),
      MapEntry('Email', data.email),
      MapEntry('Role', data.role),
      if (data.phone != null && data.phone!.trim().isNotEmpty)
        MapEntry('Phone', data.phone!),
    ];
    return Column(
      children: rows
          .map(
            (e) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 72,
                    child: Text(
                      e.key,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      e.value,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}

class _SavedPropertiesSection extends StatelessWidget {
  const _SavedPropertiesSection({required this.rows});

  final List<PropertyExportRow> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const _EmptyHint(
        icon: Icons.bookmark_outline,
        text: 'No saved properties',
      );
    }
    final preview = rows.take(5).toList();
    final rest = rows.length - preview.length;
    return Column(
      children: [
        ...preview.map((p) => _PropertyPreviewRow(row: p)),
        if (rest > 0)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '... and $rest more',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
              textAlign: TextAlign.center,
            ),
          ),
      ],
    );
  }
}

class _PropertyPreviewRow extends StatelessWidget {
  const _PropertyPreviewRow({required this.row});

  final PropertyExportRow row;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.title,
                  style: t.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  row.location,
                  style: t.bodySmall?.copyWith(color: AppColors.textSecondary),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            row.priceLabel,
            style: t.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _MessagesSection extends StatelessWidget {
  const _MessagesSection({required this.rows});

  final List<MessageExportRow> rows;

  static final DateFormat _when = DateFormat.yMMMd().add_jm();

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return Text(
        'No messages',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
            ),
        textAlign: TextAlign.center,
      );
    }
    final preview = rows.take(5).toList();
    final rest = rows.length - preview.length;
    return Column(
      children: [
        ...preview.map((m) => _MessagePreviewRow(row: m, format: _when)),
        if (rest > 0)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '... and $rest more',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
              textAlign: TextAlign.center,
            ),
          ),
      ],
    );
  }
}

class _MessagePreviewRow extends StatelessWidget {
  const _MessagePreviewRow({
    required this.row,
    required this.format,
  });

  final MessageExportRow row;
  final DateFormat format;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final when = row.createdAt != null ? format.format(row.createdAt!.toLocal()) : '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              row.text,
              style: t.bodySmall,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (when.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                when,
                style: t.bodySmall?.copyWith(color: AppColors.textSecondary),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AppointmentsSection extends StatelessWidget {
  const _AppointmentsSection({required this.rows});

  final List<AppointmentExportRow> rows;

  static final DateFormat _when = DateFormat.yMMMd().add_jm();

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return Text(
        'No appointments',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
            ),
        textAlign: TextAlign.center,
      );
    }
    final preview = rows.take(5).toList();
    final rest = rows.length - preview.length;
    return Column(
      children: [
        ...preview.map((a) => _AppointmentPreviewRow(row: a, format: _when)),
        if (rest > 0)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '... and $rest more',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
              textAlign: TextAlign.center,
            ),
          ),
      ],
    );
  }
}

class _AppointmentPreviewRow extends StatelessWidget {
  const _AppointmentPreviewRow({
    required this.row,
    required this.format,
  });

  final AppointmentExportRow row;
  final DateFormat format;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final when = row.date != null ? format.format(row.date!.toLocal()) : '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Appointment',
                  style: t.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                ),
                if (when.isNotEmpty)
                  Text(
                    when,
                    style: t.bodySmall?.copyWith(color: AppColors.textSecondary),
                  ),
              ],
            ),
          ),
          Text(
            row.status,
            style: t.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        children: [
          Icon(icon, size: 28, color: AppColors.textSecondary),
          const SizedBox(height: 8),
          Text(
            text,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
        ],
      ),
    );
  }
}
