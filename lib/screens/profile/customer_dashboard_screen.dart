import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../constants/app_colors.dart';
import '../../models/project_interest_row.dart';
import '../../models/project_model.dart';
import '../../models/user_profile_doc.dart';
import '../../repositories/project_repository.dart';
import '../../repositories/user_profile_repository.dart';
import '../../services/analytics_service.dart';
import '../../screens/home/developments_browse_screen.dart';
import '../../widgets/dashboard_compact_project_row.dart';
import '../../widgets/dashboard_interest_tile.dart';
import 'profile_subscreen_widgets.dart';

/// Seeker-facing hub — parity with iOS `CustomerDashboardRootScreen` (grouped list layout).
class CustomerDashboardScreen extends StatefulWidget {
  const CustomerDashboardScreen({super.key, required this.userId});

  final String userId;

  @override
  State<CustomerDashboardScreen> createState() =>
      _CustomerDashboardScreenState();
}

class CustomerDashboardData {
  CustomerDashboardData({
    required this.interests,
    required this.followedCount,
    required this.catalog,
  });

  final List<ProjectInterestRow> interests;
  final int followedCount;
  final List<ProjectModel> catalog;

  List<ProjectModel> get updates => computeDashboardUpdates(catalog);

  List<ProjectModel> get recommended =>
      computeDashboardRecommended(catalog, interests);
}

/// iOS `CustomerDashboardViewModel` updates — latest active projects by `createdAt`.
List<ProjectModel> computeDashboardUpdates(List<ProjectModel> catalog) {
  final pool =
      catalog.where((p) => p.isActive && !p.isExpired).toList(growable: false);
  final sorted = [...pool]..sort((a, b) {
      final da = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final db = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return db.compareTo(da);
    });
  return sorted.take(5).toList();
}

/// iOS `CustomerDashboardViewModel` recommendation heuristic.
List<ProjectModel> computeDashboardRecommended(
  List<ProjectModel> catalog,
  List<ProjectInterestRow> interests,
) {
  final interestedIds = interests
      .map((e) => e.projectId.trim())
      .where((e) => e.isNotEmpty)
      .toSet();

  final allProjects =
      catalog.where((p) => p.isActive && !p.isExpired).toList(growable: false);

  final interestProjects = allProjects.where((p) {
    final doc = p.firestoreDocumentId.trim().isEmpty ? p.id : p.firestoreDocumentId;
    return interestedIds.contains(doc) || interestedIds.contains(p.id);
  }).toList();

  final preferredLocations = interestProjects
      .map((p) => p.location.trim())
      .where((s) => s.isNotEmpty)
      .toSet();

  final preferredPrices = interestProjects
      .map((p) => p.startingPrice)
      .whereType<double>()
      .toList();

  final anchor = preferredPrices.isEmpty
      ? null
      : preferredPrices.reduce(math.min);

  bool isRecommended(ProjectModel project) {
    final doc =
        project.firestoreDocumentId.trim().isEmpty ? project.id : project.firestoreDocumentId;
    if (interestedIds.contains(doc) || interestedIds.contains(project.id)) {
      return false;
    }

    final locationMatches = project.location.trim().isNotEmpty &&
        preferredLocations.contains(project.location.trim());

    var priceMatches = false;
    final price = project.startingPrice;
    if (price != null && anchor != null && anchor > 0) {
      final delta = (price - anchor).abs() / math.max(anchor, 1);
      priceMatches = delta <= 0.3;
    }

    return locationMatches || priceMatches;
  }

  if (interestProjects.isEmpty) {
    return allProjects.take(6).toList();
  }
  return allProjects.where(isRecommended).take(6).toList();
}

class _CustomerDashboardScreenState extends State<CustomerDashboardScreen> {
  @override
  void initState() {
    super.initState();
    AnalyticsService.logDashboardView('customer');
  }

  Future<void> _refresh() async {
    // Data is Firebase-stream driven; pull-to-refresh keeps platform-native affordance.
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }

  void _openBrowseProjects(BuildContext context) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => const DevelopmentsBrowseScreen(),
      ),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
  }

  static String _displayName(UserProfileDoc? doc) {
    final n = doc?.fullName?.trim();
    if (n != null && n.isNotEmpty) return n;
    return 'Customer';
  }

  @override
  Widget build(BuildContext context) {
    final ur = context.read<UserProfileRepository>();
    return StreamBuilder<UserProfileDoc?>(
      stream: ur.watchUserProfile(widget.userId),
      builder: (context, profileSnap) {
        final name = _displayName(profileSnap.data);

        return ProfileGroupedScaffold(
          title: 'My Developments',
          child: StreamBuilder<List<ProjectInterestRow>>(
            stream: ur.watchMyDevelopments(widget.userId),
            builder: (context, interestsSnap) {
              return StreamBuilder<int>(
                stream: ur.watchFollowedDevelopmentsCount(widget.userId),
                builder: (context, followedSnap) {
                  final projects = context.read<ProjectRepository>();
                  return StreamBuilder<List<ProjectModel>>(
                    stream: projects.watchBrowseProjects(),
                    builder: (context, catalogSnap) {
                      final loading = !interestsSnap.hasData ||
                          !followedSnap.hasData ||
                          !catalogSnap.hasData;
                      final err = interestsSnap.error ??
                          followedSnap.error ??
                          catalogSnap.error;

                      if (loading && err == null) {
                        return const Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircularProgressIndicator(),
                              SizedBox(height: 12),
                              Text('Loading…'),
                            ],
                          ),
                        );
                      }
                      if (err != null) {
                        return ProfileErrorState(
                          message: '$err',
                          onRetry: _refresh,
                        );
                      }

                      final data = CustomerDashboardData(
                        interests: interestsSnap.data ?? const [],
                        followedCount: followedSnap.data ?? 0,
                        catalog: catalogSnap.data ?? const [],
                      );

                      return RefreshIndicator(
                        color: AppColors.primary,
                        onRefresh: _refresh,
                        child: CustomScrollView(
                          physics: const AlwaysScrollableScrollPhysics(
                            parent: BouncingScrollPhysics(),
                          ),
                          slivers: _buildContentSlivers(context, data, name),
                        ),
                      );
                    },
                  );
                },
              );
            },
          ),
        );
      },
    );
  }

  List<Widget> _buildContentSlivers(
    BuildContext context,
    CustomerDashboardData data,
    String welcomeValue,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final catalog = data.catalog;

    final updates = data.updates;
    final recommended = data.recommended;

    final interestTiles = <Widget>[];
    for (var i = 0; i < data.interests.length; i++) {
      if (i > 0) {
        interestTiles.add(
          const Divider(height: 1, thickness: 1, color: AppColors.divider),
        );
      }
      final row = data.interests[i];
      final project = projectForInterest(catalog, row);
      interestTiles.add(
        DashboardInterestTile(
          row: row,
          project: project,
          subtitle: interestSubtitle(project),
          registeredLabel: formatInterestRegistered(row.createdAt),
          onOpenDetail: () {
            final id = row.projectId.trim();
            if (id.isEmpty) return;
            context.push('/development/$id');
          },
        ),
      );
    }

    return [
      SliverPadding(
        padding: ProfileLayout.pagePadding,
        sliver: SliverList(
          delegate: SliverChildListDelegate([
            _InsetSectionCard(
              child: ListTile(
                title: const Text('Welcome'),
                trailing: Text(
                  welcomeValue,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                ),
                dense: true,
              ),
            ),
            const SizedBox(height: ProfileLayout.sectionGap),
            const ProfileSectionHeader('Actions'),
            const SizedBox(height: 8),
            _InsetSectionCard(
              child: ListTile(
                leading: Icon(Icons.domain_rounded, color: scheme.primary),
                title: const Text('Browse all developments'),
                trailing: Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: scheme.onSurfaceVariant,
                ),
                onTap: () => _openBrowseProjects(context),
              ),
            ),
            const SizedBox(height: ProfileLayout.sectionGap),
            const ProfileSectionHeader('Overview'),
            const SizedBox(height: 8),
            _InsetSectionCard(
              columnChildren: [
                _statRow(
                  context,
                  icon: Icons.favorite_rounded,
                  color: Colors.red.shade400,
                  label: 'Interests',
                  value: '${data.interests.length}',
                ),
                const Divider(height: 1, thickness: 1, color: AppColors.divider),
                _statRow(
                  context,
                  icon: Icons.star_rounded,
                  color: Colors.amber.shade600,
                  label: 'Following',
                  value: '${data.followedCount}',
                ),
              ],
            ),
            if (updates.isNotEmpty) ...[
              const SizedBox(height: ProfileLayout.sectionGap),
              const ProfileSectionHeader('Updates from Developers'),
              const SizedBox(height: 8),
              _InsetSectionCard(
                columnChildren: [
                  for (var i = 0; i < updates.length; i++) ...[
                    if (i > 0)
                      const Divider(height: 1, thickness: 1, color: AppColors.divider),
                    DashboardCompactProjectRow(
                      project: updates[i],
                      onTap: () => context.push(
                        '/development/${updates[i].firestoreDocumentId}',
                      ),
                    ),
                  ],
                ],
              ),
            ],
            const SizedBox(height: ProfileLayout.sectionGap),
            const ProfileSectionHeader('My Interests'),
            const SizedBox(height: 8),
            if (data.interests.isEmpty)
              const _InsetSectionCard(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(16, 28, 16, 28),
                  child: ProfileEmptyState(
                    icon: Icons.domain_outlined,
                    title: 'No interests yet',
                    subtitle:
                        'Register your interest in developments to see them here.',
                  ),
                ),
              )
            else
              _InsetSectionCard(columnChildren: interestTiles),
            if (recommended.isNotEmpty) ...[
              const SizedBox(height: ProfileLayout.sectionGap),
              const ProfileSectionHeader('Recommended Developments'),
              const SizedBox(height: 8),
              _InsetSectionCard(
                columnChildren: [
                  for (var i = 0; i < recommended.length; i++) ...[
                    if (i > 0)
                      const Divider(height: 1, thickness: 1, color: AppColors.divider),
                    DashboardCompactProjectRow(
                      project: recommended[i],
                      onTap: () => context.push(
                        '/development/${recommended[i].firestoreDocumentId}',
                      ),
                    ),
                  ],
                ],
              ),
            ],
            const SizedBox(height: 32),
          ]),
        ),
      ),
    ];
  }

  Widget _statRow(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String label,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
          ),
        ],
      ),
    );
  }
}

/// Grouped “inset” card stack — mirrors SwiftUI `.listStyle(.insetGrouped)`.
class _InsetSectionCard extends StatelessWidget {
  const _InsetSectionCard({
    this.child,
    this.columnChildren,
  }) : assert(child != null || columnChildren != null);

  final Widget? child;
  final List<Widget>? columnChildren;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ProfileTokens.radiusCard),
        side: BorderSide(
          color: scheme.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: columnChildren != null
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: columnChildren!,
            )
          : child!,
    );
  }
}
