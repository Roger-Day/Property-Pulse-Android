import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../constants/app_colors.dart';
import '../models/project_interest_row.dart';
import '../models/project_model.dart';
/// iOS `CustomerInterestRow` — building tile, title, optional removal warning, subtitle, registered date.
class DashboardInterestTile extends StatelessWidget {
  const DashboardInterestTile({
    super.key,
    required this.row,
    required this.project,
    required this.subtitle,
    required this.registeredLabel,
    required this.onOpenDetail,
  });

  final ProjectInterestRow row;
  final ProjectModel? project;
  final String subtitle;
  final String? registeredLabel;
  final VoidCallback onOpenDetail;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pid = row.projectId.trim();
    final canNavigate = pid.isNotEmpty;
    final titleText = project?.projectName ?? row.title;

    Widget content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.apartment_rounded,
              size: 22,
              color: scheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titleText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                if (project == null && pid.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    'No longer available on Property Pulse',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: AppColors.warning,
                        ),
                  ),
                ],
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                ),
                if (registeredLabel != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Registered $registeredLabel',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: AppColors.textTertiary,
                        ),
                  ),
                ],
              ],
            ),
          ),
          if (canNavigate)
            const Icon(
              Icons.chevron_right,
              size: 20,
              color: AppColors.textTertiary,
            ),
        ],
      ),
    );

    if (!canNavigate) {
      return Opacity(opacity: 0.85, child: content);
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onOpenDetail,
        child: content,
      ),
    );
  }
}

// ─── Shared helpers (iOS `CustomerInterestRow` subtitle math) ─────────────────

ProjectModel? projectForInterest(
  List<ProjectModel> projects,
  ProjectInterestRow row,
) {
  final raw = row.projectId.trim();
  if (raw.isEmpty) return null;
  for (final p in projects) {
    if (p.firestoreDocumentId == raw || p.id == raw) return p;
  }
  return null;
}

String propertyTypeLine(ProjectModel? project) {
  if (project == null || project.unitTypes.isEmpty) return 'New Development';
  final beds = project.unitTypes.map((u) => u.bedrooms).toList();
  if (beds.isEmpty) return 'New Development';
  var min = beds.first;
  var max = beds.first;
  for (final b in beds.skip(1)) {
    if (b < min) min = b;
    if (b > max) max = b;
  }
  if (min == max) {
    return min == 0 ? 'Studio' : '$min BR';
  }
  return '$min–$max BR';
}

String startingPriceLine(ProjectModel? project) {
  if (project == null || project.startingPrice == null) return 'Pricing TBA';
  final code = project.startingPriceCurrencyCode.trim().isEmpty
      ? 'USD'
      : project.startingPriceCurrencyCode;
  return NumberFormat.simpleCurrency(name: code).format(project.startingPrice);
}

String interestSubtitle(ProjectModel? project) =>
    '${propertyTypeLine(project)} • ${startingPriceLine(project)}';

String? formatInterestRegistered(DateTime? d) {
  if (d == null) return null;
  return DateFormat.yMMMd().format(d);
}
