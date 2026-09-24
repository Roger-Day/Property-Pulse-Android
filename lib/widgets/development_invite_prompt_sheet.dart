import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/development_pending_invites_provider.dart';

/// Compact bottom sheet for a pending development-team invite — mirrors iOS
/// `DevelopmentInvitePromptSheet`. Requires an explicit Accept / Decline /
/// Not now / Close tap (no swipe-to-dismiss) so a skipped invite is recorded
/// rather than silently disappearing.
class DevelopmentInvitePromptSheet extends StatelessWidget {
  const DevelopmentInvitePromptSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DevelopmentPendingInvitesProvider>();
    final invite = provider.presentedInvite;
    // The gate widget closes this route on the next frame once the
    // presented invite clears (accepted/declined/skipped elsewhere) — until
    // then, render nothing rather than crash on a null invite.
    if (invite == null) return const SizedBox.shrink();

    final name = provider.presentedDevelopmentName.isEmpty
        ? 'this development'
        : provider.presentedDevelopmentName;
    final roleLine = invite.displayRoleLabel.trim();
    final introText = roleLine.isEmpty
        ? "You've been invited to join $name."
        : "You've been invited to join $name as $roleLine.";

    // No Navigator.pop here: DevelopmentInvitePromptGate closes the route
    // when the presented invite clears (or swaps this sheet to the next
    // queued invite), so popping here as well would pop a second route.
    void closeWithResult(bool accepted) {
      provider.dismissPresented(accepted: accepted);
    }

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          16,
          20,
          MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Development invite',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed:
                      provider.isProcessing ? null : () => closeWithResult(false),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(introText, style: Theme.of(context).textTheme.bodyMedium),
            if (provider.isProcessing) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Processing…',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ],
            if ((provider.errorMessage ?? '').isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                provider.errorMessage!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: provider.isProcessing
                  ? null
                  : () async {
                      await provider.acceptPresentedInvite();
                    },
              child: const Text('Accept'),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
              onPressed: provider.isProcessing
                  ? null
                  : () async {
                      await provider.declinePresentedInvite();
                    },
              child: const Text('Decline'),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed:
                  provider.isProcessing ? null : () => closeWithResult(false),
              child: const Text('Not now'),
            ),
          ],
        ),
      ),
    );
  }
}
