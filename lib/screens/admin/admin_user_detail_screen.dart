import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../constants/app_colors.dart';
import '../../repositories/admin_repository.dart';

/// Mirrors iOS `AdminUserDetailView`: profile, activity counts, role/verification,
/// verified-badge callable, suspend & ban.
class AdminUserDetailScreen extends StatefulWidget {
  const AdminUserDetailScreen({
    super.key,
    required this.userId,
  });

  final String userId;

  @override
  State<AdminUserDetailScreen> createState() => _AdminUserDetailScreenState();
}

class _AdminUserDetailScreenState extends State<AdminUserDetailScreen> {
  bool _loading = true;
  String? _loadError;

  Map<String, dynamic>? _user;
  int _listingCount = 0;
  List<Map<String, dynamic>> _reportsAgainstUser = [];

  late String _role;
  late String _verificationStatus;
  late String _verificationLevel;

  bool _isBanned = false;
  bool _isSuspended = false;

  bool _saving = false;
  bool _badgeBusy = false;
  String? _badgeMsg;

  static const _roles = [
    'Admin',
    'Developer',
    'Realtor',
    'Property Owner',
    'Property Seeker',
  ];

  static const _statuses = [
    'unverified',
    'pending',
    'verified',
    'rejected',
    'expired',
    'suspended',
  ];

  static const _levels = ['basic', 'premium', 'elite'];

  @override
  void initState() {
    super.initState();
    _role = 'Property Seeker';
    _verificationStatus = 'unverified';
    _verificationLevel = 'basic';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  Future<void> _load() async {
    final admin = context.read<AdminRepository>();
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final doc = await admin.getUserDocument(widget.userId);
      final nProps = await admin.countPropertiesForUser(widget.userId);
      final reps = await admin.fetchModerationReportsForTargetUser(widget.userId);
      if (!mounted) return;
      if (doc == null) {
        setState(() {
          _loading = false;
          _loadError = 'User not found';
        });
        return;
      }
      final roleRaw = doc['role'] as String? ?? 'Property Seeker';
      _role = _roles.contains(roleRaw)
          ? roleRaw
          : _normalizeRole(roleRaw);
      _verificationStatus = _statuses.contains(doc['verificationStatus'] as String?)
          ? (doc['verificationStatus'] as String?)!
          : 'unverified';
      _verificationLevel = _levels.contains(doc['verificationLevel'] as String?)
          ? (doc['verificationLevel'] as String?)!
          : 'basic';
      setState(() {
        _user = doc;
        _listingCount = nProps;
        _reportsAgainstUser = reps;
        _isBanned = doc['isBanned'] as bool? ?? false;
        _isSuspended = doc['isSuspended'] as bool? ?? false;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadError = '$e';
          _loading = false;
        });
      }
    }
  }

  String _normalizeRole(String raw) {
    final n = raw.toLowerCase().replaceAll(' ', '');
    switch (n) {
      case 'admin':
        return 'Admin';
      case 'developer':
        return 'Developer';
      case 'realtor':
        return 'Realtor';
      case 'propertyowner':
        return 'Property Owner';
      case 'propertyseeker':
        return 'Property Seeker';
      default:
        return 'Property Seeker';
    }
  }

  bool get _dirty {
    if (_user == null) return false;
    final ur = _user!['role'] as String? ?? '';
    final uv = _user!['verificationStatus'] as String? ?? '';
    final ul = _user!['verificationLevel'] as String? ?? '';
    return _role != _normalizeRole(ur) ||
        _verificationStatus != (uv.isEmpty ? 'unverified' : uv) ||
        _verificationLevel != (ul.isEmpty ? 'basic' : ul);
  }

  Future<void> _save() async {
    final admin = context.read<AdminRepository>();
    setState(() => _saving = true);
    try {
      await admin.updateUserRoleVerification(
        userId: widget.userId,
        role: _role,
        verificationStatus: _verificationStatus,
        verificationLevel: _verificationLevel,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User updated')),
      );
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _syncBadge() async {
    final admin = context.read<AdminRepository>();
    setState(() {
      _badgeBusy = true;
      _badgeMsg = null;
    });
    try {
      final msg = await admin.adminBackfillUserVerification(widget.userId);
      if (mounted) {
        setState(() => _badgeMsg = msg ?? 'Done');
      }
    } catch (e) {
      if (mounted) setState(() => _badgeMsg = 'Error: $e');
    } finally {
      if (mounted) setState(() => _badgeBusy = false);
    }
  }

  Future<void> _toggleBan() async {
    final admin = context.read<AdminRepository>();
    try {
      await admin.setUserBanned(widget.userId, !_isBanned);
      if (!mounted) return;
      setState(() => _isBanned = !_isBanned);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_isBanned ? 'User banned' : 'Ban lifted')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _showSuspend() async {
    var days = 7;
    final reasonCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Suspend account'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<int>(
                value: days,
                decoration: const InputDecoration(labelText: 'Duration'),
                items: const [
                  DropdownMenuItem(value: 1, child: Text('1 day')),
                  DropdownMenuItem(value: 3, child: Text('3 days')),
                  DropdownMenuItem(value: 7, child: Text('7 days')),
                  DropdownMenuItem(value: 14, child: Text('14 days')),
                  DropdownMenuItem(value: 30, child: Text('30 days')),
                  DropdownMenuItem(value: 90, child: Text('90 days')),
                ],
                onChanged: (v) => setLocal(() => days = v ?? 7),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reasonCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Reason',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Apply')),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final reason = reasonCtrl.text.trim();
    if (reason.isEmpty) return;
    try {
      await context.read<AdminRepository>().suspendUser(
            userId: widget.userId,
            days: days,
            reason: reason,
          );
      if (mounted) {
        setState(() => _isSuspended = true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Suspension applied')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  void _openListingsPreview() {
    final admin = context.read<AdminRepository>();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (ctx) => _AdminUserPropertiesListRoute(
          userId: widget.userId,
          admin: admin,
        ),
      ),
    );
  }

  void _openReportsList() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (ctx) => _AdminUserModerationReportsRoute(
          reports: _reportsAgainstUser,
          userId: widget.userId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_user == null ? 'User' : '${_user!['fullName'] ?? _user!['email'] ?? 'User'}'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? Center(child: Text(_loadError!))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Text(
                        'Profile',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Name: ${_user!['fullName'] ?? '—'}'),
                              Text('Email: ${_user!['email'] ?? '—'}'),
                              Text(
                                'User ID: ${widget.userId.length > 14 ? '${widget.userId.substring(0, 12)}…' : widget.userId}',
                              ),
                              if ((_user!['region'] as String?)?.isNotEmpty ?? false)
                                Text('Region: ${_user!['region']}'),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Activity',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      Card(
                        child: Column(
                          children: [
                            ListTile(
                              leading: const Icon(Icons.apartment_outlined),
                              title: const Text('Properties listed'),
                              trailing: Text('$_listingCount'),
                              onTap: _openListingsPreview,
                            ),
                            const Divider(height: 1),
                            ListTile(
                              leading: const Icon(Icons.flag_outlined),
                              title: const Text('Reports against user'),
                              trailing: Text('${_reportsAgainstUser.length}'),
                              onTap: _openReportsList,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Role & verification',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      Card(
                        child: Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              child: DropdownButtonFormField<String>(
                                value: _role,
                                decoration: const InputDecoration(labelText: 'Role'),
                                items: _roles
                                    .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                                    .toList(),
                                onChanged: (v) => setState(() => _role = v ?? _role),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              child: DropdownButtonFormField<String>(
                                value: _verificationStatus,
                                decoration:
                                    const InputDecoration(labelText: 'Verification status'),
                                items: _statuses
                                    .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                                    .toList(),
                                onChanged: (v) =>
                                    setState(() => _verificationStatus = v ?? _verificationStatus),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              child: DropdownButtonFormField<String>(
                                value: _verificationLevel,
                                decoration:
                                    const InputDecoration(labelText: 'Verification level'),
                                items: _levels
                                    .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                                    .toList(),
                                onChanged: (v) =>
                                    setState(() => _verificationLevel = v ?? _verificationLevel),
                              ),
                            ),
                            ListTile(
                              leading: _badgeBusy
                                  ? const SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Icon(Icons.verified_outlined, color: Colors.green),
                              title: const Text('Sync verified badge to listings'),
                              subtitle: _badgeMsg != null ? Text(_badgeMsg!) : null,
                              onTap: _badgeBusy ? null : _syncBadge,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Account actions',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      Card(
                        child: Column(
                          children: [
                            ListTile(
                              leading: Icon(
                                Icons.schedule_outlined,
                                color: AppColors.warning,
                              ),
                              title: Text(_isSuspended ? 'Modify suspension' : 'Suspend account'),
                              subtitle: _isSuspended
                                  ? const Text('Account is currently suspended — tap to update')
                                  : null,
                              onTap: _showSuspend,
                            ),
                            ListTile(
                              leading: Icon(
                                Icons.block,
                                color: _isBanned ? Colors.green : Colors.red,
                              ),
                              title: Text(_isBanned ? 'Unban account' : 'Ban account'),
                              onTap: _toggleBan,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: (_saving || !_dirty) ? null : _save,
                          child: _saving
                              ? const SizedBox(
                                  height: 22,
                                  width: 22,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Text('Save changes'),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}

class _AdminUserPropertiesListRoute extends StatelessWidget {
  const _AdminUserPropertiesListRoute({
    required this.userId,
    required this.admin,
  });

  final String userId;
  final AdminRepository admin;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('User listings')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: admin.fetchPropertiesForUser(userId),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final rows = snap.data!;
          if (rows.isEmpty) {
            return const Center(child: Text('No listings found.'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: rows.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final r = rows[i];
              return ListTile(
                title: Text('${r['title']}'),
                subtitle: Text('${r['city']} · ${r['id']}'),
              );
            },
          );
        },
      ),
    );
  }
}

class _AdminUserModerationReportsRoute extends StatelessWidget {
  const _AdminUserModerationReportsRoute({
    required this.reports,
    required this.userId,
  });

  final List<Map<String, dynamic>> reports;
  final String userId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Moderation reports')),
      body: reports.isEmpty
          ? const Center(child: Text('No moderation_reports for this target ID.'))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: reports.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final r = reports[i];
                return ListTile(
                  title: Text('${r['reason'] ?? 'Report'}'),
                  subtitle: Text(
                    '${r['targetType'] ?? ''} · ${r['status'] ?? ''}\n${r['details'] ?? ''}',
                  ),
                );
              },
            ),
    );
  }
}
