import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../constants/development_editor_catalog.dart';
import '../../models/development_team_role.dart';
import '../../models/project_model.dart';
import '../../models/project_unit_type_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/user_role_provider.dart';
import '../../repositories/project_repository.dart';
import '../../utils/effective_development_role.dart';
import '../../utils/team_access_permissions.dart';

/// Aligns with iOS `ProjectEditorView` — top-level `projects/{id}` fields (URLs as lines; no Storage upload).
class EditDevelopmentScreen extends StatefulWidget {
  const EditDevelopmentScreen({
    super.key,
    required this.projectId,
    this.isCreating = false,
  });

  final String projectId;

  /// When true the screen was opened to create a new development (modal sheet).
  /// Affects the AppBar title and is used to show "New development" instead of "Edit development".
  final bool isCreating;

  @override
  State<EditDevelopmentScreen> createState() => _EditDevelopmentScreenState();
}

class _UnitTypeForm {
  _UnitTypeForm({required this.id})
      : name = TextEditingController(),
        bedrooms = TextEditingController(),
        bathrooms = TextEditingController(),
        price = TextEditingController(),
        currency = TextEditingController(),
        sqft = TextEditingController(),
        totalUnits = TextEditingController(),
        availableUnits = TextEditingController(),
        interiorUrls = TextEditingController(),
        floorUrls = TextEditingController();

  final String id;
  final TextEditingController name;
  final TextEditingController bedrooms;
  final TextEditingController bathrooms;
  final TextEditingController price;
  final TextEditingController currency;
  final TextEditingController sqft;
  final TextEditingController totalUnits;
  final TextEditingController availableUnits;
  final TextEditingController interiorUrls;
  final TextEditingController floorUrls;

  factory _UnitTypeForm.fromModel(ProjectUnitTypeModel u) {
    final f = _UnitTypeForm(id: u.id);
    f.name.text = u.name ?? '';
    f.bedrooms.text = '${u.bedrooms}';
    f.bathrooms.text = '${u.bathrooms}';
    f.price.text = '${u.price}';
    f.currency.text = u.currencyCode ?? '';
    f.sqft.text = u.squareFootage?.toString() ?? '';
    f.totalUnits.text = u.totalUnits?.toString() ?? '';
    f.availableUnits.text = u.availableUnits?.toString() ?? '';
    f.interiorUrls.text = u.imageURLs.join('\n');
    f.floorUrls.text = u.floorPlanImageURLs.join('\n');
    return f;
  }

  void dispose() {
    name.dispose();
    bedrooms.dispose();
    bathrooms.dispose();
    price.dispose();
    currency.dispose();
    sqft.dispose();
    totalUnits.dispose();
    availableUnits.dispose();
    interiorUrls.dispose();
    floorUrls.dispose();
  }

  Map<String, dynamic> toFirestoreMap() {
    final map = <String, dynamic>{
      'id': id,
      'bedrooms': int.tryParse(bedrooms.text.trim()) ?? 0,
      'bathrooms': int.tryParse(bathrooms.text.trim()) ?? 0,
      'price': double.tryParse(price.text.trim()) ?? 0.0,
    };
    final n = name.text.trim();
    if (n.isNotEmpty) map['name'] = n;
    final c = currency.text.trim();
    if (c.isNotEmpty) map['currencyCode'] = c;
    final imgs = _linesToUrlList(interiorUrls.text);
    if (imgs.isNotEmpty) map['imageURLs'] = imgs;
    final floors = _linesToUrlList(floorUrls.text);
    if (floors.isNotEmpty) map['floorPlanImageURLs'] = floors;
    final sq = int.tryParse(sqft.text.trim());
    if (sq != null) map['squareFootage'] = sq;
    final tu = int.tryParse(totalUnits.text.trim());
    if (tu != null) map['totalUnits'] = tu;
    final au = int.tryParse(availableUnits.text.trim());
    if (au != null) map['availableUnits'] = au;
    return map;
  }
}

List<String> _linesToUrlList(String text) {
  return text
      .split('\n')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
}

class _EditDevelopmentScreenState extends State<EditDevelopmentScreen> {
  final _projectName = TextEditingController();
  final _developerName = TextEditingController();
  final _developerId = TextEditingController();
  final _location = TextEditingController();
  final _totalUnits = TextEditingController();
  final _description = TextEditingController();
  final _lifestyle = TextEditingController();
  final _heroUrls = TextEditingController();
  final _sitePlanUrls = TextEditingController();
  final _floorPlanUrls = TextEditingController();
  final _contactPerson = TextEditingController();
  final _contactPhone = TextEditingController();
  final _contactEmail = TextEditingController();

  final List<_UnitTypeForm> _unitForms = [];

  Set<String> _selectedAmenities = {};
  Set<String> _selectedFeatureKeys = {};
  String _statusRaw = 'planning';
  bool _isActive = true;
  bool _expiresEnabled = false;
  DateTime? _expiresAt;

  bool _seeded = false;
  bool _saving = false;

  @override
  void dispose() {
    _projectName.dispose();
    _developerName.dispose();
    _developerId.dispose();
    _location.dispose();
    _totalUnits.dispose();
    _description.dispose();
    _lifestyle.dispose();
    _heroUrls.dispose();
    _sitePlanUrls.dispose();
    _floorPlanUrls.dispose();
    _contactPerson.dispose();
    _contactPhone.dispose();
    _contactEmail.dispose();
    for (final f in _unitForms) {
      f.dispose();
    }
    super.dispose();
  }

  void _applyProject(ProjectModel p) {
    _projectName.text = p.projectName;
    _developerName.text = p.developerName;
    _developerId.text = p.developerId;
    _location.text = p.location;
    _totalUnits.text = p.totalUnits?.toString() ?? '';
    _description.text = p.description;
    _lifestyle.text = p.lifestyleFeatures ?? '';
    _heroUrls.text = p.heroImages.join('\n');
    _sitePlanUrls.text = p.sitePlanImageURLs.join('\n');
    _floorPlanUrls.text = p.floorPlanImageURLs.join('\n');
    _contactPerson.text = p.contactPerson ?? '';
    _contactPhone.text = p.contactPhone ?? '';
    _contactEmail.text = p.contactEmail ?? '';

    _selectedAmenities = Set<String>.from(p.amenities);
    _selectedFeatureKeys = Set<String>.from(p.developmentFeatureTypes);

    final known =
        DevelopmentEditorCatalog.projectStatuses.map((e) => e.raw).toSet();
    _statusRaw = known.contains(p.statusRaw)
        ? p.statusRaw
        : (p.statusRaw.isNotEmpty ? p.statusRaw : 'planning');

    _isActive = p.isActive;
    _expiresEnabled = p.expiresAt != null;
    _expiresAt = p.expiresAt ?? DateTime.now().add(const Duration(days: 30));

    for (final f in _unitForms) {
      f.dispose();
    }
    _unitForms.clear();
    for (final u in p.unitTypes) {
      _unitForms.add(_UnitTypeForm.fromModel(u));
    }
  }

  void _addUnitType() {
    setState(() {
      _unitForms.add(
        _UnitTypeForm(id: 'ut_${DateTime.now().microsecondsSinceEpoch}'),
      );
    });
  }

  void _removeUnitType(int index) {
    setState(() {
      _unitForms[index].dispose();
      _unitForms.removeAt(index);
    });
  }

  /// Clones a unit type's fields into a new one inserted right after it —
  /// mirrors iOS `UnitTypeEditorCard.onDuplicate`, for quickly adding near-
  /// identical layouts (e.g. "1BR City View" → "1BR City View (Floor 2)")
  /// without re-entering every field.
  void _duplicateUnitType(int index) {
    final source = _unitForms[index];
    final copy =
        _UnitTypeForm(id: 'ut_${DateTime.now().microsecondsSinceEpoch}')
          ..name.text = source.name.text
          ..bedrooms.text = source.bedrooms.text
          ..bathrooms.text = source.bathrooms.text
          ..price.text = source.price.text
          ..currency.text = source.currency.text
          ..sqft.text = source.sqft.text
          ..totalUnits.text = source.totalUnits.text
          ..availableUnits.text = source.availableUnits.text
          ..interiorUrls.text = source.interiorUrls.text
          ..floorUrls.text = source.floorUrls.text;
    setState(() => _unitForms.insert(index + 1, copy));
  }

  Future<void> _pickExpiryDate() async {
    final initial = _expiresAt ?? DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (d != null) {
      setState(() {
        _expiresAt = d;
        _expiresEnabled = true;
      });
    }
  }

  Future<void> _save(BuildContext context) async {
    if (_projectName.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Development name is required.')),
      );
      return;
    }
    if (_developerId.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Developer ID is required.')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final patch = <String, dynamic>{
        'projectName': _projectName.text.trim(),
        'developerName': _developerName.text.trim(),
        'developerId': _developerId.text.trim(),
        'location': _location.text.trim(),
        'description': _description.text.trim(),
        'status': _statusRaw,
        'isActive': _isActive,
        'heroImages': _linesToUrlList(_heroUrls.text),
        'sitePlanImageURLs': _linesToUrlList(_sitePlanUrls.text),
        'floorPlanImageURLs': _linesToUrlList(_floorPlanUrls.text),
        'amenities': _selectedAmenities.toList()..sort(),
        'developmentFeatureTypes': _selectedFeatureKeys.toList()..sort(),
        'unitTypes': _unitForms.map((f) => f.toFirestoreMap()).toList(),
      };

      if (_lifestyle.text.trim().isEmpty) {
        patch['lifestyleFeatures'] = FieldValue.delete();
      } else {
        patch['lifestyleFeatures'] = _lifestyle.text.trim();
      }

      final tu = int.tryParse(_totalUnits.text.trim());
      if (tu != null) {
        patch['totalUnits'] = tu;
      } else {
        patch['totalUnits'] = FieldValue.delete();
      }

      void optContact(String key, String value) {
        if (value.isEmpty) {
          patch[key] = FieldValue.delete();
        } else {
          patch[key] = value;
        }
      }

      optContact('contactPerson', _contactPerson.text.trim());
      optContact('contactPhone', _contactPhone.text.trim());
      optContact('contactEmail', _contactEmail.text.trim());

      if (_expiresEnabled && _expiresAt != null) {
        patch['expiresAt'] = Timestamp.fromDate(_expiresAt!);
      } else {
        patch['expiresAt'] = FieldValue.delete();
      }

      await context.read<ProjectRepository>().mergeProjectFields(
            widget.projectId,
            patch,
          );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Saved')),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _sectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
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
    final title =
        Text(widget.isCreating ? 'New development' : 'Edit development');

    if (uid == null) {
      return Scaffold(
        appBar: AppBar(title: title),
        body: const Center(child: Text('Sign in to edit this development.')),
      );
    }

    return StreamBuilder<ProjectModel?>(
      stream: repo.watchProject(widget.projectId),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(title: title),
            body: Center(child: Text(snapshot.error.toString())),
          );
        }
        if (!snapshot.hasData) {
          return Scaffold(
            appBar: AppBar(title: title),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        final p = snapshot.data;
        if (p == null) {
          return Scaffold(
            appBar: AppBar(title: title),
            body: const Center(child: Text('Project not found.')),
          );
        }
        if (!_seeded) {
          _applyProject(p);
          _seeded = true;
        }

        // Only the development's Owner/Manager (or an app admin) may edit
        // it — this screen and its route previously had no access check at
        // all, so any signed-in user who knew/guessed a project id could
        // deep-link straight here and overwrite arbitrary fields via
        // mergeProjectFields. Same permission the toolbar already uses to
        // decide whether to even show the "Edit" button
        // (project_detail_screen.dart's _ToolbarPermissions.resolve).
        return StreamBuilder<DevelopmentTeamRole?>(
          stream: repo.watchMyTeamRole(p.firestoreDocumentId, uid),
          builder: (context, roleSnap) {
            final effective = resolveEffectiveDevelopmentRole(
              isAppAdmin: userRole.isAdmin,
              currentUserId: uid,
              project: p,
              firestoreTeamDocRole: roleSnap.data,
            );
            final canManage = userRole.isAdmin ||
                TeamAccessPermissions.canEditUnits(effective);
            // Don't flash "no permission" while the team role / admin flag
            // are still resolving.
            if (!canManage &&
                (roleSnap.connectionState == ConnectionState.waiting ||
                    !userRole.adminRoleResolved)) {
              return Scaffold(
                appBar: AppBar(title: title),
                body: const Center(child: CircularProgressIndicator()),
              );
            }
            if (!canManage) {
              return Scaffold(
                appBar: AppBar(title: title),
                body: const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      "You don't have permission to edit this development.",
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              );
            }

            final catalogAmenitySet =
                DevelopmentEditorCatalog.amenities.toSet();
            final extraAmenities = p.amenities
                .where((a) => !catalogAmenitySet.contains(a))
                .toSet();

            final catalogFeatureKeys = DevelopmentEditorCatalog
                .developmentFeatureTypes
                .map((e) => e.key)
                .toSet();
            final extraFeatures = p.developmentFeatureTypes
                .where((k) => !catalogFeatureKeys.contains(k))
                .toList();

            return Scaffold(
              appBar: AppBar(
                title: title,
                actions: [
                  TextButton(
                    onPressed: _saving ? null : () => _save(context),
                    child: _saving
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Save'),
                  ),
                ],
              ),
              body: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                children: [
                  _sectionTitle(context, 'Basic info'),
                  TextField(
                    controller: _projectName,
                    decoration: const InputDecoration(
                      labelText: 'Development name',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _developerName,
                    decoration: const InputDecoration(
                      labelText: 'Developer / company name',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _developerId,
                    decoration: const InputDecoration(
                      labelText: 'Developer ID',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _location,
                    decoration: const InputDecoration(
                      labelText: 'Location',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _totalUnits,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Total units (optional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Development types',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ...DevelopmentEditorCatalog.developmentFeatureTypes.map(
                        (e) {
                          final on = _selectedFeatureKeys.contains(e.key);
                          return FilterChip(
                            label: Text(e.label),
                            selected: on,
                            onSelected: (v) {
                              setState(() {
                                if (v) {
                                  _selectedFeatureKeys.add(e.key);
                                } else {
                                  _selectedFeatureKeys.remove(e.key);
                                }
                              });
                            },
                          );
                        },
                      ),
                      ...extraFeatures.map(
                        (key) {
                          final on = _selectedFeatureKeys.contains(key);
                          return FilterChip(
                            label: Text('$key (custom)'),
                            selected: on,
                            onSelected: (v) {
                              setState(() {
                                if (v) {
                                  _selectedFeatureKeys.add(key);
                                } else {
                                  _selectedFeatureKeys.remove(key);
                                }
                              });
                            },
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Development status',
                      border: OutlineInputBorder(),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        value: _statusRaw,
                        items: [
                          ...DevelopmentEditorCatalog.projectStatuses.map(
                            (e) => DropdownMenuItem(
                              value: e.raw,
                              child: Text(e.label),
                            ),
                          ),
                          if (!DevelopmentEditorCatalog.projectStatuses
                              .any((e) => e.raw == _statusRaw))
                            DropdownMenuItem(
                              value: _statusRaw,
                              child: Text(_statusRaw),
                            ),
                        ],
                        onChanged: (v) {
                          if (v != null) setState(() => _statusRaw = v);
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    title: const Text('Active listing'),
                    value: _isActive,
                    onChanged: (v) => setState(() => _isActive = v),
                  ),
                  SwitchListTile(
                    title: const Text('Expiry date'),
                    subtitle: _expiresEnabled && _expiresAt != null
                        ? Text(
                            MaterialLocalizations.of(context).formatFullDate(
                              _expiresAt!,
                            ),
                          )
                        : const Text('No expiry'),
                    value: _expiresEnabled,
                    onChanged: (v) {
                      setState(() {
                        _expiresEnabled = v;
                        if (v && _expiresAt == null) {
                          _expiresAt =
                              DateTime.now().add(const Duration(days: 30));
                        }
                      });
                    },
                  ),
                  if (_expiresEnabled)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: _pickExpiryDate,
                        icon: const Icon(Icons.calendar_today, size: 18),
                        label: const Text('Choose expiry date'),
                      ),
                    ),
                  _sectionTitle(context, 'Description'),
                  TextField(
                    controller: _description,
                    maxLines: 6,
                    decoration: const InputDecoration(
                      labelText: 'Overview',
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _lifestyle,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Lifestyle features',
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                  _sectionTitle(context, 'Amenities'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ...DevelopmentEditorCatalog.amenities.map((a) {
                        final on = _selectedAmenities.contains(a);
                        return FilterChip(
                          label: Text(a),
                          selected: on,
                          onSelected: (v) {
                            setState(() {
                              if (v) {
                                _selectedAmenities.add(a);
                              } else {
                                _selectedAmenities.remove(a);
                              }
                            });
                          },
                        );
                      }),
                      ...extraAmenities.map((a) {
                        final on = _selectedAmenities.contains(a);
                        return FilterChip(
                          label: Text('$a (custom)'),
                          selected: on,
                          onSelected: (v) {
                            setState(() {
                              if (v) {
                                _selectedAmenities.add(a);
                              } else {
                                _selectedAmenities.remove(a);
                              }
                            });
                          },
                        );
                      }),
                    ],
                  ),
                  _sectionTitle(context, 'Media URLs'),
                  Text(
                    'One URL per line (same as pasting into Firestore). Uploads from the iOS app still apply there.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _heroUrls,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      labelText: 'Hero images',
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _sitePlanUrls,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Site plan images',
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _floorPlanUrls,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Floor plan images',
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                  _sectionTitle(context, 'Unit types'),
                  Text(
                    'Edit catalog layouts (pricing, counts, optional gallery URLs).',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 8),
                  ...List.generate(_unitForms.length, (index) {
                    final f = _unitForms[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Unit type ${index + 1}',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.copy_outlined),
                                  onPressed: () => _duplicateUnitType(index),
                                  tooltip: 'Duplicate',
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: () => _removeUnitType(index),
                                  tooltip: 'Remove',
                                ),
                              ],
                            ),
                            TextField(
                              controller: f.name,
                              decoration: const InputDecoration(
                                labelText: 'Label (e.g. 1BR City View)',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: f.bedrooms,
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(
                                      labelText: 'Beds',
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextField(
                                    controller: f.bathrooms,
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(
                                      labelText: 'Baths',
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  flex: 2,
                                  child: TextField(
                                    controller: f.price,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                    decoration: const InputDecoration(
                                      labelText: 'Price',
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextField(
                                    controller: f.currency,
                                    decoration: const InputDecoration(
                                      labelText: 'Currency',
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: f.sqft,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Sq ft (optional)',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: f.totalUnits,
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(
                                      labelText: 'Total units',
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextField(
                                    controller: f.availableUnits,
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(
                                      labelText: 'Available',
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: f.interiorUrls,
                              maxLines: 3,
                              decoration: const InputDecoration(
                                labelText: 'Interior image URLs (one per line)',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: f.floorUrls,
                              maxLines: 3,
                              decoration: const InputDecoration(
                                labelText: 'Floor plan URLs (one per line)',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                  OutlinedButton.icon(
                    onPressed: _addUnitType,
                    icon: const Icon(Icons.add),
                    label: const Text('Add unit type'),
                  ),
                  _sectionTitle(context, 'Contact'),
                  TextField(
                    controller: _contactPerson,
                    decoration: const InputDecoration(
                      labelText: 'Contact name',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _contactPhone,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Phone',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _contactEmail,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
