import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/development_pending_invites_provider.dart';
import 'development_invite_prompt_sheet.dart';

/// Wraps the app and opens [DevelopmentInvitePromptSheet] as a modal bottom
/// sheet whenever [DevelopmentPendingInvitesProvider] has an invite to show
/// — mirrors iOS's `.sheet(item: $developmentPendingInvitesViewModel.presentedInvite)`
/// in ContentView, which is declarative there; this reproduces the same
/// "show at most one, from anywhere in the app" behavior imperatively.
///
/// [navigatorKey] must be the app's root navigator key (the one passed to
/// `GoRouter`/`MaterialApp.router`) — this widget sits in `MaterialApp`'s
/// `builder`, which wraps *around* the Navigator, so its own `context` has
/// no Navigator ancestor and `showModalBottomSheet(context: context)` would
/// silently fail with "Navigator operation requested with a context that
/// does not include a Navigator." `navigatorKey.currentContext` reaches
/// inside the Navigator instead.
class DevelopmentInvitePromptGate extends StatefulWidget {
  const DevelopmentInvitePromptGate({
    super.key,
    required this.navigatorKey,
    required this.child,
  });

  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  @override
  State<DevelopmentInvitePromptGate> createState() =>
      _DevelopmentInvitePromptGateState();
}

class _DevelopmentInvitePromptGateState
    extends State<DevelopmentInvitePromptGate> {
  bool _sheetOpen = false;
  bool _sheetClosing = false;

  void _maybeShowSheet(DevelopmentPendingInvitesProvider provider) {
    if (provider.presentedInvite == null || _sheetOpen) return;
    final navContext = widget.navigatorKey.currentContext;
    if (navContext == null) return;
    _sheetOpen = true;
    _sheetClosing = false;
    showModalBottomSheet<void>(
      context: navContext,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      builder: (_) => const DevelopmentInvitePromptSheet(),
    ).whenComplete(() {
      _sheetOpen = false;
      // Accepting/declining can immediately reveal the next queued invite
      // (DevelopmentPendingInvitesProvider presents one at a time) — check
      // again now that this sheet's route is gone.
      if (!mounted) return;
      _maybeShowSheet(context.read<DevelopmentPendingInvitesProvider>());
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DevelopmentPendingInvitesProvider>(
      builder: (context, provider, child) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          // The invite was cleared underneath an open sheet (accepted,
          // declined, skipped, signed out, or revoked) — close it, since the
          // sheet itself is non-dismissible and would otherwise stay up as a
          // blank modal. The sheet's buttons rely on this rather than
          // popping themselves.
          if (_sheetOpen && !_sheetClosing && provider.presentedInvite == null) {
            final navContext = widget.navigatorKey.currentContext;
            if (navContext != null) {
              _sheetClosing = true;
              Navigator.of(navContext).maybePop();
            }
            return;
          }
          _maybeShowSheet(provider);
        });
        return child!;
      },
      child: widget.child,
    );
  }
}
