import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Logs admin actions for an audit trail — mirrors iOS `AdminAuditService`.
///
/// Writes to the `admin_audit_log` collection (same name iOS's client-side
/// service uses; not to be confused with the Cloud Functions' own
/// `adminAuditLog` collection used for server-resolved dispute/payout
/// actions). Every admin-mutating call in [AdminRepository] should log here
/// after the underlying write succeeds, since bans, suspensions, role
/// changes, and listing/verification decisions currently have no other
/// record of who did what and when.
///
/// Logging failures are swallowed (matching iOS) — an audit-log hiccup must
/// never block the admin action itself.
class AdminAuditService {
  AdminAuditService({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _db = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  String get _currentAdminId => _auth.currentUser?.uid ?? 'unknown';

  Future<void> log({
    required String action,
    required String targetType,
    required String targetId,
    Map<String, dynamic> details = const {},
  }) async {
    try {
      await _db.collection('admin_audit_log').add(<String, dynamic>{
        'adminId': _currentAdminId,
        'action': action,
        'targetType': targetType,
        'targetId': targetId,
        'details': details,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // Non-fatal — never let audit logging break the admin action.
    }
  }

  Future<void> logPropertyStatusChange({
    required String propertyId,
    required String oldStatus,
    required String newStatus,
  }) {
    return log(
      action: 'property_status_change',
      targetType: 'property',
      targetId: propertyId,
      details: {'oldStatus': oldStatus, 'newStatus': newStatus},
    );
  }

  Future<void> logPropertyDelete(String propertyId) {
    return log(
      action: 'property_delete',
      targetType: 'property',
      targetId: propertyId,
    );
  }

  Future<void> logUserBan({required String userId, required bool banned}) {
    return log(
      action: banned ? 'user_ban' : 'user_unban',
      targetType: 'user',
      targetId: userId,
    );
  }

  Future<void> logUserSuspend({
    required String userId,
    required int days,
    required String reason,
  }) {
    return log(
      action: 'user_suspend',
      targetType: 'user',
      targetId: userId,
      details: {'days': days, 'reason': reason},
    );
  }

  Future<void> logUserUpdate({
    required String userId,
    required List<String> fields,
  }) {
    return log(
      action: 'user_update',
      targetType: 'user',
      targetId: userId,
      details: {'fields': fields},
    );
  }

  Future<void> logReportStatusChange({
    required String reportId,
    required String newStatus,
  }) {
    return log(
      action: 'report_status_change',
      targetType: 'moderation_report',
      targetId: reportId,
      details: {'newStatus': newStatus},
    );
  }

  /// Verified Realtor Rewards, Part 9 — "view verification history" and any
  /// other future per-target audit trail. Newest first.
  Stream<List<Map<String, dynamic>>> watchLog({
    required String targetType,
    required String targetId,
    int limit = 50,
  }) {
    return _db
        .collection('admin_audit_log')
        .where('targetType', isEqualTo: targetType)
        .where('targetId', isEqualTo: targetId)
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map((d) => d.data()).toList())
        .handleError((_) => <Map<String, dynamic>>[]);
  }
}
