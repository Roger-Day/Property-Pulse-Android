import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../constants/app_colors.dart';
import '../../router/navigate_admin_dashboard.dart';
import '../../models/admin_application.dart';
import '../../providers/auth_provider.dart';
import '../../repositories/admin_application_repository.dart';

/// Android parity with iOS `AdminApplicationStatusView` (+ navigates to the
/// `AdminApplicationView`-equivalent form).
class ApplyAdminScreen extends StatefulWidget {
  const ApplyAdminScreen({super.key});

  @override
  State<ApplyAdminScreen> createState() => _ApplyAdminScreenState();
}

class _ApplyAdminScreenState extends State<ApplyAdminScreen> {
  bool _loading = true;
  bool _canApply = false;
  AdminApplicationRecord? _application;
  String? _errorMessage;
  bool _withdrawing = false;

  static final _dateFmt = DateFormat.yMd().add_jm();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    final auth = context.read<AuthProvider>();
    final uid = auth.user?.uid;
    if (uid == null) {
      setState(() {
        _loading = false;
        _errorMessage = 'Sign in required.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final repo = context.read<AdminApplicationRepository>();
      final can = await repo.canUserApply(uid);
      final app = await repo.loadLatestUserApplication(uid);
      if (!mounted) return;
      setState(() {
        _canApply = can;
        _application = app;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _openForm() async {
    await context.push('/profile/apply-admin/form');
    if (mounted) await _refresh();
  }

  Future<void> _withdraw(String applicationId) async {
    if (_withdrawing) return;
    setState(() => _withdrawing = true);
    try {
      await context.read<AdminApplicationRepository>().withdrawApplication(
            applicationId,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Application withdrawn.')),
      );
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not withdraw: $e')),
      );
    } finally {
      if (mounted) setState(() => _withdrawing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget body;
    if (_loading) {
      body = _loadingBody(theme);
    } else if (_errorMessage != null && _errorMessage!.isNotEmpty) {
      body = _errorBody(theme, _errorMessage!);
    } else if (_application != null) {
      body = _statusBody(context, theme, _application!);
    } else if (_canApply) {
      body = _emptyEligibleBody(theme);
    } else {
      body = _notEligibleBody(theme);
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Admin Application'),
        backgroundColor: AppColors.surface,
      ),
      body: body,
    );
  }

  Widget _loadingBody(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(width: 40, height: 40, child: CircularProgressIndicator()),
          const SizedBox(height: 24),
          Text(
            'Loading application status…',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorBody(ThemeData theme, String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline_rounded, size: 56, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Text(
              'Something went wrong',
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _refresh,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusBody(
    BuildContext context,
    ThemeData theme,
    AdminApplicationRecord app,
  ) {
    final cs = theme.colorScheme;
    final st = app.status;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Icon(st.icon, size: 56, color: st.accentColor(cs)),
                const SizedBox(height: 12),
                Text(
                  st.displayName,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: st.accentColor(cs),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  st.statusDescription,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        _sectionCard(
          theme,
          title: 'Application Details',
          child: Column(
            children: [
              _detailRow(theme, 'Application ID', app.id),
              _detailRow(theme, 'Submitted', _dateFmt.format(app.applicationDate)),
              _detailRow(theme, 'Current Role', app.currentRoleRaw),
              if (app.reviewedBy != null && app.reviewedBy!.isNotEmpty)
                _detailRow(theme, 'Reviewed By', app.reviewedBy!),
              if (app.reviewedAt != null)
                _detailRow(
                  theme,
                  'Reviewed At',
                  _dateFmt.format(app.reviewedAt!),
                ),
              if (app.rejectionReason != null &&
                  app.rejectionReason!.trim().isNotEmpty)
                _detailRow(theme, 'Rejection Reason', app.rejectionReason!),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _sectionCard(
          theme,
          title: 'Application Timeline',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _timelineEvent(
                theme,
                title: 'Application Submitted',
                description: 'Your admin application was submitted',
                date: app.applicationDate,
                done: true,
              ),
              if (app.status == AdminApplicationStatus.underReview)
                _timelineEvent(
                  theme,
                  title: 'Under Review',
                  description:
                      'Your application is being reviewed by our admin team',
                  date: app.reviewedAt ?? app.updatedAt,
                  done: true,
                ),
              if (app.status == AdminApplicationStatus.approved)
                _timelineEvent(
                  theme,
                  title: 'Application Approved',
                  description:
                      'Congratulations! Your admin application has been approved',
                  date: app.reviewedAt ?? app.updatedAt,
                  done: true,
                ),
              if (app.status == AdminApplicationStatus.rejected)
                _timelineEvent(
                  theme,
                  title: 'Application Rejected',
                  description:
                      'Your application was not approved at this time',
                  date: app.reviewedAt ?? app.updatedAt,
                  done: true,
                ),
              if (app.status == AdminApplicationStatus.withdrawn)
                _timelineEvent(
                  theme,
                  title: 'Application Withdrawn',
                  description: 'You withdrew your admin application',
                  date: app.updatedAt,
                  done: true,
                ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        ..._actions(context, theme, app),
      ],
    );
  }

  List<Widget> _actions(
    BuildContext context,
    ThemeData theme,
    AdminApplicationRecord app,
  ) {
    switch (app.status) {
      case AdminApplicationStatus.pending:
      case AdminApplicationStatus.underReview:
        return [
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: _withdrawing ? null : () => _withdraw(app.id),
              child: _withdrawing
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Withdraw Application'),
            ),
          ),
        ];
      case AdminApplicationStatus.rejected:
      case AdminApplicationStatus.withdrawn:
        return [
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _openForm,
              child: Text(
                app.status == AdminApplicationStatus.rejected
                    ? 'Apply Again'
                    : 'Submit New Application',
              ),
            ),
          ),
        ];
      case AdminApplicationStatus.approved:
        return [
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () async => navigateToAdminDashboard(context),
              child: const Text('View Admin Dashboard'),
            ),
          ),
        ];
    }
  }

  Widget _emptyEligibleBody(ThemeData theme) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.person_add_alt_1_rounded,
                  size: 64,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 20),
                Text(
                  'No Admin Application',
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  'You haven\'t submitted an admin application yet. Apply now '
                  'to become an admin and help manage the platform.',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: AppColors.textSecondary),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 28),
                FilledButton(
                  onPressed: _openForm,
                  child: const Text('Apply for Admin'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _notEligibleBody(ThemeData theme) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  size: 64,
                  color: Colors.orange,
                ),
                const SizedBox(height: 20),
                Text(
                  'Not Eligible',
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  'You currently have a pending admin application or are not '
                  'eligible to apply at this time.',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: AppColors.textSecondary),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 28),
                OutlinedButton(
                  onPressed: _refresh,
                  child: const Text('Check Status'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionCard(
    ThemeData theme, {
    required String title,
    required Widget child,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }

  Widget _detailRow(ThemeData theme, String title, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              title,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _timelineEvent(
    ThemeData theme, {
    required String title,
    required String description,
    required DateTime date,
    required bool done,
  }) {
    final dotColor =
        done ? theme.colorScheme.primary : theme.colorScheme.outline;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: dotColor,
                ),
              ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _dateFmt.format(date),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
