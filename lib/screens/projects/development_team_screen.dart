import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/development_team_member_model.dart';
import '../../models/development_team_role.dart';
import '../../models/project_model.dart';
import '../../models/team_member_directory_entry.dart';
import '../../providers/auth_provider.dart';
import '../../providers/user_role_provider.dart';
import '../../repositories/project_repository.dart';
import '../../utils/effective_development_role.dart';
import '../../utils/team_access_permissions.dart';
import 'invite_teammate_screen.dart';

/// Parity with iOS [TeamManagementView]: overview, hydrated roster, roles legend, invites.
class DevelopmentTeamScreen extends StatefulWidget {
  const DevelopmentTeamScreen({super.key, required this.projectId});

  final String projectId;

  @override
  State<DevelopmentTeamScreen> createState() => _DevelopmentTeamScreenState();
}

class _DevelopmentTeamScreenState extends State<DevelopmentTeamScreen> {
  Map<String, TeamMemberDirectoryEntry> _directory = {};
  String? _directoryFetchKey;
  bool _loadingDirectory = false;
  String? _busyMemberId;

  String _ownerId(ProjectModel p) =>
      p.ownerId.trim().isEmpty ? p.developerId : p.ownerId;

  String _displayName(
    DevelopmentTeamMemberModel m,
    TeamMemberDirectoryEntry? dir,
  ) {
    final n = dir?.displayName.trim() ?? '';
    if (n.isNotEmpty) return n;
    return m.userId;
  }

  String? _avatarUrl(
    DevelopmentTeamMemberModel m,
    TeamMemberDirectoryEntry? dir,
  ) {
    final custom = m.displayPhotoURL?.trim() ?? '';
    if (custom.isNotEmpty) return custom;
    final p = dir?.profileImageUrl?.trim() ?? '';
    return p.isEmpty ? null : p;
  }

  String _initials(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  bool _removalAllowed({
    required bool canManageTeam,
    required String ownerUserId,
    required DevelopmentTeamMemberModel member,
  }) {
    return canManageTeam &&
        member.userId != ownerUserId &&
        member.role != DevelopmentTeamRole.owner;
  }

  Future<void> _loadDirectory(List<DevelopmentTeamMemberModel> members) async {
    if (!mounted) return;
    setState(() => _loadingDirectory = true);
    try {
      final repo = context.read<ProjectRepository>();
      final map = await repo.fetchTeamMemberDirectory(
        members.map((m) => m.userId),
      );
      if (!mounted) return;
      setState(() {
        _directory = map;
        _loadingDirectory = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingDirectory = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load member info: $e')),
      );
    }
  }

  void _scheduleDirectoryHydration(List<DevelopmentTeamMemberModel> members) {
    final key = members.map((m) => m.userId).join('|');
    if (key == _directoryFetchKey) return;
    _directoryFetchKey = key;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadDirectory(members);
    });
  }

  Future<void> _confirmRemove({
    required ProjectModel project,
    required DevelopmentTeamMemberModel member,
    required String displayName,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove from team?'),
        content: Text(
          '$displayName will lose access to this development.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busyMemberId = member.userId);
    try {
      await context.read<ProjectRepository>().removeTeamMember(
            developmentId: project.firestoreDocumentId,
            memberUserId: member.userId,
            ownerUserId: _ownerId(project),
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Removed from team')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _busyMemberId = null);
    }
  }

  Future<void> _editJobTitle({
    required ProjectModel project,
    required DevelopmentTeamMemberModel member,
    required String displayName,
  }) async {
    final controller = TextEditingController(text: member.roleTitle ?? '');
    final tier = member.role.title;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Job title'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              displayName,
              style: Theme.of(ctx).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              'Permission tier: $tier',
              style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                    color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Custom title (optional)',
                border: OutlineInputBorder(),
              ),
              maxLength: 120,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) {
      controller.dispose();
      return;
    }
    final trimmed = controller.text.trim();
    controller.dispose();
    setState(() => _busyMemberId = member.userId);
    try {
      await context.read<ProjectRepository>().setTeamMemberRoleTitle(
            developmentId: project.firestoreDocumentId,
            memberUserId: member.userId,
            roleTitle: trimmed.isEmpty ? null : trimmed,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Job title updated')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _busyMemberId = null);
    }
  }

  Future<void> _pickTeamPhoto({
    required ProjectModel project,
    required DevelopmentTeamMemberModel member,
  }) async {
    final picker = ImagePicker();
    final x = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    if (x == null || !mounted) return;
    setState(() => _busyMemberId = member.userId);
    try {
      await context.read<ProjectRepository>().uploadTeamMemberDisplayPhoto(
            developmentId: project.firestoreDocumentId,
            memberUserId: member.userId,
            imageFile: File(x.path),
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Team photo updated')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not upload photo: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busyMemberId = null);
    }
  }

  void _showInviteSheet({
    required BuildContext context,
    required ProjectModel project,
    required String invitedBy,
  }) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (ctx) => InviteTeammateScreen(
          project: project,
          invitedBy: invitedBy,
          ownerId: _ownerId(project),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.read<ProjectRepository>();
    final auth = context.watch<AuthProvider>();
    final userRole = context.watch<UserRoleProvider>();
    final uid = auth.user?.uid;

    return StreamBuilder<ProjectModel?>(
      stream: repo.watchProject(widget.projectId),
      builder: (context, projectSnap) {
        final project = projectSnap.data;
        if (projectSnap.hasError) {
          return Scaffold(
            appBar: AppBar(title: const Text('Team')),
            body: Center(child: Text(projectSnap.error.toString())),
          );
        }
        if (!projectSnap.hasData || project == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (uid == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Team')),
            body: const Center(child: Text('Sign in to view team.')),
          );
        }

        return StreamBuilder<DevelopmentTeamRole?>(
          stream: repo.watchMyTeamRole(project.firestoreDocumentId, uid),
          builder: (context, roleSnap) {
            final effective = resolveEffectiveDevelopmentRole(
              isAppAdmin: userRole.isAdmin,
              currentUserId: uid,
              project: project,
              firestoreTeamDocRole: roleSnap.data,
            );
            final canManageTeam = userRole.isAdmin ||
                TeamAccessPermissions.canManageTeam(effective);

            return Scaffold(
              appBar: AppBar(
                title: const Text('Team'),
                actions: [
                  if (canManageTeam)
                    IconButton(
                      tooltip: 'Invite',
                      icon: const Icon(Icons.person_add_alt_1_outlined),
                      onPressed: () => _showInviteSheet(
                        context: context,
                        project: project,
                        invitedBy: uid,
                      ),
                    ),
                ],
              ),
              body: Stack(
                children: [
                  StreamBuilder<List<DevelopmentTeamMemberModel>>(
                    stream: repo.watchTeamMembers(project.firestoreDocumentId),
                    builder: (context, teamSnap) {
                      if (teamSnap.hasError) {
                        return Center(child: Text(teamSnap.error.toString()));
                      }
                      final members = teamSnap.data ?? [];
                      _scheduleDirectoryHydration(members);

                      return ListView(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                        children: [
                          if (_loadingDirectory)
                            const Padding(
                              padding: EdgeInsets.only(bottom: 8),
                              child: LinearProgressIndicator(),
                            ),
                          _sectionHeader(context, 'Overview'),
                          Card(
                            margin: EdgeInsets.zero,
                            child: Column(
                              children: [
                                ListTile(
                                  title: const Text('Development'),
                                  trailing: Text(
                                    project.projectName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                ListTile(
                                  title: const Text('Members'),
                                  trailing: Text(
                                    '${members.length}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          _sectionFooter(
                            context,
                            'There is no limit on teammates you invite. '
                            'Remove someone anytime—they lose access immediately.',
                          ),
                          const SizedBox(height: 16),
                          _sectionHeader(context, 'Team'),
                          if (!teamSnap.hasData && !teamSnap.hasError)
                            const Padding(
                              padding: EdgeInsets.all(24),
                              child: Center(child: CircularProgressIndicator()),
                            )
                          else if (members.isEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Text(
                                'No team records yet. Invites appear here after acceptance, '
                                'or sync from your legacy project team if you are the owner.',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                              ),
                            ),
                          ...members.map((m) {
                            final dir = _directory[m.userId];
                            final name = _displayName(m, dir);
                            final email = dir?.email.trim() ?? '';
                            final avatar = _avatarUrl(m, dir);
                            final busy = _busyMemberId == m.userId;
                            final canRemove = _removalAllowed(
                              canManageTeam: canManageTeam,
                              ownerUserId: _ownerId(project),
                              member: m,
                            );

                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                  horizontal: 4,
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _Avatar(
                                      url: avatar,
                                      initials: _initials(name),
                                      size: 48,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            name,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 15,
                                            ),
                                          ),
                                          if (email.isNotEmpty)
                                            Text(
                                              email,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall
                                                  ?.copyWith(
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .onSurfaceVariant,
                                                  ),
                                            ),
                                          const SizedBox(height: 4),
                                          Text(
                                            DateFormat.yMMMd()
                                                .add_jm()
                                                .format(m.createdAt),
                                            style: Theme.of(context)
                                                .textTheme
                                                .labelSmall
                                                ?.copyWith(
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .outline,
                                                ),
                                          ),
                                          Text(
                                            'Permission: ${m.role.title}',
                                            style: Theme.of(context)
                                                .textTheme
                                                .labelSmall,
                                          ),
                                        ],
                                      ),
                                    ),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          m.displayJobTitle,
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelLarge
                                              ?.copyWith(
                                                fontWeight: FontWeight.w600,
                                              ),
                                        ),
                                        if (canManageTeam) ...[
                                          const SizedBox(height: 4),
                                          if (busy)
                                            const SizedBox(
                                              width: 22,
                                              height: 22,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            )
                                          else
                                            PopupMenuButton<String>(
                                              onSelected: (v) {
                                                if (v == 'title') {
                                                  _editJobTitle(
                                                    project: project,
                                                    member: m,
                                                    displayName: name,
                                                  );
                                                } else if (v == 'photo') {
                                                  _pickTeamPhoto(
                                                    project: project,
                                                    member: m,
                                                  );
                                                } else if (v == 'remove') {
                                                  _confirmRemove(
                                                    project: project,
                                                    member: m,
                                                    displayName: name,
                                                  );
                                                }
                                              },
                                              itemBuilder: (ctx) => [
                                                const PopupMenuItem(
                                                  value: 'title',
                                                  child: Text('Edit job title'),
                                                ),
                                                const PopupMenuItem(
                                                  value: 'photo',
                                                  child: Text(
                                                    'Change team photo',
                                                  ),
                                                ),
                                                if (canRemove)
                                                  PopupMenuItem(
                                                    value: 'remove',
                                                    child: Text(
                                                      'Remove',
                                                      style: TextStyle(
                                                        color: Theme.of(ctx)
                                                            .colorScheme
                                                            .error,
                                                      ),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }),
                          _sectionFooter(
                            context,
                            'This roster is the only team list in the app. It appears on '
                            'your public profile under "Project team," merged across your developments.',
                          ),
                          const SizedBox(height: 16),
                          _sectionHeader(context, 'Roles'),
                          _legendRow(
                            context,
                            DevelopmentTeamRole.owner,
                            'Full access: team, units, pricing, and inquiries.',
                          ),
                          _legendRow(
                            context,
                            DevelopmentTeamRole.manager,
                            'Manage inventory units and view bookings / inquiries.',
                          ),
                          _legendRow(
                            context,
                            DevelopmentTeamRole.sales,
                            'Handle inquiries and leads only (no unit edits).',
                          ),
                          _legendRow(
                            context,
                            DevelopmentTeamRole.viewer,
                            'View the development as team; cannot edit inventory or handle leads.',
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _sectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
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

  Widget _legendRow(
    BuildContext context,
    DevelopmentTeamRole role,
    String text,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              role.title,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.initials,
    required this.size,
    this.url,
  });

  final String? url;
  final String initials;
  final double size;

  @override
  Widget build(BuildContext context) {
    final u = url?.trim() ?? '';
    if (u.isNotEmpty) {
      return ClipOval(
        child: CachedNetworkImage(
          imageUrl: u,
          width: size,
          height: size,
          fit: BoxFit.cover,
          placeholder: (_, __) => SizedBox(
            width: size,
            height: size,
            child: const Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
          errorWidget: (_, __, ___) => _initialsCircle(context),
        ),
      );
    }
    return _initialsCircle(context);
  }

  Widget _initialsCircle(BuildContext context) {
    return CircleAvatar(
      radius: size / 2,
      child: Text(
        initials,
        style: TextStyle(
          fontSize: size * 0.35,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
