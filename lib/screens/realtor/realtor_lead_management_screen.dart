import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../constants/app_colors.dart';
import '../../models/listing_entitlements.dart';
import '../../models/realtor_lead_model.dart';
import '../../services/realtor_lead_service.dart';
import 'realtor_upgrade_prompt_screen.dart';

/// Entry point — checks entitlement before presenting lead management.
class RealtorLeadManagementScreen extends StatelessWidget {
  const RealtorLeadManagementScreen({super.key, required this.isProOrElite});

  final bool isProOrElite;

  @override
  Widget build(BuildContext context) {
    if (isProOrElite) {
      return ChangeNotifierProvider(
        create: (_) => RealtorLeadService(),
        child: const _LeadManagementContent(),
      );
    }
    return const _LeadManagementLockedView();
  }
}

// ─── Locked (Free tier) ───────────────────────────────────────────────────────

class _LeadManagementLockedView extends StatelessWidget {
  const _LeadManagementLockedView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Lead Management')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const SizedBox(height: 16),
            // Header
            Column(
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.people,
                      size: 36, color: Colors.green),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Lead Management',
                  style: TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Text(
                  'Track prospects, add notes, prioritise inquiries\nand save quick-reply templates.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 14, color: AppColors.textSecondary),
                ),
              ],
            ),
            const SizedBox(height: 24),
            // Blurred pipeline preview
            SoftGateOverlay(
              feature: RealtorGatedFeature.leadManagement,
              label: 'Lead Pipeline',
              child: _LeadPipelinePreview(),
            ),
            const SizedBox(height: 16),
            // Upgrade CTA
            _LeadUpgradeSummaryCard(),
          ],
        ),
      ),
    );
  }
}

class _LeadPipelinePreview extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final statuses = ['New', 'Contacted', 'Showing', 'Closed'];
    return Column(
      children: statuses
          .map(
            (s) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const CircleAvatar(radius: 4, backgroundColor: Colors.blue),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text('2 leads',
                          style: TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary)),
                    ],
                  ),
                  const Spacer(),
                  Text('View →',
                      style: TextStyle(
                          fontSize: 12, color: AppColors.textSecondary)),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}

class _LeadUpgradeSummaryCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.green.withOpacity(0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.workspace_premium, color: Colors.orange, size: 24),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Unlock full Lead Management',
                    style: TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14)),
                Text('Available on Realtor Pro and Elite.',
                    style: TextStyle(
                        fontSize: 12, color: AppColors.textSecondary)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: () => showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              builder: (_) => const RealtorUpgradePromptScreen(
                  feature: RealtorGatedFeature.leadManagement),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.green,
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              textStyle:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
            child: const Text('Upgrade'),
          ),
        ],
      ),
    );
  }
}

// ─── Main content (Pro / Elite) ───────────────────────────────────────────────

enum _LeadTab { pipeline, priority, templates }

class _LeadManagementContent extends StatefulWidget {
  const _LeadManagementContent();

  @override
  State<_LeadManagementContent> createState() =>
      _LeadManagementContentState();
}

class _LeadManagementContentState extends State<_LeadManagementContent> {
  _LeadTab _selectedTab = _LeadTab.pipeline;
  bool _started = false;

  String get _uid =>
      fb.FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started && _uid.isNotEmpty) {
      _started = true;
      context.read<RealtorLeadService>().startListening(_uid);
    }
  }

  @override
  void dispose() {
    context.read<RealtorLeadService>().stopListening();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<RealtorLeadService>();

    if (svc.errorMessage != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(svc.errorMessage!)),
        );
        svc.errorMessage = null;
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Lead Management'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: _selectedTab == _LeadTab.templates
                ? 'New template'
                : 'New lead',
            onPressed: () {
              if (_selectedTab == _LeadTab.templates) {
                _showNewTemplateSheet(context, svc);
              } else {
                _showNewLeadSheet(context, svc);
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Tab bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: SegmentedButton<_LeadTab>(
              segments: const [
                ButtonSegment(
                    value: _LeadTab.pipeline, label: Text('Pipeline')),
                ButtonSegment(
                    value: _LeadTab.priority, label: Text('Priority')),
                ButtonSegment(
                    value: _LeadTab.templates, label: Text('Templates')),
              ],
              selected: {_selectedTab},
              onSelectionChanged: (s) =>
                  setState(() => _selectedTab = s.first),
              style: const ButtonStyle(
                  visualDensity: VisualDensity.compact),
            ),
          ),
          const Divider(height: 1),
          Expanded(child: _buildTabContent(svc)),
        ],
      ),
    );
  }

  Widget _buildTabContent(RealtorLeadService svc) {
    switch (_selectedTab) {
      case _LeadTab.pipeline:
        return _LeadPipelineView(
          leads: svc.leads,
          leadService: svc,
          onEdit: (lead) => _showLeadDetailSheet(context, svc, lead),
        );
      case _LeadTab.priority:
        return _PriorityLeadsView(
          leads: svc.highPriorityLeads,
          leadService: svc,
          onEdit: (lead) => _showLeadDetailSheet(context, svc, lead),
        );
      case _LeadTab.templates:
        return _SavedResponsesView(
          responses: svc.savedResponses,
          realtorId: _uid,
          leadService: svc,
        );
    }
  }

  void _showNewLeadSheet(BuildContext ctx, RealtorLeadService svc) {
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      builder: (_) => _NewLeadSheet(realtorId: _uid, leadService: svc),
    );
  }

  void _showNewTemplateSheet(BuildContext ctx, RealtorLeadService svc) {
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      builder: (_) =>
          _NewSavedResponseSheet(realtorId: _uid, leadService: svc),
    );
  }

  void _showLeadDetailSheet(
      BuildContext ctx, RealtorLeadService svc, RealtorLead lead) {
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      builder: (_) => _LeadDetailSheet(lead: lead, leadService: svc),
    );
  }
}

// ─── Pipeline view ────────────────────────────────────────────────────────────

class _LeadPipelineView extends StatelessWidget {
  const _LeadPipelineView({
    required this.leads,
    required this.leadService,
    required this.onEdit,
  });

  final List<RealtorLead> leads;
  final RealtorLeadService leadService;
  final void Function(RealtorLead) onEdit;

  static const _order = [
    RealtorLeadStatus.newLead,
    RealtorLeadStatus.contacted,
    RealtorLeadStatus.qualified,
    RealtorLeadStatus.showing,
    RealtorLeadStatus.negotiating,
    RealtorLeadStatus.closed,
    RealtorLeadStatus.lost,
  ];

  @override
  Widget build(BuildContext context) {
    if (leads.isEmpty) {
      return _EmptyLeadsPlaceholder(
          message: 'No leads yet.\nTap + to add your first lead.');
    }
    // A realtor's pipeline can grow to hundreds of leads over time — flatten
    // the grouped-by-status sections into one list up front, then hand it to
    // a lazy builder instead of eagerly building every row.
    final items = _order.expand((status) {
      final group = leads.where((l) => l.status == status).toList();
      if (group.isEmpty) return <Widget>[];
      return [
        _LeadStatusHeader(status: status, count: group.count),
        ...group.map(
          (lead) => _LeadRow(
            lead: lead,
            leadService: leadService,
            onTap: () => onEdit(lead),
          ),
        ),
      ];
    }).toList();
    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (context, i) => items[i],
    );
  }
}

extension on List<RealtorLead> {
  int get count => length;
}

class _LeadStatusHeader extends StatelessWidget {
  const _LeadStatusHeader({required this.status, required this.count});
  final RealtorLeadStatus status;
  final int count;

  Color get _color {
    switch (status) {
      case RealtorLeadStatus.newLead:
        return Colors.blue;
      case RealtorLeadStatus.contacted:
        return Colors.orange;
      case RealtorLeadStatus.qualified:
        return Colors.purple;
      case RealtorLeadStatus.showing:
        return Colors.teal;
      case RealtorLeadStatus.negotiating:
        return Colors.yellow.shade700;
      case RealtorLeadStatus.closed:
        return Colors.green;
      case RealtorLeadStatus.lost:
        return Colors.red;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Row(
        children: [
          Icon(Icons.circle, size: 8, color: _color),
          const SizedBox(width: 8),
          Text(
            status.displayName,
            style: const TextStyle(
                fontWeight: FontWeight.w600, fontSize: 14),
          ),
          const Spacer(),
          Text('$count',
              style: TextStyle(
                  fontSize: 12, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

class _LeadRow extends StatelessWidget {
  const _LeadRow({
    required this.lead,
    required this.leadService,
    required this.onTap,
  });
  final RealtorLead lead;
  final RealtorLeadService leadService;
  final VoidCallback onTap;

  Color get _priorityColor {
    switch (lead.priority) {
      case RealtorLeadPriority.high:
        return Colors.red;
      case RealtorLeadPriority.medium:
        return Colors.orange;
      case RealtorLeadPriority.low:
        return AppColors.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                  shape: BoxShape.circle, color: _priorityColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(lead.prospectName ?? 'Unknown Prospect',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(lead.propertyTitle,
                      style: TextStyle(
                          fontSize: 12, color: AppColors.textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  if (lead.notes.isNotEmpty)
                    Text(lead.notes,
                        style: TextStyle(
                            fontSize: 11, color: AppColors.textSecondary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: _priorityColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(
                lead.priority.displayName,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: _priorityColor),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Priority view ────────────────────────────────────────────────────────────

class _PriorityLeadsView extends StatelessWidget {
  const _PriorityLeadsView({
    required this.leads,
    required this.leadService,
    required this.onEdit,
  });
  final List<RealtorLead> leads;
  final RealtorLeadService leadService;
  final void Function(RealtorLead) onEdit;

  @override
  Widget build(BuildContext context) {
    if (leads.isEmpty) {
      return _EmptyLeadsPlaceholder(
        message:
            "No high-priority leads.\nSet a lead's priority to High in the pipeline.",
      );
    }
    return ListView.builder(
      itemCount: leads.length,
      itemBuilder: (context, i) => _LeadRow(
        lead: leads[i],
        leadService: leadService,
        onTap: () => onEdit(leads[i]),
      ),
    );
  }
}

// ─── Templates view ───────────────────────────────────────────────────────────

class _SavedResponsesView extends StatelessWidget {
  const _SavedResponsesView({
    required this.responses,
    required this.realtorId,
    required this.leadService,
  });
  final List<SavedResponse> responses;
  final String realtorId;
  final RealtorLeadService leadService;

  @override
  Widget build(BuildContext context) {
    if (responses.isEmpty) {
      return _EmptyLeadsPlaceholder(
        message: 'No saved templates yet.\nTap + to create a quick-reply template.',
      );
    }
    return ListView.separated(
      itemCount: responses.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (ctx, i) {
        final resp = responses[i];
        return Dismissible(
          key: ValueKey(resp.id ?? i),
          direction: DismissDirection.endToStart,
          background: Container(
            color: Colors.red,
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 16),
            child: const Icon(Icons.delete, color: Colors.white),
          ),
          onDismissed: (_) =>
              leadService.deleteSavedResponse(
                  realtorId: realtorId, response: resp),
          child: ListTile(
            title: Text(resp.title,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(resp.body, maxLines: 2, overflow: TextOverflow.ellipsis),
          ),
        );
      },
    );
  }
}

// ─── Empty state ──────────────────────────────────────────────────────────────

class _EmptyLeadsPlaceholder extends StatelessWidget {
  const _EmptyLeadsPlaceholder({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.people_outline,
                size: 48, color: AppColors.textSecondary.withOpacity(0.5)),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── New Lead Sheet ───────────────────────────────────────────────────────────

class _NewLeadSheet extends StatefulWidget {
  const _NewLeadSheet({required this.realtorId, required this.leadService});
  final String realtorId;
  final RealtorLeadService leadService;

  @override
  State<_NewLeadSheet> createState() => _NewLeadSheetState();
}

class _NewLeadSheetState extends State<_NewLeadSheet> {
  final _propertyCtrl = TextEditingController();
  final _prospectCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  RealtorLeadPriority _priority = RealtorLeadPriority.medium;

  @override
  void dispose() {
    _propertyCtrl.dispose();
    _prospectCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  void _save() {
    if (_propertyCtrl.text.trim().isEmpty) return;
    final lead = RealtorLead(
      realtorId: widget.realtorId,
      propertyId: '',
      propertyTitle: _propertyCtrl.text.trim(),
      prospectName: _prospectCtrl.text.trim().isEmpty
          ? null
          : _prospectCtrl.text.trim(),
      priority: _priority,
      notes: _notesCtrl.text,
    );
    widget.leadService.createLead(lead);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('New Lead',
                    style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _propertyCtrl.text.trim().isNotEmpty
                      ? _save
                      : null,
                  child: const Text('Save'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _propertyCtrl,
              decoration: const InputDecoration(
                labelText: 'Property title or address',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _prospectCtrl,
              decoration: const InputDecoration(
                labelText: 'Prospect name (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            const Text('Priority',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            SegmentedButton<RealtorLeadPriority>(
              segments: RealtorLeadPriority.values
                  .map((p) => ButtonSegment(
                      value: p, label: Text(p.displayName)))
                  .toList(),
              selected: {_priority},
              onSelectionChanged: (s) =>
                  setState(() => _priority = s.first),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notesCtrl,
              decoration: const InputDecoration(
                labelText: 'Notes',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ─── Lead Detail Sheet ────────────────────────────────────────────────────────

class _LeadDetailSheet extends StatefulWidget {
  const _LeadDetailSheet({required this.lead, required this.leadService});
  final RealtorLead lead;
  final RealtorLeadService leadService;

  @override
  State<_LeadDetailSheet> createState() => _LeadDetailSheetState();
}

class _LeadDetailSheetState extends State<_LeadDetailSheet> {
  late TextEditingController _notesCtrl;
  late RealtorLeadStatus _status;
  late RealtorLeadPriority _priority;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _notesCtrl = TextEditingController(text: widget.lead.notes);
    _status = widget.lead.status;
    _priority = widget.lead.priority;
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveNotes() async {
    setState(() => _saving = true);
    await widget.leadService.updateLeadNotes(widget.lead, _notesCtrl.text);
    if (mounted) {
      setState(() => _saving = false);
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.lead.propertyTitle,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _saving ? null : _saveNotes,
                  child: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save Notes'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text('Status',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            DropdownButtonFormField<RealtorLeadStatus>(
              value: _status,
              decoration: const InputDecoration(border: OutlineInputBorder()),
              items: RealtorLeadStatus.values
                  .map((s) => DropdownMenuItem(
                      value: s, child: Text(s.displayName)))
                  .toList(),
              onChanged: (s) {
                if (s == null) return;
                setState(() => _status = s);
                widget.leadService.updateLeadStatus(widget.lead, s);
              },
            ),
            const SizedBox(height: 12),
            const Text('Priority',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            SegmentedButton<RealtorLeadPriority>(
              segments: RealtorLeadPriority.values
                  .map((p) => ButtonSegment(
                      value: p, label: Text(p.displayName)))
                  .toList(),
              selected: {_priority},
              onSelectionChanged: (s) {
                setState(() => _priority = s.first);
                widget.leadService.updateLeadPriority(widget.lead, s.first);
              },
            ),
            const SizedBox(height: 12),
            const Text('Notes',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            TextField(
              controller: _notesCtrl,
              decoration: const InputDecoration(border: OutlineInputBorder()),
              maxLines: 4,
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ─── New Saved Response Sheet ─────────────────────────────────────────────────

class _NewSavedResponseSheet extends StatefulWidget {
  const _NewSavedResponseSheet(
      {required this.realtorId, required this.leadService});
  final String realtorId;
  final RealtorLeadService leadService;

  @override
  State<_NewSavedResponseSheet> createState() =>
      _NewSavedResponseSheetState();
}

class _NewSavedResponseSheetState extends State<_NewSavedResponseSheet> {
  final _titleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  void _save() {
    if (_titleCtrl.text.trim().isEmpty) return;
    widget.leadService.createSavedResponse(
      realtorId: widget.realtorId,
      title: _titleCtrl.text.trim(),
      body: _bodyCtrl.text,
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('New Template',
                    style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
                const Spacer(),
                TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel')),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed:
                      _titleCtrl.text.trim().isNotEmpty ? _save : null,
                  child: const Text('Save'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _titleCtrl,
              decoration: const InputDecoration(
                labelText:
                    'e.g. Initial intro, Follow-up, Viewing confirm',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _bodyCtrl,
              decoration: const InputDecoration(
                labelText: 'Message body',
                border: OutlineInputBorder(),
              ),
              maxLines: 5,
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
