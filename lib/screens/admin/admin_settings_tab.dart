import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../constants/app_colors.dart';
import '../../constants/app_constants.dart';
import '../../models/moderation_flags.dart';
import '../../providers/moderation_feature_flags_provider.dart';
import '../../repositories/admin_repository.dart';
import '../../utils/responsive.dart';

/// Matches iOS `AdminSettingsView`: `config/adminSettings` + `backfillExpirationFields`.
class AdminSettingsTab extends StatefulWidget {
  const AdminSettingsTab({super.key});

  @override
  State<AdminSettingsTab> createState() => _AdminSettingsTabState();
}

class _AdminSettingsTabState extends State<AdminSettingsTab> {
  bool _loading = false;

  bool _maintenanceMode = false;
  bool _allowGuestMode = true;
  double _featuredListingsLimit = 10;

  bool _backfillDryRun = true;
  double _backfillBatchLimit = 200;
  String? _backfillNextStartAfterId;
  String? _backfillLastResultSummary;
  bool _backfillRunning = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final admin = context.read<AdminRepository>();
    setState(() {
      _loading = true;
    });
    try {
      final s = await admin.fetchAdminSettings();
      if (!mounted) return;
      setState(() {
        _maintenanceMode = s.maintenanceMode;
        _allowGuestMode = s.allowGuestMode;
        _featuredListingsLimit = s.featuredListingsLimit.toDouble();
      });
    } catch (e) {
      if (mounted) _showError('$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final admin = context.read<AdminRepository>();
    setState(() {
      _loading = true;
    });
    try {
      await admin.saveAdminSettings(
        AdminRemoteSettings(
          maintenanceMode: _maintenanceMode,
          allowGuestMode: _allowGuestMode,
          featuredListingsLimit: _featuredListingsLimit.round().clamp(0, 100),
        ),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Settings saved')),
        );
      }
    } catch (e) {
      if (mounted) _showError('$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showError(String message) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Error'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _runBackfillBatch() async {
    if (_backfillRunning) return;
    final admin = context.read<AdminRepository>();
    setState(() {
      _backfillRunning = true;
    });
    try {
      final r = await admin.backfillExpirationFields(
        dryRun: _backfillDryRun,
        limit: _backfillBatchLimit.round().clamp(50, 500),
        startAfterId: _backfillNextStartAfterId,
      );
      if (!mounted) return;
      setState(() {
        _backfillNextStartAfterId = r.nextStartAfterId;
        final examined = r.examined ?? 0;
        final updated = r.updated ?? 0;
        final dry = r.dryRun ?? _backfillDryRun;
        _backfillLastResultSummary =
            '${dry ? "Dry run" : "Applied"}: examined $examined, updated $updated, nextStartAfterId: ${r.nextStartAfterId ?? "nil"}';
      });
    } catch (e) {
      if (mounted) _showError('$e');
    } finally {
      if (mounted) setState(() => _backfillRunning = false);
    }
  }

  Future<void> _runBackfillUntilDone() async {
    if (_backfillRunning) return;
    final admin = context.read<AdminRepository>();
    setState(() {
      _backfillRunning = true;
    });
    try {
      var cursor = _backfillNextStartAfterId;
      for (var batch = 1; batch <= 50; batch++) {
        final r = await admin.backfillExpirationFields(
          dryRun: _backfillDryRun,
          limit: _backfillBatchLimit.round().clamp(50, 500),
          startAfterId: cursor,
        );
        if (!mounted) return;
        final examined = r.examined ?? 0;
        final updated = r.updated ?? 0;
        final dry = r.dryRun ?? _backfillDryRun;
        setState(() {
          _backfillNextStartAfterId = r.nextStartAfterId;
          _backfillLastResultSummary =
              'Batch $batch: ${dry ? "dry run" : "applied"}, examined $examined, updated $updated, nextStartAfterId: ${r.nextStartAfterId ?? "nil"}';
        });
        if (updated == 0) break;
        if (r.nextStartAfterId == null || r.nextStartAfterId!.isEmpty) break;
        cursor = r.nextStartAfterId;
      }
    } catch (e) {
      if (mounted) _showError('$e');
    } finally {
      if (mounted) setState(() => _backfillRunning = false);
    }
  }

  void _resetBackfillCursor() {
    setState(() {
      _backfillNextStartAfterId = null;
      _backfillLastResultSummary = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: Responsive.hPadding(context, top: 12, bottom: 32),
        children: [
          Text(
            'Settings',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            'Platform configuration and maintenance (same document as iOS).',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
          const SizedBox(height: 20),
          const _SectionTitle(title: 'Platform'),
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Maintenance mode'),
                  value: _maintenanceMode,
                  onChanged: _loading
                      ? null
                      : (v) => setState(() => _maintenanceMode = v),
                ),
                SwitchListTile(
                  title: const Text('Allow guest mode'),
                  value: _allowGuestMode,
                  onChanged: _loading
                      ? null
                      : (v) => setState(() => _allowGuestMode = v),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const _SectionTitle(title: 'Listings'),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Featured limit'),
                    trailing: Text(
                      '${_featuredListingsLimit.round()}',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondary,
                          ),
                    ),
                  ),
                  Slider(
                    value: _featuredListingsLimit.clamp(0, 100),
                    min: 0,
                    max: 100,
                    divisions: 100,
                    label: '${_featuredListingsLimit.round()}',
                    onChanged: _loading
                        ? null
                        : (v) => setState(() => _featuredListingsLimit = v),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          const _SectionTitle(title: 'Content Moderation'),
          Text(
            'Part 9 — each flag rolls out independently via config/moderationFeatureFlags. '
            'Defaults to OFF; the pipeline is server-enforced so this toggle is the real switch, '
            'not just a UI hint.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                for (final flag in ModerationFlag.values)
                  _ModerationFlagTile(flag: flag),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const _SectionTitle(title: 'Admin Maintenance'),
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SwitchListTile(
                  title: const Text('Backfill (dry run)'),
                  value: _backfillDryRun,
                  onChanged: _backfillRunning
                      ? null
                      : (v) => setState(() => _backfillDryRun = v),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Expanded(child: Text('Batch limit')),
                          Text(
                            '${_backfillBatchLimit.round()}',
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                  color: AppColors.textSecondary,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ],
                      ),
                      Slider(
                        value: _backfillBatchLimit.clamp(50, 500),
                        min: 50,
                        max: 500,
                        divisions: 9,
                        label: '${_backfillBatchLimit.round()}',
                        onChanged: _backfillRunning
                            ? null
                            : (v) {
                                final n = ((v - 50) / 50).round() * 50 + 50;
                                setState(
                                  () => _backfillBatchLimit =
                                      n.clamp(50, 500).toDouble(),
                                );
                              },
                      ),
                    ],
                  ),
                ),
                if (_backfillNextStartAfterId != null &&
                    _backfillNextStartAfterId!.isNotEmpty)
                  ListTile(
                    title: const Text('Cursor'),
                    subtitle: Text(
                      _backfillNextStartAfterId!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                if (_backfillLastResultSummary != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Text(
                      _backfillLastResultSummary!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: FilledButton.tonal(
                    onPressed: _backfillRunning ? null : _runBackfillBatch,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (_backfillRunning)
                          const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        else
                          const SizedBox.shrink(),
                        if (_backfillRunning) const SizedBox(width: 10),
                        const Text('Run Backfill Batch'),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: FilledButton.tonal(
                    onPressed: _backfillRunning ? null : _runBackfillUntilDone,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (_backfillRunning)
                          const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        else
                          const SizedBox.shrink(),
                        if (_backfillRunning) const SizedBox(width: 10),
                        const Text('Run Until Done'),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: TextButton(
                    onPressed:
                        _backfillRunning ? null : _resetBackfillCursor,
                    style: TextButton.styleFrom(foregroundColor: AppColors.error),
                    child: const Text('Reset Backfill Cursor'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _loading ? null : _save,
              child: _loading
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save Settings'),
            ),
          ),
        ],
      ),
    );
  }
}

/// One row per [ModerationFlag] — reads live from
/// [ModerationFeatureFlagsProvider] and writes directly to
/// `config/moderationFeatureFlags` (allowed by the generic
/// `config/{docId}` rule: `allow write: if isAdmin()`). No repository
/// indirection needed for a single boolean field, same as how
/// `config/aiFeatureFlags` has always been edited via Console/Admin SDK —
/// this is the first in-app UI for either flags doc.
class _ModerationFlagTile extends StatefulWidget {
  const _ModerationFlagTile({required this.flag});
  final ModerationFlag flag;

  @override
  State<_ModerationFlagTile> createState() => _ModerationFlagTileState();
}

class _ModerationFlagTileState extends State<_ModerationFlagTile> {
  bool _saving = false;

  Future<void> _toggle(bool value) async {
    setState(() => _saving = true);
    try {
      await FirebaseFirestore.instance
          .collection(AppConstants.configCollection)
          .doc('moderationFeatureFlags')
          .set({widget.flag.wireValue: value}, SetOptions(merge: true));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = context.watch<ModerationFeatureFlagsProvider>().isEnabled(widget.flag);
    return SwitchListTile(
      title: Text(widget.flag.label),
      subtitle: Text(widget.flag.description),
      value: enabled,
      onChanged: _saving ? null : _toggle,
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}
