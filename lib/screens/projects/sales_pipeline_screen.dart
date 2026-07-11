import 'package:flutter/material.dart';

import '../../models/project_interest_model.dart';

/// iOS `ConversionStatus.allCases` order.
const List<String> kPipelineConversionStages = [
  'new',
  'contacted',
  'viewing',
  'negotiating',
  'reserved',
  'closed',
];

String _normalizeStage(String raw) {
  final s = raw.trim().toLowerCase();
  if (kPipelineConversionStages.contains(s)) return s;
  return 'new';
}

/// Lead plus project context for developer pipeline / iOS `ProjectInterestWithProject`.
class LeadWithProject {
  const LeadWithProject({
    required this.interest,
    required this.projectName,
    required this.projectId,
  });

  final ProjectInterestModel interest;
  final String projectName;
  final String projectId;
}

/// Horizontal Kanban — iOS `SalesPipelineView`.
class SalesPipelineBoard extends StatelessWidget {
  const SalesPipelineBoard({
    super.key,
    required this.leads,
    required this.onSelectLead,
    this.columnWidth = 220,
    this.minHeight = 320,
  });

  final List<LeadWithProject> leads;
  final void Function(LeadWithProject lead) onSelectLead;
  final double columnWidth;
  final double minHeight;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: minHeight,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: kPipelineConversionStages.length,
        separatorBuilder: (_, __) => const SizedBox(width: 4),
        itemBuilder: (context, i) {
          final stage = kPipelineConversionStages[i];
          final items = leads
              .where((l) => _normalizeStage(l.interest.conversionStatusRaw) == stage)
              .toList();
          return _PipelineColumn(
            width: columnWidth,
            stage: stage,
            items: items,
            colorScheme: cs,
            onTapLead: onSelectLead,
          );
        },
      ),
    );
  }
}

class _PipelineColumn extends StatelessWidget {
  const _PipelineColumn({
    required this.width,
    required this.stage,
    required this.items,
    required this.colorScheme,
    required this.onTapLead,
  });

  final double width;
  final String stage;
  final List<LeadWithProject> items;
  final ColorScheme colorScheme;
  final void Function(LeadWithProject lead) onTapLead;

  String get _title {
    if (stage.isEmpty) return '—';
    return stage[0].toUpperCase() + stage.substring(1);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              Text(
                '${items.length}',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: items.isEmpty
                ? Text(
                    'No leads',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                  )
                : ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, j) {
                      final item = items[j];
                      final lead = item.interest;
                      return Material(
                        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(10),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () => onTapLead(item),
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  lead.name,
                                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                        fontWeight: FontWeight.w600,
                                      ),
                                ),
                                if (lead.unitId != null &&
                                    lead.unitId!.trim().isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    'Unit: ${lead.unitId}',
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                          color: colorScheme.onSurfaceVariant,
                                        ),
                                  ),
                                ],
                                const SizedBox(height: 4),
                                Text(
                                  lead.contactUnlocked ? lead.email : '••••••••',
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  item.projectName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                        color: colorScheme.primary,
                                        fontWeight: FontWeight.w500,
                                      ),
                                ),
                              ],
                            ),
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
}

/// Full-screen pipeline (optional entry from developer dashboard).
class SalesPipelineScreen extends StatelessWidget {
  const SalesPipelineScreen({
    super.key,
    required this.leads,
    required this.onLeadStageChange,
  });

  final List<LeadWithProject> leads;
  final void Function(LeadWithProject lead, String newStage) onLeadStageChange;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sales pipeline'),
      ),
      body: SalesPipelineBoard(
        leads: leads,
        minHeight: MediaQuery.sizeOf(context).height - kToolbarHeight - 48,
        onSelectLead: (lead) => _showStagePicker(
          context,
          lead: lead,
          onPick: (stage) => onLeadStageChange(lead, stage),
        ),
      ),
    );
  }
}

Future<void> _showStagePicker(
  BuildContext context, {
  required LeadWithProject lead,
  required void Function(String stage) onPick,
}) async {
  final current = _normalizeStage(lead.interest.conversionStatusRaw);
  final chosen = await showDialog<String>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: Text('Move · ${lead.interest.name}'),
      children: [
        for (final s in kPipelineConversionStages)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, s),
            child: Row(
              children: [
                if (s == current) Icon(Icons.check, size: 18, color: Theme.of(ctx).colorScheme.primary),
                if (s == current) const SizedBox(width: 6),
                Expanded(
                  child: Text(s[0].toUpperCase() + s.substring(1)),
                ),
              ],
            ),
          ),
      ],
    ),
  );
  if (chosen != null && context.mounted) {
    onPick(chosen);
  }
}

/// Shared helper for embedded pipeline + cards.
Future<void> showLeadConversionPicker(
  BuildContext context, {
  required LeadWithProject lead,
  required void Function(String stage) onPick,
}) {
  return _showStagePicker(context, lead: lead, onPick: onPick);
}
