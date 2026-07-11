import 'package:flutter/material.dart';

import '../../repositories/admin_repository.dart';

/// Detail sheet aligned with iOS `ModerationReportDetailView` (compact).
Future<void> showAdminModerationReportDetailSheet({
  required BuildContext context,
  required AdminRepository admin,
  required Map<String, dynamic> report,
}) {
  final id = report['id'] as String;
  final status = report['status'] as String? ?? '';
  final targetType = report['targetType'] as String? ?? '';
  final targetId = report['targetId'] as String? ?? '';
  final reason = report['reason'] as String? ?? '';
  final details = report['details'] as String? ?? '';
  final reporterId = report['reporterId'] as String? ?? '';

  Future<void> apply(String next) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    Navigator.of(context).pop();
    try {
      await admin.updateModerationReportStatus(docId: id, status: next);
      messenger?.showSnackBar(SnackBar(content: Text('Report marked $next')));
    } catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: MediaQuery.paddingOf(ctx).bottom + 16,
        top: 8,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              reason.isEmpty ? 'Moderation report' : reason,
              style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            _kv(ctx, 'Status', status),
            _kv(ctx, 'Target type', targetType),
            SelectableText('Target ID: $targetId'),
            if (reporterId.isNotEmpty) _kv(ctx, 'Reporter', reporterId),
            if (details.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(details, style: Theme.of(ctx).textTheme.bodyMedium),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: [
                TextButton(onPressed: () => apply('reviewing'), child: const Text('Reviewing')),
                TextButton(onPressed: () => apply('resolved'), child: const Text('Resolved')),
                TextButton(onPressed: () => apply('dismissed'), child: const Text('Dismissed')),
                TextButton(onPressed: () => apply('open'), child: const Text('Open')),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

Widget _kv(BuildContext context, String k, String v) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 110,
          child: Text(k, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey)),
        ),
        Expanded(child: Text(v)),
      ],
    ),
  );
}
