import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../constants/app_colors.dart';
import '../../models/development_unit_model.dart';
import '../../models/project_interest_model.dart';
import '../../providers/auth_provider.dart';
import '../../repositories/project_repository.dart';
import '../../repositories/property_repository.dart';
import '../../services/analytics_service.dart';
import '../../services/developer_monetization_service.dart';
import '../../services/lead_credit_service.dart';
import '../developer/lead_credit_topup_screen.dart';
import 'sales_pipeline_screen.dart';

/// Developer-facing lead list — iOS `ProjectLeadsView` parity.
class ProjectLeadsScreen extends StatelessWidget {
  const ProjectLeadsScreen({
    super.key,
    required this.projectId,
    required this.projectName,
  });

  final String projectId;
  final String projectName;

  @override
  Widget build(BuildContext context) {
    final repo = context.read<ProjectRepository>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Leads'),
      ),
      body: StreamBuilder<List<DevelopmentUnitModel>>(
        stream: repo.watchDevelopmentUnits(projectId),
        builder: (context, unitSnap) {
          final units = unitSnap.data ?? const <DevelopmentUnitModel>[];
          final unitsById = {for (final u in units) u.id: u};

          return StreamBuilder<List<ProjectInterestModel>>(
            stream: repo.watchProjectInterests(projectId),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      snapshot.error.toString(),
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final leads = snapshot.data!;
              if (leads.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.people_outline,
                          size: 56,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant
                              .withValues(alpha: 0.5),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No leads yet',
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    color:
                                        Theme.of(context).colorScheme.onSurface,
                                  ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Interests from “Register interest” will appear here.',
                          textAlign: TextAlign.center,
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              final totalClosed = leads
                  .where(
                    (l) => l.conversionStatusRaw.toLowerCase() == 'closed',
                  )
                  .length;
              final rate = leads.isEmpty
                  ? 0
                  : ((totalClosed / leads.length) * 100).round();

              final pipelineLeads = leads
                  .map(
                    (l) => LeadWithProject(
                      interest: l,
                      projectName: projectName,
                      projectId: projectId,
                    ),
                  )
                  .toList();

              void openDetail(ProjectInterestModel lead) {
                showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  showDragHandle: true,
                  builder: (ctx) => _LeadDetailSheet(
                    lead: lead,
                    projectId: projectId,
                    projectName: projectName,
                    units: units,
                  ),
                );
              }

              return RefreshIndicator(
                onRefresh: () async {
                  await Future<void>.delayed(const Duration(milliseconds: 200));
                },
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 32),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                      child: Text(
                        'Project',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Text(
                        projectName,
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Text(
                        'Analytics',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                    _AnalyticsRow(
                      icon: Icons.people,
                      label: 'Total leads',
                      value: '${leads.length}',
                    ),
                    _AnalyticsRow(
                      icon: Icons.check_circle,
                      label: 'Closed',
                      value: '$totalClosed',
                    ),
                    _AnalyticsRow(
                      icon: Icons.show_chart,
                      label: 'Conversion rate',
                      value: '$rate%',
                    ),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Text(
                        'Sales pipeline',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                    SalesPipelineBoard(
                      leads: pipelineLeads,
                      minHeight: 300,
                      onSelectLead: (lw) => openDetail(lw.interest),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Text(
                        'Interests',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...leads.map(
                      (l) => Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        child: _LeadTile(
                          lead: l,
                          projectId: projectId,
                          projectName: projectName,
                          unitsById: unitsById,
                          onOpenDetail: () => openDetail(l),
                        ),
                      ),
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
}

class _AnalyticsRow extends StatelessWidget {
  const _AnalyticsRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 20, color: cs.primary),
          const SizedBox(width: 10),
          Expanded(child: Text(label)),
          Text(
            value,
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _LeadTile extends StatefulWidget {
  const _LeadTile({
    required this.lead,
    required this.projectId,
    required this.projectName,
    required this.unitsById,
    required this.onOpenDetail,
  });

  final ProjectInterestModel lead;
  final String projectId;
  final String projectName;
  final Map<String, DevelopmentUnitModel> unitsById;
  final VoidCallback onOpenDetail;

  @override
  State<_LeadTile> createState() => _LeadTileState();
}

class _LeadTileState extends State<_LeadTile> {
  bool _unlocking = false;
  bool _marking = false;

  Future<void> _unlock() async {
    setState(() => _unlocking = true);
    try {
      final svc = context.read<DeveloperMonetizationService>();
      final pid = widget.lead.projectId.isNotEmpty
          ? widget.lead.projectId
          : widget.projectId;
      final result = await svc.unlockDevelopmentLead(
        projectId: pid,
        interestId: widget.lead.id,
      );
      if (!mounted) return;
      if (!result.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.message ?? 'Could not unlock lead')),
        );
      } else {
        unawaited(AnalyticsService.logLeadRevealed(pid, widget.lead.id));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result.alreadyUnlocked
                  ? 'Contact was already unlocked'
                  : 'Contact details unlocked',
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    } finally {
      if (mounted) setState(() => _unlocking = false);
    }
  }

  Future<void> _markContacted() async {
    setState(() => _marking = true);
    try {
      await context.read<ProjectRepository>().markInterestContacted(
            projectId: widget.projectId,
            interestId: widget.lead.id,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Marked as contacted')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _marking = false);
    }
  }

  Future<void> _openChat() async {
    final uid = widget.lead.userId?.trim() ?? '';
    if (uid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'This lead doesn’t have a linked user account for in-app messaging.',
          ),
        ),
      );
      return;
    }
    final me = context.read<AuthProvider>().user?.uid;
    if (me == null || me.isEmpty) return;
    try {
      final threadId = await context.read<PropertyRepository>().ensureDirectConversation(
            currentUserId: me,
            otherUserId: uid,
          );
      if (!mounted) return;
      context.push('/messages/thread/$threadId');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to open chat: $e')),
        );
      }
    }
  }

  Future<void> _openMail() async {
    final email = widget.lead.email.trim();
    if (!email.contains('@')) return;
    final subject = Uri.encodeComponent('Re: ${widget.projectName}');
    final uri = Uri.parse('mailto:$email?subject=$subject');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _openCall() async {
    final phone = widget.lead.phone?.trim() ?? '';
    if (phone.isEmpty) return;
    final uri = Uri.parse('tel:${Uri.encodeComponent(phone)}');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Color _statusPillColor(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'new':
        return Colors.blue.shade700;
      case 'contacted':
        return Colors.green.shade700;
      case 'viewing':
        return Colors.purple.shade700;
      case 'negotiating':
        return Colors.orange.shade800;
      case 'reserved':
        return Colors.amber.shade800;
      case 'closed':
        return Colors.red.shade700;
      default:
        return Colors.blueGrey.shade700;
    }
  }

  @override
  Widget build(BuildContext context) {
    final lead = widget.lead;
    final cs = Theme.of(context).colorScheme;
    final dateStr = DateFormat.yMMMd().format(lead.createdAt);
    final locked = !lead.contactUnlocked;

    if (locked) {
      return Card(
        elevation: 0,
        color: cs.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.9)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'New lead',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade700,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      lead.intentDisplayName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              if (lead.previewSnippet != null &&
                  lead.previewSnippet!.trim().isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  lead.previewSnippet!,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                ),
              ],
              const SizedBox(height: 4),
              Text(
                dateStr,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 10),
              // Pricing context — lets the developer know the cost before tapping.
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade100),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 14, color: Colors.blue.shade700),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Unlocking deducts from your lead credit balance (~\$8–\$9 base rate).',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.blue.shade900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _unlocking ? null : _unlock,
                      icon: _unlocking
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.lock_open, size: 18),
                      label: Text(
                        _unlocking ? 'Unlocking…' : 'Unlock contact',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(context).push<void>(
                        MaterialPageRoute<void>(
                          fullscreenDialog: true,
                          builder: (_) => LeadCreditTopUpScreen(
                            currentBalance: 0,
                            onPurchaseCompleted: () {},
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.add_circle_outline, size: 18),
                    label: const Text('Top up'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: const BorderSide(color: AppColors.primary),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    final unit = lead.unitId != null && lead.unitId!.isNotEmpty
        ? widget.unitsById[lead.unitId]
        : null;

    return Card(
      elevation: 0,
      color: cs.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.9)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    lead.name,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: _statusPillColor(lead.conversionStatusRaw),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    lead.conversionTitle,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              lead.email,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
            ),
            if (unit != null) ...[
              const SizedBox(height: 4),
              Text(
                'Unit: ${unit.unitNumber}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
              ),
            ],
            if (lead.phone != null && lead.phone!.trim().isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                lead.phone!,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
              ),
            ],
            if (lead.message != null && lead.message!.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                lead.message!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
              ),
            ],
            const SizedBox(height: 4),
            Text(
              dateStr,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _openChat,
                  icon: const Icon(Icons.chat_bubble_outline, size: 18),
                  label: const Text('Message'),
                ),
                OutlinedButton.icon(
                  onPressed: _openMail,
                  icon: const Icon(Icons.email_outlined, size: 18),
                  label: const Text('Email'),
                ),
                if (lead.phone != null && lead.phone!.trim().isNotEmpty)
                  OutlinedButton.icon(
                    onPressed: _openCall,
                    icon: const Icon(Icons.phone_outlined, size: 18),
                    label: const Text('Call'),
                  ),
                if (lead.contactedAt == null)
                  FilledButton.icon(
                    onPressed: _marking ? null : _markContacted,
                    icon: _marking
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check_circle_outline, size: 18),
                    label: const Text('Mark contacted'),
                  ),
                OutlinedButton.icon(
                  onPressed: widget.onOpenDetail,
                  icon: const Icon(Icons.tune, size: 18),
                  label: const Text('Details'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LeadDetailSheet extends StatefulWidget {
  const _LeadDetailSheet({
    required this.lead,
    required this.projectId,
    required this.projectName,
    required this.units,
  });

  final ProjectInterestModel lead;
  final String projectId;
  final String projectName;
  final List<DevelopmentUnitModel> units;

  @override
  State<_LeadDetailSheet> createState() => _LeadDetailSheetState();
}

class _LeadDetailSheetState extends State<_LeadDetailSheet> {
  late String _status;
  late String _unitId;
  late TextEditingController _notes;
  bool _savingNotes = false;

  @override
  void initState() {
    super.initState();
    _status = widget.lead.conversionStatusRaw.trim().toLowerCase().isEmpty
        ? 'new'
        : widget.lead.conversionStatusRaw.trim().toLowerCase();
    if (!kPipelineConversionStages.contains(_status)) {
      _status = 'new';
    }
    _unitId = widget.lead.unitId ?? '';
    _notes = TextEditingController(text: widget.lead.notes ?? '');
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _applyStatus(String v) async {
    setState(() => _status = v);
    try {
      await context.read<ProjectRepository>().updateLeadConversionStatus(
            projectId: widget.projectId,
            leadId: widget.lead.id,
            statusRaw: v,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pipeline status updated')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _applyUnit(String? newId) async {
    final id = newId ?? '';
    setState(() => _unitId = id);
    try {
      await context.read<ProjectRepository>().assignLeadToUnit(
            projectId: widget.projectId,
            leadId: widget.lead.id,
            unitId: id,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unit assignment updated')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _saveNotes() async {
    setState(() => _savingNotes = true);
    try {
      await context.read<ProjectRepository>().updateLeadNotes(
            projectId: widget.projectId,
            leadId: widget.lead.id,
            notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Notes saved')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _savingNotes = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lead = widget.lead;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Lead detail',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 16),
              Text('Lead', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              _Labeled('Name', lead.name),
              _Labeled('Email', lead.email),
              if (lead.phone != null && lead.phone!.trim().isNotEmpty)
                _Labeled('Phone', lead.phone!),
              const SizedBox(height: 16),
              Text(
                'Sales pipeline',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _status,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Status',
                ),
                items: [
                  for (final s in kPipelineConversionStages)
                    DropdownMenuItem(
                      value: s,
                      child: Text(
                        s[0].toUpperCase() + s.substring(1),
                      ),
                    ),
                ],
                onChanged: (v) {
                  if (v != null) _applyStatus(v);
                },
              ),
              const SizedBox(height: 16),
              Text(
                'Assign unit',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _unitId.isEmpty
                    ? ''
                    : widget.units.any((u) => u.id == _unitId)
                        ? _unitId
                        : '',
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Unit',
                ),
                items: [
                  const DropdownMenuItem(value: '', child: Text('Not assigned')),
                  ...widget.units.map(
                    (u) => DropdownMenuItem(
                      value: u.id,
                      child: Text('${u.unitNumber} • ${u.status.title}'),
                    ),
                  ),
                ],
                onChanged: (v) => _applyUnit(v),
              ),
              const SizedBox(height: 16),
              Text('Notes', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              TextField(
                controller: _notes,
                maxLines: 4,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Add notes',
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _savingNotes ? null : _saveNotes,
                child: _savingNotes
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save notes'),
              ),
              SizedBox(height: cs.brightness == Brightness.dark ? 8 : 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _Labeled extends StatelessWidget {
  const _Labeled(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}
