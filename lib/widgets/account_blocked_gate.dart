import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';

/// Shows the deleted / banned / suspended notice from anywhere in the app.
///
/// `AuthProvider` signs the user out and sets `blockedReason` only after its
/// Firestore account-status read completes — by then the router has usually
/// already moved the user off the sign-in screen (which used to be the only
/// place that listened), so they just landed back on Welcome with no
/// explanation. Mirrors iOS's `isDeleted`/`isBanned`/`isSuspended` alerts.
///
/// [navigatorKey] is the root navigator key: this widget sits above the
/// Navigator (in MaterialApp's `builder`), so its own context can't show
/// dialogs.
class AccountBlockedGate extends StatefulWidget {
  const AccountBlockedGate({
    super.key,
    required this.navigatorKey,
    required this.child,
  });

  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  @override
  State<AccountBlockedGate> createState() => _AccountBlockedGateState();
}

class _AccountBlockedGateState extends State<AccountBlockedGate> {
  bool _showing = false;

  void _maybeShow(AuthProvider auth) {
    final reason = auth.blockedReason;
    if (reason == null || _showing) return;
    final navContext = widget.navigatorKey.currentContext;
    if (navContext == null) return;
    _showing = true;
    final deleted = reason == AccountBlockedReason.deleted;
    showDialog<void>(
      context: navContext,
      builder: (ctx) => AlertDialog(
        title: Text(deleted ? 'Account Deleted' : 'Account Disabled'),
        content: Text(deleted
            ? 'This account has been permanently deleted. If this is a mistake, please contact support.'
            : 'This account has been disabled. Please contact support if you think this is a mistake.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    ).whenComplete(() {
      _showing = false;
      if (mounted) context.read<AuthProvider>().clearBlockedReason();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, auth, child) {
        if (auth.blockedReason != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _maybeShow(auth);
          });
        }
        return child!;
      },
      child: widget.child,
    );
  }
}
