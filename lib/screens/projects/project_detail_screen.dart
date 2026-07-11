import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../constants/app_colors.dart';
import '../../models/development_team_role.dart';
import '../../models/development_unit_model.dart';
import '../../models/project_model.dart';
import '../../models/project_unit_type_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/user_role_provider.dart';
import '../../repositories/project_repository.dart';
import '../../repositories/user_profile_repository.dart';
import '../../services/analytics_service.dart';
import '../../utils/effective_development_role.dart';
import '../../utils/team_access_permissions.dart';
import '../../widgets/full_screen_image_gallery.dart';

/// Development / new-build detail — parity with iOS `ProjectDetailView` sections.
class ProjectDetailScreen extends StatelessWidget {
  const ProjectDetailScreen({super.key, required this.projectId});

  final String projectId;

  @override
  Widget build(BuildContext context) {
    final repo = context.read<ProjectRepository>();

    return StreamBuilder<ProjectModel?>(
      stream: repo.watchProject(projectId),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(title: const Text('Development')),
            body: Center(child: Text(snapshot.error.toString())),
          );
        }
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final project = snapshot.data;
        if (project == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Development')),
            body: const Center(child: Text('Project not found.')),
          );
        }
        return _ProjectDetailBody(project: project);
      },
    );
  }
}

class _ToolbarPermissions {
  const _ToolbarPermissions._({
    required this.leads,
    required this.inventory,
    required this.team,
    required this.edit,
    required this.delete,
  });

  final bool leads;
  final bool inventory;
  final bool team;
  final bool edit;
  final bool delete;

  bool get showAny => leads || inventory || team || edit || delete;

  factory _ToolbarPermissions.guest() => const _ToolbarPermissions._(
        leads: false,
        inventory: false,
        team: false,
        edit: false,
        delete: false,
      );

  factory _ToolbarPermissions.resolve({
    required bool isAdmin,
    required DevelopmentTeamRole? effective,
  }) {
    return _ToolbarPermissions._(
      leads: isAdmin || TeamAccessPermissions.canHandleInquiries(effective),
      inventory: isAdmin || TeamAccessPermissions.canEditUnits(effective),
      team: isAdmin || TeamAccessPermissions.canManageTeam(effective),
      edit: isAdmin || TeamAccessPermissions.canEditUnits(effective),
      delete: isAdmin || TeamAccessPermissions.canEditUnits(effective),
    );
  }
}

Future<void> _confirmDeleteProject(
  BuildContext context,
  ProjectModel project,
) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Delete development?'),
      content: Text(
        'This removes “${project.projectName}” from Property Pulse. '
        'Subcollections may still exist until cleaned up by your backend rules.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: TextButton.styleFrom(foregroundColor: Colors.red),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  try {
    await context.read<ProjectRepository>().deleteProject(
          project.firestoreDocumentId,
        );
    if (context.mounted) {
      context.go('/home');
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }
}

class _ProjectDetailBody extends StatelessWidget {
  const _ProjectDetailBody({required this.project});

  final ProjectModel project;

  List<Widget> _toolbarActions(
    BuildContext context,
    _ToolbarPermissions p,
  ) {
    final id = project.firestoreDocumentId;
    final name = project.projectName;
    return [
      if (p.leads)
        IconButton(
          tooltip: 'Leads',
          icon: const Icon(Icons.groups_outlined),
          onPressed: () {
            context.push('/development/$id/leads', extra: name);
          },
        ),
      if (p.inventory)
        IconButton(
          tooltip: 'Manage inventory',
          icon: const Icon(Icons.grid_view),
          onPressed: () {
            context.push('/development/$id/inventory');
          },
        ),
      if (p.team)
        IconButton(
          tooltip: 'Team',
          icon: const Icon(Icons.group_add_outlined),
          onPressed: () {
            context.push('/development/$id/team');
          },
        ),
      if (p.edit)
        IconButton(
          tooltip: 'Edit',
          icon: const Icon(Icons.edit_outlined),
          onPressed: () {
            context.push('/development/$id/edit');
          },
        ),
      if (p.delete)
        IconButton(
          tooltip: 'Delete',
          icon: const Icon(Icons.delete_outline),
          color: Colors.red.shade700,
          onPressed: () => _confirmDeleteProject(context, project),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final uid = context.select<AuthProvider, String?>((a) => a.user?.uid);
    final role = context.watch<UserRoleProvider>();
    final repo = context.read<ProjectRepository>();

    final gallery = project.heroImages;
    final priceText = project.startingPrice != null
        ? NumberFormat.simpleCurrency(name: project.startingPriceCurrencyCode)
            .format(project.startingPrice)
        : 'Pricing TBA';

    final mod = project.moderationStatusRaw.trim().toLowerCase();
    final modOk = mod.isEmpty || mod == 'approved';

    final sortedUnits = List<ProjectUnitTypeModel>.from(project.unitTypes)
      ..sort((a, b) {
        if (a.bedrooms != b.bedrooms) {
          return a.bedrooms.compareTo(b.bedrooms);
        }
        if (a.bathrooms != b.bathrooms) {
          return a.bathrooms.compareTo(b.bathrooms);
        }
        return a.price.compareTo(b.price);
      });

    final scrollBody = CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: _HeroGallery(urls: gallery),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!modOk) ...[
                    _ModerationBanner(
                      status: project.moderationStatusRaw,
                      reason: project.rejectionReason,
                    ),
                    const SizedBox(height: 12),
                  ],
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _InfoChip(
                        label: projectStatusDisplayLabel(project.statusRaw),
                        icon: Icons.timeline,
                      ),
                      ...project.developmentFeatureTypes.map(
                        (k) => _InfoChip(
                          label: developmentFeatureTypeDisplayLabel(k),
                          icon: Icons.category_outlined,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    priceText,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  if (project.totalUnits != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      '${project.totalUnits} units (total)',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                  if (project.location.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.place_outlined,
                          size: 20,
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            project.location,
                            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurface,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 20),
                  Text(
                    'Developer',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 8),
                  if (project.developerId.isNotEmpty)
                    Material(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest
                          .withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(10),
                      child: InkWell(
                        onTap: () => context.push('/user/${project.developerId}'),
                        borderRadius: BorderRadius.circular(10),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.apartment_outlined,
                                size: 20,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      project.developerName.isNotEmpty
                                          ? project.developerName
                                          : project.developerId,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w600,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurface,
                                          ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'View developer profile',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .primary,
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(
                                Icons.chevron_right,
                                size: 18,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                  else
                    Text(
                      project.developerName.isNotEmpty
                          ? project.developerName
                          : '—',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                    ),
                  if (project.description.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Text(
                      'About',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      project.description,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            height: 1.45,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                    ),
                  ],
                  if (project.lifestyleFeatures != null &&
                      project.lifestyleFeatures!.trim().isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Text(
                      'Lifestyle',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      project.lifestyleFeatures!.trim(),
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            height: 1.45,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                    ),
                  ],
                  if (project.amenities.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Text(
                      'Amenities',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: project.amenities
                          .map((a) => Chip(
                                label: Text(
                                  a,
                                  style: TextStyle(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface,
                                  ),
                                ),
                                visualDensity: VisualDensity.compact,
                                backgroundColor: Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerHighest
                                    .withValues(alpha: 0.85),
                                side: BorderSide(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .outline
                                      .withValues(alpha: 0.35),
                                ),
                              ))
                          .toList(),
                    ),
                  ],
                  if (sortedUnits.isNotEmpty)
                    _AvailableUnitTypesSection(
                      project: project,
                      sortedUnits: sortedUnits,
                    ),
                  const SizedBox(height: 12),
                  _DevelopmentInventorySection(project: project),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
    );

    final appBarTitle = Text(
      project.projectName,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );

    if (uid == null) {
      final perms = _ToolbarPermissions.guest();
      return Scaffold(
        appBar: AppBar(
          title: appBarTitle,
          actions: perms.showAny ? _toolbarActions(context, perms) : null,
        ),
        body: scrollBody,
      );
    }

    return StreamBuilder<DevelopmentTeamRole?>(
      stream: repo.watchMyTeamRole(project.firestoreDocumentId, uid),
      builder: (context, snap) {
        final effective = resolveEffectiveDevelopmentRole(
          isAppAdmin: role.isAdmin,
          currentUserId: uid,
          project: project,
          firestoreTeamDocRole: snap.data,
        );
        final perms = _ToolbarPermissions.resolve(
          isAdmin: role.isAdmin,
          effective: effective,
        );
        // Seekers (non-team, non-admin) see the Register Interest CTA.
        final isSeeker = !perms.showAny;
        return Scaffold(
          appBar: AppBar(
            title: appBarTitle,
            actions: perms.showAny
                ? _toolbarActions(context, perms)
                : [
                    _FollowButton(
                      project: project,
                      userId: uid,
                    ),
                  ],
          ),
          body: scrollBody,
          bottomNavigationBar: isSeeker
              ? _RegisterInterestBar(project: project, userId: uid)
              : null,
        );
      },
    );
  }
}

class _ModerationBanner extends StatelessWidget {
  const _ModerationBanner({required this.status, this.reason});

  final String status;
  final String? reason;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.amber.shade100,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Moderation: ${status.isEmpty ? "Pending" : status}',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
            ),
            if (reason != null && reason!.trim().isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                reason!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Chip(
      avatar: Icon(icon, size: 18, color: cs.primary),
      label: Text(
        label,
        style: TextStyle(color: cs.onSurface, fontSize: 13),
      ),
      visualDensity: VisualDensity.compact,
      backgroundColor: cs.surfaceContainerHighest.withValues(alpha: 0.9),
      side: BorderSide(color: cs.outline.withValues(alpha: 0.35)),
    );
  }
}

class _HeroGallery extends StatefulWidget {
  const _HeroGallery({required this.urls});

  final List<String> urls;

  @override
  State<_HeroGallery> createState() => _HeroGalleryState();
}

class _HeroGalleryState extends State<_HeroGallery> {
  final PageController _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.sizeOf(context).height * 0.28;
    final urls = widget.urls;

    if (urls.isEmpty) {
      final cs = Theme.of(context).colorScheme;
      return SizedBox(
        height: h,
        child: Container(
          color: cs.surfaceContainerHighest,
          child: Center(
            child: Icon(
              Icons.apartment,
              size: 72,
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: h,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          PageView.builder(
            controller: _controller,
            itemCount: urls.length,
            onPageChanged: (i) => setState(() => _page = i),
            itemBuilder: (context, i) {
              final cs = Theme.of(context).colorScheme;
              return GestureDetector(
                onTap: () => FullScreenImageGallery.open(context, urls, i),
                behavior: HitTestBehavior.opaque,
                child: CachedNetworkImage(
                  imageUrl: urls[i],
                  fit: BoxFit.cover,
                  width: double.infinity,
                  // Full-width gallery: cap decode height to limit GPU memory.
                  memCacheHeight: 800,
                  placeholder: (_, __) => Container(
                    color: cs.surfaceContainerHighest,
                    child: Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: cs.primary,
                      ),
                    ),
                  ),
                  errorWidget: (_, __, ___) => Container(
                    color: cs.surfaceContainerHighest,
                    child: Icon(
                      Icons.broken_image_outlined,
                      size: 48,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
              );
            },
          ),
          if (urls.length > 1)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: RepaintBoundary(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    urls.length,
                    (i) => AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: i == _page ? 18 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        color: i == _page
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.45),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Live per-layout counts — iOS `inventoryCountsForUnitType`.
_UnitTypeInvCounts _inventoryCountsForUnitType(
  List<DevelopmentUnitModel> units,
  String unitTypeId,
) {
  final trimmed = unitTypeId.trim();
  if (trimmed.isEmpty) {
    return const _UnitTypeInvCounts(available: 0, reserved: 0, sold: 0);
  }
  var a = 0;
  var r = 0;
  var s = 0;
  for (final u in units) {
    final pid = u.projectUnitTypeId?.trim() ?? '';
    if (pid != trimmed) continue;
    switch (u.status) {
      case DevelopmentUnitStatus.available:
        a++;
        break;
      case DevelopmentUnitStatus.reserved:
        r++;
        break;
      case DevelopmentUnitStatus.sold:
        s++;
        break;
    }
  }
  return _UnitTypeInvCounts(available: a, reserved: r, sold: s);
}

class _UnitTypeInvCounts {
  const _UnitTypeInvCounts({
    required this.available,
    required this.reserved,
    required this.sold,
  });

  final int available;
  final int reserved;
  final int sold;

  int get total => available + reserved + sold;
}

/// iOS `ProjectDetailView` "Available Units" + `unitRow` (catalog + live inventory).
class _AvailableUnitTypesSection extends StatelessWidget {
  const _AvailableUnitTypesSection({
    required this.project,
    required this.sortedUnits,
  });

  final ProjectModel project;
  final List<ProjectUnitTypeModel> sortedUnits;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<DevelopmentUnitModel>>(
      stream: context
          .read<ProjectRepository>()
          .watchDevelopmentUnits(project.firestoreDocumentId),
      builder: (context, snapshot) {
        final units = snapshot.data ?? const <DevelopmentUnitModel>[];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 28),
            Text(
              'Available Units',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
            ),
            const SizedBox(height: 12),
            ...sortedUnits.map(
              (u) => _UnitTypeCard(
                unit: u,
                inventoryUnits: units,
                projectName: project.projectName,
                fallbackImages: project.heroImages,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _UnitTypeCard extends StatelessWidget {
  const _UnitTypeCard({
    required this.unit,
    required this.inventoryUnits,
    required this.projectName,
    this.fallbackImages = const [],
  });

  final ProjectUnitTypeModel unit;
  final List<DevelopmentUnitModel> inventoryUnits;
  final String projectName;
  final List<String> fallbackImages;

  void _showUnitDetail(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _UnitDetailSheet(
        unit: unit,
        projectName: projectName,
        fallbackImages: fallbackImages,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final inv = _inventoryCountsForUnitType(inventoryUnits, unit.id);
    final hasLiveRowsForType = inv.total > 0;
    final catalogTotal = unit.totalUnits;
    final legacyAvail = unit.availableUnits;
    final sqft = unit.squareFootage;

    final hasMetadata = catalogTotal != null ||
        legacyAvail != null ||
        sqft != null ||
        hasLiveRowsForType;

    final currency = unit.currencyCode ?? 'USD';
    final priceStr =
        NumberFormat.simpleCurrency(name: currency).format(unit.price);

    String? scarcity;
    if (hasLiveRowsForType) {
      if (inv.available <= 0) {
        scarcity = 'Sold out';
      } else if (inv.available == 1) {
        scarcity = 'Last unit';
      } else if (inv.total > 0 && inv.available * 3 <= inv.total) {
        scarcity = 'Limited';
      }
    } else if (catalogTotal != null && legacyAvail != null) {
      if (legacyAvail <= 0) {
        scarcity = 'Sold out';
      } else if (legacyAvail == 1) {
        scarcity = 'Last unit';
      } else if (legacyAvail * 3 <= catalogTotal) {
        scarcity = 'Limited';
      }
    }

    final name = unit.name?.trim();
    final hasName = name != null && name.isNotEmpty;

    final cs = Theme.of(context).colorScheme;
    final captionStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: cs.onSurfaceVariant,
        );
    final tinyStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
          color: cs.onSurfaceVariant,
        );
    final dotStyle = tinyStyle?.copyWith(
      color: cs.onSurfaceVariant.withValues(alpha: 0.8),
    );

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      color: cs.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: cs.outlineVariant.withValues(alpha: 0.9),
        ),
      ),
      child: InkWell(
        onTap: () => _showUnitDetail(context),
        child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (unit.imageURLs.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: CachedNetworkImage(
                  imageUrl: unit.imageURLs.first,
                  width: 72,
                  height: 72,
                  fit: BoxFit.cover,
                  memCacheWidth: 144,
                  memCacheHeight: 144,
                  placeholder: (_, __) => Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: cs.primary,
                      ),
                    ),
                  ),
                  errorWidget: (_, __, ___) => Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.image_not_supported_outlined,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
              )
            else
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.home_work_outlined,
                  color: cs.onSurfaceVariant,
                ),
              ),
            const SizedBox(width: 12),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (hasName) ...[
                          Text(
                            name,
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: cs.onSurface,
                                ),
                          ),
                          Text(
                            '${unit.bedrooms} bed · ${unit.bathrooms} bath',
                            style: captionStyle,
                          ),
                        ] else ...[
                          Text(
                            '${unit.bedrooms} bed · ${unit.bathrooms} bath',
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: cs.onSurface,
                                ),
                          ),
                          Text('Unit type', style: captionStyle),
                        ],
                        if (hasMetadata) ...[
                          const SizedBox(height: 4),
                          if (hasLiveRowsForType) ...[
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                if (sqft != null) Text('$sqft sqft', style: tinyStyle),
                                Text('Avail ${inv.available}', style: tinyStyle),
                                Text('·', style: dotStyle),
                                Text('Res ${inv.reserved}', style: tinyStyle),
                                Text('·', style: dotStyle),
                                Text('Sold ${inv.sold}', style: tinyStyle),
                              ],
                            ),
                            if (catalogTotal != null &&
                                catalogTotal != inv.total) ...[
                              const SizedBox(height: 4),
                              Text(
                                'Planned in catalog: $catalogTotal units',
                                style: tinyStyle?.copyWith(
                                  color: cs.onSurfaceVariant
                                      .withValues(alpha: 0.85),
                                ),
                              ),
                            ],
                          ] else ...[
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              children: [
                                if (sqft != null) Text('$sqft sqft', style: tinyStyle),
                                if (catalogTotal != null)
                                  Text('Planned: $catalogTotal units', style: tinyStyle),
                                if (legacyAvail != null)
                                  Text(
                                    'Catalog: $legacyAvail avail',
                                    style: tinyStyle?.copyWith(
                                      color: legacyAvail == 0
                                          ? cs.error
                                          : cs.onSurfaceVariant,
                                    ),
                                  ),
                              ],
                            ),
                            if (inventoryUnits.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                'Generate or link inventory with this layout to see live counts.',
                                style: tinyStyle,
                              ),
                            ],
                          ],
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        priceStr,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: cs.onSurface,
                            ),
                      ),
                      if (scarcity != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          scarcity,
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: scarcity == 'Sold out'
                                        ? Colors.red
                                        : Colors.orange.shade800,
                                  ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }
}

class _DevelopmentInventorySection extends StatefulWidget {
  const _DevelopmentInventorySection({required this.project});

  final ProjectModel project;

  @override
  State<_DevelopmentInventorySection> createState() =>
      _DevelopmentInventorySectionState();
}

class _DevelopmentInventorySectionState extends State<_DevelopmentInventorySection> {
  /// iOS `ProjectDetailView`: defaults to on.
  bool _showOnlyAvailable = true;
  bool _hideSold = false;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<DevelopmentUnitModel>>(
      stream: context
          .read<ProjectRepository>()
          .watchDevelopmentUnits(widget.project.firestoreDocumentId),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Inventory could not be loaded.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),
              Text(
                'Development inventory',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Loading units…',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ],
          );
        }
        final units = snapshot.data!;

        // iOS `buyerInventorySection`: filters use raw `status`, not derived holds.
        final availableForFilter = units
            .where((u) => u.status == DevelopmentUnitStatus.available)
            .toList();
        List<DevelopmentUnitModel> filtered;
        if (_showOnlyAvailable) {
          filtered = availableForFilter;
        } else if (_hideSold) {
          filtered = units
              .where((u) => u.status != DevelopmentUnitStatus.sold)
              .toList();
        } else {
          filtered = List<DevelopmentUnitModel>.from(units);
        }
        filtered.sort((a, b) {
          final cmp = a.price.compareTo(b.price);
          if (cmp != 0) return cmp;
          return a.unitNumber.toLowerCase().compareTo(b.unitNumber.toLowerCase());
        });

        final availableCount = units
            .where((u) => u.status == DevelopmentUnitStatus.available)
            .length;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            Text(
              'Development inventory',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              'Per-unit availability (${units.length} units)',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Show only available'),
              value: _showOnlyAvailable,
              onChanged: (v) => setState(() => _showOnlyAvailable = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Hide sold units'),
              value: _hideSold,
              onChanged: _showOnlyAvailable
                  ? null
                  : (v) => setState(() => _hideSold = v),
            ),
            if (availableCount <= 3 && units.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Only $availableCount units left',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Colors.orange.shade800,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
            const SizedBox(height: 8),
            if (filtered.isEmpty)
              Text(
                'No units to display.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              )
            else
              ...filtered.map(
                (u) => _InventoryRow(
                  project: widget.project,
                  unit: u,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _InventoryRow extends StatelessWidget {
  const _InventoryRow({
    required this.project,
    required this.unit,
  });

  final ProjectModel project;
  final DevelopmentUnitModel unit;

  Color _statusColor(BuildContext context) {
    // iOS `UnitStatusBadge` uses raw `unit.status`.
    switch (unit.status) {
      case DevelopmentUnitStatus.available:
        return Colors.green.shade700;
      case DevelopmentUnitStatus.reserved:
        return Colors.orange.shade800;
      case DevelopmentUnitStatus.sold:
        return Theme.of(context).colorScheme.onSurfaceVariant;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final typeLine = project.inventoryTypeLabel(unit);
    final priceStr =
        NumberFormat.simpleCurrency(name: 'USD').format(unit.price);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      unit.unitNumber,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: cs.onSurface,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      typeLine,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      priceStr,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: cs.onSurfaceVariant,
                            fontWeight: FontWeight.w500,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _statusColor(context).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  unit.status.title,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: _statusColor(context),
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ─────────────────────────────────────────────────────────────────────────────
// Follow button — AppBar action for seekers
// ─────────────────────────────────────────────────────────────────────────────

class _FollowButton extends StatefulWidget {
  const _FollowButton({required this.project, required this.userId});

  final ProjectModel project;
  final String userId;

  @override
  State<_FollowButton> createState() => _FollowButtonState();
}

class _FollowButtonState extends State<_FollowButton> {
  bool _toggling = false;

  Future<void> _toggle(bool currentlyFollowing) async {
    if (_toggling) return;
    setState(() => _toggling = true);
    try {
      final repo = context.read<UserProfileRepository>();
      if (currentlyFollowing) {
        await repo.unfollowDevelopment(
          userId: widget.userId,
          projectId: widget.project.firestoreDocumentId,
        );
      } else {
        await repo.followDevelopment(
          userId: widget.userId,
          projectId: widget.project.firestoreDocumentId,
          projectName: widget.project.projectName,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update follow: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _toggling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.read<UserProfileRepository>();
    return StreamBuilder<bool>(
      stream: repo.watchIsFollowingDevelopment(
        widget.userId,
        widget.project.firestoreDocumentId,
      ),
      builder: (context, snap) {
        final isFollowing = snap.data ?? false;
        return IconButton(
          tooltip: isFollowing ? 'Unfollow' : 'Follow',
          icon: _toggling
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(
                  isFollowing ? Icons.star_rounded : Icons.star_outline_rounded,
                  color: isFollowing ? Colors.amber : null,
                ),
          onPressed: _toggling ? null : () => _toggle(isFollowing),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Register Interest CTA bar (seeker view) — mirrors iOS RegisterInterestView
// ─────────────────────────────────────────────────────────────────────────────

class _RegisterInterestBar extends StatefulWidget {
  const _RegisterInterestBar({
    required this.project,
    required this.userId,
  });

  final ProjectModel project;
  final String userId;

  @override
  State<_RegisterInterestBar> createState() => _RegisterInterestBarState();
}

class _RegisterInterestBarState extends State<_RegisterInterestBar> {
  @override
  Widget build(BuildContext context) {
    final repo = context.read<UserProfileRepository>();
    return StreamBuilder<bool>(
      stream: repo.watchHasRegisteredInterest(
        widget.userId,
        widget.project.firestoreDocumentId,
      ),
      builder: (context, snap) {
        final alreadyRegistered = snap.data ?? false;
        return SafeArea(
          child: Material(
            elevation: 8,
            color: Theme.of(context).colorScheme.surface,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: alreadyRegistered
                  ? FilledButton.icon(
                      onPressed: null,
                      icon: const Icon(Icons.check_circle_outline),
                      label: const Text('Interest Registered'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(double.infinity, 48),
                        disabledBackgroundColor: Colors.green.shade600,
                        disabledForegroundColor: Colors.white,
                      ),
                    )
                  : FilledButton.icon(
                      onPressed: () {
                        AnalyticsService.logRegisterInterestOpened(
                          widget.project.firestoreDocumentId,
                          widget.project.projectName,
                          'interest',
                        );
                        showModalBottomSheet<void>(
                          context: context,
                          isScrollControlled: true,
                          backgroundColor: Colors.transparent,
                          builder: (_) => _RegisterInterestSheet(
                            project: widget.project,
                            userId: widget.userId,
                          ),
                        );
                      },
                      icon: const Icon(Icons.favorite_outline),
                      label: const Text('Register Interest'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(double.infinity, 48),
                      ),
                    ),
            ),
          ),
        );
      },
    );
  }
}

class _RegisterInterestSheet extends StatefulWidget {
  const _RegisterInterestSheet({
    required this.project,
    required this.userId,
  });

  final ProjectModel project;
  final String userId;

  @override
  State<_RegisterInterestSheet> createState() => _RegisterInterestSheetState();
}

class _RegisterInterestSheetState extends State<_RegisterInterestSheet> {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _messageCtrl = TextEditingController();
  final _budgetCtrl = TextEditingController();
  final _timelineCtrl = TextEditingController();
  final _financingCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    // Pre-fill from the signed-in user's Auth profile.
    final u = context.read<AuthProvider>().user;
    if (u != null) {
      _nameCtrl.text = u.displayName ?? '';
      _emailCtrl.text = u.email ?? '';
      _phoneCtrl.text = u.phoneNumber ?? '';
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _messageCtrl.dispose();
    _budgetCtrl.dispose();
    _timelineCtrl.dispose();
    _financingCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _submitting = true);
    AnalyticsService.logRegisterInterestSubmitAttempt(
      widget.project.firestoreDocumentId,
      widget.project.projectName,
      'interest',
    );
    try {
      await context.read<ProjectRepository>().submitInterest(
            projectId: widget.project.firestoreDocumentId,
            projectName: widget.project.projectName,
            name: _nameCtrl.text.trim(),
            email: _emailCtrl.text.trim(),
            phone: _phoneCtrl.text.trim().isNotEmpty
                ? _phoneCtrl.text.trim()
                : null,
            message: _messageCtrl.text.trim().isNotEmpty
                ? _messageCtrl.text.trim()
                : null,
            userId: widget.userId,
          );
      unawaited(AnalyticsService.logRegisterInterestSuccess(
        widget.project.firestoreDocumentId,
        widget.project.projectName,
        'interest',
      ));
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Interest registered for ${widget.project.projectName}!',
          ),
        ),
      );
    } on AlreadyRegisteredException {
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You have already registered interest in this development.'),
        ),
      );
    } catch (e) {
      unawaited(AnalyticsService.logRegisterInterestFailed(
        widget.project.firestoreDocumentId,
        widget.project.projectName,
        'interest',
        e.toString(),
      ));
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed: $e')));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(24, 16, 24, 24 + bottom),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Register Interest',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                widget.project.projectName,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Full name *',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email *',
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Required';
                  if (!v.contains('@')) return 'Enter a valid email';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Phone (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _messageCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Message (optional)',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              // Qualification fields (mirrors iOS RegisterInterestView)
              Text(
                'Help the developer qualify your inquiry',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _budgetCtrl,
                decoration: const InputDecoration(
                  labelText: 'Budget range (optional)',
                  hintText: 'e.g. \$500k–\$700k',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _timelineCtrl,
                decoration: const InputDecoration(
                  labelText: 'Purchase timeline (optional)',
                  hintText: 'e.g. 6–12 months',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _financingCtrl,
                decoration: const InputDecoration(
                  labelText: 'Financing (optional)',
                  hintText: 'e.g. cash, mortgage pre-approved',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              // Lead billing context banner
              _LeadBillingBanner(project: widget.project),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _submitting ? null : _submit,
                style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, 48)),
                child: _submitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Submit Interest'),
              ),
              const SizedBox(height: 8),
              Text(
                'Your inquiry is sent securely to the developer.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Mirrors iOS `LeadBillingContextView` — shows lead credit/cost info before submit.
class _LeadBillingBanner extends StatelessWidget {
  const _LeadBillingBanner({required this.project});
  final ProjectModel project;

  @override
  Widget build(BuildContext context) {
    // Simplified: just show a neutral info banner since billing context
    // requires developer-side data. Full billing integration via LeadCreditService.
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.primary.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: AppColors.primary, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Lead credit required',
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: AppColors.primary),
                ),
                Text(
                  'Submitting this inquiry uses 1 lead credit from the developer\'s balance.',
                  style: TextStyle(
                      fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Unit detail bottom sheet — mirrors iOS ProjectUnitDetailView
// ─────────────────────────────────────────────────────────────────────────────

/// Bottom sheet shown when tapping a unit type row.
/// Displays unit photos (or development hero photos as fallback) + key details.
class _UnitDetailSheet extends StatelessWidget {
  const _UnitDetailSheet({
    required this.unit,
    required this.projectName,
    this.fallbackImages = const [],
  });

  final ProjectUnitTypeModel unit;
  final String projectName;
  final List<String> fallbackImages;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final galleryUrls =
        unit.imageURLs.isNotEmpty ? unit.imageURLs : fallbackImages;
    final isFallback =
        unit.imageURLs.isEmpty && fallbackImages.isNotEmpty;

    final name = unit.name?.trim();
    final hasName = name != null && name.isNotEmpty;
    final title = hasName ? name : projectName;
    final currency = unit.currencyCode ?? 'USD';
    final priceStr =
        NumberFormat.simpleCurrency(name: currency).format(unit.price);

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Material(
          color: cs.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          child: Column(
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: cs.onSurfaceVariant.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: EdgeInsets.zero,
                  children: [
                    // ── Image section ──
                    if (galleryUrls.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                        child: Text(
                          isFallback ? 'Development photos' : 'Unit photos',
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: cs.onSurfaceVariant,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.3,
                                  ),
                        ),
                      ),
                      _UnitImageCarousel(urls: galleryUrls),
                    ] else
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                        child: Row(
                          children: [
                            Icon(
                              Icons.photo_library_outlined,
                              size: 20,
                              color: cs.onSurfaceVariant,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'No unit photos yet',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(color: cs.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),

                    // ── Details section ──
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: cs.onSurface,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${unit.bedrooms} bed · ${unit.bathrooms} bath',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(color: cs.onSurfaceVariant),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            priceStr,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: cs.primary,
                                ),
                          ),
                          if (unit.squareFootage != null) ...[
                            const SizedBox(height: 6),
                            Text(
                              '${unit.squareFootage} sqft',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: cs.onSurfaceVariant),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Horizontal paging image carousel used inside [_UnitDetailSheet].
class _UnitImageCarousel extends StatefulWidget {
  const _UnitImageCarousel({required this.urls});

  final List<String> urls;

  @override
  State<_UnitImageCarousel> createState() => _UnitImageCarouselState();
}

class _UnitImageCarouselState extends State<_UnitImageCarousel> {
  final PageController _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const double h = 224;
    final cs = Theme.of(context).colorScheme;
    final urls = widget.urls;

    return SizedBox(
      height: h,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          PageView.builder(
            controller: _controller,
            itemCount: urls.length,
            onPageChanged: (i) => setState(() => _page = i),
            itemBuilder: (context, i) {
              return GestureDetector(
                onTap: () => FullScreenImageGallery.open(context, urls, i),
                behavior: HitTestBehavior.opaque,
                child: CachedNetworkImage(
                  imageUrl: urls[i],
                  fit: BoxFit.cover,
                  width: double.infinity,
                  memCacheHeight: 600,
                  placeholder: (_, __) => Container(
                    color: cs.surfaceContainerHighest,
                    child: Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: cs.primary,
                      ),
                    ),
                  ),
                  errorWidget: (_, __, ___) => Container(
                    color: cs.surfaceContainerHighest,
                    child: Icon(
                      Icons.broken_image_outlined,
                      size: 40,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
              );
            },
          ),
          if (urls.length > 1)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  urls.length,
                  (i) => AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: i == _page ? 18 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      color: i == _page
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.45),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
