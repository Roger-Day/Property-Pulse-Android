import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/development_team_role.dart';
import '../../models/project_model.dart';
import '../../repositories/project_repository.dart';

/// Parity with iOS [InviteView]: sections, footers, presets, toolbar Send/Cancel.
class InviteTeammateScreen extends StatefulWidget {
  const InviteTeammateScreen({
    super.key,
    required this.project,
    required this.invitedBy,
    required this.ownerId,
  });

  final ProjectModel project;
  final String invitedBy;
  final String ownerId;

  /// Same rule as iOS `InviteView.isEmailValid`.
  static bool isEmailValid(String raw) {
    final trimmed = raw.trim();
    return trimmed.contains('@') && trimmed.contains('.');
  }

  @override
  State<InviteTeammateScreen> createState() => _InviteTeammateScreenState();
}

class _InviteTeammateScreenState extends State<InviteTeammateScreen> {
  final _emailController = TextEditingController();
  final _jobTitleController = TextEditingController();
  DevelopmentTeamRole _selectedRole = DevelopmentTeamRole.manager;

  @override
  void initState() {
    super.initState();
    _emailController.addListener(_onFieldChanged);
    _jobTitleController.addListener(_onFieldChanged);
  }

  void _onFieldChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _emailController.removeListener(_onFieldChanged);
    _jobTitleController.removeListener(_onFieldChanged);
    _emailController.dispose();
    _jobTitleController.dispose();
    super.dispose();
  }

  Future<void> _sendInvite() async {
    final email = _emailController.text.trim();
    if (!InviteTeammateScreen.isEmailValid(email)) return;

    final messenger = ScaffoldMessenger.maybeOf(context);
    final repo = context.read<ProjectRepository>();
    final title = _jobTitleController.text.trim();
    final roleTitle = title.isEmpty
        ? null
        : (title.length > 120 ? title.substring(0, 120) : title);

    Navigator.of(context).pop();

    try {
      await repo.createTeamInvite(
        developmentId: widget.project.firestoreDocumentId,
        email: email,
        role: _selectedRole,
        roleTitle: roleTitle,
        invitedByUserId: widget.invitedBy,
        developmentDisplayName: widget.project.projectName,
        ownerUserId: widget.ownerId,
      );
      messenger?.showSnackBar(
        const SnackBar(content: Text('Invite sent')),
      );
    } catch (e) {
      messenger?.showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  void _applyPreset(DevelopmentTeamRole role, String jobTitle) {
    setState(() {
      _selectedRole = role;
      _jobTitleController.text = jobTitle;
    });
  }

  void _clearJobTitle() {
    setState(() => _jobTitleController.clear());
  }

  @override
  Widget build(BuildContext context) {
    final canSend = InviteTeammateScreen.isEmailValid(_emailController.text);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        leading: TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        leadingWidth: 88,
        title: const Text('Invite teammate'),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: canSend ? _sendInvite : null,
            child: const Text('Send invite'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          _sectionHeader(context, 'Team member'),
          TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            textCapitalization: TextCapitalization.none,
            decoration: const InputDecoration(
              labelText: 'Email',
              border: OutlineInputBorder(),
            ),
          ),
          _sectionFooter(
            context,
            'They must sign in with this email to accept. You can invite as many '
            'teammates as you need—there is no cap.',
          ),
          const SizedBox(height: 16),
          _sectionHeader(context, 'Access level'),
          InputDecorator(
            decoration: const InputDecoration(
              labelText: 'Permission',
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<DevelopmentTeamRole>(
                value: _selectedRole,
                isExpanded: true,
                items: DevelopmentTeamRole.invitableRoles
                    .map(
                      (r) => DropdownMenuItem(
                        value: r,
                        child: Text(r.title),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _selectedRole = v);
                },
              ),
            ),
          ),
          _sectionFooter(
            context,
            'Manager: edit units and bookings. Sales: handle inquiries (no unit edits). '
            'Viewer: see the project as team only.',
          ),
          const SizedBox(height: 16),
          _sectionHeader(context, 'How they appear'),
          TextField(
            controller: _jobTitleController,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Job title (optional)',
              border: OutlineInputBorder(),
            ),
          ),
          _sectionFooter(
            context,
            'Examples: Coordinator, VP Sales, Marketing. This is only a label—the '
            'access level above controls what they can do.',
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: PopupMenuButton<String>(
              onSelected: (value) {
                switch (value) {
                  case 'coord':
                    _applyPreset(DevelopmentTeamRole.manager, 'Coordinator');
                  case 'ops':
                    _applyPreset(DevelopmentTeamRole.manager, 'Operations');
                  case 'mkt':
                    _applyPreset(DevelopmentTeamRole.sales, 'Marketing');
                  case 'agent':
                    _applyPreset(DevelopmentTeamRole.sales, 'Listing agent');
                  case 'clear':
                    _clearJobTitle();
                }
              },
              itemBuilder: (ctx) => [
                const PopupMenuItem(
                  value: 'coord',
                  child: Text('Coordinator'),
                ),
                const PopupMenuItem(
                  value: 'ops',
                  child: Text('Operations'),
                ),
                const PopupMenuItem(
                  value: 'mkt',
                  child: Text('Marketing'),
                ),
                const PopupMenuItem(
                  value: 'agent',
                  child: Text('Listing agent'),
                ),
                PopupMenuDivider(
                  color: scheme.outlineVariant.withValues(alpha: 0.5),
                ),
                const PopupMenuItem(
                  value: 'clear',
                  child: Text('Clear custom title'),
                ),
              ],
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.label_outline, size: 20, color: scheme.primary),
                    const SizedBox(width: 8),
                    Text(
                      'Apply label preset',
                      style: TextStyle(
                        color: scheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.arrow_drop_down, color: scheme.primary),
                  ],
                ),
              ),
            ),
          ),
          _sectionFooter(
            context,
            'Presets fill the job title field—you can edit the text freely or type your own.',
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
        ),
      ),
    );
  }

  Widget _sectionFooter(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      ),
    );
  }
}
