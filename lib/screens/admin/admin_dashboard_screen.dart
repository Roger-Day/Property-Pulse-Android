import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../constants/app_colors.dart';
import '../../models/blocked_word.dart';
import '../../models/moderation_flags.dart';
import '../../models/moderation_log.dart';
import '../../models/moderation_stats.dart';
import '../../providers/moderation_feature_flags_provider.dart';
import '../../repositories/admin_repository.dart';
import '../../services/dispute_service.dart';
import '../../utils/responsive.dart';
import '../host/dispute_detail_screen.dart';
import '../profile/edit_property_screen.dart';
import 'admin_analytics_tab.dart';
import 'admin_moderation_detail_sheet.dart';
import 'admin_settings_tab.dart';
import 'admin_user_detail_screen.dart';

/// Tabbed admin shell — layout aligned with iOS `AdminDashboardView`:
/// welcome header, stat cards, horizontal pill tabs, rich Overview.
class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  int _tabIndex = 0;

  static const _tabs = <_AdminTabDef>[
    _AdminTabDef('Overview', Icons.home_rounded, Color(0xFF007AFF)),
    _AdminTabDef('Applications', Icons.description_outlined, Color(0xFF5856D6)),
    _AdminTabDef('Verification', Icons.verified_user_outlined, Color(0xFF34C759)),
    _AdminTabDef('Moderation', Icons.shield_outlined, Color(0xFFFF9500)),
    _AdminTabDef('Users', Icons.people_outline, Color(0xFF5E5CE6)),
    _AdminTabDef('Properties', Icons.apartment_outlined, Color(0xFF00C7BE)),
    _AdminTabDef('Analytics', Icons.bar_chart_outlined, Color(0xFFFF2D55)),
    _AdminTabDef('Developments', Icons.business_outlined, Color(0xFF8E8E93)),
    _AdminTabDef('Bookings', Icons.gavel_outlined, Color(0xFFFF6B6B)),
    _AdminTabDef('Settings', Icons.settings_outlined, Color(0xFF8E8E93)),
  ];

  void _goTab(int i) {
    if (i < 0 || i >= _tabs.length) return;
    setState(() => _tabIndex = i);
  }

  @override
  Widget build(BuildContext context) {
    final admin = context.read<AdminRepository>();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Admin Dashboard'),
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => _goTab(9),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _AdminDashboardHeader(
            admin: admin,
            onUsersTap: () => _goTab(4),
            onAlertsTap: () => _goTab(3),
          ),
          _AdminHorizontalTabBar(
            tabs: _tabs,
            selectedIndex: _tabIndex,
            onSelect: _goTab,
          ),
          Expanded(
            child: IndexedStack(
              index: _tabIndex,
              children: [
                _OverviewTab(
                  admin: admin,
                  onQuickAction: _goTab,
                ),
                _ApplicationsTabEnhanced(admin: admin),
                _VerificationHubTab(admin: admin),
                _ModerationHubTab(admin: admin),
                _UsersTab(admin: admin),
                _PropertiesTab(admin: admin),
                const AdminAnalyticsTab(),
                _DevelopmentsTab(admin: admin),
                _BookingModerationTab(admin: admin),
                const AdminSettingsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminTabDef {
  const _AdminTabDef(this.label, this.icon, this.accent);
  final String label;
  final IconData icon;
  final Color accent;
}

// ─────────────────────────────────────────────────────────────────────────────
// Header + iOS-style tab strip (fixed under AppBar)
// ─────────────────────────────────────────────────────────────────────────────

class _AdminDashboardHeader extends StatelessWidget {
  const _AdminDashboardHeader({
    required this.admin,
    required this.onUsersTap,
    required this.onAlertsTap,
  });

  final AdminRepository admin;
  final VoidCallback onUsersTap;
  final VoidCallback onAlertsTap;

  @override
  Widget build(BuildContext context) {
    final pad = Responsive.hPadding(context, top: 12, bottom: 8);
    return Padding(
      padding: pad,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Welcome back, Admin',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            'Manage your Property Pulse platform',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: onUsersTap,
                  icon: const Icon(Icons.people_outline, size: 20),
                  label: const Text('Users'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: onAlertsTap,
                  icon: const Icon(Icons.warning_amber_rounded, size: 20),
                  label: const Text('Alerts'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}


extension on Color {
  Color darken([double amount = .25]) {
    final hsl = HSLColor.fromColor(this);
    return hsl.withLightness((hsl.lightness - amount).clamp(0.0, 1.0)).toColor();
  }
}

class _AdminHorizontalTabBar extends StatelessWidget {
  const _AdminHorizontalTabBar({
    required this.tabs,
    required this.selectedIndex,
    required this.onSelect,
  });

  final List<_AdminTabDef> tabs;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.background,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: Responsive.hPadding(context, bottom: 8),
        child: Row(
          children: [
            for (var i = 0; i < tabs.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              _AdminTabPill(
                tab: tabs[i],
                selected: i == selectedIndex,
                onTap: () => onSelect(i),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AdminTabPill extends StatelessWidget {
  const _AdminTabPill({
    required this.tab,
    required this.selected,
    required this.onTap,
  });

  final _AdminTabDef tab;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bg = selected
        ? tab.accent.withValues(alpha: 0.22)
        : Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.6);
    final fg = selected ? tab.accent.darken(0.05) : AppColors.textSecondary;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(tab.icon, size: 18, color: fg),
              const SizedBox(width: 6),
              Text(
                tab.label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: fg,
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
// Overview
// ─────────────────────────────────────────────────────────────────────────────

class _OverviewTab extends StatefulWidget {
  const _OverviewTab({
    required this.admin,
    required this.onQuickAction,
  });

  final AdminRepository admin;
  final ValueChanged<int> onQuickAction;

  @override
  State<_OverviewTab> createState() => _OverviewTabState();
}

class _OverviewTabState extends State<_OverviewTab> {
  List<Map<String, dynamic>> _verifications = const [];
  List<Map<String, dynamic>> _reports = const [];
  List<Map<String, dynamic>> _moderation = const [];
  List<Map<String, dynamic>> _adminApplications = const [];
  StreamSubscription<List<Map<String, dynamic>>>? _subVer;
  StreamSubscription<List<Map<String, dynamic>>>? _subRep;
  StreamSubscription<List<Map<String, dynamic>>>? _subMod;
  StreamSubscription<List<Map<String, dynamic>>>? _subApps;

  @override
  void initState() {
    super.initState();
    _subVer = widget.admin.watchVerificationRequests().listen((v) {
      if (mounted) setState(() => _verifications = v);
    });
    _subRep = widget.admin.watchPropertyReports().listen((r) {
      if (mounted) setState(() => _reports = r);
    });
    _subMod = widget.admin.watchModerationReports().listen((m) {
      if (mounted) setState(() => _moderation = m);
    });
    _subApps = widget.admin.watchAdminApplications().listen((a) {
      if (mounted) setState(() => _adminApplications = a);
    });
  }

  @override
  void dispose() {
    _subVer?.cancel();
    _subRep?.cancel();
    _subMod?.cancel();
    _subApps?.cancel();
    super.dispose();
  }

  List<_ActivityItem> _buildActivity() {
    final items = <_ActivityItem>[];
    for (final r in _moderation.take(40)) {
      final id = r['id'] as String? ?? '';
      final st = r['status'] as String? ?? 'open';
      final ts = AdminRepository.timestampMillis(r['updatedAt']) != 0
          ? AdminRepository.timestampMillis(r['updatedAt'])
          : AdminRepository.timestampMillis(r['createdAt']);
      final target = r['targetType'] as String? ?? 'content';
      items.add(_ActivityItem(
        icon: Icons.shield_outlined,
        color: const Color(0xFFFF3B30),
        title: 'Moderation report ($target)',
        subtitle: '${r['reason'] ?? 'Report'} · $st',
        millis: ts,
        docId: id,
      ));
    }
    // Admin applications from the real collection (mirrors iOS AdminApplicationService)
    for (final r in _adminApplications.take(5)) {
      final id = r['id'] as String? ?? '';
      final st = r['status'] as String? ?? 'pending';
      final ts = AdminRepository.timestampMillis(r['createdAt']);
      items.add(_ActivityItem(
        icon: Icons.description_outlined,
        color: const Color(0xFF5856D6),
        title: 'Admin application',
        subtitle: '${r['applicantName'] ?? 'Applicant'} · $st',
        millis: ts,
        docId: id,
      ));
    }
    // Identity verification requests from verificationRequests collection
    for (final r in _verifications.where(AdminRepository.isIdentityVerification).take(5)) {
      final id = r['id'] as String? ?? '';
      final st = r['status'] as String? ?? 'pending';
      final ts = AdminRepository.timestampMillis(r['updatedAt']) != 0
          ? AdminRepository.timestampMillis(r['updatedAt'])
          : AdminRepository.timestampMillis(r['createdAt']);
      items.add(_ActivityItem(
        icon: Icons.verified_user_outlined,
        color: const Color(0xFF34C759),
        title: 'Verification request',
        subtitle: 'User ${r['userId'] ?? '—'} · $st',
        millis: ts,
        docId: id,
      ));
    }
    for (final r in _reports.take(40)) {
      final id = r['id'] as String? ?? '';
      final st = r['status'] as String? ?? 'pending';
      final ts = AdminRepository.timestampMillis(r['updatedAt']) != 0
          ? AdminRepository.timestampMillis(r['updatedAt'])
          : AdminRepository.timestampMillis(r['createdAt']);
      items.add(_ActivityItem(
        icon: Icons.flag_outlined,
        color: const Color(0xFFFF9500),
        title: 'Property report',
        subtitle: '${r['reason'] ?? 'Report'} · $st',
        millis: ts,
        docId: id,
      ));
    }
    items.sort((a, b) => b.millis.compareTo(a.millis));
    return items.take(8).toList();
  }

  @override
  Widget build(BuildContext context) {
    // ── Derived counts (mirrors iOS overviewContent computed properties) ──────
    // Admin applications come from the real `adminApplications` collection,
    // same as iOS AdminApplicationService — NOT from verificationRequests.
    final adminApps = _adminApplications;

    final pendingApps =
        adminApps.where((d) => (d['status'] as String? ?? 'pending') == 'pending').length;
    final approvedApps =
        adminApps.where((d) => (d['status'] as String? ?? '') == 'approved').length;
    final now = DateTime.now();
    final thisMonthApps = adminApps.where((d) {
      final ms = AdminRepository.timestampMillis(d['createdAt']);
      if (ms == 0) return false;
      final dt = DateTime.fromMillisecondsSinceEpoch(ms);
      return dt.year == now.year && dt.month == now.month;
    }).length;

    final pendingKyc = _verifications
        .where(AdminRepository.isIdentityVerification)
        .where((d) => (d['status'] as String? ?? 'pending') == 'pending')
        .length;
    final verifiedKyc = _verifications
        .where(AdminRepository.isIdentityVerification)
        .where((d) => (d['status'] as String? ?? '') == 'approved')
        .length;
    final recentVerifications = _verifications
        .where(AdminRepository.isIdentityVerification)
        .toList()
      ..sort((a, b) {
        final ta = AdminRepository.timestampMillis(a['updatedAt'] ?? a['createdAt']);
        final tb = AdminRepository.timestampMillis(b['updatedAt'] ?? b['createdAt']);
        return tb.compareTo(ta);
      });

    final openModQueue = _moderation.where((d) {
      final s = d['status'] as String? ?? '';
      return s == 'open' || s == 'reviewing';
    }).length;
    final openReports =
        _reports.where((d) => (d['status'] as String? ?? 'pending') == 'pending').length;

    final activity = _buildActivity();
    final pad = Responsive.hPadding(context, top: 16, bottom: 32);

    return ListView(
      padding: pad,
      children: [
        // ── 1. Recent Activity ──────────────────────────────────────────────
        _OverviewSectionHeader(title: 'Recent Activity'),
        const SizedBox(height: 8),
        _OverviewCard(
          child: activity.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                    child: Text(
                      'No recent activity',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: AppColors.textSecondary),
                    ),
                  ),
                )
              : Column(
                  children: [
                    for (var i = 0; i < activity.length; i++) ...[
                      if (i > 0) const Divider(height: 1, indent: 56),
                      _ActivityRowTile(item: activity[i]),
                    ],
                  ],
                ),
        ),

        const SizedBox(height: 20),

        // ── 2. Admin Applications ───────────────────────────────────────────
        _OverviewCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row — title + View All button (matches iOS HStack layout)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Admin Applications',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  TextButton(
                    onPressed: () => widget.onQuickAction(1),
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('View All'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // 3 stat cards — Pending / Approved / This Month
              LayoutBuilder(builder: (context, c) {
                final w = (c.maxWidth - 24) / 3;
                return Row(
                  children: [
                    for (final e in [
                      ('Pending', '$pendingApps', const Color(0xFFFF9500),
                          Icons.hourglass_empty_rounded),
                      ('Approved', '$approvedApps', const Color(0xFF34C759),
                          Icons.check_circle_outline),
                      ('This Month', '$thisMonthApps', const Color(0xFF007AFF),
                          Icons.calendar_today_outlined),
                    ]) ...[
                      if (e.$1 != 'Pending') const SizedBox(width: 12),
                      SizedBox(
                        width: w,
                        child: _OverviewMiniStat(
                          label: e.$1,
                          value: e.$2,
                          color: e.$3 as Color,
                          icon: e.$4 as IconData,
                        ),
                      ),
                    ],
                  ],
                );
              }),
              // Recent applications sub-list (mirrors iOS recentApplicationsSection)
              const SizedBox(height: 14),
              Text(
                'Recent Applications',
                style: Theme.of(context)
                    .textTheme
                    .labelMedium
                    ?.copyWith(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              if (adminApps.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'No applications yet',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: AppColors.textSecondary),
                  ),
                )
              else
                for (final app in adminApps.take(5)) ...[
                  const Divider(height: 1),
                  _RecentAppRow(app: app),
                ],
            ],
          ),
        ),

        const SizedBox(height: 20),

        // ── 3. Verification Overview ────────────────────────────────────────
        _OverviewCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Verification Overview',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              // Pending + Verified stat row
              Row(
                children: [
                  Expanded(
                    child: _OverviewMiniStat(
                      label: 'Pending',
                      value: '$pendingKyc',
                      color: const Color(0xFFFF9500),
                      icon: Icons.hourglass_empty_rounded,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _OverviewMiniStat(
                      label: 'Verified',
                      value: '$verifiedKyc',
                      color: const Color(0xFF34C759),
                      icon: Icons.verified_outlined,
                    ),
                  ),
                ],
              ),
              // Recent verification requests
              if (recentVerifications.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(
                  'Recent Requests',
                  style: Theme.of(context)
                      .textTheme
                      .labelMedium
                      ?.copyWith(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                for (final req in recentVerifications.take(3)) ...[
                  const Divider(height: 1),
                  _VerificationRequestRow(req: req),
                ],
              ],
              const SizedBox(height: 4),
              TextButton(
                onPressed: () => widget.onQuickAction(2),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Open Verification Queue →'),
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // ── 4. System Status ────────────────────────────────────────────────
        _OverviewCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'System Status',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              _SystemStatusRow(
                title: 'Firebase',
                statusLabel: 'Connected',
                statusColor: const Color(0xFF34C759),
              ),
              const Divider(height: 16),
              _SystemStatusRow(
                title: 'Open Reports',
                statusLabel:
                    '${openModQueue + openReports}',
                statusColor: (openModQueue + openReports) > 0
                    ? const Color(0xFFFF9500)
                    : const Color(0xFF34C759),
              ),
              const Divider(height: 16),
              _SystemStatusRow(
                title: 'Pending Verifications',
                statusLabel: '$pendingKyc',
                statusColor: pendingKyc > 0
                    ? const Color(0xFFFF9500)
                    : const Color(0xFF34C759),
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // ── 5. Quick Actions ────────────────────────────────────────────────
        Text(
          'Quick Actions',
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        // 2-column grid matching iOS LazyVGrid (2 flexible columns)
        LayoutBuilder(builder: (context, c) {
          final w = (c.maxWidth - 12) / 2;
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(
                width: w,
                child: _QuickActionCard(
                  icon: Icons.verified_user_outlined,
                  title: 'Review Verifications',
                  subtitle: '$pendingKyc pending',
                  color: const Color(0xFF34C759),
                  onTap: () => widget.onQuickAction(2),
                ),
              ),
              SizedBox(
                width: w,
                child: _QuickActionCard(
                  icon: Icons.people_outline,
                  title: 'Manage Users',
                  subtitle: 'View all users',
                  color: const Color(0xFF007AFF),
                  onTap: () => widget.onQuickAction(4),
                ),
              ),
              SizedBox(
                width: w,
                child: _QuickActionCard(
                  icon: Icons.bar_chart_outlined,
                  title: 'View Analytics',
                  subtitle: 'Platform insights',
                  color: const Color(0xFFAF52DE),
                  onTap: () => widget.onQuickAction(6),
                ),
              ),
              SizedBox(
                width: w,
                child: _QuickActionCard(
                  icon: Icons.settings_outlined,
                  title: 'System Settings',
                  subtitle: 'Configure platform',
                  color: const Color(0xFF8E8E93),
                  onTap: () => widget.onQuickAction(9),
                ),
              ),
            ],
          );
        }),
      ],
    );
  }
}

class _ActivityItem {
  _ActivityItem({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.millis,
    required this.docId,
  }) : timeAgo = _relativeTime(millis);

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final int millis;
  final String docId;
  final String timeAgo;

  static String _relativeTime(int millis) {
    if (millis == 0) return '';
    final diff =
        DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(millis));
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${(diff.inDays / 7).floor()}w ago';
  }
}

// ── Overview shared widgets ──────────────────────────────────────────────────

/// Section heading — matches iOS `.font(.headline).fontWeight(.semibold)`.
class _OverviewSectionHeader extends StatelessWidget {
  const _OverviewSectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context)
          .textTheme
          .titleSmall
          ?.copyWith(fontWeight: FontWeight.w700),
    );
  }
}

/// Rounded card with a subtle border — matches iOS `.background + .overlay(stroke)`.
class _OverviewCard extends StatelessWidget {
  const _OverviewCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.08),
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: child,
    );
  }
}

/// Activity row — icon · title + subtitle · time — matches iOS `ActivityRow`.
class _ActivityRowTile extends StatelessWidget {
  const _ActivityRowTile({required this.item});
  final _ActivityItem item;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: item.color.withValues(alpha: 0.15),
            child: Icon(item.icon, color: item.color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                Text(
                  item.subtitle,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: AppColors.textSecondary),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (item.timeAgo.isNotEmpty) ...[
            const SizedBox(width: 8),
            Text(
              item.timeAgo,
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: AppColors.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}

/// Mini stat card used inside overview cards — icon + big value + label.
/// Matches iOS `QuickStatCard` layout.
class _OverviewMiniStat extends StatelessWidget {
  const _OverviewMiniStat({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  final String label;
  final String value;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 6),
            Text(
              value,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: color.darken(),
                  ),
            ),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Recent application row — name · role · status chip · time-ago.
/// Matches iOS `ApplicationRow`.
class _RecentAppRow extends StatelessWidget {
  const _RecentAppRow({required this.app});
  final Map<String, dynamic> app;

  @override
  Widget build(BuildContext context) {
    final name = app['applicantName'] as String? ?? '—';
    final role = app['currentRole'] as String? ?? app['role'] as String? ?? '';
    final st = app['status'] as String? ?? 'pending';
    final ms = AdminRepository.timestampMillis(app['createdAt']);
    final timeAgo = ms > 0 ? _ActivityItem._relativeTime(ms) : '';
    final Color statusColor = st == 'approved'
        ? const Color(0xFF34C759)
        : st == 'rejected'
            ? const Color(0xFFFF3B30)
            : const Color(0xFFFF9500);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
                if (role.isNotEmpty)
                  Text(role,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: AppColors.textSecondary)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              st,
              style: TextStyle(
                  color: statusColor,
                  fontWeight: FontWeight.w600,
                  fontSize: 11),
            ),
          ),
          if (timeAgo.isNotEmpty) ...[
            const SizedBox(width: 8),
            Text(
              timeAgo,
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: AppColors.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}

/// Verification request row — user ID · level · status badge.
/// Matches iOS `VerificationRequestRow`.
class _VerificationRequestRow extends StatelessWidget {
  const _VerificationRequestRow({required this.req});
  final Map<String, dynamic> req;

  @override
  Widget build(BuildContext context) {
    final rawUid = req['userId'] as String? ?? '';
    final uid = rawUid.length > 12 ? '${rawUid.substring(0, 12)}…' : rawUid;
    final level = req['requestedLevel'] as String? ?? '';
    final st = req['status'] as String? ?? 'pending';
    final Color statusColor = st == 'approved'
        ? const Color(0xFF34C759)
        : st == 'rejected'
            ? const Color(0xFFFF3B30)
            : const Color(0xFFFF9500);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('User: $uid',
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
                if (level.isNotEmpty)
                  Text('Level: $level',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: AppColors.textSecondary)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              st,
              style: TextStyle(
                  color: statusColor,
                  fontWeight: FontWeight.w600,
                  fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}

/// System status row — title on left, colored dot + label on right.
/// Matches iOS `SystemHealthRow`.
class _SystemStatusRow extends StatelessWidget {
  const _SystemStatusRow({
    required this.title,
    required this.statusLabel,
    required this.statusColor,
  });
  final String title;
  final String statusLabel;
  final Color statusColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title,
            style: Theme.of(context).textTheme.bodyMedium),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: statusColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              statusLabel,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: statusColor,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Quick action card — icon (top-left) + title + subtitle.
/// Matches iOS `AdminQuickActionCard` exactly.
class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 26),
              const SizedBox(height: 8),
              Text(
                title,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
              ),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
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
// Applications — reads from `adminApplications` collection
// Mirrors iOS AdminApplicationListView + AdminApplicationDetailView
// ─────────────────────────────────────────────────────────────────────────────

class _ApplicationsTabEnhanced extends StatefulWidget {
  const _ApplicationsTabEnhanced({required this.admin});
  final AdminRepository admin;

  @override
  State<_ApplicationsTabEnhanced> createState() => _ApplicationsTabEnhancedState();
}

class _ApplicationsTabEnhancedState extends State<_ApplicationsTabEnhanced> {
  int _viewMode = 0; // 0 = List, 1 = Analytics
  String? _statusFilter;
  String _search = '';
  String _sort = 'newest'; // newest | oldest | name | status

  void _showDetail(BuildContext context, Map<String, dynamic> r) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _ApplicationDetailSheet(data: r, admin: widget.admin),
    );
  }

  List<Map<String, dynamic>> _filtered(List<Map<String, dynamic>> all) {
    var list = all;
    if (_statusFilter != null) {
      list = list.where((d) => (d['status'] as String? ?? '') == _statusFilter).toList();
    }
    final q = _search.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list.where((d) {
        final name = (d['applicantName'] as String? ?? '').toLowerCase();
        final email = (d['applicantEmail'] as String? ?? '').toLowerCase();
        final role = (d['currentRole'] as String? ?? '').toLowerCase();
        return name.contains(q) || email.contains(q) || role.contains(q);
      }).toList();
    }
    switch (_sort) {
      case 'oldest':
        list.sort((a, b) => AdminRepository.timestampMillis(a['createdAt'])
            .compareTo(AdminRepository.timestampMillis(b['createdAt'])));
      case 'name':
        list.sort((a, b) => (a['applicantName'] as String? ?? '')
            .compareTo(b['applicantName'] as String? ?? ''));
      case 'status':
        list.sort((a, b) => (a['status'] as String? ?? '')
            .compareTo(b['status'] as String? ?? ''));
      default:
        list.sort((a, b) => AdminRepository.timestampMillis(b['createdAt'])
            .compareTo(AdminRepository.timestampMillis(a['createdAt'])));
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: widget.admin.watchAdminApplications(),
      builder: (context, snapshot) {
        final allApps = snapshot.data ?? [];
        final filtered = _filtered(allApps);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── List | Analytics toggle ───────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: SegmentedButton<int>(
                segments: const [
                  ButtonSegment<int>(
                    value: 0,
                    label: Text('Applications'),
                    icon: Icon(Icons.list_alt_outlined, size: 16),
                  ),
                  ButtonSegment<int>(
                    value: 1,
                    label: Text('Analytics'),
                    icon: Icon(Icons.bar_chart_outlined, size: 16),
                  ),
                ],
                selected: {_viewMode},
                onSelectionChanged: (s) => setState(() => _viewMode = s.first),
              ),
            ),

            if (_viewMode == 0) ...[
              // ── Search bar ────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                child: TextField(
                  onChanged: (v) => setState(() => _search = v),
                  decoration: InputDecoration(
                    hintText: 'Search applications...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: _search.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () => setState(() => _search = ''),
                          )
                        : null,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: Colors.grey.shade100,
                  ),
                ),
              ),
              // ── Filter chips + Sort ───────────────────────────────────
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
                child: Row(
                  children: [
                    _AppFilterChip(
                      label: 'All',
                      count: allApps.length,
                      selected: _statusFilter == null,
                      onTap: () => setState(() => _statusFilter = null),
                    ),
                    const SizedBox(width: 6),
                    for (final s in [
                      ('pending', 'Pending'),
                      ('under_review', 'Under Review'),
                      ('approved', 'Approved'),
                      ('rejected', 'Rejected'),
                    ]) ...[
                      _AppFilterChip(
                        label: s.$2,
                        count: allApps
                            .where((d) => (d['status'] as String? ?? '') == s.$1)
                            .length,
                        selected: _statusFilter == s.$1,
                        onTap: () => setState(
                            () => _statusFilter = _statusFilter == s.$1 ? null : s.$1),
                      ),
                      const SizedBox(width: 6),
                    ],
                    PopupMenuButton<String>(
                      tooltip: 'Sort',
                      icon: const Icon(Icons.sort_rounded),
                      onSelected: (v) => setState(() => _sort = v),
                      itemBuilder: (_) => [
                        for (final e in [
                          ('newest', 'Newest First'),
                          ('oldest', 'Oldest First'),
                          ('name', 'Name A–Z'),
                          ('status', 'Status'),
                        ])
                          PopupMenuItem(
                            value: e.$1,
                            child: Row(
                              children: [
                                Expanded(child: Text(e.$2)),
                                if (_sort == e.$1)
                                  const Icon(Icons.check,
                                      size: 16, color: Color(0xFF007AFF)),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              // ── List ─────────────────────────────────────────────────
              Expanded(
                child: !snapshot.hasData
                    ? const Center(child: CircularProgressIndicator())
                    : snapshot.hasError
                        ? Center(child: Text('Error: ${snapshot.error}'))
                        : filtered.isEmpty
                            ? _emptyState(context, allApps.isEmpty)
                            : ListView.separated(
                                padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
                                itemCount: filtered.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 8),
                                itemBuilder: (ctx, i) => _AppRow(
                                  data: filtered[i],
                                  onTap: () => _showDetail(ctx, filtered[i]),
                                ),
                              ),
              ),
            ] else ...[
              // ── Analytics sub-view ────────────────────────────────────
              Expanded(child: _ApplicationAnalyticsView(apps: allApps)),
            ],
          ],
        );
      },
    );
  }

  Widget _emptyState(BuildContext context, bool noData) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              noData ? Icons.description_outlined : Icons.search_off_rounded,
              size: 56,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: 16),
            Text(
              noData ? 'No Applications Yet' : 'No Applications Found',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              noData
                  ? 'No admin applications have been submitted yet.'
                  : 'Try adjusting your search or filter criteria.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            if (!noData) ...[
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => setState(() {
                  _search = '';
                  _statusFilter = null;
                }),
                child: const Text('Clear Filters'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Application data helpers ──────────────────────────────────────────────────

/// Safely casts a Firestore dynamic value to `Map<String, dynamic>`.
/// Handles the edge-case `Map<Object?, Object?>` that can surface from the
/// Firestore SDK in nested contexts (iOS-sourced documents in particular).
Map<String, dynamic> _appToStringMap(dynamic v) {
  if (v is Map<String, dynamic>) return v;
  if (v is Map) return v.map((k, val) => MapEntry(k.toString(), val));
  return const {};
}

/// Safely converts a Firestore `List` field to `List<String>`.
List<String> _appToStringList(dynamic v) {
  if (v is List) return v.map((e) => e.toString()).toList();
  return const [];
}

// ── Application row card — matches iOS AdminApplicationRowView ────────────────

class _AppRow extends StatelessWidget {
  const _AppRow({required this.data, required this.onTap});
  final Map<String, dynamic> data;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = data['applicantName'] as String? ?? '—';
    final email = data['applicantEmail'] as String? ?? '';
    final role = data['currentRole'] as String? ?? data['role'] as String? ?? '';
    final st = data['status'] as String? ?? 'pending';
    final ms = AdminRepository.timestampMillis(data['createdAt']);
    final timeAgo = ms > 0 ? _ActivityItem._relativeTime(ms) : '';

    final details = _appToStringMap(data['applicationDetails']);
    final skills = _appToStringList(details['technicalSkills']).take(3).toList();

    final Color statusColor;
    final String statusLabel;
    switch (st) {
      case 'approved':
        statusColor = const Color(0xFF34C759);
        statusLabel = 'Approved';
      case 'rejected':
        statusColor = const Color(0xFFFF3B30);
        statusLabel = 'Rejected';
      case 'under_review':
        statusColor = const Color(0xFF007AFF);
        statusLabel = 'Under Review';
      case 'withdrawn':
        statusColor = const Color(0xFF8E8E93);
        statusLabel = 'Withdrawn';
      default:
        statusColor = const Color(0xFFFF9500);
        statusLabel = 'Pending';
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade200),
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Name + status badge
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.w600)),
                      if (email.isNotEmpty)
                        Text(email,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: AppColors.textSecondary)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(statusLabel,
                      style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.w600,
                          fontSize: 12)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            // Role + time-ago
            Row(
              children: [
                if (role.isNotEmpty) ...[
                  Icon(Icons.badge_outlined, size: 13, color: AppColors.textSecondary),
                  const SizedBox(width: 3),
                  Text(role,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: AppColors.textSecondary)),
                  const SizedBox(width: 10),
                ],
                if (timeAgo.isNotEmpty)
                  Text('Applied $timeAgo',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: AppColors.textSecondary)),
              ],
            ),
            // Skills preview
            if (skills.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('Skills: ${skills.join(', ')}',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: AppColors.textSecondary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Filter chip with count badge — matches iOS AdminFilterChip ────────────────

class _AppFilterChip extends StatelessWidget {
  const _AppFilterChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF007AFF) : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: TextStyle(
                    color: selected ? Colors.white : Colors.black87,
                    fontSize: 12,
                    fontWeight: FontWeight.w500)),
            if (count > 0) ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: selected
                      ? Colors.white.withValues(alpha: 0.3)
                      : Colors.grey.shade400.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('$count',
                    style: TextStyle(
                        color: selected ? Colors.white : Colors.black87,
                        fontSize: 10,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Application detail sheet — mirrors iOS AdminApplicationDetailView ─────────

class _ApplicationDetailSheet extends StatefulWidget {
  const _ApplicationDetailSheet({required this.data, required this.admin});
  final Map<String, dynamic> data;
  final AdminRepository admin;

  @override
  State<_ApplicationDetailSheet> createState() => _ApplicationDetailSheetState();
}

class _ApplicationDetailSheetState extends State<_ApplicationDetailSheet> {
  bool _isProcessing = false;
  late String _currentStatus;

  @override
  void initState() {
    super.initState();
    _currentStatus = widget.data['status'] as String? ?? 'pending';
  }

  Future<void> _approve() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(children: const [
          Icon(Icons.check_circle_outline, color: Colors.green),
          SizedBox(width: 8),
          Text('Approve Application'),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Are you sure you want to approve this application?'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text('This will:', style: TextStyle(fontWeight: FontWeight.w600)),
                  SizedBox(height: 4),
                  Text('• Promote applicant to Admin role'),
                  Text('• Grant full admin privileges'),
                  Text('• Send notification to applicant'),
                  Text('• Update verification status to Elite'),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.green),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Approve'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _isProcessing = true);
    try {
      await widget.admin.updateAdminApplicationStatus(
        applicationId: widget.data['id'] as String,
        status: 'approved',
      );
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _currentStatus = 'approved';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Application approved. User promoted to Admin.')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _reject() async {
    String reason = '';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Row(children: const [
            Icon(Icons.cancel_outlined, color: Colors.red),
            SizedBox(width: 8),
            Text('Reject Application'),
          ]),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                  'Please provide a reason for rejecting. The applicant will be notified.'),
              const SizedBox(height: 12),
              const Text('Rejection Reason',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 6),
              TextField(
                onChanged: (v) {
                  reason = v;
                  setLocal(() {});
                },
                maxLines: 4,
                decoration: InputDecoration(
                  hintText: 'Enter reason...',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.all(10),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed:
                  reason.trim().isEmpty ? null : () => Navigator.pop(ctx, true),
              child: const Text('Reject'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _isProcessing = true);
    try {
      await widget.admin.updateAdminApplicationStatus(
        applicationId: widget.data['id'] as String,
        status: 'rejected',
        rejectionReason: reason.trim(),
      );
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _currentStatus = 'rejected';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content:
                  Text('Application rejected. Applicant has been notified.')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _markUnderReview() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.rate_review_outlined, color: Color(0xFF007AFF)),
            SizedBox(width: 8),
            Text('Mark as Under Review'),
          ],
        ),
        content: const Text(
            'Move this application to Under Review? The applicant will be notified.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Mark Under Review'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _isProcessing = true);
    try {
      await widget.admin.updateAdminApplicationStatus(
        applicationId: widget.data['id'] as String,
        status: 'under_review',
      );
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _currentStatus = 'under_review';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Application marked as Under Review')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final name = d['applicantName'] as String? ?? '—';
    final email = d['applicantEmail'] as String? ?? '';
    final phone = d['applicantPhone'] as String? ?? d['phone'] as String? ?? '';
    final applicantUserId =
        d['applicantUserId'] as String? ?? d['userId'] as String? ?? '';
    final role = d['currentRole'] as String? ?? d['role'] as String? ?? '';
    final st = _currentStatus;
    final motivation = d['motivation'] as String? ?? '';
    final id = d['id'] as String? ?? '';
    final ms = AdminRepository.timestampMillis(d['createdAt']);
    final reviewedAtMs = AdminRepository.timestampMillis(d['reviewedAt']);
    final reviewedBy = d['reviewedBy'] as String? ?? '';
    final rejectionReason = d['rejectionReason'] as String? ?? '';
    final appDate = ms > 0 ? DateTime.fromMillisecondsSinceEpoch(ms) : null;
    final reviewedAtDate =
        reviewedAtMs > 0 ? DateTime.fromMillisecondsSinceEpoch(reviewedAtMs) : null;

    final details = _appToStringMap(d['applicationDetails']);
    final companyName = details['companyName'] as String? ?? '';
    final position = details['position'] as String? ?? '';
    final department = details['department'] as String? ?? '';
    final yearsRE = details['yearsInRealEstate'];
    final yearsMgmt = details['managementExperience'];
    final teamSize = details['teamSize'];
    final skills = _appToStringList(details['technicalSkills']);
    final certs = _appToStringList(details['certifications']);
    final languages = _appToStringList(details['languages']);
    final avail = _appToStringMap(details['availability']);
    final hoursPerWeek = avail['hoursPerWeek'];
    final timezone = avail['timezone'] as String? ?? '';
    final commitment = avail['commitment'] as String? ?? '';
    final flexibility = avail['flexibility'] as String? ?? '';

    final refs = (d['references'] is List)
        ? (d['references'] as List)
            .map((e) => _appToStringMap(e))
            .where((m) => m.isNotEmpty)
            .toList()
        : <Map<String, dynamic>>[];
    final docs = (d['supportingDocuments'] is List)
        ? (d['supportingDocuments'] as List)
            .map((e) => _appToStringMap(e))
            .where((m) => m.isNotEmpty)
            .toList()
        : <Map<String, dynamic>>[];

    final Color statusColor;
    final String statusLabel;
    switch (st) {
      case 'approved':
        statusColor = const Color(0xFF34C759);
        statusLabel = 'Approved';
      case 'rejected':
        statusColor = const Color(0xFFFF3B30);
        statusLabel = 'Rejected';
      case 'under_review':
        statusColor = const Color(0xFF007AFF);
        statusLabel = 'Under Review';
      case 'withdrawn':
        statusColor = const Color(0xFF8E8E93);
        statusLabel = 'Withdrawn';
      default:
        statusColor = const Color(0xFFFF9500);
        statusLabel = 'Pending';
    }

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.9,
      maxChildSize: 0.97,
      builder: (_, controller) => Column(
        children: [
          // ── Title bar ────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: 10),
                          decoration: BoxDecoration(
                              color: Colors.grey.shade300,
                              borderRadius: BorderRadius.circular(2)),
                        ),
                      ),
                      Text('Application Review',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
                if (st == 'pending' || st == 'under_review')
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_horiz_rounded),
                    onSelected: (v) {
                      if (v == 'approve') _approve();
                      if (v == 'reject') _reject();
                      if (v == 'review') _markUnderReview();
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                          value: 'approve',
                          child: Text('Approve Application')),
                      const PopupMenuItem(
                          value: 'reject', child: Text('Reject Application')),
                      if (st == 'pending')
                        const PopupMenuItem(
                            value: 'review', child: Text('Mark Under Review')),
                    ],
                  ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // ── Scrollable content ───────────────────────────────────────
          Expanded(
            child: ListView(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
              children: [
                // Application header card
                _AppDetailCard(
                  title: '',
                  child: Column(
                    children: [
                      Row(children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(statusLabel,
                              style: TextStyle(
                                  color: statusColor,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12)),
                        ),
                        const Spacer(),
                        if (id.length >= 8)
                          Text('Application #${id.substring(0, 8)}',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: AppColors.textSecondary)),
                      ]),
                      const SizedBox(height: 14),
                      Text(name,
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      if (email.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(email,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(color: AppColors.textSecondary)),
                      ],
                      if (role.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text('Current Role: $role',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: AppColors.textSecondary)),
                      ],
                      if (appDate != null) ...[
                        const SizedBox(height: 4),
                        Text('Applied ${_fmtDate(appDate)}',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: AppColors.textSecondary)),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Status banner / action buttons
                if (st == 'pending' || st == 'under_review') ...[
                  Row(children: [
                    Expanded(
                      child: FilledButton.icon(
                        icon: _isProcessing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.check_circle_outline),
                        label: const Text('Approve'),
                        style: FilledButton.styleFrom(
                            backgroundColor: Colors.green),
                        onPressed: _isProcessing ? null : _approve,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        icon: const Icon(Icons.cancel_outlined),
                        label: const Text('Reject'),
                        style:
                            FilledButton.styleFrom(backgroundColor: Colors.red),
                        onPressed: _isProcessing ? null : _reject,
                      ),
                    ),
                  ]),
                  if (st == 'pending') ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.tonalIcon(
                        icon: _isProcessing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.rate_review_outlined, size: 18),
                        label: const Text('Mark as Under Review'),
                        onPressed: _isProcessing ? null : _markUnderReview,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                ] else if (st == 'approved') ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(children: const [
                      Icon(Icons.check_circle_rounded, color: Colors.green),
                      SizedBox(width: 8),
                      Text('Application Approved',
                          style: TextStyle(
                              color: Colors.green,
                              fontWeight: FontWeight.w600,
                              fontSize: 15)),
                    ]),
                  ),
                  const SizedBox(height: 12),
                ] else if (st == 'rejected') ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(children: const [
                      Icon(Icons.cancel_rounded, color: Colors.red),
                      SizedBox(width: 8),
                      Text('Application Rejected',
                          style: TextStyle(
                              color: Colors.red,
                              fontWeight: FontWeight.w600,
                              fontSize: 15)),
                    ]),
                  ),
                  const SizedBox(height: 12),
                ],

                // Personal Information
                _AppDetailCard(
                  title: 'Personal Information',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _AppDetailRow(label: 'Full Name', value: name),
                      if (email.isNotEmpty)
                        _AppDetailRow(label: 'Email', value: email),
                      if (phone.isNotEmpty)
                        _AppDetailRow(label: 'Phone', value: phone),
                      if (role.isNotEmpty)
                        _AppDetailRow(label: 'Current Role', value: role),
                      if (appDate != null)
                        _AppDetailRow(
                            label: 'Application Date',
                            value: _fmtDate(appDate)),
                      if (applicantUserId.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.person_outline, size: 16),
                          label: const Text('View Applicant Profile'),
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) => AdminUserDetailScreen(
                                  userId: applicantUserId),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Professional Information
                if (companyName.isNotEmpty ||
                    position.isNotEmpty ||
                    yearsRE != null) ...[
                  _AppDetailCard(
                    title: 'Professional Information',
                    child: Column(children: [
                      if (companyName.isNotEmpty)
                        _AppDetailRow(label: 'Company', value: companyName),
                      if (position.isNotEmpty)
                        _AppDetailRow(label: 'Position', value: position),
                      if (department.isNotEmpty)
                        _AppDetailRow(label: 'Department', value: department),
                      if (yearsRE != null)
                        _AppDetailRow(
                            label: 'Real Estate Exp.',
                            value: '$yearsRE years'),
                      if (yearsMgmt != null)
                        _AppDetailRow(
                            label: 'Management Exp.',
                            value: '$yearsMgmt years'),
                      if (teamSize != null)
                        _AppDetailRow(
                            label: 'Team Size', value: '$teamSize people'),
                    ]),
                  ),
                  const SizedBox(height: 12),
                ],

                // Experience & Skills
                if (skills.isNotEmpty ||
                    certs.isNotEmpty ||
                    languages.isNotEmpty) ...[
                  _AppDetailCard(
                    title: 'Experience & Skills',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (skills.isNotEmpty) ...[
                          Text('Technical Skills',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelMedium
                                  ?.copyWith(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 6),
                          Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: skills
                                  .map((s) => _SkillChip(
                                      label: s,
                                      color: const Color(0xFF007AFF)))
                                  .toList()),
                          const SizedBox(height: 12),
                        ],
                        if (certs.isNotEmpty) ...[
                          Text('Certifications',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelMedium
                                  ?.copyWith(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 6),
                          Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: certs
                                  .map((s) => _SkillChip(
                                      label: s,
                                      color: const Color(0xFF34C759)))
                                  .toList()),
                          const SizedBox(height: 12),
                        ],
                        if (languages.isNotEmpty) ...[
                          Text('Languages',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelMedium
                                  ?.copyWith(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 4),
                          Text(languages.join(', '),
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(color: AppColors.textSecondary)),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                // Availability
                if (hoursPerWeek != null || timezone.isNotEmpty) ...[
                  _AppDetailCard(
                    title: 'Availability',
                    child: Column(children: [
                      if (hoursPerWeek != null)
                        _AppDetailRow(
                            label: 'Hours / Week', value: '$hoursPerWeek'),
                      if (commitment.isNotEmpty)
                        _AppDetailRow(
                            label: 'Commitment', value: commitment),
                      if (flexibility.isNotEmpty)
                        _AppDetailRow(
                            label: 'Flexibility', value: flexibility),
                      if (timezone.isNotEmpty)
                        _AppDetailRow(label: 'Timezone', value: timezone),
                    ]),
                  ),
                  const SizedBox(height: 12),
                ],

                // Motivation
                if (motivation.isNotEmpty) ...[
                  _AppDetailCard(
                    title: 'Motivation',
                    child: Text(motivation,
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: AppColors.textSecondary)),
                  ),
                  const SizedBox(height: 12),
                ],

                // References
                _AppDetailCard(
                  title: 'References',
                  child: refs.isEmpty
                      ? Text('No references provided',
                          style: TextStyle(
                              color: AppColors.textSecondary,
                              fontStyle: FontStyle.italic))
                      : Column(
                          children:
                              refs.map((r) => _ReferenceCard(ref: r)).toList()),
                ),
                const SizedBox(height: 12),

                // Supporting Documents
                _AppDetailCard(
                  title: 'Supporting Documents',
                  child: docs.isEmpty
                      ? Text('No documents uploaded',
                          style: TextStyle(
                              color: AppColors.textSecondary,
                              fontStyle: FontStyle.italic))
                      : Column(
                          children:
                              docs.map((doc) => _DocCard(doc: doc)).toList()),
                ),
                const SizedBox(height: 12),

                // Application Timeline
                _AppDetailCard(
                  title: 'Application Timeline',
                  child: Column(children: [
                    _TimelineEvent(
                      title: 'Application Submitted',
                      description: 'Application was submitted',
                      date: appDate,
                      done: true,
                    ),
                    if (st == 'under_review')
                      _TimelineEvent(
                        title: 'Under Review',
                        description: 'Application is being reviewed',
                        date: reviewedAtDate,
                        done: true,
                      ),
                    if (st == 'approved')
                      _TimelineEvent(
                        title: 'Application Approved',
                        description: reviewedBy.isNotEmpty
                            ? 'Approved by $reviewedBy'
                            : 'Application was approved',
                        date: reviewedAtDate,
                        done: true,
                      ),
                    if (st == 'rejected') ...[
                      _TimelineEvent(
                        title: 'Application Rejected',
                        description: reviewedBy.isNotEmpty
                            ? 'Rejected by $reviewedBy'
                            : 'Application was rejected',
                        date: reviewedAtDate,
                        done: true,
                      ),
                      if (rejectionReason.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(left: 22, top: 4),
                          child: Text('Reason: $rejectionReason',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: AppColors.textSecondary)),
                        ),
                    ],
                  ]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _fmtDate(DateTime dt) =>
      '${dt.day}/${dt.month}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}

// ── Supporting widgets for application detail ─────────────────────────────────

class _AppDetailCard extends StatelessWidget {
  const _AppDetailCard({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title.isNotEmpty) ...[
            Text(title,
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
          ],
          child,
        ],
      ),
    );
  }
}

class _AppDetailRow extends StatelessWidget {
  const _AppDetailRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Text(label,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: AppColors.textSecondary)),
        const Spacer(),
        Flexible(
          child: Text(value,
              textAlign: TextAlign.right,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(fontWeight: FontWeight.w500)),
        ),
      ]),
    );
  }
}

class _SkillChip extends StatelessWidget {
  const _SkillChip({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 11, fontWeight: FontWeight.w500)),
    );
  }
}

class _ReferenceCard extends StatelessWidget {
  const _ReferenceCard({required this.ref});
  final Map<String, dynamic> ref;

  @override
  Widget build(BuildContext context) {
    final name = ref['name'] as String? ?? '—';
    final pos = ref['position'] as String? ?? '';
    final company = ref['company'] as String? ?? '';
    final email = ref['email'] as String? ?? '';
    final years = ref['yearsKnown'];
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
              child: Text(name,
                  style: const TextStyle(fontWeight: FontWeight.w600))),
          if (years != null)
            Text('$years yrs',
                style:
                    TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        ]),
        if (pos.isNotEmpty)
          Text(pos, style: TextStyle(color: AppColors.textSecondary)),
        if (company.isNotEmpty)
          Text(company, style: TextStyle(color: AppColors.textSecondary)),
        if (email.isNotEmpty)
          Text(email,
              style: const TextStyle(
                  color: Color(0xFF007AFF), fontSize: 12)),
      ]),
    );
  }
}

class _DocCard extends StatelessWidget {
  const _DocCard({required this.doc});
  final Map<String, dynamic> doc;

  @override
  Widget build(BuildContext context) {
    final fileName = doc['fileName'] as String? ?? 'Document';
    final type = doc['type'] as String? ?? '';
    final fileUrl = doc['fileURL'] as String? ?? '';
    final fileSize = doc['fileSize'] as int? ?? 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(children: [
        const Icon(Icons.description_outlined, color: Color(0xFF007AFF)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(fileName,
                style: const TextStyle(
                    fontWeight: FontWeight.w500, fontSize: 13)),
            if (type.isNotEmpty)
              Text(type,
                  style: TextStyle(
                      color: AppColors.textSecondary, fontSize: 11)),
            if (fileSize > 0)
              Text(_fmtSize(fileSize),
                  style: TextStyle(
                      color: AppColors.textSecondary, fontSize: 11)),
          ]),
        ),
        if (fileUrl.isNotEmpty)
          TextButton(
            onPressed: () async {
              final uri = Uri.tryParse(fileUrl);
              if (uri != null && await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
            child: const Text('View', style: TextStyle(fontSize: 12)),
          )
        else
          Text('No file',
              style:
                  TextStyle(color: AppColors.textSecondary, fontSize: 12)),
      ]),
    );
  }

  String _fmtSize(int bytes) {
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    return '${(kb / 1024).toStringAsFixed(1)} MB';
  }
}

class _TimelineEvent extends StatelessWidget {
  const _TimelineEvent({
    required this.title,
    required this.description,
    this.date,
    required this.done,
  });
  final String title;
  final String description;
  final DateTime? date;
  final bool done;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          margin: const EdgeInsets.only(top: 4),
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: done ? const Color(0xFF007AFF) : Colors.grey,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w500)),
            Text(description,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: AppColors.textSecondary)),
            if (date != null)
              Text('${date!.day}/${date!.month}/${date!.year}',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(
                          color: AppColors.textSecondary, fontSize: 11)),
          ]),
        ),
      ]),
    );
  }
}

// ── Application analytics sub-view — mirrors iOS AdminApplicationAnalyticsView ─

class _ApplicationAnalyticsView extends StatelessWidget {
  const _ApplicationAnalyticsView({required this.apps});
  final List<Map<String, dynamic>> apps;

  @override
  Widget build(BuildContext context) {
    final total = apps.length;
    final pending =
        apps.where((d) => (d['status'] as String? ?? 'pending') == 'pending').length;
    final approved =
        apps.where((d) => (d['status'] as String? ?? '') == 'approved').length;
    final rejected =
        apps.where((d) => (d['status'] as String? ?? '') == 'rejected').length;
    final now = DateTime.now();
    final thisMonth = apps.where((d) {
      final ms = AdminRepository.timestampMillis(d['createdAt']);
      if (ms == 0) return false;
      final dt = DateTime.fromMillisecondsSinceEpoch(ms);
      return dt.year == now.year && dt.month == now.month;
    }).length;
    final successRate = (total - pending) > 0
        ? approved / (approved + rejected) * 100
        : 0.0;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Application analytics',
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(builder: (context, c) {
          final w = (c.maxWidth - 12) / 2;
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final e in [
                ('Total', '$total', const Color(0xFF007AFF)),
                ('Pending', '$pending', const Color(0xFFFF9500)),
                ('Approved', '$approved', const Color(0xFF34C759)),
                ('Rejected', '$rejected', const Color(0xFFFF3B30)),
                ('This month', '$thisMonth', const Color(0xFF5856D6)),
                ('Success rate', '${successRate.toStringAsFixed(0)}%', const Color(0xFFAF52DE)),
              ])
                SizedBox(
                  width: w,
                  child: _VerStatCard(
                    label: e.$1,
                    value: e.$2,
                    color: e.$3 as Color,
                  ),
                ),
            ],
          );
        }),
        if (total > 0 && (approved + rejected) > 0) ...[
          const SizedBox(height: 20),
          Text(
            'Status distribution',
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          for (final e in [
            ('Approved', approved, const Color(0xFF34C759)),
            ('Pending', pending, const Color(0xFFFF9500)),
            ('Rejected', rejected, const Color(0xFFFF3B30)),
          ])
            _VerStatusBar(
              label: e.$1,
              count: e.$2 as int,
              total: total,
              color: e.$3 as Color,
            ),
        ],
        // Recent 5 applications
        if (apps.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text(
            'Recent applications',
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < apps.take(5).length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  ListTile(
                    title: Text(apps[i]['applicantName'] as String? ?? '—'),
                    trailing: Text(
                      apps[i]['status'] as String? ?? 'pending',
                      style: TextStyle(
                        color: (apps[i]['status'] as String? ?? '') == 'approved'
                            ? Colors.green
                            : (apps[i]['status'] as String? ?? '') == 'rejected'
                                ? Colors.red
                                : Colors.orange,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Verification hub — 4 sub-segments matching iOS AdminVerificationView:
//   Pending · Verified · Rejected · Analytics
// ─────────────────────────────────────────────────────────────────────────────

class _VerificationHubTab extends StatefulWidget {
  const _VerificationHubTab({required this.admin});
  final AdminRepository admin;

  @override
  State<_VerificationHubTab> createState() => _VerificationHubTabState();
}

class _VerificationHubTabState extends State<_VerificationHubTab> {
  /// 0=Pending  1=Verified  2=Rejected  3=Analytics
  int _segment = 0;
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// Sets status on a verification request, passing userId so the user's
  /// profile is also updated (verified badge, `userVerifications` record).
  Future<void> _setStatus(
    BuildContext context,
    String id,
    String status, {
    String? userId,
    String? note,
  }) async {
    try {
      await widget.admin.updateVerificationRequestStatus(
        docId: id,
        status: status,
        userId: userId,
        note: note,
      );
      if (context.mounted) {
        final label = status == 'verified' ? 'approved' : status;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Verification $label')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  /// Shows a rejection-reason dialog then marks rejected — mirrors iOS alert.
  Future<void> _rejectWithReason(
    BuildContext context,
    String id, {
    String? userId,
  }) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rejection reason'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'Enter reason — user will be notified',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final reason = ctrl.text.trim().isEmpty ? 'Incomplete documentation' : ctrl.text.trim();
    await _setStatus(context, id, 'rejected', userId: userId, note: reason);
  }

  /// Verified Realtor Rewards, Part 9 — optional approval notes dialog,
  /// mirroring [_rejectWithReason]'s pattern but with an empty note allowed
  /// (approval doesn't require justification the way a rejection does).
  Future<void> _approveWithNotes(
    BuildContext context,
    String id, {
    String? userId,
  }) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Approve verification'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'Approval notes (optional)',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.green),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Approve'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final note = ctrl.text.trim();
    await _setStatus(context, id, 'verified',
        userId: userId, note: note.isEmpty ? null : note);
  }

  /// Verified Realtor Rewards, Part 9 — a true revoke, distinct from
  /// [_setStatus]'s existing 'suspended' action. Writes `verificationStatus:
  /// 'revoked'` to `users/{userId}`, which the `syncUserToPublicProfile`
  /// trigger picks up and forwards to `handleVerificationStatusChange` →
  /// `revokeVerifiedRewards` (zeroes verifiedBonusListings/isFeaturedEligible
  /// and recomputes totalListingAllowance server-side).
  Future<void> _revokeWithConfirmation(
    BuildContext context,
    String id, {
    String? userId,
  }) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Revoke verification?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This immediately removes the Verified badge and every '
              'verified-realtor reward, including the bonus listing slots.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'Reason (optional)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Revoke'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final note = ctrl.text.trim();
    await _setStatus(context, id, 'revoked',
        userId: userId, note: note.isEmpty ? null : note);
  }

  /// Verified Realtor Rewards, Part 9 — "view verification history": every
  /// status change on this request is already logged to `admin_audit_log`
  /// by [AdminRepository.updateVerificationRequestStatus] (targetType
  /// 'verification_request', targetId == this request's docId).
  void _showHistory(BuildContext context, String id) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (ctx, scrollController) => StreamBuilder<List<Map<String, dynamic>>>(
          stream: widget.admin.watchAuditLog(
            targetType: 'verification_request',
            targetId: id,
          ),
          builder: (context, snap) {
            final rows = snap.data ?? const [];
            return Column(
              children: [
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Verification History',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
                Expanded(
                  child: !snap.hasData
                      ? const Center(child: CircularProgressIndicator())
                      : rows.isEmpty
                          ? const Center(child: Text('No history yet.'))
                          : ListView.separated(
                              controller: scrollController,
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              itemCount: rows.length,
                              separatorBuilder: (_, __) => const Divider(height: 1),
                              itemBuilder: (context, i) {
                                final r = rows[i];
                                final details =
                                    r['details'] as Map<String, dynamic>? ?? {};
                                final newStatus =
                                    details['newStatus'] as String? ?? '';
                                final ts = r['timestamp'];
                                final when = ts is Timestamp
                                    ? '${ts.toDate().day}/${ts.toDate().month}/${ts.toDate().year}'
                                    : '';
                                return ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(newStatus.isEmpty
                                      ? (r['action'] as String? ?? '')
                                      : 'Status → $newStatus'),
                                  subtitle: Text(
                                    'by ${r['adminId'] ?? 'unknown'} · $when',
                                  ),
                                );
                              },
                            ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: widget.admin.watchVerificationRequests(),
      builder: (context, snapshot) {
        final all = snapshot.data ?? [];
        final identity = all.where(AdminRepository.isIdentityVerification).toList();
        final q = _search.text.trim().toLowerCase();

        // 'verified' is the canonical iOS status; treat legacy 'approved' as alias.
        List<Map<String, dynamic>> byStatus(String status) => identity
            .where((d) {
              final s = d['status'] as String? ?? 'pending';
              if (status == 'verified') return s == 'verified' || s == 'approved';
              return s == status;
            })
            .where((d) {
              if (q.isEmpty) return true;
              return '${d['userId'] ?? ''}'.toLowerCase().contains(q);
            })
            .toList();

        final pending = byStatus('pending');
        // Pre-existing bug fix: this previously called byStatus('approved'),
        // which — since the alias-check above only fires for the literal
        // 'verified' argument — filtered for a raw status of 'approved'.
        // updateVerificationRequestStatus always normalises to 'verified'
        // before writing, so no admin-approved request could ever appear
        // here; the Verified tab was effectively always empty for anyone
        // actually approved through this UI (blocking Suspend/Revoke too).
        final verified = byStatus('verified');
        final rejected = byStatus('rejected');
        final revoked = byStatus('revoked');

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Search bar ──────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: TextField(
                controller: _search,
                decoration: const InputDecoration(
                  hintText: 'Search by user ID…',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            // ── Segmented control ───────────────────────────────────────────
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
              child: Row(
                children: [
                  for (final entry in [
                    (0, 'Pending', pending.length, Icons.hourglass_empty_rounded, const Color(0xFFFF9500)),
                    (1, 'Verified', verified.length, Icons.verified_outlined, const Color(0xFF34C759)),
                    (2, 'Rejected', rejected.length, Icons.cancel_outlined, const Color(0xFFFF3B30)),
                    (3, 'Revoked', revoked.length, Icons.remove_moderator_outlined, const Color(0xFF8E8E93)),
                    (4, 'Analytics', null, Icons.bar_chart_outlined, const Color(0xFF007AFF)),
                  ]) ...[
                    if (entry.$1 > 0) const SizedBox(width: 8),
                    _VerSegPill(
                      label: entry.$2,
                      count: entry.$3,
                      icon: entry.$4 as IconData,
                      color: entry.$5 as Color,
                      selected: _segment == entry.$1,
                      onTap: () => setState(() => _segment = entry.$1 as int),
                    ),
                  ],
                ],
              ),
            ),
            // ── Content area ────────────────────────────────────────────────
            Expanded(
              child: !snapshot.hasData
                  ? const Center(child: CircularProgressIndicator())
                  : snapshot.hasError
                      ? Center(child: Text('Error: ${snapshot.error}'))
                      : _buildSegmentContent(context, pending, verified, rejected, revoked, identity),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSegmentContent(
    BuildContext context,
    List<Map<String, dynamic>> pending,
    List<Map<String, dynamic>> verified,
    List<Map<String, dynamic>> rejected,
    List<Map<String, dynamic>> revoked,
    List<Map<String, dynamic>> allIdentity,
  ) {
    switch (_segment) {
      case 0:
        return _VerificationList(
          rows: pending,
          emptyLabel: 'No pending identity documents.',
          buildTrailing: (r) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'History',
                icon: const Icon(Icons.history, color: AppColors.textSecondary),
                onPressed: () => _showHistory(context, r['id'] as String),
              ),
              IconButton(
                tooltip: 'Approve',
                icon: const Icon(Icons.check_circle_outline, color: Colors.green),
                onPressed: () => _approveWithNotes(context, r['id'] as String, userId: r['userId'] as String?),
              ),
              IconButton(
                tooltip: 'Reject',
                icon: const Icon(Icons.cancel_outlined, color: Colors.red),
                onPressed: () => _rejectWithReason(context, r['id'] as String, userId: r['userId'] as String?),
              ),
            ],
          ),
        );
      case 1:
        return _VerificationList(
          rows: verified,
          emptyLabel: 'No verified users.',
          buildTrailing: (r) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'History',
                icon: const Icon(Icons.history, color: AppColors.textSecondary),
                onPressed: () => _showHistory(context, r['id'] as String),
              ),
              TextButton(
                style: TextButton.styleFrom(foregroundColor: Colors.orange),
                onPressed: () => _setStatus(context, r['id'] as String, 'suspended', userId: r['userId'] as String?),
                child: const Text('Suspend'),
              ),
              // Verified Realtor Rewards, Part 9 — a true revoke, distinct
              // from Suspend: strips the verified badge and every reward
              // (bonus listings, featured eligibility) immediately, rather
              // than just blocking the account.
              TextButton(
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                onPressed: () => _revokeWithConfirmation(context, r['id'] as String, userId: r['userId'] as String?),
                child: const Text('Revoke'),
              ),
            ],
          ),
        );
      case 2:
        return _VerificationList(
          rows: rejected,
          emptyLabel: 'No rejected requests.',
          buildTrailing: (r) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'History',
                icon: const Icon(Icons.history, color: AppColors.textSecondary),
                onPressed: () => _showHistory(context, r['id'] as String),
              ),
              TextButton(
                onPressed: () => _setStatus(context, r['id'] as String, 'pending'),
                child: const Text('Re-review'),
              ),
            ],
          ),
        );
      case 3:
        return _VerificationList(
          rows: revoked,
          emptyLabel: 'No revoked verifications.',
          buildTrailing: (r) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'History',
                icon: const Icon(Icons.history, color: AppColors.textSecondary),
                onPressed: () => _showHistory(context, r['id'] as String),
              ),
              TextButton(
                onPressed: () => _approveWithNotes(context, r['id'] as String, userId: r['userId'] as String?),
                child: const Text('Re-verify'),
              ),
            ],
          ),
        );
      case 4:
      default:
        return _VerificationAnalyticsView(allIdentity: allIdentity);
    }
  }
}

// ── Pill tab button ──────────────────────────────────────────────────────────

class _VerSegPill extends StatelessWidget {
  const _VerSegPill({
    required this.label,
    required this.count,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final int? count;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bg = selected
        ? color.withValues(alpha: 0.18)
        : Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5);
    final fg = selected ? color.darken(0.1) : AppColors.textSecondary;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: fg),
              const SizedBox(width: 6),
              Text(
                count != null ? '$label ($count)' : label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: fg,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Shared list widget ───────────────────────────────────────────────────────

class _VerificationList extends StatelessWidget {
  const _VerificationList({
    required this.rows,
    required this.emptyLabel,
    required this.buildTrailing,
  });
  final List<Map<String, dynamic>> rows;
  final String emptyLabel;
  final Widget Function(Map<String, dynamic> r) buildTrailing;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return Center(child: Text(emptyLabel));
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: rows.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final r = rows[i];
        final uid = r['userId'] as String? ?? '';
        final level = r['requestedLevel'] as String? ?? '';
        final note = r['note'] as String? ?? '';

        // Support both submission schemas: the legacy single-`documentUrl`
        // flow (identity_verification_screen.dart) and the multi-document
        // `documentUrls` flow (enhanced_verification_screen.dart) — the
        // admin view previously only ever read `documentUrl`, so any
        // enhanced-flow submission's documents were entirely invisible here.
        final urls = <String>{
          if ((r['documentUrl'] as String? ?? '').isNotEmpty)
            r['documentUrl'] as String,
          if (r['documentUrls'] is List)
            ...(r['documentUrls'] as List).whereType<String>(),
        }.toList();

        return Card(
          margin: const EdgeInsets.only(bottom: 4),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('UID: $uid',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 13)),
                          if (level.isNotEmpty)
                            Text('Level: $level',
                                style: const TextStyle(fontSize: 12)),
                          if (note.isNotEmpty)
                            Text('Note: $note',
                                style: const TextStyle(
                                    fontSize: 12, color: Colors.grey)),
                        ],
                      ),
                    ),
                    buildTrailing(r),
                  ],
                ),
                if (urls.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (var d = 0; d < urls.length; d++)
                        _VerificationDocumentTile(
                          url: urls[d],
                          label: urls.length > 1 ? 'Document ${d + 1}' : null,
                        ),
                    ],
                  ),
                ] else
                  const Text('No document uploaded',
                      style: TextStyle(color: Colors.red, fontSize: 12)),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _VerificationDocumentTile extends StatelessWidget {
  const _VerificationDocumentTile({required this.url, this.label});
  final String url;
  final String? label;

  bool get _isPdf => url.toLowerCase().split('?').first.endsWith('.pdf');

  Future<void> _open(BuildContext context) async {
    if (_isPdf) {
      final uri = Uri.tryParse(url);
      if (uri == null || !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('Could not open document.')));
        }
      }
      return;
    }
    showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        child: InteractiveViewer(
          child: Image.network(url, fit: BoxFit.contain),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _open(context),
      child: SizedBox(
        width: 140,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: _isPdf
                  ? Container(
                      height: 100,
                      width: 140,
                      color: Colors.red.shade50,
                      alignment: Alignment.center,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.picture_as_pdf,
                              color: Colors.red.shade400, size: 32),
                          const SizedBox(height: 4),
                          Text('View PDF',
                              style: TextStyle(
                                  fontSize: 11, color: Colors.red.shade700)),
                        ],
                      ),
                    )
                  : Image.network(
                      url,
                      height: 100,
                      width: 140,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        height: 100,
                        width: 140,
                        color: Colors.grey.shade200,
                        alignment: Alignment.center,
                        child: const Text('Unavailable',
                            style: TextStyle(color: Colors.grey, fontSize: 11)),
                      ),
                    ),
            ),
            if (label != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(label!,
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textSecondary)),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Analytics sub-view ───────────────────────────────────────────────────────

class _VerificationAnalyticsView extends StatelessWidget {
  const _VerificationAnalyticsView({required this.allIdentity});
  final List<Map<String, dynamic>> allIdentity;

  @override
  Widget build(BuildContext context) {
    final pending =
        allIdentity.where((d) => (d['status'] as String? ?? '') == 'pending').length;
    final approved =
        allIdentity.where((d) => (d['status'] as String? ?? '') == 'approved').length;
    final rejected =
        allIdentity.where((d) => (d['status'] as String? ?? '') == 'rejected').length;
    final suspended =
        allIdentity.where((d) => (d['status'] as String? ?? '') == 'suspended').length;
    final total = allIdentity.length;
    final successRate = total > 0 ? (approved / total * 100) : 0.0;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Verification overview',
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(builder: (context, c) {
          final w = (c.maxWidth - 12) / 2;
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final e in [
                ('Total', '$total', const Color(0xFF007AFF)),
                ('Verified', '$approved', const Color(0xFF34C759)),
                ('Pending', '$pending', const Color(0xFFFF9500)),
                ('Rejected', '$rejected', const Color(0xFFFF3B30)),
                if (suspended > 0) ('Suspended', '$suspended', Colors.orange),
                ('Success rate', '${successRate.toStringAsFixed(0)}%', const Color(0xFFAF52DE)),
              ])
                SizedBox(
                  width: w,
                  child: _VerStatCard(
                    label: e.$1,
                    value: e.$2,
                    color: e.$3 as Color,
                  ),
                ),
            ],
          );
        }),
        if (total > 0) ...[
          const SizedBox(height: 20),
          Text(
            'Status distribution',
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          for (final e in [
            ('Verified', approved, const Color(0xFF34C759)),
            ('Pending', pending, const Color(0xFFFF9500)),
            ('Rejected', rejected, const Color(0xFFFF3B30)),
            if (suspended > 0) ('Suspended', suspended, Colors.orange),
          ])
            _VerStatusBar(
              label: e.$1,
              count: e.$2 as int,
              total: total,
              color: e.$3 as Color,
            ),
        ],
      ],
    );
  }
}

class _VerStatCard extends StatelessWidget {
  const _VerStatCard({
    required this.label,
    required this.value,
    required this.color,
  });
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: color.darken(),
                  ),
            ),
            Text(
              label,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _VerStatusBar extends StatelessWidget {
  const _VerStatusBar({
    required this.label,
    required this.count,
    required this.total,
    required this.color,
  });
  final String label;
  final int count;
  final int total;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final pct = total > 0 ? count / total : 0.0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label),
              Text('$count  (${(pct * 100).toStringAsFixed(0)}%)'),
            ],
          ),
          const SizedBox(height: 4),
          LinearProgressIndicator(
            value: pct,
            color: color,
            backgroundColor: color.withValues(alpha: 0.15),
            minHeight: 8,
            borderRadius: BorderRadius.circular(4),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Moderation — moderation_reports (iOS `ModerationQueue`) + property_reports
// ─────────────────────────────────────────────────────────────────────────────

class _ModerationHubTab extends StatefulWidget {
  const _ModerationHubTab({required this.admin});
  final AdminRepository admin;

  @override
  State<_ModerationHubTab> createState() => _ModerationHubTabState();
}

class _ModerationHubTabState extends State<_ModerationHubTab> {
  /// 0 = `moderation_reports`, 1 = `property_reports`
  int _segment = 0;
  String? _modStatusFilter;

  static const _modStatuses = ['open', 'reviewing', 'resolved', 'dismissed'];

  Future<void> _resolvePropertyReport(
    BuildContext context,
    String id,
    String status,
  ) async {
    try {
      await widget.admin.updatePropertyReportStatus(docId: id, status: status);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Listing report updated')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: SegmentedButton<int>(
            segments: const [
              ButtonSegment<int>(
                value: 0,
                label: Text('Moderation queue'),
                icon: Icon(Icons.shield_outlined, size: 18),
              ),
              ButtonSegment<int>(
                value: 1,
                label: Text('Listing reports'),
                icon: Icon(Icons.flag_outlined, size: 18),
              ),
              ButtonSegment<int>(
                value: 2,
                label: Text('Auto-moderation'),
                icon: Icon(Icons.smart_toy_outlined, size: 18),
              ),
            ],
            selected: {_segment},
            onSelectionChanged: (Set<int> s) => setState(() => _segment = s.first),
          ),
        ),
        if (_segment == 0) ...[
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                FilterChip(
                  label: const Text('All'),
                  selected: _modStatusFilter == null,
                  onSelected: (_) => setState(() => _modStatusFilter = null),
                ),
                const SizedBox(width: 8),
                for (final s in _modStatuses) ...[
                  FilterChip(
                    label: Text(s),
                    selected: _modStatusFilter == s,
                    onSelected: (_) => setState(() => _modStatusFilter = s),
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: widget.admin.watchModerationReports(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                var rows = snapshot.data!;
                if (_modStatusFilter != null) {
                  rows = rows
                      .where((d) => (d['status'] as String? ?? '') == _modStatusFilter)
                      .toList();
                }
                if (rows.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        _modStatusFilter == null
                            ? 'No moderation_reports yet.\n(iOS uses this collection for user/message/review reports.)'
                            : 'No reports with status "$_modStatusFilter".',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: rows.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final r = rows[i];
                    final status = r['status'] as String? ?? '';
                    final targetType = r['targetType'] as String? ?? '';
                    final targetId = r['targetId'] as String? ?? '';
                    final reason = r['reason'] as String? ?? '';
                    return ListTile(
                      title: Text(reason.isEmpty ? 'Moderation report' : reason),
                      subtitle: Text(
                        '$targetType · $status\n$targetId',
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      isThreeLine: true,
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => showAdminModerationReportDetailSheet(
                        context: context,
                        admin: widget.admin,
                        report: r,
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ] else if (_segment == 1)
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: widget.admin.watchPropertyReports(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final rows = snapshot.data!
                    .where((d) => (d['status'] as String? ?? 'pending') == 'pending')
                    .toList();
                if (rows.isEmpty) {
                  return const Center(child: Text('No open listing reports.'));
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: rows.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final r = rows[i];
                    final id = r['id'] as String;
                    final title = r['propertyTitle'] as String? ?? 'Listing';
                    final reason = r['reason'] as String? ?? '';
                    final details = r['details'] as String? ?? '';
                    return ExpansionTile(
                      title: Text(title),
                      subtitle: Text(reason),
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(details),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: () =>
                                  _resolvePropertyReport(context, id, 'dismissed'),
                              child: const Text('Dismiss'),
                            ),
                            FilledButton(
                              onPressed: () =>
                                  _resolvePropertyReport(context, id, 'reviewed'),
                              child: const Text('Mark reviewed'),
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          )
        else
          Expanded(child: _AutoModerationPanel(admin: widget.admin)),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Auto-moderation — Parts 2/7/8/9 of the content-moderation spec: stats,
// blocked-words management, and a live moderation_logs feed, gated behind
// its own `adminModerationDashboard` flag (shown regardless of the flag so
// admins can turn it ON from here, but the banner makes the state obvious).
// ─────────────────────────────────────────────────────────────────────────────

class _AutoModerationPanel extends StatefulWidget {
  const _AutoModerationPanel({required this.admin});
  final AdminRepository admin;

  @override
  State<_AutoModerationPanel> createState() => _AutoModerationPanelState();
}

class _AutoModerationPanelState extends State<_AutoModerationPanel>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final flags = context.watch<ModerationFeatureFlagsProvider>();
    final dashboardEnabled = flags.isEnabled(ModerationFlag.adminModerationDashboard);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!dashboardEnabled)
          Container(
            width: double.infinity,
            color: Theme.of(context).colorScheme.errorContainer,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              'adminModerationDashboard flag is OFF — stats below may be stale for other admins. '
              'Enable it in the Flags tab.',
              style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
            ),
          ),
        TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Stats'),
            Tab(text: 'Blocked words'),
            Tab(text: 'Logs'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _ModerationStatsTab(admin: widget.admin),
              _BlockedWordsTab(admin: widget.admin),
              _ModerationLogsTab(admin: widget.admin),
            ],
          ),
        ),
      ],
    );
  }
}

class _ModerationStatsTab extends StatefulWidget {
  const _ModerationStatsTab({required this.admin});
  final AdminRepository admin;

  @override
  State<_ModerationStatsTab> createState() => _ModerationStatsTabState();
}

class _ModerationStatsTabState extends State<_ModerationStatsTab> {
  late Future<ModerationStats> _future = widget.admin.fetchModerationStats();

  Future<void> _reload() async {
    setState(() => _future = widget.admin.fetchModerationStats());
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _reload,
      child: FutureBuilder<ModerationStats>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('Error loading stats: ${snapshot.error}'),
                ),
              ],
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final s = snapshot.data!;
          Widget statTile(String label, String value) => Card(
                margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(value, style: Theme.of(context).textTheme.headlineSmall),
                      const SizedBox(height: 4),
                      Text(label, style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
              );

          Widget countList(String title, List<ModerationStatCount> items) => Card(
                margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: 8),
                      if (items.isEmpty)
                        const Text('No data yet.', style: TextStyle(color: Colors.grey))
                      else
                        for (final item in items)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(item.key, overflow: TextOverflow.ellipsis),
                                ),
                                Text('${item.count}'),
                              ],
                            ),
                          ),
                    ],
                  ),
                ),
              );

          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: 1.8,
                children: [
                  statTile('Rejected today', '${s.rejectedToday}'),
                  statTile('Rejected images (${s.sampleWindowDays}d)', '${s.mostRejectedImagesCount}'),
                  statTile(
                    'Avg. moderation time',
                    s.averageModerationTimeMs != null ? '${s.averageModerationTimeMs} ms' : '—',
                  ),
                  statTile(
                    'False positive rate',
                    s.falsePositiveRate != null
                        ? '${(s.falsePositiveRate! * 100).toStringAsFixed(1)}%'
                        : 'N/A',
                  ),
                ],
              ),
              const SizedBox(height: 8),
              countList('Most common violations', s.mostCommonViolations),
              countList('Top offending users', s.topOffendingUsers),
              countList('Most blocked words', s.mostBlockedWords),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  '${s.activeBlockedWordsCount} active blocked words · sampled ${s.sampleSize} logs '
                  'from the last ${s.sampleWindowDays} days',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _BlockedWordsTab extends StatefulWidget {
  const _BlockedWordsTab({required this.admin});
  final AdminRepository admin;

  @override
  State<_BlockedWordsTab> createState() => _BlockedWordsTabState();
}

class _BlockedWordsTabState extends State<_BlockedWordsTab> {
  Future<void> _openEditor({BlockedWord? existing}) async {
    final wordController = TextEditingController(text: existing?.word ?? '');
    final replacementController = TextEditingController(text: existing?.replacement ?? '');
    final categoryController = TextEditingController(text: existing?.category ?? '');
    String severity = existing?.severity ?? 'block';
    bool enabled = existing?.enabled ?? true;

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(existing == null ? 'Add blocked word' : 'Edit blocked word'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: wordController,
                  decoration: const InputDecoration(labelText: 'Word'),
                  autofocus: existing == null,
                ),
                TextField(
                  controller: categoryController,
                  decoration: const InputDecoration(labelText: 'Category (optional)'),
                ),
                TextField(
                  controller: replacementController,
                  decoration: const InputDecoration(labelText: 'Replacement (optional)'),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: severity,
                  decoration: const InputDecoration(labelText: 'Severity'),
                  items: const [
                    DropdownMenuItem(value: 'block', child: Text('Block')),
                    DropdownMenuItem(value: 'warn', child: Text('Warn')),
                  ],
                  onChanged: (v) => setDialogState(() => severity = v ?? 'block'),
                ),
                SwitchListTile(
                  title: const Text('Enabled'),
                  value: enabled,
                  onChanged: (v) => setDialogState(() => enabled = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (saved != true || !mounted) return;
    final word = wordController.text.trim();
    if (word.isEmpty) return;

    final entry = BlockedWord(
      id: existing?.id ?? '',
      word: word,
      severity: severity,
      replacement: replacementController.text.trim().isEmpty ? null : replacementController.text.trim(),
      category: categoryController.text.trim().isEmpty ? null : categoryController.text.trim(),
      enabled: enabled,
    );

    try {
      if (existing == null) {
        await widget.admin.addBlockedWord(entry);
      } else {
        await widget.admin.updateBlockedWord(entry);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _delete(BlockedWord word) async {
    try {
      await widget.admin.deleteBlockedWord(word.id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openEditor(),
        tooltip: 'Add blocked word',
        child: const Icon(Icons.add),
      ),
      body: StreamBuilder<List<BlockedWord>>(
        stream: widget.admin.watchBlockedWords(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final words = snapshot.data!;
          if (words.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No blocked words yet. Tap + to add one — admins manage this list here '
                  'instead of publishing a new app build.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
            itemCount: words.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final w = words[i];
              return ListTile(
                title: Text(w.word),
                subtitle: Text(
                  [
                    w.severity,
                    if (w.category != null) w.category!,
                    if (!w.enabled) 'disabled',
                  ].join(' · '),
                ),
                leading: Icon(
                  w.severity == 'block' ? Icons.block : Icons.warning_amber,
                  color: w.severity == 'block' ? Colors.red : Colors.orange,
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () => _openEditor(existing: w),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _delete(w),
                    ),
                  ],
                ),
                onTap: () => _openEditor(existing: w),
              );
            },
          );
        },
      ),
    );
  }
}

class _ModerationLogsTab extends StatefulWidget {
  const _ModerationLogsTab({required this.admin});
  final AdminRepository admin;

  @override
  State<_ModerationLogsTab> createState() => _ModerationLogsTabState();
}

class _ModerationLogsTabState extends State<_ModerationLogsTab> {
  String? _decisionFilter = 'block';

  Future<void> _review(ModerationLog log, bool falsePositive) async {
    try {
      await widget.admin.markModerationLogReviewed(
        logId: log.id,
        falsePositive: falsePositive,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(falsePositive ? 'Marked false positive' : 'Marked correct')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              for (final s in const [null, 'block', 'warn', 'pass'])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(s ?? 'All'),
                    selected: _decisionFilter == s,
                    onSelected: (_) => setState(() => _decisionFilter = s),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<List<ModerationLog>>(
            stream: widget.admin.watchModerationLogs(decisionFilter: _decisionFilter),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(child: Text('Error: ${snapshot.error}'));
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final logs = snapshot.data!;
              if (logs.isEmpty) {
                return const Center(child: Text('No moderation events yet.'));
              }
              return ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: logs.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final log = logs[i];
                  return ExpansionTile(
                    leading: Icon(
                      log.decision == 'block'
                          ? Icons.block
                          : log.decision == 'warn'
                              ? Icons.warning_amber
                              : Icons.check_circle_outline,
                      color: log.decision == 'block'
                          ? Colors.red
                          : log.decision == 'warn'
                              ? Colors.orange
                              : Colors.green,
                    ),
                    title: Text('${log.type} · ${log.decision} · ${log.source}'),
                    subtitle: Text(
                      log.reason ?? log.violations.join(', '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('User: ${log.userId ?? '—'}'),
                            if (log.listingId != null) Text('Listing: ${log.listingId}'),
                            if (log.messageId != null) Text('Message: ${log.messageId}'),
                            if (log.reviewId != null) Text('Review: ${log.reviewId}'),
                            Text('Confidence: ${(log.confidence * 100).toStringAsFixed(0)}%'),
                            Text('Violations: ${log.violations.join(', ')}'),
                            if (log.matchedTerms.isNotEmpty)
                              Text('Matched terms: ${log.matchedTerms.join(', ')}'),
                            if (log.latencyMs != null) Text('Latency: ${log.latencyMs} ms'),
                            if (log.createdAt != null) Text('At: ${log.createdAt}'),
                            const SizedBox(height: 8),
                            if (log.isReviewed)
                              Text(
                                log.falsePositive ? 'Reviewed — false positive' : 'Reviewed — correct',
                                style: const TextStyle(fontStyle: FontStyle.italic),
                              )
                            else
                              Row(
                                children: [
                                  TextButton(
                                    onPressed: () => _review(log, true),
                                    child: const Text('Mark false positive'),
                                  ),
                                  const SizedBox(width: 8),
                                  FilledButton(
                                    onPressed: () => _review(log, false),
                                    child: const Text('Mark correct'),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Users — search + role filter + detail (iOS AdminUsersView / AdminUserDetailView)
// ─────────────────────────────────────────────────────────────────────────────

class _UsersTab extends StatefulWidget {
  const _UsersTab({required this.admin});
  final AdminRepository admin;

  @override
  State<_UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends State<_UsersTab> {
  late Future<List<Map<String, dynamic>>> _future;
  final _search = TextEditingController();
  String? _roleFilter;

  static const _roleChips = [
    'Admin',
    'Developer',
    'Realtor',
    'Property Owner',
    'Property Seeker',
  ];

  @override
  void initState() {
    super.initState();
    _future = widget.admin.fetchAdminUsers();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() {
      _future = widget.admin.fetchAdminUsers();
    });
    await _future;
  }

  bool _matchesRole(String? roleRaw, String? filter) {
    if (filter == null) return true;
    if (roleRaw == null || roleRaw.isEmpty) return false;
    final a = roleRaw.toLowerCase().replaceAll(' ', '');
    final b = filter.toLowerCase().replaceAll(' ', '');
    return a == b || roleRaw == filter || a.contains(b) || b.contains(a);
  }

  Future<void> _quickEditRole(
    BuildContext context,
    String userId,
    String current,
  ) async {
    final ctrl = TextEditingController(text: current == '—' ? '' : current);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Set user role'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textInputAction: TextInputAction.done,
          textCapitalization: TextCapitalization.none,
          onSubmitted: (_) => Navigator.pop(ctx, true),
          decoration: const InputDecoration(
            hintText: 'Same values as iOS (e.g. Property Seeker)',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final role = ctrl.text.trim();
    if (role.isEmpty) return;
    try {
      await widget.admin.setUserRole(userId: userId, role: role);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Role updated')),
        );
        await _refresh();
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: TextField(
            controller: _search,
            decoration: const InputDecoration(
              hintText: 'Search name, email, region',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              FilterChip(
                label: const Text('All roles'),
                selected: _roleFilter == null,
                onSelected: (_) => setState(() => _roleFilter = null),
              ),
              for (final role in _roleChips) ...[
                const SizedBox(width: 8),
                FilterChip(
                  label: Text(role),
                  selected: _roleFilter == role,
                  onSelected: (_) => setState(() => _roleFilter = role),
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(child: Text('Error: ${snapshot.error}'));
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final q = _search.text.trim().toLowerCase();
              var rows = snapshot.data!;
              rows = rows.where((u) {
                if (!_matchesRole(u['role'] as String?, _roleFilter)) return false;
                if (q.isEmpty) return true;
                final name = '${u['fullName'] ?? ''}'.toLowerCase();
                final email = '${u['email'] ?? ''}'.toLowerCase();
                final region = '${u['region'] ?? ''}'.toLowerCase();
                return name.contains(q) || email.contains(q) || region.contains(q);
              }).toList();
              if (rows.isEmpty) {
                return Center(
                  child: Text(
                    q.isEmpty && _roleFilter == null
                        ? 'No users loaded.'
                        : 'No users match filters.',
                  ),
                );
              }
              return RefreshIndicator(
                onRefresh: _refresh,
                child: ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: rows.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final r = rows[i];
                    final id = r['id'] as String;
                    final name =
                        r['fullName'] as String? ?? r['displayName'] as String? ?? '—';
                    final email = r['email'] as String? ?? '';
                    final role = r['role'] as String? ?? '—';
                    return ListTile(
                      title: Text(name),
                      subtitle: Text('$email\nRole: $role', maxLines: 3),
                      trailing: IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        tooltip: 'Quick edit role',
                        onPressed: () => _quickEditRole(context, id, role),
                      ),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => AdminUserDetailScreen(userId: id),
                          ),
                        );
                      },
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Properties — search · status filter · include-deleted · trust score · change
// status · archive  (iOS AdminPropertiesView parity)
// ─────────────────────────────────────────────────────────────────────────────

enum _PropAction {
  edit,
  approveMod,
  rejectMod,
  changeStatus,
  archive,
  trustVerify,
  trustSpam,
  softDelete,
}

class _PropertiesTab extends StatefulWidget {
  const _PropertiesTab({required this.admin});
  final AdminRepository admin;

  @override
  State<_PropertiesTab> createState() => _PropertiesTabState();
}

class _PropertiesTabState extends State<_PropertiesTab> {
  final _search = TextEditingController();
  String? _statusFilter;   // null = all non-deleted
  bool _includeDeleted = false;

  // ── Bulk selection — mirrors iOS AdminPropertiesView's selection mode
  // (multi-select archive/take-down/delete) ─────────────────────────────
  bool _selectionMode = false;
  final Set<String> _selectedIds = {};

  static const _statuses = ['active', 'pending', 'archived', 'rejected', 'expired'];

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  // ── helpers ──────────────────────────────────────────────────────────────

  Future<void> _modStatus(
    BuildContext context,
    String id,
    String status, {
    String? reason,
  }) async {
    try {
      await widget.admin.setPropertyModerationStatus(
        propertyId: id,
        moderationStatus: status,
        rejectionReason: reason,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Listing $status')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _changeStatus(
    BuildContext context,
    String id,
    String title, [
    String? currentStatus,
  ]) async {
    final chosen = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Change status — $title',
                style: Theme.of(ctx).textTheme.titleMedium,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            for (final s in _statuses)
              ListTile(
                title: Text(s),
                onTap: () => Navigator.pop(ctx, s),
              ),
            ListTile(
              title: const Text('Cancel'),
              onTap: () => Navigator.pop(ctx),
            ),
          ],
        ),
      ),
    );
    if (chosen == null || !context.mounted) return;
    try {
      await widget.admin.updatePropertyStatus(
          propertyId: id, status: chosen, oldStatus: currentStatus);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Status → $chosen')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _archive(BuildContext context, String id,
      [String? currentStatus]) async {
    try {
      await widget.admin.updatePropertyStatus(
          propertyId: id, status: 'archived', oldStatus: currentStatus);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Listing archived')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _trustScore(
    BuildContext context,
    String id,
    String eventType,
    String label,
  ) async {
    try {
      await widget.admin.applyTrustScoreEvent(propertyId: id, eventType: eventType);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Trust score: $label applied')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _softDelete(BuildContext context, String id, String title) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove listing?'),
        content: Text('Soft-delete "$title" (hidden from search).'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await widget.admin.adminSoftDeleteProperty(id);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Listing removed')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  /// Mirrors iOS `EditPropertyView(isAdminContext: true)` — lets an admin
  /// edit any listing's fields directly, not just moderate its status.
  Future<void> _edit(BuildContext context, String id) async {
    final adminUid = FirebaseAuth.instance.currentUser?.uid;
    if (adminUid == null) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => EditPropertyScreen(
        propertyId: id,
        userId: adminUid,
        isAdminContext: true,
      ),
    ));
  }

  void _toggleSelectionMode() {
    setState(() {
      _selectionMode = !_selectionMode;
      _selectedIds.clear();
    });
  }

  void _toggleSelected(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  Future<void> _bulkArchive(BuildContext context) async {
    final ids = _selectedIds.toList();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Archive selected listings?'),
        content: Text('${ids.length} listing${ids.length == 1 ? '' : 's'} will be archived.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Archive')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    var failures = 0;
    for (final id in ids) {
      try {
        await widget.admin.updatePropertyStatus(propertyId: id, status: 'archived');
      } catch (_) {
        failures++;
      }
    }
    if (!context.mounted) return;
    setState(() {
      _selectedIds.clear();
      _selectionMode = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(failures == 0
            ? 'Archived ${ids.length} listings'
            : 'Archived ${ids.length - failures} of ${ids.length} (some failed)')));
  }

  Future<void> _bulkSoftDelete(BuildContext context) async {
    final ids = _selectedIds.toList();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove selected listings?'),
        content: Text(
            '${ids.length} listing${ids.length == 1 ? '' : 's'} will be soft-deleted (hidden from search).'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    var failures = 0;
    for (final id in ids) {
      try {
        await widget.admin.adminSoftDeleteProperty(id);
      } catch (_) {
        failures++;
      }
    }
    if (!context.mounted) return;
    setState(() {
      _selectedIds.clear();
      _selectionMode = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(failures == 0
            ? 'Removed ${ids.length} listings'
            : 'Removed ${ids.length - failures} of ${ids.length} (some failed)')));
  }

  Future<String?> _promptReason(BuildContext context) async {
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rejection reason'),
        content: TextField(
          controller: c,
          autofocus: true,
          maxLines: 3,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true), child: const Text('Reject')),
        ],
      ),
    );
    if (ok != true) return null;
    return c.text.trim().isEmpty ? '(no reason)' : c.text.trim();
  }

  // ── build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: widget.admin.watchAllListingsAdmin(),
      builder: (context, snapshot) {
        // Apply filters client-side (same pattern as iOS).
        final all = snapshot.data ?? [];
        final q = _search.text.trim().toLowerCase();
        final rows = all.where((r) {
          final deleted = r['deleted'] as bool? ?? false;
          if (!_includeDeleted && deleted) return false;
          if (_statusFilter != null &&
              (r['status'] as String? ?? '') != _statusFilter) return false;
          if (q.isEmpty) return true;
          final title = '${r['title'] ?? ''}'.toLowerCase();
          final city = '${r['city'] ?? ''}'.toLowerCase();
          final owner = '${r['ownerName'] ?? ''}'.toLowerCase();
          return title.contains(q) || city.contains(q) || owner.contains(q);
        }).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Search ────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _search,
                      decoration: const InputDecoration(
                        hintText: 'Search title, city, owner',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    tooltip: _selectionMode ? 'Cancel selection' : 'Select multiple',
                    icon: Icon(_selectionMode ? Icons.close : Icons.checklist_rounded),
                    onPressed: _toggleSelectionMode,
                  ),
                ],
              ),
            ),
            if (_selectionMode)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                child: Row(
                  children: [
                    Text('${_selectedIds.length} selected',
                        style: Theme.of(context).textTheme.bodySmall),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: _selectedIds.isEmpty
                          ? null
                          : () => _bulkArchive(context),
                      icon: const Icon(Icons.archive_outlined, size: 18),
                      label: const Text('Archive'),
                    ),
                    TextButton.icon(
                      onPressed: _selectedIds.isEmpty
                          ? null
                          : () => _bulkSoftDelete(context),
                      icon: Icon(Icons.delete_outline, size: 18, color: AppColors.error),
                      label: Text('Remove', style: TextStyle(color: AppColors.error)),
                    ),
                  ],
                ),
              ),
            // ── Status filter chips ───────────────────────────────────────
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Row(
                children: [
                  FilterChip(
                    label: const Text('All'),
                    selected: _statusFilter == null,
                    onSelected: (_) => setState(() => _statusFilter = null),
                  ),
                  for (final s in _statuses) ...[
                    const SizedBox(width: 8),
                    FilterChip(
                      label: Text(s),
                      selected: _statusFilter == s,
                      onSelected: (_) => setState(() => _statusFilter = s),
                    ),
                  ],
                  const SizedBox(width: 8),
                  FilterChip(
                    label: const Text('Include deleted'),
                    selected: _includeDeleted,
                    onSelected: (v) => setState(() => _includeDeleted = v),
                  ),
                ],
              ),
            ),
            // ── List ──────────────────────────────────────────────────────
            if (!snapshot.hasData)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else if (snapshot.hasError)
              Expanded(child: Center(child: Text('Error: ${snapshot.error}')))
            else if (rows.isEmpty)
              const Expanded(child: Center(child: Text('No listings match filters.')))
            else
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: rows.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final r = rows[i];
                    final id = r['id'] as String;
                    final title = (r['title'] as String? ?? '').isEmpty
                        ? 'Listing $id'
                        : r['title'] as String;
                    final city = r['city'] as String? ?? '';
                    final status = r['status'] as String? ?? '';
                    final mod = r['moderationStatus'] as String?;
                    final deleted = r['deleted'] as bool? ?? false;
                    final owner = r['ownerName'] as String? ?? '';

                    return ListTile(
                      leading: _selectionMode
                          ? Checkbox(
                              value: _selectedIds.contains(id),
                              onChanged: (_) => _toggleSelected(id),
                            )
                          : null,
                      onTap: _selectionMode ? () => _toggleSelected(id) : null,
                      title: Text(title,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                        [
                          if (owner.isNotEmpty) 'Owner: $owner',
                          if (city.isNotEmpty) city,
                          if (status.isNotEmpty) 'status: $status',
                          if (mod != null) 'mod: $mod',
                          if (deleted) '⚠ DELETED',
                        ].join(' · '),
                        maxLines: 2,
                      ),
                      trailing: _selectionMode
                          ? null
                          : PopupMenuButton<_PropAction>(
                        icon: const Icon(Icons.more_vert),
                        onSelected: (action) async {
                          switch (action) {
                            case _PropAction.edit:
                              await _edit(context, id);
                            case _PropAction.approveMod:
                              await _modStatus(context, id, 'approved');
                            case _PropAction.rejectMod:
                              final reason = await _promptReason(context);
                              if (reason == null || !context.mounted) return;
                              await _modStatus(context, id, 'rejected',
                                  reason: reason);
                            case _PropAction.changeStatus:
                              await _changeStatus(context, id, title, status);
                            case _PropAction.archive:
                              await _archive(context, id, status);
                            case _PropAction.trustVerify:
                              await _trustScore(context, id,
                                  'photo_auth_verified', 'Photos verified (+3)');
                            case _PropAction.trustSpam:
                              await _trustScore(context, id, 'confirmed_spam',
                                  'Spam listing (−12)');
                            case _PropAction.softDelete:
                              await _softDelete(context, id, title);
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: _PropAction.edit,
                            child: ListTile(
                              dense: true,
                              leading: Icon(Icons.edit_outlined),
                              title: Text('Edit listing'),
                            ),
                          ),
                          PopupMenuDivider(),
                          PopupMenuItem(
                            value: _PropAction.approveMod,
                            child: ListTile(
                              dense: true,
                              leading: Icon(Icons.check, color: Colors.green),
                              title: Text('Approve listing'),
                            ),
                          ),
                          PopupMenuItem(
                            value: _PropAction.rejectMod,
                            child: ListTile(
                              dense: true,
                              leading: Icon(Icons.block, color: Colors.orange),
                              title: Text('Reject listing'),
                            ),
                          ),
                          PopupMenuDivider(),
                          PopupMenuItem(
                            value: _PropAction.changeStatus,
                            child: ListTile(
                              dense: true,
                              leading: Icon(Icons.swap_horiz_outlined),
                              title: Text('Change status…'),
                            ),
                          ),
                          PopupMenuItem(
                            value: _PropAction.archive,
                            child: ListTile(
                              dense: true,
                              leading: Icon(Icons.archive_outlined),
                              title: Text('Archive'),
                            ),
                          ),
                          PopupMenuDivider(),
                          PopupMenuItem(
                            value: _PropAction.trustVerify,
                            child: ListTile(
                              dense: true,
                              leading: Icon(Icons.verified_outlined,
                                  color: Colors.green),
                              title: Text('Trust: photos verified (+3)'),
                            ),
                          ),
                          PopupMenuItem(
                            value: _PropAction.trustSpam,
                            child: ListTile(
                              dense: true,
                              leading: Icon(Icons.warning_amber_rounded,
                                  color: Colors.red),
                              title: Text('Trust: spam listing (−12)'),
                            ),
                          ),
                          PopupMenuDivider(),
                          PopupMenuItem(
                            value: _PropAction.softDelete,
                            child: ListTile(
                              dense: true,
                              leading:
                                  Icon(Icons.delete_outline, color: Colors.red),
                              title: Text('Soft delete'),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Developments — pending project moderation (Cloud Function)
// ─────────────────────────────────────────────────────────────────────────────

class _DevelopmentsTab extends StatelessWidget {
  const _DevelopmentsTab({required this.admin});
  final AdminRepository admin;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: admin.watchPendingProjects(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final rows = snapshot.data!;
        if (rows.isEmpty) {
          return const Center(child: Text('No projects pending moderation.'));
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: rows.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final r = rows[i];
            final id = r['id'] as String;
            final name = r['name'] as String? ?? 'Project';
            return ListTile(
              title: Text(name),
              subtitle: Text('ID: $id'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.check_circle_outline, color: Colors.green),
                    onPressed: () => _projectMod(context, admin, id, 'approved'),
                  ),
                  IconButton(
                    icon: const Icon(Icons.cancel_outlined, color: Colors.red),
                    onPressed: () async {
                      final reason = await _reason(context);
                      if (reason == null || !context.mounted) return;
                      await _projectMod(context, admin, id, 'rejected', reason: reason);
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _projectMod(
    BuildContext context,
    AdminRepository admin,
    String projectId,
    String status, {
    String? reason,
  }) async {
    try {
      await admin.setProjectModeration(
        projectId: projectId,
        moderationStatus: status,
        rejectionReason: reason,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Project $status')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<String?> _reason(BuildContext context) async {
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rejection reason'),
        content: TextField(
          controller: c,
          autofocus: true,
          maxLines: 3,
          keyboardType: TextInputType.multiline,
          textInputAction: TextInputAction.newline,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('OK')),
        ],
      ),
    );
    if (ok != true) return null;
    return c.text.trim().isEmpty ? null : c.text.trim();
  }
}

// ─── Booking Moderation Tab (mirrors iOS BookingModerationView) ───────────────

class _BookingModerationTab extends StatefulWidget {
  const _BookingModerationTab({required this.admin});
  final AdminRepository admin;

  @override
  State<_BookingModerationTab> createState() => _BookingModerationTabState();
}

class _BookingModerationTabState extends State<_BookingModerationTab> {
  int _segment = 0; // 0=Disputes  1=Refunds  2=Fraud

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('Disputes')),
              ButtonSegment(value: 1, label: Text('Refunds')),
              ButtonSegment(value: 2, label: Text('Fraud')),
            ],
            selected: {_segment},
            onSelectionChanged: (s) => setState(() => _segment = s.first),
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: IndexedStack(
            index: _segment,
            children: [
              _DisputeQueueAdmin(admin: widget.admin),
              _RefundsAdmin(admin: widget.admin),
              _FraudSignalsAdmin(admin: widget.admin),
            ],
          ),
        ),
      ],
    );
  }
}

class _DisputeQueueAdmin extends StatelessWidget {
  const _DisputeQueueAdmin({required this.admin});
  final AdminRepository admin;

  /// Self-assigns the dispute (mirrors iOS `assignDispute`) — the actual
  /// resolve/dismiss decision requires a resolution type + note, which is
  /// handled in [DisputeDetailScreen]'s resolve sheet, not here.
  Future<void> _assignToMe(BuildContext ctx, String id) async {
    final adminId = FirebaseAuth.instance.currentUser?.uid;
    if (adminId == null) return;
    try {
      await ctx.read<DisputeService>().assignDispute(disputeId: id, adminId: adminId);
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx)
            .showSnackBar(const SnackBar(content: Text('Assigned to you')));
      }
    } catch (e) {
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  void _openDetail(BuildContext ctx, String id) {
    Navigator.of(ctx).push(MaterialPageRoute<void>(
      builder: (_) => DisputeDetailScreen(disputeId: id, isAdmin: true),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      // Dispute docs are written with `openedAt` (see functions/dispute-functions.js
      // `openDispute`), not `createdAt` — ordering by the wrong field silently
      // excluded every dispute from this query.
      stream: FirebaseFirestore.instance
          .collection('disputes')
          .orderBy('openedAt', descending: true)
          .limit(100)
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snap.data!.docs;
        if (docs.isEmpty) {
          return const Center(child: Text('No disputes filed.'));
        }
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (ctx, i) {
            final d = docs[i].data() as Map<String, dynamic>;
            final id = docs[i].id;
            final status = d['status'] as String? ?? 'open';
            final reason = d['reason'] as String? ?? '—';
            final propertyId = d['propertyId'] as String? ?? '—';
            final ts = d['openedAt'];
            final date = ts is Timestamp
                ? DateFormat('MMM d, y').format(ts.toDate())
                : '—';
            final assigned = d['assignedAdminId'] as String?;
            final statusColor = status == 'open'
                ? Colors.blue
                : status == 'under_review'
                    ? Colors.orange
                    : status == 'resolved'
                        ? Colors.green
                        : Colors.grey;

            return InkWell(
              onTap: () => _openDetail(ctx, id),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 3),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(reason.replaceAll('_', ' '),
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold)),
                        ),
                        _StatusChipAdmin(status: status, color: statusColor),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text('Property: $propertyId',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textSecondary)),
                    Text('Filed: $date'
                        '${assigned != null ? ' · Assigned' : ''}',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textSecondary)),
                    if (d['description'] != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          d['description'] as String,
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textSecondary),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        if (assigned == null)
                          _AdminActionButton(
                            label: 'Assign to me',
                            color: Colors.orange,
                            onTap: () => _assignToMe(ctx, id),
                          ),
                        const SizedBox(width: 8),
                        _AdminActionButton(
                          label: status == 'resolved' ? 'View' : 'Open & resolve',
                          color: Colors.green,
                          onTap: () => _openDetail(ctx, id),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _RefundsAdmin extends StatelessWidget {
  const _RefundsAdmin({required this.admin});
  final AdminRepository admin;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('bookings')
          .where('refundAmount', isGreaterThan: 0)
          .orderBy('refundAmount', descending: true)
          .limit(100)
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snap.data!.docs;
        if (docs.isEmpty) {
          return const Center(child: Text('No refunds pending.'));
        }
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (ctx, i) {
            final d = docs[i].data() as Map<String, dynamic>;
            final refund = (d['refundAmount'] as num?)?.toDouble() ?? 0;
            final status = d['status'] as String? ?? '—';
            final property = d['propertyTitle'] as String? ?? '—';
            return Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.money_off, color: Colors.orange),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(property,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold)),
                        Text('Status: $status',
                            style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                  Text(
                    '\$${refund.toStringAsFixed(2)}',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.orange,
                        fontSize: 15),
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

class _FraudSignalsAdmin extends StatelessWidget {
  const _FraudSignalsAdmin({required this.admin});
  final AdminRepository admin;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('fraudSignals')
          .orderBy('createdAt', descending: true)
          .limit(100)
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snap.data!.docs;
        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.verified_user, size: 48, color: Colors.green),
                const SizedBox(height: 12),
                Text('No fraud signals detected',
                    style: TextStyle(color: AppColors.textSecondary)),
              ],
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (ctx, i) {
            final d = docs[i].data() as Map<String, dynamic>;
            final type = d['type'] as String? ?? 'Unknown';
            final severity = d['severity'] as String? ?? 'low';
            final userId = d['userId'] as String? ?? '—';
            final sevColor = severity == 'high'
                ? Colors.red
                : severity == 'medium'
                    ? Colors.orange
                    : Colors.yellow;
            return Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: sevColor.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber, color: sevColor),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(type,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold)),
                        Text('User: $userId',
                            style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                  _StatusChipAdmin(
                    status: severity,
                    color: sevColor,
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

class _StatusChipAdmin extends StatelessWidget {
  const _StatusChipAdmin({required this.status, required this.color});
  final String status;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        status.replaceAll('_', ' ').toUpperCase(),
        style: TextStyle(
            fontSize: 10, fontWeight: FontWeight.bold, color: color),
      ),
    );
  }
}

class _AdminActionButton extends StatelessWidget {
  const _AdminActionButton(
      {required this.label, required this.color, required this.onTap});
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Text(label,
            style: TextStyle(
                color: color, fontSize: 12, fontWeight: FontWeight.bold)),
      ),
    );
  }
}

