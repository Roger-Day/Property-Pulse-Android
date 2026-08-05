import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';
import '../../constants/app_constants.dart';
import '../../repositories/admin_repository.dart';
import '../profile/edit_property_screen.dart';
import 'admin_user_detail_screen.dart';

/// Detail sheet aligned with iOS `ModerationReportDetailView` — fetches and
/// renders the actual reported entity (property/user/review), not just its
/// raw id, with a way to open it for direct action.
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
            if (reporterId.isNotEmpty) _kv(ctx, 'Reporter', reporterId),
            if (details.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(details, style: Theme.of(ctx).textTheme.bodyMedium),
            ],
            const SizedBox(height: 12),
            if (targetId.isEmpty)
              const Text('No target id on this report.',
                  style: TextStyle(color: AppColors.textSecondary))
            else
              _ReportedTargetPreview(targetType: targetType, targetId: targetId),
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

/// Fetches and previews the actual reported property/user/review, with a
/// button to open it directly for admin action — mirrors iOS
/// `ModerationReportDetailView`'s drill-through, which the raw-target-id
/// text view it replaced didn't have at all.
class _ReportedTargetPreview extends StatefulWidget {
  const _ReportedTargetPreview({required this.targetType, required this.targetId});
  final String targetType;
  final String targetId;

  @override
  State<_ReportedTargetPreview> createState() => _ReportedTargetPreviewState();
}

class _ReportedTargetPreviewState extends State<_ReportedTargetPreview> {
  late Future<Map<String, dynamic>?> _future;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  Future<Map<String, dynamic>?> _fetch() async {
    final db = FirebaseFirestore.instance;
    final collection = switch (widget.targetType) {
      'property' => AppConstants.propertiesCollection,
      'user' => AppConstants.usersCollection,
      'review' => AppConstants.reviewsCollection,
      _ => null,
    };
    if (collection == null) return null;
    final doc = await db.collection(collection).doc(widget.targetId).get();
    if (!doc.exists) return null;
    return doc.data();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        final data = snap.data;
        if (data == null) {
          return Text('Target ID: ${widget.targetId} (not found — may have been deleted)',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13));
        }

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ..._previewLines(data),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => _openTarget(context),
                  child: Text(switch (widget.targetType) {
                    'property' => 'View & edit listing',
                    'user' => 'View user',
                    _ => 'View details',
                  }),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _previewLines(Map<String, dynamic> data) {
    switch (widget.targetType) {
      case 'property':
        final title = data['title'] as String? ?? 'Listing';
        final city = data['city'] as String? ?? '';
        final status = data['status'] as String? ?? '';
        return [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          if (city.isNotEmpty || status.isNotEmpty)
            Text([if (city.isNotEmpty) city, if (status.isNotEmpty) 'status: $status'].join(' · '),
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        ];
      case 'user':
        final name = data['fullName'] as String? ?? data['displayName'] as String? ?? 'User';
        final email = data['email'] as String? ?? '';
        return [
          Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
          if (email.isNotEmpty)
            Text(email, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        ];
      case 'review':
        final author = data['userName'] as String? ?? 'Reviewer';
        final comment = data['comment'] as String? ?? '';
        final rating = data['rating'];
        return [
          Text('$author${rating != null ? ' · $rating★' : ''}',
              style: const TextStyle(fontWeight: FontWeight.w700)),
          if (comment.isNotEmpty)
            Text(comment,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        ];
      default:
        return [Text('Target ID: ${widget.targetId}')];
    }
  }

  void _openTarget(BuildContext context) {
    switch (widget.targetType) {
      case 'property':
        Navigator.of(context).pop(); // close the sheet first
        Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => EditPropertyScreen(
            propertyId: widget.targetId,
            userId: FirebaseAuth.instance.currentUser?.uid ?? '',
            isAdminContext: true,
          ),
        ));
      case 'user':
        Navigator.of(context).pop();
        Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => AdminUserDetailScreen(userId: widget.targetId),
        ));
      default:
        // No dedicated detail screen for this target type yet — the inline
        // preview above is the full drill-through available.
        break;
    }
  }
}
