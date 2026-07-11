import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../constants/app_colors.dart';
import '../../models/project_interest_row.dart';
import '../../models/project_model.dart';
import '../../repositories/project_repository.dart';
import '../../repositories/user_profile_repository.dart';
import '../../widgets/dashboard_interest_tile.dart';
import 'profile_subscreen_widgets.dart';

/// Full list of registered interests — iOS `CustomerDashboardRootScreen` “My Interests” section.
class MyDevelopmentsScreen extends StatefulWidget {
  const MyDevelopmentsScreen({super.key, required this.userId});

  final String userId;

  @override
  State<MyDevelopmentsScreen> createState() => _MyDevelopmentsScreenState();
}

class _MyDevelopmentsScreenState extends State<MyDevelopmentsScreen> {
  Future<void> _onRefresh() async {
    // Firebase stream-backed; keep pull-to-refresh affordance.
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }

  @override
  Widget build(BuildContext context) {
    final projectsRepo = context.read<ProjectRepository>();

    return ProfileGroupedScaffold(
      title: 'My Developments',
      child: StreamBuilder<List<ProjectModel>>(
        stream: projectsRepo.watchBrowseProjects(),
        builder: (context, projectSnap) {
          final projects = projectSnap.data ?? const <ProjectModel>[];
          final profileRepo = context.read<UserProfileRepository>();

          return StreamBuilder<List<ProjectInterestRow>>(
            stream: profileRepo.watchMyDevelopments(widget.userId),
            builder: (context, snapshot) {
              if (!snapshot.hasData && snapshot.error == null) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return ProfileErrorState(
                  message: snapshot.error.toString(),
                  onRetry: _onRefresh,
                );
              }

              final items = snapshot.data ?? const <ProjectInterestRow>[];

              final interestRows = <Widget>[];
              for (var i = 0; i < items.length; i++) {
                if (i > 0) {
                  interestRows.add(
                    const Divider(
                      height: 1,
                      thickness: 1,
                      color: AppColors.divider,
                    ),
                  );
                }
                final row = items[i];
                final project = projectForInterest(projects, row);
                interestRows.add(
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

              return RefreshIndicator(
                onRefresh: _onRefresh,
                color: AppColors.primary,
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    const SliverPadding(
                      padding: ProfileLayout.pagePadding,
                      sliver: SliverToBoxAdapter(
                        child: ProfileSectionHeader('My Interests'),
                      ),
                    ),
                    if (items.isEmpty)
                      const SliverFillRemaining(
                        hasScrollBody: false,
                        child: ProfileEmptyState(
                          icon: Icons.domain_outlined,
                          title: 'No interests yet',
                          subtitle:
                              'Register your interest in developments to see them here.',
                        ),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(
                          16,
                          0,
                          16,
                          32,
                        ),
                        sliver: SliverToBoxAdapter(
                          child: Card(
                            clipBehavior: Clip.antiAlias,
                            elevation: 0,
                            color: Theme.of(context).colorScheme.surface,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                ProfileTokens.radiusCard,
                              ),
                              side: BorderSide(
                                color: Theme.of(context)
                                    .colorScheme
                                    .outlineVariant
                                    .withValues(alpha: 0.35),
                              ),
                            ),
                            child: Column(children: interestRows),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
