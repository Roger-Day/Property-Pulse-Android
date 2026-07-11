import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../constants/app_colors.dart';
import '../../models/project_model.dart';
import '../../models/property_model.dart';
import '../../models/public_profile_summary.dart';
import '../../repositories/project_repository.dart';
import '../../repositories/user_profile_repository.dart';
import '../../utils/responsive.dart';
import '../../widgets/property_card.dart';
import 'profile_subscreen_widgets.dart';

/// Read-only public agent/host/developer profile — aligns with iOS `PublicProfileView`.
class PublicProfileScreen extends StatefulWidget {
  const PublicProfileScreen({super.key, required this.userId});

  final String userId;

  @override
  State<PublicProfileScreen> createState() => _PublicProfileScreenState();
}

class _PublicProfileExtras {
  const _PublicProfileExtras({
    required this.listings,
    required this.projects,
    required this.team,
  });

  final List<PropertyModel> listings;
  final List<ProjectModel> projects;
  final List<AggregatedPublicTeamMember> team;
}

class _PublicProfileScreenState extends State<PublicProfileScreen> {
  Future<_PublicProfileExtras>? _extrasFuture;

  @override
  void didUpdateWidget(covariant PublicProfileScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId) {
      setState(() => _extrasFuture = null);
    }
  }

  bool _showsDevSections(PublicProfileSummary p) {
    final r = (p.role ?? '').toLowerCase().trim();
    return r == 'developer' || r == 'admin';
  }

  Future<_PublicProfileExtras> _loadExtras(PublicProfileSummary p) async {
    final userRepo = context.read<UserProfileRepository>();
    final projectRepo = context.read<ProjectRepository>();
    final listings = await userRepo.getMyListings(widget.userId);
    if (!_showsDevSections(p)) {
      return _PublicProfileExtras(
        listings: listings,
        projects: const [],
        team: const [],
      );
    }
    final projects = await projectRepo.fetchProjectsByDeveloper(widget.userId);
    final team =
        await projectRepo.aggregateTeamAcrossDeveloperProjects(projects);
    return _PublicProfileExtras(
      listings: listings,
      projects: projects,
      team: team,
    );
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.read<UserProfileRepository>();

    return StreamBuilder<PublicProfileSummary?>(
      stream: repo.watchPublicProfile(widget.userId),
      builder: (context, snapshot) {
        final loaded = snapshot.hasData ? snapshot.data : null;
        final title =
            (loaded != null && loaded.displayName.trim().isNotEmpty)
                ? loaded.displayName
                : 'Profile';

        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            title: Text(title),
            centerTitle: true,
            scrolledUnderElevation: 0,
          ),
          body: _buildBody(context, snapshot),
        );
      },
    );
  }

  Widget _buildBody(
    BuildContext context,
    AsyncSnapshot<PublicProfileSummary?> snapshot,
  ) {
    if (snapshot.hasError) {
      return ProfileEmptyState(
        icon: Icons.person_off_outlined,
        title: 'Profile unavailable',
        subtitle: '${snapshot.error}',
      );
    }

    if (snapshot.connectionState == ConnectionState.waiting &&
        snapshot.data == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              'Loading profile…',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
          ],
        ),
      );
    }

    final p = snapshot.data;
    if (p == null) {
      return const ProfileEmptyState(
        icon: Icons.person_search_outlined,
        title: 'Profile unavailable',
        subtitle: 'This profile could not be loaded.',
      );
    }

    _extrasFuture ??= _loadExtras(p);
    final bio = p.bio?.trim() ?? '';

    return ListView(
      padding: Responsive.hPadding(context, top: 16, bottom: 32),
      children: [
        _PublicProfileHeader(p: p),
        const SizedBox(height: 16),
        _PublicProfileStatsBar(userId: p.userId),
        if (bio.isNotEmpty) ...[
          const SizedBox(height: 16),
          _AboutSection(bio: bio),
        ],
        const SizedBox(height: 24),
        FutureBuilder<_PublicProfileExtras>(
          future: _extrasFuture,
          builder: (context, futSnap) {
            final loadingExtras = futSnap.connectionState ==
                    ConnectionState.waiting &&
                !futSnap.hasData;

            if (futSnap.hasError) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  'Could not load listings or projects: ${futSnap.error}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                ),
              );
            }

            final e = futSnap.data;
            final listings = e?.listings ?? [];
            final projects = e?.projects ?? [];
            final team = e?.team ?? [];

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ListingsSection(
                  listings: listings,
                  loadingExtras: loadingExtras,
                ),
                if (_showsDevSections(p)) ...[
                  _DevelopmentsSection(
                    projects: projects,
                    loadingExtras: loadingExtras,
                  ),
                  _TeamSection(
                    team: team,
                    loadingExtras: loadingExtras,
                  ),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Header — iOS `profileHeader`: centered avatar (100), title2 name, role capsule,
// verification badge.
// ─────────────────────────────────────────────────────────────────────────────

class _PublicProfileHeader extends StatelessWidget {
  const _PublicProfileHeader({required this.p});

  final PublicProfileSummary p;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final role = p.role?.trim() ?? '';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(ProfileTokens.radiusCard),
        boxShadow: ProfileShadows.card(),
      ),
      child: Column(
        children: [
          _Avatar(url: p.photoUrl, name: p.displayName, radius: 50),
          const SizedBox(height: 16),
          Text(
            p.displayName,
            textAlign: TextAlign.center,
            style: tt.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          if (role.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                role,
                style: tt.bodyMedium?.copyWith(color: AppColors.textSecondary),
              ),
            ),
          ],
          if (p.isVerified) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.verified,
                  color: AppColors.verifiedBadge,
                  size: 18,
                ),
                const SizedBox(width: 6),
                Text(
                  'Verified',
                  style: tt.labelLarge?.copyWith(
                    color: AppColors.verifiedBadge,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _AboutSection extends StatelessWidget {
  const _AboutSection({required this.bio});

  final String bio;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(ProfileTokens.radiusCard),
        boxShadow: ProfileShadows.card(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'About',
            style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            bio,
            style: tt.bodyMedium?.copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Properties — iOS `propertiesSection` card + grid / loading / empty.
// ─────────────────────────────────────────────────────────────────────────────

class _ListingsSection extends StatelessWidget {
  const _ListingsSection({
    required this.listings,
    required this.loadingExtras,
  });

  final List<PropertyModel> listings;
  final bool loadingExtras;

  static const double _cellHeight = 152;

  @override
  Widget build(BuildContext context) {
    final cross = Responsive.gridColumns(
      context,
      phone: 2,
      tablet: 3,
      desktop: 3,
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(ProfileTokens.radiusCard),
        boxShadow: ProfileShadows.card(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Properties',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 12),
          if (loadingExtras)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Loading properties…',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                  ),
                ],
              ),
            )
          else if (listings.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'No properties listed.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
            )
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: listings.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: cross,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                mainAxisExtent: _cellHeight,
              ),
              itemBuilder: (context, i) {
                final prop = listings[i];
                return PropertyCard(
                  property: prop,
                  gridCompact: true,
                  onTap: () => context.push('/property/${prop.id}'),
                );
              },
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Developments — iOS `CompactProjectCard`: 120pt image + gradient + captions.
// ─────────────────────────────────────────────────────────────────────────────

class _DevelopmentsSection extends StatelessWidget {
  const _DevelopmentsSection({
    required this.projects,
    required this.loadingExtras,
  });

  final List<ProjectModel> projects;
  final bool loadingExtras;

  static const double _tileHeight = 120;

  @override
  Widget build(BuildContext context) {
    final cross = Responsive.gridColumns(
      context,
      phone: 2,
      tablet: 3,
      desktop: 3,
    );

    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(ProfileTokens.radiusCard),
          boxShadow: ProfileShadows.card(),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Developments',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 12),
            if (loadingExtras)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Loading developments…',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                    ),
                  ],
                ),
              )
            else if (projects.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'No development projects listed.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                ),
              )
            else
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: projects.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: cross,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  mainAxisExtent: _tileHeight,
                ),
                itemBuilder: (context, i) {
                  final project = projects[i];
                  return _CompactPublicProjectTile(
                    project: project,
                    onTap: () => context.push(
                      '/development/${project.firestoreDocumentId}',
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _CompactPublicProjectTile extends StatelessWidget {
  const _CompactPublicProjectTile({
    required this.project,
    required this.onTap,
  });

  final ProjectModel project;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final priceText = project.startingPrice != null
        ? 'From ${NumberFormat.simpleCurrency(name: project.startingPriceCurrencyCode).format(project.startingPrice)}'
        : 'Price TBA';
    final name = project.projectName.trim().isEmpty
        ? 'Development'
        : project.projectName;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (project.primaryImageUrl != null &&
                  project.primaryImageUrl!.isNotEmpty)
                CachedNetworkImage(
                  imageUrl: project.primaryImageUrl!,
                  fit: BoxFit.cover,
                  memCacheHeight: 240,
                  placeholder: (_, __) => Container(
                    color: AppColors.surfaceVariant,
                    child: const Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ),
                  errorWidget: (_, __, ___) => Container(
                    color: AppColors.surfaceVariant,
                    child: const Icon(Icons.apartment, size: 36),
                  ),
                )
              else
                ColoredBox(
                  color: AppColors.surfaceVariant,
                  child: Icon(
                    Icons.apartment,
                    size: 40,
                    color: AppColors.textTertiary.withValues(alpha: 0.8),
                  ),
                ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.85),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: tt.labelLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        priceText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tt.labelSmall?.copyWith(
                          color: Colors.white.withValues(alpha: 0.95),
                          fontWeight: FontWeight.w500,
                          fontSize: 11,
                        ),
                      ),
                    ],
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
// Project team — iOS `projectTeamSection`: 2-column grid + caption footer.
// ─────────────────────────────────────────────────────────────────────────────

class _TeamSection extends StatelessWidget {
  const _TeamSection({
    required this.team,
    required this.loadingExtras,
  });

  final List<AggregatedPublicTeamMember> team;
  final bool loadingExtras;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(ProfileTokens.radiusCard),
          boxShadow: ProfileShadows.card(),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Project team',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 12),
            if (loadingExtras)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Loading team…',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                    ),
                  ],
                ),
              )
            else if (team.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'No project team yet. The developer adds people from each '
                  'development’s Team screen.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                ),
              )
            else
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: team.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  mainAxisExtent: 168,
                ),
                itemBuilder: (context, i) {
                  final m = team[i];
                  return _PublicTeamMemberCard(member: m);
                },
              ),
            const SizedBox(height: 8),
            Text(
              'Roles here match app permissions (owner, manager, sales) for '
              'each development.',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PublicTeamMemberCard extends StatelessWidget {
  const _PublicTeamMemberCard({required this.member});

  final AggregatedPublicTeamMember member;

  String get _projectsLine {
    if (member.projectNames.isEmpty) return '';
    if (member.projectNames.length == 1) return member.projectNames.first;
    return member.projectNames.join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Material(
      color: AppColors.surfaceVariant,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () => context.push('/user/${member.userId}'),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _TeamAvatar(url: member.photoUrl, name: member.displayName),
              const SizedBox(height: 8),
              Text(
                member.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              Text(
                member.roleLabel,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: tt.bodySmall?.copyWith(color: AppColors.textSecondary),
              ),
              if (_projectsLine.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  _projectsLine,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: tt.labelSmall?.copyWith(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TeamAvatar extends StatelessWidget {
  const _TeamAvatar({required this.url, required this.name});

  final String? url;
  final String name;

  @override
  Widget build(BuildContext context) {
    final initials = name.trim().isEmpty
        ? '?'
        : name
            .trim()
            .split(RegExp(r'\s+'))
            .where((s) => s.isNotEmpty)
            .map((s) => s[0])
            .take(2)
            .join();

    if (url != null && url!.isNotEmpty) {
      return CircleAvatar(
        radius: 32,
        backgroundColor: AppColors.surfaceVariant,
        backgroundImage: CachedNetworkImageProvider(url!),
      );
    }
    return CircleAvatar(
      radius: 32,
      backgroundColor: AppColors.primary.withValues(alpha: 0.12),
      child: Text(
        initials.toUpperCase(),
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: AppColors.primary,
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.url,
    required this.name,
    this.radius = 40,
  });

  final String? url;
  final String name;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final initials = name.trim().isEmpty
        ? '?'
        : name
            .trim()
            .split(RegExp(r'\s+'))
            .where((s) => s.isNotEmpty)
            .map((s) => s[0])
            .take(2)
            .join();

    if (url != null && url!.isNotEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: AppColors.surfaceVariant,
        backgroundImage: CachedNetworkImageProvider(url!),
      );
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.primary.withValues(alpha: 0.12),
      child: Text(
        initials.toUpperCase(),
        style: TextStyle(
          fontSize: radius * 0.44,
          fontWeight: FontWeight.w700,
          color: AppColors.primary,
        ),
      ),
    );
  }
}

// ─── Public Profile Stats Bar ────────────────────────────────────────────────
// Mirrors iOS EnhancedUserProfileView stats row: avg rating, total reviews, trust score.

class _PublicProfileStatsBar extends StatelessWidget {
  const _PublicProfileStatsBar({required this.userId});
  final String userId;

  Future<_ProfileStats> _load() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('reviews')
          .where('realtorId', isEqualTo: userId)
          .get();
      if (snap.docs.isEmpty) return const _ProfileStats();
      final ratings =
          snap.docs.map((d) => (d.data()['rating'] as num?)?.toInt() ?? 0);
      final avg = ratings.reduce((a, b) => a + b) / snap.docs.length;
      return _ProfileStats(
        averageRating: avg,
        totalReviews: snap.docs.length,
      );
    } catch (_) {
      return const _ProfileStats();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_ProfileStats>(
      future: _load(),
      builder: (context, snap) {
        final stats = snap.data ?? const _ProfileStats();
        if (stats.totalReviews == 0 && !snap.hasData) {
          return const SizedBox.shrink();
        }
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.05), blurRadius: 4),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _StatChip(
                icon: Icons.star,
                color: Colors.amber,
                value: stats.totalReviews > 0
                    ? stats.averageRating.toStringAsFixed(1)
                    : '—',
                label: 'Rating',
              ),
              _StatDivider(),
              _StatChip(
                icon: Icons.rate_review,
                color: AppColors.primary,
                value: '${stats.totalReviews}',
                label: 'Reviews',
              ),
              _StatDivider(),
              _StatChip(
                icon: Icons.verified_user,
                color: Colors.green,
                value: stats.totalReviews > 0 ? 'Active' : 'New',
                label: 'Status',
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ProfileStats {
  const _ProfileStats({this.averageRating = 0.0, this.totalReviews = 0});
  final double averageRating;
  final int totalReviews;
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
  });
  final IconData icon;
  final Color color;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 14),
            const SizedBox(width: 4),
            Text(value,
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 15)),
          ],
        ),
        const SizedBox(height: 2),
        Text(label,
            style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
      ],
    );
  }
}

class _StatDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      width: 1,
      color: AppColors.divider,
    );
  }
}
