import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/development_team_role.dart';
import '../../models/development_unit_model.dart';
import '../../models/project_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/user_role_provider.dart';
import '../../repositories/project_repository.dart';
import '../../utils/effective_development_role.dart';
import '../../utils/team_access_permissions.dart';

/// Parity with iOS `DevelopmentInventoryView` — manage per-unit rows under `developments/{id}/units`.
class DevelopmentInventoryScreen extends StatelessWidget {
  const DevelopmentInventoryScreen({super.key, required this.projectId});

  final String projectId;

  @override
  Widget build(BuildContext context) {
    final repo = context.read<ProjectRepository>();
    final auth = context.watch<AuthProvider>();
    final userRole = context.watch<UserRoleProvider>();
    final uid = auth.user?.uid;

    return StreamBuilder<ProjectModel?>(
      stream: repo.watchProject(projectId),
      builder: (context, projectSnap) {
        final project = projectSnap.data;
        if (projectSnap.hasError) {
          return Scaffold(
            appBar: AppBar(title: const Text('Inventory')),
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
            appBar: AppBar(title: const Text('Inventory')),
            body: const Center(child: Text('Sign in to manage inventory.')),
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
            final canManage = userRole.isAdmin ||
                TeamAccessPermissions.canEditUnits(effective);

            return _InventoryBody(
              project: project,
              canManage: canManage,
            );
          },
        );
      },
    );
  }
}

enum _UnitFilter { all, available, reserved, sold }

class _InventoryBody extends StatefulWidget {
  const _InventoryBody({
    required this.project,
    required this.canManage,
  });

  final ProjectModel project;
  final bool canManage;

  @override
  State<_InventoryBody> createState() => _InventoryBodyState();
}

class _InventoryBodyState extends State<_InventoryBody> {
  _UnitFilter _filter = _UnitFilter.all;

  Future<void> _pickStatus(
    BuildContext context,
    DevelopmentUnitModel unit,
  ) async {
    final repo = context.read<ProjectRepository>();
    final chosen = await showModalBottomSheet<DevelopmentUnitStatus>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('Available'),
              onTap: () =>
                  Navigator.pop(ctx, DevelopmentUnitStatus.available),
            ),
            ListTile(
              title: const Text('Reserved'),
              onTap: () =>
                  Navigator.pop(ctx, DevelopmentUnitStatus.reserved),
            ),
            ListTile(
              title: const Text('Sold'),
              onTap: () => Navigator.pop(ctx, DevelopmentUnitStatus.sold),
            ),
          ],
        ),
      ),
    );
    if (chosen == null || !context.mounted) return;
    try {
      await repo.updateDevelopmentUnitStatus(
        developmentId: widget.project.firestoreDocumentId,
        unitId: unit.id,
        status: chosen,
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.read<ProjectRepository>();

    return Scaffold(
      appBar: AppBar(title: const Text('Manage inventory')),
      floatingActionButton: widget.canManage
          ? FloatingActionButton.extended(
              icon: const Icon(Icons.add),
              label: const Text('Add Unit'),
              onPressed: () => showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                builder: (_) => _AddUnitSheet(
                  project: widget.project,
                  repo: repo,
                ),
              ),
            )
          : null,
      body: StreamBuilder<List<DevelopmentUnitModel>>(
        stream: repo.watchDevelopmentUnits(widget.project.firestoreDocumentId),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text(snapshot.error.toString()));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final units = snapshot.data!;
          if (units.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'No inventory rows yet. On iOS, inventory can be generated from unit types or added when you edit the project.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
            );
          }

          final available =
              units.where((u) => u.status == DevelopmentUnitStatus.available).length;
          final reserved =
              units.where((u) => u.status == DevelopmentUnitStatus.reserved).length;
          final sold =
              units.where((u) => u.status == DevelopmentUnitStatus.sold).length;

          List<DevelopmentUnitModel> filtered = units;
          switch (_filter) {
            case _UnitFilter.all:
              break;
            case _UnitFilter.available:
              filtered =
                  units.where((u) => u.status == DevelopmentUnitStatus.available).toList();
              break;
            case _UnitFilter.reserved:
              filtered =
                  units.where((u) => u.status == DevelopmentUnitStatus.reserved).toList();
              break;
            case _UnitFilter.sold:
              filtered =
                  units.where((u) => u.status == DevelopmentUnitStatus.sold).toList();
              break;
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                widget.project.projectName,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
              ),
              const SizedBox(height: 12),
              SegmentedButton<_UnitFilter>(
                segments: const [
                  ButtonSegment(value: _UnitFilter.all, label: Text('All')),
                  ButtonSegment(
                      value: _UnitFilter.available, label: Text('Avail.')),
                  ButtonSegment(
                      value: _UnitFilter.reserved, label: Text('Res.')),
                  ButtonSegment(value: _UnitFilter.sold, label: Text('Sold')),
                ],
                selected: {_filter},
                onSelectionChanged: (s) {
                  setState(() => _filter = s.first);
                },
              ),
              const SizedBox(height: 16),
              _StatRow(
                  label: 'Total', value: '${units.length}', icon: Icons.apartment),
              _StatRow(
                label: 'Available',
                value: '$available',
                icon: Icons.check_circle_outline,
                color: Colors.green.shade700,
              ),
              _StatRow(
                label: 'Reserved',
                value: '$reserved',
                icon: Icons.schedule,
                color: Colors.orange.shade800,
              ),
              _StatRow(
                label: 'Sold',
                value: '$sold',
                icon: Icons.sell_outlined,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 16),
              ...filtered.map((u) {
                final price =
                    NumberFormat.simpleCurrency(name: 'USD').format(u.price);
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    title: Text(
                      u.unitNumber,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text('${u.type} · $price'),
                    trailing: Chip(
                      label: Text(u.status.title),
                      visualDensity: VisualDensity.compact,
                    ),
                    onTap: widget.canManage
                        ? () => _pickStatus(context, u)
                        : null,
                  ),
                );
              }),
            ],
          );
        },
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({
    required this.label,
    required this.value,
    required this.icon,
    this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            icon,
            size: 20,
            color: color ??
                Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
          ),
        ],
      ),
    );
  }
}

// ─── Add Unit Sheet (mirrors iOS AddUnitView) ─────────────────────────────────

class _AddUnitSheet extends StatefulWidget {
  const _AddUnitSheet({required this.project, required this.repo});
  final ProjectModel project;
  final ProjectRepository repo;

  @override
  State<_AddUnitSheet> createState() => _AddUnitSheetState();
}

class _AddUnitSheetState extends State<_AddUnitSheet> {
  final _unitNumberCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  String _unitType = 'Apartment';
  bool _submitting = false;

  static const _legacyTypes = ['Apartment', 'Lot', 'House', 'Studio', 'Penthouse'];

  bool get _canSubmit {
    final num = _unitNumberCtrl.text.trim();
    final price = double.tryParse(_priceCtrl.text.trim());
    return num.isNotEmpty && price != null && price > 0;
  }

  @override
  void dispose() {
    _unitNumberCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() => _submitting = true);
    try {
      await widget.repo.addDevelopmentUnit(
        developmentId: widget.project.firestoreDocumentId,
        unitNumber: _unitNumberCtrl.text.trim(),
        unitType: _unitType,
        price: double.parse(_priceCtrl.text.trim()),
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Add Unit',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: (_canSubmit && !_submitting) ? _submit : null,
                child: _submitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('Add'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _unitNumberCtrl,
            decoration: const InputDecoration(
              labelText: 'Unit Number (e.g. A101, Lot 5)',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _unitType,
            decoration: const InputDecoration(
              labelText: 'Unit Type',
              border: OutlineInputBorder(),
            ),
            items: _legacyTypes
                .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                .toList(),
            onChanged: (v) => setState(() => _unitType = v ?? _unitType),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _priceCtrl,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Price',
              prefixText: '\$',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
    );
  }
}
