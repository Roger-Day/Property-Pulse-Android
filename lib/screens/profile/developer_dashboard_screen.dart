import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../constants/app_colors.dart';
import '../../models/project_interest_model.dart';
import '../../models/project_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/user_role_provider.dart';
import '../../repositories/project_repository.dart';
import '../../services/analytics_service.dart';
import '../../services/lead_credit_service.dart';
import '../../models/development_team_role.dart';
import '../../utils/effective_development_role.dart';
import '../../utils/responsive.dart';
import '../../utils/team_access_permissions.dart';
import '../developer/lead_credit_topup_screen.dart';
import '../projects/edit_development_screen.dart';
import '../projects/sales_pipeline_screen.dart';

/// Developer / new-build hub — parity with iOS `DeveloperDashboardView` (KPIs, pipeline, inventory, leads).
class DeveloperDashboardScreen extends StatefulWidget {
  const DeveloperDashboardScreen({super.key});

  @override
  State<DeveloperDashboardScreen> createState() => _DeveloperDashboardScreenState();
}

class _DeveloperDashboardScreenState extends State<DeveloperDashboardScreen> {
  @override
  void initState() {
    super.initState();
    AnalyticsService.logDashboardView('developer');
  }

  @override
  Widget build(BuildContext context) {
    // select<> rebuilds only when the UID itself changes (sign-in/out), not
    // on unrelated AuthProvider notifications (e.g. email-verification state).
    final uid = context.select<AuthProvider, String?>((a) => a.user?.uid);
    if (uid == null || uid.isEmpty) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(title: const Text('Developer Dashboard')),
        body: const Center(child: Text('Sign in to view your developer tools.')),
      );
    }

    final repo = context.read<ProjectRepository>();
    final isAdmin = context.select<UserRoleProvider, bool>((p) => p.isAdmin);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Developer Dashboard'),
        backgroundColor: AppColors.surface,
      ),
      body: StreamBuilder<List<ProjectModel>>(
        stream: repo.watchMyPortfolioProjects(uid, isAdmin: isAdmin),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(snap.error.toString(), textAlign: TextAlign.center),
              ),
            );
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final projects = snap.data!;
          return _PortfolioWithInterests(
            uid: uid,
            projects: projects,
            isAdmin: isAdmin,
          );
        },
      ),
    );
  }
}

class _PortfolioWithInterests extends StatefulWidget {
  const _PortfolioWithInterests({
    required this.uid,
    required this.projects,
    required this.isAdmin,
  });

  final String uid;
  final List<ProjectModel> projects;
  final bool isAdmin;

  @override
  State<_PortfolioWithInterests> createState() => _PortfolioWithInterestsState();
}

class _PortfolioWithInterestsState extends State<_PortfolioWithInterests> {
  final Map<String, List<ProjectInterestModel>> _byProject = {};
  final List<StreamSubscription<List<ProjectInterestModel>>> _subs = [];

  // Lets the fullscreen Sales Pipeline route (pushed via Navigator, so it
  // isn't rebuilt by this widget's own setState) stay live — without this,
  // moving a lead's stage there updated Firestore but the board kept
  // showing the card in its old column until the user backed out and
  // reopened it.
  final ValueNotifier<List<LeadWithProject>> _leadsNotifier =
      ValueNotifier(const []);

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(covariant _PortfolioWithInterests oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_sameProjectIds(oldWidget.projects, widget.projects)) {
      _subscribe();
    }
  }

  bool _sameProjectIds(List<ProjectModel> a, List<ProjectModel> b) {
    if (a.length != b.length) return false;
    final sa = a.map((e) => e.firestoreDocumentId).toSet();
    final sb = b.map((e) => e.firestoreDocumentId).toSet();
    return sa.length == sb.length && sa.containsAll(sb);
  }

  void _subscribe() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    _byProject.clear();

    final repo = context.read<ProjectRepository>();
    final limited = widget.projects.take(20).toList();

    for (final p in limited) {
      final id = p.firestoreDocumentId;
      _subs.add(
        repo.watchProjectInterests(id).listen((list) {
          if (mounted) {
            setState(() => _byProject[id] = list);
            _leadsNotifier.value = _allLeads;
          }
        },
            // Viewer-role members can see the project but the `interests`
            // read rule only allows Owner/Manager/Sales — treat that (or any
            // other listener failure) as "no leads visible" instead of an
            // unhandled stream error on every dashboard open.
            onError: (_) {
          if (mounted) {
            setState(() => _byProject[id] = const []);
            _leadsNotifier.value = _allLeads;
          }
        }),
      );
    }
    setState(() {});
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _leadsNotifier.dispose();
    super.dispose();
  }

  List<LeadWithProject> get _allLeads {
    final out = <LeadWithProject>[];
    for (final p in widget.projects.take(20)) {
      final id = p.firestoreDocumentId;
      final list = _byProject[id] ?? const <ProjectInterestModel>[];
      for (final interest in list) {
        out.add(
          LeadWithProject(
            interest: interest,
            projectName: p.projectName,
            projectId: id,
          ),
        );
      }
    }
    out.sort((a, b) {
      final an = a.interest.contactedAt == null;
      final bn = b.interest.contactedAt == null;
      if (an != bn) return an ? -1 : 1;
      final ad = a.interest.contactedAt ?? a.interest.createdAt;
      final bd = b.interest.contactedAt ?? b.interest.createdAt;
      return bd.compareTo(ad);
    });
    return out;
  }

  _DashboardKpi get _kpi {
    final leads = _allLeads;
    final uncontacted = leads.where((l) => l.interest.contactedAt == null).length;
    final contactedPct = leads.isEmpty
        ? 0
        : ((leads.length - uncontacted) / leads.length * 100).round();
    final active = widget.projects
        .where((p) => p.isActive && !p.isExpired)
        .length;
    return _DashboardKpi(
      totalProjects: widget.projects.length,
      activeProjects: active,
      totalLeads: leads.length,
      uncontactedLeads: uncontacted,
      contactedPercent: contactedPct,
    );
  }

  Future<void> _onStageChange(LeadWithProject lead, String stage) async {
    final repo = context.read<ProjectRepository>();
    try {
      await repo.updateProjectInterestConversionStatus(
        projectId: lead.projectId,
        interestId: lead.interest.id,
        conversionStatus: stage,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Moved to ${stage[0].toUpperCase()}${stage.substring(1)}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _createDraft(BuildContext context) async {
    final auth = context.read<AuthProvider>();
    final repo = context.read<ProjectRepository>();
    final uid = auth.user?.uid;
    if (uid == null) return;
    final name = auth.user?.displayName?.trim().isNotEmpty == true
        ? auth.user!.displayName!.trim()
        : 'Developer';
    try {
      final id = await repo.createDraftProject(
        developerUserId: uid,
        developerDisplayName: name,
      );
      if (!context.mounted) return;
      // Matches iOS: iPhone presents ProjectEditorView(mode: .create) as a sheet;
      // iPad pushes it. On Android we use fullscreenDialog (slides up from the
      // bottom like an iOS sheet) on phones, and a standard push on tablets.
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  void _openPipelineFullscreen(BuildContext context) {
    _leadsNotifier.value = _allLeads;
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (ctx) => ValueListenableBuilder<List<LeadWithProject>>(
          valueListenable: _leadsNotifier,
          builder: (ctx, leads, _) => SalesPipelineScreen(
            leads: leads,
            onLeadStageChange: (lead, stage) async {
              await _onStageChange(lead, stage);
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final kpi = _kpi;
    final hot = _allLeads.take(8).toList();
    final portfolioName =
        widget.projects.isEmpty ? 'Portfolio' : widget.projects.first.projectName;
    final limitedProjects = widget.projects.take(24).toList();

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () async {
        setState(() {});
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: Responsive.hPadding(context, top: 12, bottom: 32),
        children: [
          _HeaderCard(
            portfolioName: portfolioName,
            contactedPercent: kpi.contactedPercent,
          ),
          const SizedBox(height: 14),
          _ActionRow(
            onNewProject: () => _createDraft(context),
            onBrowse: () => context.go('/search'),
            onLeads: () {
              final first = limitedProjects.firstOrNull;
              if (first == null) return;
              context.push(
                '/home/development/${first.firestoreDocumentId}/leads',
                extra: first.projectName,
              );
            },
            onPipelineFull: () => _openPipelineFullscreen(context),
            hasProjects: limitedProjects.isNotEmpty,
          ),
          const SizedBox(height: 18),
          _LeadCreditsBanner(uid: widget.uid),
          const SizedBox(height: 14),
          _KpiGrid(kpi: kpi),
          const SizedBox(height: 20),
          Row(
            children: [
              Text(
                'Sales pipeline',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _allLeads.isEmpty ? null : () => _openPipelineFullscreen(context),
                icon: const Icon(Icons.open_in_full, size: 18),
                label: const Text('Full screen'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_allLeads.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  'No leads across your projects yet. When buyers register interest, they appear here and in columns by stage.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                ),
              ),
            )
          else
            SalesPipelineBoard(
              leads: _allLeads,
              onSelectLead: (lead) {
                showLeadConversionPicker(
                  context,
                  lead: lead,
                  onPick: (stage) => _onStageChange(lead, stage),
                );
              },
            ),
          const SizedBox(height: 24),
          Text(
            'Priority leads',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 8),
          if (hot.isEmpty)
            Text(
              'No activity yet.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            )
          else
            ...hot.map(
              (l) => _HotLeadRow(
                lead: l,
                onOpen: () {
                  context.push(
                    '/home/development/${l.projectId}/leads',
                    extra: l.projectName,
                  );
                },
              ),
            ),
          const SizedBox(height: 24),
          Text(
            'Projects & units',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 8),
          if (limitedProjects.isEmpty)
            Text(
              'No developments in your portfolio. Create a project or join a team on iOS/web if invited.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            )
          else
            ...limitedProjects.map(
              (p) => _ProjectManagementCard(
                project: p,
                uid: widget.uid,
                isAdmin: widget.isAdmin,
              ),
            ),
        ],
      ),
    );
  }
}

extension _FirstOrNull<E> on List<E> {
  E? get firstOrNull => isEmpty ? null : first;
}

class _DashboardKpi {
  const _DashboardKpi({
    required this.totalProjects,
    required this.activeProjects,
    required this.totalLeads,
    required this.uncontactedLeads,
    required this.contactedPercent,
  });

  final int totalProjects;
  final int activeProjects;
  final int totalLeads;
  final int uncontactedLeads;
  final int contactedPercent;
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({
    required this.portfolioName,
    required this.contactedPercent,
  });

  final String portfolioName;
  final int contactedPercent;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.indigo.shade50,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(Icons.apartment, size: 32, color: Colors.indigo.shade400),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    portfolioName,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Contacted $contactedPercent% of leads',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.onNewProject,
    required this.onBrowse,
    required this.onLeads,
    required this.onPipelineFull,
    required this.hasProjects,
  });

  final VoidCallback onNewProject;
  final VoidCallback onBrowse;
  final VoidCallback onLeads;
  final VoidCallback onPipelineFull;
  final bool hasProjects;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilledButton.icon(
          onPressed: onNewProject,
          icon: const Icon(Icons.add_circle_outline),
          label: const Text('New project'),
        ),
        OutlinedButton.icon(
          onPressed: onBrowse,
          icon: const Icon(Icons.explore_outlined),
          label: const Text('Browse'),
        ),
        OutlinedButton.icon(
          onPressed: hasProjects ? onLeads : null,
          icon: const Icon(Icons.people_outline),
          label: const Text('Leads'),
        ),
        OutlinedButton.icon(
          onPressed: onPipelineFull,
          icon: const Icon(Icons.view_week_outlined),
          label: const Text('Pipeline'),
        ),
      ],
    );
  }
}

// ── Lead Credits Banner ────────────────────────────────────────────────────────

class _LeadCreditsBanner extends StatelessWidget {
  const _LeadCreditsBanner({required this.uid});

  final String uid;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('developers')
          .doc(uid)
          .snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data() ?? {};
        final balance = (data['paidCredits'] as num?)?.toDouble() ?? 0.0;
        final freeLeads = (data['freeLeads'] as num?)?.toInt() ?? 0;

        // Determine pricing tier label.
        String tierLabel;
        if (balance >= 200) {
          tierLabel = '~\$6 / lead (volume)';
        } else if (balance >= 100) {
          tierLabel = '~\$8 / lead';
        } else {
          tierLabel = '~\$9 / lead (base rate)';
        }

        return Card(
          elevation: 0,
          color: AppColors.surface,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: AppColors.border),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header row
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.credit_card,
                        size: 22,
                        color: Colors.green.shade600,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Lead Credits',
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          Text(
                            'Charged per buyer inquiry',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '\$${balance.toStringAsFixed(2)}',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: balance > 0
                                    ? AppColors.primary
                                    : AppColors.error,
                              ),
                        ),
                        Text(
                          'balance',
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Pricing tier + free leads row
                Row(
                  children: [
                    _CreditInfoChip(
                      icon: Icons.local_offer_outlined,
                      label: tierLabel,
                    ),
                    if (freeLeads > 0) ...[
                      const SizedBox(width: 8),
                      _CreditInfoChip(
                        icon: Icons.card_giftcard_outlined,
                        label: '$freeLeads free remaining',
                        color: AppColors.success,
                      ),
                    ],
                  ],
                ),

                if (balance < 10) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.warning_amber_rounded,
                            size: 16, color: Colors.orange.shade700),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Low balance — top up to keep receiving leads.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.orange.shade900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.of(context).push<void>(
                        MaterialPageRoute<void>(
                          fullscreenDialog: true,
                          builder: (_) => LeadCreditTopUpScreen(
                            currentBalance: balance,
                            onPurchaseCompleted: () {
                              // Firestore stream auto-refreshes — nothing extra needed.
                            },
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.add_circle_outline, size: 18),
                    label: const Text('Top Up Credits'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CreditInfoChip extends StatelessWidget {
  const _CreditInfoChip({
    required this.icon,
    required this.label,
    this.color = AppColors.textSecondary,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(fontSize: 12, color: color),
          ),
        ],
      ),
    );
  }
}

// ── KPI Grid ───────────────────────────────────────────────────────────────────

class _KpiGrid extends StatelessWidget {
  const _KpiGrid({required this.kpi});

  final _DashboardKpi kpi;

  @override
  Widget build(BuildContext context) {
    final chips = [
      ('Projects', '${kpi.totalProjects}'),
      ('Active', '${kpi.activeProjects}'),
      ('Leads', '${kpi.totalLeads}'),
      ('New (no contact)', '${kpi.uncontactedLeads}'),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: chips
          .map(
            (c) => Chip(
              avatar: const Icon(Icons.insights, size: 18, color: AppColors.primary),
              label: Text('${c.$1}: ${c.$2}'),
            ),
          )
          .toList(),
    );
  }
}

class _HotLeadRow extends StatelessWidget {
  const _HotLeadRow({required this.lead, required this.onOpen});

  final LeadWithProject lead;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.person_outline)),
        title: Text(
          lead.interest.name,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(lead.projectName),
        trailing: const Icon(Icons.chevron_right),
        onTap: onOpen,
      ),
    );
  }
}

class _ProjectManagementCard extends StatefulWidget {
  const _ProjectManagementCard({
    required this.project,
    required this.uid,
    required this.isAdmin,
  });

  final ProjectModel project;
  final String uid;
  final bool isAdmin;

  @override
  State<_ProjectManagementCard> createState() => _ProjectManagementCardState();
}

class _ProjectManagementCardState extends State<_ProjectManagementCard> {
  // Built once per (project, uid) — creating it inside build() re-subscribed
  // on every dashboard rebuild and flashed the role back to "unknown".
  Stream<DevelopmentTeamRole?>? _roleStream;
  String? _roleStreamKey;

  Stream<DevelopmentTeamRole?> _roleStreamFor(BuildContext context) {
    final key = '${widget.project.firestoreDocumentId}|${widget.uid}';
    if (_roleStream == null || _roleStreamKey != key) {
      _roleStreamKey = key;
      _roleStream = context
          .read<ProjectRepository>()
          .watchMyTeamRole(widget.project.firestoreDocumentId, widget.uid);
    }
    return _roleStream!;
  }

  @override
  Widget build(BuildContext context) {
    final project = widget.project;
    final uid = widget.uid;
    final isAdmin = widget.isAdmin;
    final pid = project.firestoreDocumentId;
    final thumb = project.primaryImageUrl;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            leading: thumb != null && thumb.isNotEmpty
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: CachedNetworkImage(
                      imageUrl: thumb,
                      width: 56,
                      height: 56,
                      fit: BoxFit.cover,
                      // 56dp × 2× density = 112px decoded cap.
                      memCacheWidth: 112,
                      memCacheHeight: 112,
                    ),
                  )
                : const Icon(Icons.business, size: 40),
            title: Text(
              project.projectName,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              project.location.isEmpty ? 'Location TBA' : project.location,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: StreamBuilder<DevelopmentTeamRole?>(
              stream: _roleStreamFor(context),
              builder: (context, roleSnap) {
                // Real Owner/Manager/Sales/Viewer tier from the team roster
                // — the old `teamMembers.contains(uid)` check enabled Leads
                // and Units for every tier, including read-only Viewers.
                final role = resolveEffectiveDevelopmentRole(
                  isAppAdmin: isAdmin,
                  currentUserId: uid,
                  project: project,
                  firestoreTeamDocRole: roleSnap.data,
                );
                final canLeads = TeamAccessPermissions.canManageLeads(role);
                final canUnits = TeamAccessPermissions.canManageUnits(role);
                return Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _MiniAction(
                  label: 'Leads',
                  icon: Icons.people_outline,
                  onTap: canLeads
                      ? () => context.push('/development/$pid/leads', extra: project.projectName)
                      : null,
                ),
                _MiniAction(
                  label: 'Units',
                  icon: Icons.grid_view_outlined,
                  onTap: canUnits
                      ? () => context.push('/development/$pid/inventory')
                      : null,
                ),
                _MiniAction(
                  label: 'Team',
                  icon: Icons.groups_outlined,
                  onTap: () => context.push('/development/$pid/team'),
                ),
                _MiniAction(
                  label: 'Edit',
                  icon: Icons.edit_outlined,
                  onTap: () => context.push('/development/$pid/edit'),
                ),
              ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniAction extends StatelessWidget {
  const _MiniAction({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}
