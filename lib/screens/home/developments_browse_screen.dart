import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../constants/app_colors.dart';
import '../../models/project_model.dart';
import '../../models/user_profile_doc.dart';
import '../../providers/auth_provider.dart';
import '../../providers/user_role_provider.dart';
import '../../repositories/project_repository.dart';
import '../../repositories/user_profile_repository.dart';
import '../../screens/projects/edit_development_screen.dart';
import '../../utils/responsive.dart';
import '../../widgets/project_listing_card.dart';

/// Parity with iOS `ProjectListingsRootScreen` — large “Projects” title, search,
/// status chips, adaptive grid (`LazyVGrid`), `ProjectCardView`-style rows,
/// plus `ProjectViewModel.loadMoreIfNeeded` pagination (page size **50**).
class DevelopmentsBrowseScreen extends StatefulWidget {
  const DevelopmentsBrowseScreen({super.key});

  @override
  State<DevelopmentsBrowseScreen> createState() =>
      _DevelopmentsBrowseScreenState();
}

class _DevelopmentsBrowseScreenState extends State<DevelopmentsBrowseScreen> {
  final TextEditingController _queryController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  /// Matches iOS `ProjectStatus.allCases` order + `All`.
  static const List<(String?, String)> _statusChips = [
    (null, 'All'),
    ('planning', 'Planning'),
    ('pre-construction', 'Pre-construction'),
    ('pre-sale', 'Pre-construction'),
    ('under-construction', 'Under Construction'),
    ('completed', 'Completed'),
  ];

  static const int _pageSize = 50;

  /// Selected Firestore `status` raw, or `null` for All.
  String? _selectedStatusRaw;

  final List<ProjectModel> _projects = [];
  final Set<String> _seenFirestoreIds = {};

  DocumentSnapshot<Map<String, dynamic>>? _pageCursor;
  bool _hasMore = true;

  bool _loadingInitial = false;
  bool _loadingMore = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _queryController.addListener(_onQueryChanged);
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshCatalog());
  }

  void _onQueryChanged() => setState(() {});

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_loadingMore || !_hasMore || _loadingInitial) return;
    final position = _scrollController.position;
    final max = position.maxScrollExtent;
    if (max <= 0) return;
    // Near bottom — analogous to iOS last-row `onAppear`.
    if (position.pixels >= max - 480) {
      _appendNextPage();
    }
  }

  Future<void> _refreshCatalog() async {
    final repo = context.read<ProjectRepository>();
    setState(() {
      _loadingInitial = true;
      _error = null;
      _projects.clear();
      _seenFirestoreIds.clear();
      _pageCursor = null;
      _hasMore = true;
    });

    try {
      var page = await repo.fetchBrowseProjectsPage(limit: _pageSize);
      if (!mounted) return;
      _merge(page.projects, reset: true);
      _pageCursor = page.lastRawDocument;
      _hasMore = page.hasMore;

      // If every doc in early pages is filtered out (sample/invisible), keep paging
      // until we show something or exhaust the catalog — scroll cannot trigger yet.
      while (mounted && _projects.isEmpty && _hasMore) {
        page = await repo.fetchBrowseProjectsPage(
          limit: _pageSize,
          startAfter: _pageCursor,
        );
        if (!mounted) return;
        _merge(page.projects, reset: false);
        _pageCursor = page.lastRawDocument;
        _hasMore = page.hasMore;
      }

      if (!mounted) return;
      setState(() => _loadingInitial = false);
    } catch (e, st) {
      debugPrint('DevelopmentsBrowseScreen: refresh failed: $e\n$st');
      if (!mounted) return;
      setState(() {
        _error = e;
        _loadingInitial = false;
      });
    }
  }

  Future<void> _appendNextPage() async {
    if (!_hasMore || _loadingMore || _loadingInitial) return;

    final repo = context.read<ProjectRepository>();
    final cursor = _pageCursor;

    setState(() => _loadingMore = true);

    try {
      final page = await repo.fetchBrowseProjectsPage(
        limit: _pageSize,
        startAfter: cursor,
      );
      if (!mounted) return;
      setState(() {
        _merge(page.projects, reset: false);
        _pageCursor = page.lastRawDocument;
        _hasMore = page.hasMore;
        _loadingMore = false;
      });
    } catch (e, st) {
      debugPrint('DevelopmentsBrowseScreen: loadMore failed: $e\n$st');
      if (!mounted) return;
      setState(() => _loadingMore = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    }
  }

  void _merge(List<ProjectModel> incoming, {required bool reset}) {
    if (reset) {
      _projects
        ..clear()
        ..addAll(incoming);
      _seenFirestoreIds
        ..clear()
        ..addAll(_projects.map((e) => e.firestoreDocumentId));
      return;
    }
    for (final p in incoming) {
      final id = p.firestoreDocumentId;
      if (_seenFirestoreIds.add(id)) _projects.add(p);
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _queryController.removeListener(_onQueryChanged);
    _queryController.dispose();
    super.dispose();
  }

  bool _matchesSearch(ProjectModel p, String q) {
    final t = q.trim().toLowerCase();
    if (t.isEmpty) return true;
    return p.projectName.toLowerCase().contains(t) ||
        p.developerId.toLowerCase().contains(t) ||
        p.location.toLowerCase().contains(t);
  }

  bool _matchesStatus(ProjectModel p) {
    final sel = _selectedStatusRaw;
    if (sel == null) return true;
    return p.statusRaw.trim().toLowerCase() == sel.trim().toLowerCase();
  }

  List<ProjectModel> _applyFilters(List<ProjectModel> list, String query) {
    return list
        .where((p) => _matchesSearch(p, query) && _matchesStatus(p))
        .toList();
  }

  Future<void> _createProject(BuildContext context) async {
    final auth = context.read<AuthProvider>();
    final repo = context.read<ProjectRepository>();
    final uid = auth.user?.uid;
    if (uid == null) return;
    final name = auth.user!.displayName?.trim().isNotEmpty == true
        ? auth.user!.displayName!.trim()
        : 'Developer';
    try {
      final id = await repo.createDraftProject(
        developerUserId: uid,
        developerDisplayName: name,
      );
      if (!context.mounted) return;
      final isTablet = Responsive.isTablet(context);
      if (isTablet) {
        context.push('/development/$id/edit');
      } else {
        await Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            fullscreenDialog: true,
            builder: (_) => EditDevelopmentScreen(
              projectId: id,
              isCreating: true,
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final auth = context.watch<AuthProvider>();
    final uid = auth.user?.uid;
    final profileRepo = context.read<UserProfileRepository>();
    final role = context.watch<UserRoleProvider>();

    final filtered =
        _applyFilters(_projects, _queryController.text);

    return StreamBuilder<UserProfileDoc?>(
      stream:
          uid != null ? profileRepo.watchUserProfile(uid) : Stream.value(null),
      builder: (context, profileSnap) {
        final doc = profileSnap.data;
        final canCreate = doc?.hasDeveloperEquivalentAccess(
              mergedIsAdmin: role.isAdmin,
            ) ??
            role.isAdmin;
        final fullscreenSheet =
            ModalRoute.of(context)?.fullscreenDialog == true;

        return Scaffold(
          backgroundColor: scheme.surface,
          body: RefreshIndicator(
            color: AppColors.primary,
            onRefresh: _refreshCatalog,
            child: CustomScrollView(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              slivers: [
                SliverAppBar.large(
                  backgroundColor: scheme.surface,
                  surfaceTintColor: Colors.transparent,
                  pinned: true,
                  automaticallyImplyLeading: !fullscreenSheet,
                  leading: fullscreenSheet
                      ? IconButton(
                          icon: const Icon(Icons.close),
                          tooltip: 'Done',
                          onPressed: () =>
                              Navigator.of(context).maybePop(),
                        )
                      : null,
                  title: const Text('Projects'),
                  actions: [
                    if (canCreate)
                      IconButton(
                        tooltip: 'Create Project',
                        onPressed: () => _createProject(context),
                        icon: const Icon(Icons.add_circle_rounded),
                      ),
                  ],
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: SearchBar(
                      hintText: 'Search projects, developers, locations',
                      controller: _queryController,
                      leading: const Icon(Icons.search_rounded),
                      trailing: _queryController.text.trim().isNotEmpty
                          ? [
                              IconButton(
                                icon: const Icon(Icons.clear_rounded),
                                onPressed: () {
                                  _queryController.clear();
                                },
                              ),
                            ]
                          : null,
                    ),
                  ),
                ),
                SliverToBoxAdapter(child: _filterStrip(context, filtered.length)),
                if (_loadingInitial && _projects.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Padding(
                        padding: EdgeInsets.only(top: 24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 12),
                            Text('Loading projects…'),
                          ],
                        ),
                      ),
                    ),
                  )
                else if (_error != null && _projects.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _EmptyProjectsState(
                      title: 'Couldn’t load projects',
                      subtitle: '$_error',
                      icon: Icons.wifi_find_rounded,
                    ),
                  )
                else if (filtered.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: _EmptyProjectsState(
                      title: 'No projects found',
                      subtitle:
                          'Try adjusting your search or filters.',
                      icon: Icons.domain_outlined,
                    ),
                  )
                else ...[
                  _buildGrid(context, filtered),
                  if (_loadingMore)
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.only(top: 8, bottom: 20),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    ),
                ],
                const SliverToBoxAdapter(child: SizedBox(height: 24)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _filterStrip(BuildContext context, int filteredCount) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _statusChips.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, i) {
                final raw = _statusChips[i].$1;
                final title = _statusChips[i].$2;
                final selected = _selectedStatusRaw == raw;
                return _FilterChip(
                  title: title,
                  selected: selected,
                  onTap: () => setState(() => _selectedStatusRaw = raw),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '$filteredCount ${filteredCount == 1 ? 'project' : 'projects'}',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGrid(BuildContext context, List<ProjectModel> filteredLive) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    const horizontalPad = 16.0;
    const spacing = 16.0;
    const minTile = 280.0;
    const cardMainExtent = 312.0;
    final inner = screenWidth - horizontalPad * 2;
    final cols =
        ((inner + spacing) / (minTile + spacing)).floor().clamp(1, 8);
    final cellW = (inner - (cols - 1) * spacing) / cols;
    final aspect = cellW / cardMainExtent;

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(horizontalPad, 8, horizontalPad, 0),
      sliver: SliverGrid(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols,
          mainAxisSpacing: spacing,
          crossAxisSpacing: spacing,
          childAspectRatio: aspect,
        ),
        delegate: SliverChildBuilderDelegate(
          childCount: filteredLive.length,
          (context, index) {
            final p = filteredLive[index];
            return ProjectListingCard(
              project: p,
              onTap: () =>
                  context.push('/development/${p.firestoreDocumentId}'),
            );
          },
        ),
      ),
    );
  }
}

/// iOS `filterChip` — capsule, primary fill when selected.
class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.title,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: selected ? Colors.white : scheme.onSurface,
                ),
          ),
        ),
      ),
    );
  }
}

class _EmptyProjectsState extends StatelessWidget {
  const _EmptyProjectsState({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 28, 16, 24),
      child: Column(
        children: [
          Icon(icon, size: 44, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}
