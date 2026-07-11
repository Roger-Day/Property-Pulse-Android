import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../repositories/user_profile_repository.dart';

/// Matches shell branch order in [createAppRouter]: home, search, map, messages, profile, admin.
const int adminShellBranchIndex = 5;

/// Switches to the Admin tab reliably (nested `/profile/...` routes do not always
/// cooperate with `context.go('/admin')` alone) and refreshes role docs from the
/// server so promotion is visible before the `/admin` redirect runs.
Future<void> navigateToAdminDashboard(BuildContext context) async {
  final uid = context.read<AuthProvider>().user?.uid;
  if (uid != null) {
    try {
      await context.read<UserProfileRepository>().refreshUserRoleDocuments(uid);
    } catch (_) {}
    // Let [UserRoleProvider] apply the new snapshot before navigation + redirect.
    await Future<void>.delayed(Duration.zero);
  }
  if (!context.mounted) return;

  final shell = StatefulNavigationShell.maybeOf(context);
  if (shell != null) {
    shell.goBranch(adminShellBranchIndex, initialLocation: true);
    return;
  }
  context.go('/admin');
}
