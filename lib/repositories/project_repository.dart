import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../constants/app_constants.dart';
import '../models/development_team_member_model.dart';
import '../models/development_team_role.dart';
import '../models/development_unit_model.dart';
import '../models/project_interest_model.dart';
import '../models/project_model.dart';
import '../models/team_member_directory_entry.dart';

/// One row on a public developer profile — team member deduped across developments.
class AggregatedPublicTeamMember {
  const AggregatedPublicTeamMember({
    required this.userId,
    required this.displayName,
    this.photoUrl,
    required this.roleLabel,
    required this.projectNames,
  });

  final String userId;
  final String displayName;
  final String? photoUrl;
  final String roleLabel;
  final List<String> projectNames;
}

int _developmentTeamRoleRank(DevelopmentTeamRole r) {
  switch (r) {
    case DevelopmentTeamRole.owner:
      return 4;
    case DevelopmentTeamRole.manager:
      return 3;
    case DevelopmentTeamRole.sales:
      return 2;
    case DevelopmentTeamRole.viewer:
      return 1;
  }
}

class _TeamAgg {
  _TeamAgg({
    required this.userId,
    required this.role,
    this.roleTitle,
    this.photoUrl,
    required this.projects,
  });

  final String userId;
  DevelopmentTeamRole role;
  String? roleTitle;
  String? photoUrl;
  final Set<String> projects;
}

/// Cursor page aligned with iOS `ProjectService.fetchProjectsPage` — non-streaming `get()`
/// reads used by `ProjectViewModel.startListening` / `loadMore`.
class BrowseProjectsPageResult {
  const BrowseProjectsPageResult({
    required this.projects,
    required this.hasMore,
    this.lastRawDocument,
  });

  /// After browse filters (`isPublicHomeVisible`, sample exclusion).
  final List<ProjectModel> projects;

  /// True when the Firestore page returned at least [limit] **raw** documents (iOS `canLoadMore`).
  final bool hasMore;

  /// Last raw snapshot doc — pass as `startAfter` on the next page.
  final QueryDocumentSnapshot<Map<String, dynamic>>? lastRawDocument;
}

/// Thrown by [ProjectRepository.submitInterest] when the user has already
/// registered interest in a project. The UI should surface a friendly message
/// rather than treating this as an unexpected error.
class AlreadyRegisteredException implements Exception {
  const AlreadyRegisteredException();

  @override
  String toString() => 'You have already registered interest in this development.';
}

/// Firestore `projects` — aligned with iOS `ProjectViewModel.activeHomeProjects`.
class ProjectRepository {
  ProjectRepository(this._db);

  final FirebaseFirestore _db;

  static bool _isSampleOrSeed(ProjectModel p) {
    if (p.developerId.toLowerCase() == 'dev-seed') return true;
    if (p.projectName.toLowerCase().contains('harbor heights')) return true;
    if (p.description.toLowerCase().contains('quick ui testing')) return true;
    return false;
  }

  /// Home horizontal strip — newest projects, filtered like iOS (active, visible, not expired).
  Stream<List<ProjectModel>> watchHomeProjects() {
    return _db
        .collection(AppConstants.projectsCollection)
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .map((snap) {
      final out = <ProjectModel>[];
      for (final d in snap.docs) {
        final p = ProjectModel.fromFirestore(d);
        if (_isSampleOrSeed(p)) continue;
        if (p.isPublicHomeVisible) out.add(p);
        if (out.length >= 12) break;
      }
      return out;
    });
  }

  /// Full vertical browse — same filters as [watchHomeProjects], without the 12-item strip cap.
  Stream<List<ProjectModel>> watchBrowseProjects() {
    return _db
        .collection(AppConstants.projectsCollection)
        .orderBy('createdAt', descending: true)
        .limit(120)
        .snapshots()
        .map((snap) {
      final out = <ProjectModel>[];
      for (final d in snap.docs) {
        final p = ProjectModel.fromFirestore(d);
        if (_isSampleOrSeed(p)) continue;
        if (p.isPublicHomeVisible) out.add(p);
      }
      return out;
    });
  }

  /// iOS `ProjectService.fetchProjectsPage` — one-shot paginated reads (`limit` default **50**).
  ///
  /// Avoids composite-index pitfalls by not querying `isActive` server-side; matches browse filtering.
  Future<BrowseProjectsPageResult> fetchBrowseProjectsPage({
    int limit = 50,
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
  }) async {
    Query<Map<String, dynamic>> q = _db
        .collection(AppConstants.projectsCollection)
        .orderBy('createdAt', descending: true)
        .limit(limit);

    if (startAfter != null) {
      q = q.startAfterDocument(startAfter);
    }

    final snap = await q.get();
    final docs = snap.docs;
    final rawHasMore = docs.length >= limit;
    final lastRaw = docs.isEmpty ? null : docs.last;

    final projects = <ProjectModel>[];
    for (final d in docs) {
      final p = ProjectModel.fromFirestore(d);
      if (_isSampleOrSeed(p)) continue;
      if (!p.isPublicHomeVisible) continue;
      projects.add(p);
    }

    return BrowseProjectsPageResult(
      projects: projects,
      hasMore: rawHasMore,
      lastRawDocument: lastRaw,
    );
  }

  /// Aggregates paged browse reads for [`CustomerDashboardScreen`] — mirrors how much iOS holds in memory (~120 cap).
  Future<List<ProjectModel>> fetchBrowseProjectsAggregated({
    int maxItems = 120,
    int pageSize = 50,
  }) async {
    final out = <ProjectModel>[];
    final seen = <String>{};
    DocumentSnapshot<Map<String, dynamic>>? cursor;
    var hasMore = true;

    while (hasMore && out.length < maxItems) {
      final page = await fetchBrowseProjectsPage(limit: pageSize, startAfter: cursor);
      for (final p in page.projects) {
        if (seen.add(p.firestoreDocumentId)) out.add(p);
      }
      cursor = page.lastRawDocument;
      hasMore = page.hasMore;
      if (cursor == null && !hasMore) break;
    }

    return out;
  }

  Stream<ProjectModel?> watchProject(String projectId) {
    return _db
        .collection(AppConstants.projectsCollection)
        .doc(projectId)
        .snapshots()
        .map((doc) {
      if (!doc.exists) return null;
      return ProjectModel.fromFirestore(doc);
    });
  }

  /// iOS `DevelopmentInventoryViewModel`: `developments/{id}/units` ordered by `unitNumber`.
  Stream<List<DevelopmentUnitModel>> watchDevelopmentUnits(String projectId) {
    final trimmed = projectId.trim();
    if (trimmed.isEmpty) {
      return Stream.value([]);
    }
    return _db
        .collection(AppConstants.developmentsCollection)
        .doc(trimmed)
        .collection('units')
        .orderBy('unitNumber')
        .snapshots()
        .map((snap) {
      final out = <DevelopmentUnitModel>[];
      for (final d in snap.docs) {
        final u = DevelopmentUnitModel.fromFirestore(d);
        if (u != null) out.add(u);
      }
      return out;
    });
  }

  /// iOS `ProjectService.fetchInterests`: `projects/{id}/interests`.
  Stream<List<ProjectInterestModel>> watchProjectInterests(String projectId) {
    final trimmed = projectId.trim();
    if (trimmed.isEmpty) {
      return Stream.value([]);
    }
    return _db
        .collection(AppConstants.projectsCollection)
        .doc(trimmed)
        .collection('interests')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) {
      final out = <ProjectInterestModel>[];
      for (final d in snap.docs) {
        final data = d.data();
        out.add(ProjectInterestModel.fromFirestore(d.id, data));
      }
      return out;
    });
  }

  /// iOS `TeamService.listenMyTeamRole`: `developments/{id}/team/{userId}`.
  Stream<DevelopmentTeamRole?> watchMyTeamRole(
    String developmentId,
    String userId,
  ) {
    final d = developmentId.trim();
    final u = userId.trim();
    if (d.isEmpty || u.isEmpty) {
      return Stream.value(null);
    }
    return _db
        .collection(AppConstants.developmentsCollection)
        .doc(d)
        .collection('team')
        .doc(u)
        .snapshots()
        .map((doc) {
      if (!doc.exists) return null;
      final data = doc.data();
      if (data == null) return null;
      final roleStr = data['role'] as String?;
      return DevelopmentTeamRole.decode(roleStr);
    });
  }

  /// Full team directory — iOS `developments/{id}/team` (sorted client-side).
  Stream<List<DevelopmentTeamMemberModel>> watchTeamMembers(String developmentId) {
    final d = developmentId.trim();
    if (d.isEmpty) {
      return Stream.value([]);
    }
    return _db
        .collection(AppConstants.developmentsCollection)
        .doc(d)
        .collection('team')
        .snapshots()
        .map((snap) {
      final list = snap.docs
          .map(DevelopmentTeamMemberModel.fromFirestore)
          .whereType<DevelopmentTeamMemberModel>()
          .toList();
      list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      return list;
    });
  }

  /// iOS `DevelopmentInventoryViewModel.updateUnitStatus`.
  Future<void> updateDevelopmentUnitStatus({
    required String developmentId,
    required String unitId,
    required DevelopmentUnitStatus status,
  }) async {
    final d = developmentId.trim();
    final u = unitId.trim();
    if (d.isEmpty || u.isEmpty) return;
    await _db
        .collection(AppConstants.developmentsCollection)
        .doc(d)
        .collection('units')
        .doc(u)
        .set(
      {
        'status': status.name,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  /// iOS `AddUnitView` — adds a new unit row to `developments/{id}/units`.
  Future<void> addDevelopmentUnit({
    required String developmentId,
    required String unitNumber,
    required String unitType,
    required double price,
  }) async {
    final d = developmentId.trim();
    if (d.isEmpty) throw ArgumentError('Missing development id');
    await _db
        .collection(AppConstants.developmentsCollection)
        .doc(d)
        .collection('units')
        .add({
      'unitNumber': unitNumber.trim(),
      'unitType': unitType,
      'price': price,
      'status': DevelopmentUnitStatus.available.name,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// iOS `ProjectService.deleteProject` — removes the `projects` document.
  Future<void> deleteProject(String projectId) async {
    final id = projectId.trim();
    if (id.isEmpty) {
      throw ArgumentError('Missing project id');
    }
    await _db.collection(AppConstants.projectsCollection).doc(id).delete();
  }

  /// Merge-update editable fields (subset of iOS project editor).
  Future<void> mergeProjectFields(
    String projectId,
    Map<String, dynamic> fields,
  ) async {
    final id = projectId.trim();
    if (id.isEmpty) return;
    if (fields.isEmpty) return;
    await _db
        .collection(AppConstants.projectsCollection)
        .doc(id)
        .set(fields, SetOptions(merge: true));
  }

  /// iOS `TeamService.ensureDevelopmentMetadata` — stub doc under `developments/{id}`.
  Future<void> ensureDevelopmentMetadata({
    required String developmentId,
    required String name,
    required String ownerId,
  }) async {
    final id = developmentId.trim();
    final n = name.trim();
    final o = ownerId.trim();
    if (id.isEmpty || o.isEmpty) return;
    await _db.collection(AppConstants.developmentsCollection).doc(id).set(
      {
        'name': n,
        'ownerId': o,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  /// One-shot read of `users/{uid}` for team roster hydration — iOS `hydrateUsers`.
  Future<Map<String, TeamMemberDirectoryEntry>> fetchTeamMemberDirectory(
    Iterable<String> userIds,
  ) async {
    final out = <String, TeamMemberDirectoryEntry>{};
    final unique =
        userIds.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
    await Future.wait(unique.map((uid) async {
      try {
        final snap = await _db.collection('users').doc(uid).get();
        final d = snap.data();
        if (d == null) {
          out[uid] = const TeamMemberDirectoryEntry();
          return;
        }
        final name = (d['fullName'] as String?)?.trim() ??
            (d['full_name'] as String?)?.trim() ??
            '';
        final email = (d['email'] as String?)?.trim() ?? '';
        final rawPhoto = (d['profileImageURL'] as String?)?.trim() ??
            (d['profile_image_url'] as String?)?.trim() ??
            '';
        out[uid] = TeamMemberDirectoryEntry(
          displayName: name,
          email: email,
          profileImageUrl: rawPhoto.isEmpty ? null : rawPhoto,
        );
      } catch (_) {
        out[uid] = const TeamMemberDirectoryEntry();
      }
    }));
    return out;
  }

  /// iOS `TeamService.removeTeamMember` — deletes team doc and best-effort Storage portrait.
  Future<void> removeTeamMember({
    required String developmentId,
    required String memberUserId,
    required String ownerUserId,
  }) async {
    final devId = developmentId.trim();
    final memberId = memberUserId.trim();
    final owner = ownerUserId.trim();
    if (devId.isEmpty || memberId.isEmpty || memberId == owner) return;
    await _db
        .collection(AppConstants.developmentsCollection)
        .doc(devId)
        .collection('team')
        .doc(memberId)
        .delete();
    try {
      await FirebaseStorage.instance
          .ref()
          .child('development_team_photos/$devId/$memberId.jpg')
          .delete();
    } catch (_) {}
  }

  /// iOS `TeamService.setTeamMemberRoleTitle`.
  Future<void> setTeamMemberRoleTitle({
    required String developmentId,
    required String memberUserId,
    String? roleTitle,
  }) async {
    final devId = developmentId.trim();
    final memberId = memberUserId.trim();
    if (devId.isEmpty || memberId.isEmpty) return;
    final trimmed = roleTitle?.trim() ?? '';
    final teamRef = _db
        .collection(AppConstants.developmentsCollection)
        .doc(devId)
        .collection('team')
        .doc(memberId);
    if (trimmed.isEmpty) {
      await teamRef.update({
        'updatedAt': FieldValue.serverTimestamp(),
        'roleTitle': FieldValue.delete(),
      });
    } else {
      final capped =
          trimmed.length > 120 ? trimmed.substring(0, 120) : trimmed;
      await teamRef.update({
        'updatedAt': FieldValue.serverTimestamp(),
        'roleTitle': capped,
      });
    }
  }

  /// iOS `TeamService.setTeamMemberDisplayPhotoURL`.
  Future<void> setTeamMemberDisplayPhotoURL({
    required String developmentId,
    required String memberUserId,
    required String downloadURL,
  }) async {
    final devId = developmentId.trim();
    final memberId = memberUserId.trim();
    if (devId.isEmpty || memberId.isEmpty) return;
    await _db
        .collection(AppConstants.developmentsCollection)
        .doc(devId)
        .collection('team')
        .doc(memberId)
        .set(
      {
        'displayPhotoURL': downloadURL,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  /// iOS `TeamService.uploadTeamMemberDisplayPhoto` + URL write.
  Future<String> uploadTeamMemberDisplayPhoto({
    required String developmentId,
    required String memberUserId,
    required File imageFile,
  }) async {
    final devId = developmentId.trim();
    final memberId = memberUserId.trim();
    if (devId.isEmpty || memberId.isEmpty) {
      throw ArgumentError('developmentId and memberUserId required');
    }
    final path = 'development_team_photos/$devId/$memberId.jpg';
    final ref = FirebaseStorage.instance.ref().child(path);
    await ref.putFile(
      imageFile,
      SettableMetadata(contentType: 'image/jpeg'),
    );
    final url = await ref.getDownloadURL();
    await setTeamMemberDisplayPhotoURL(
      developmentId: devId,
      memberUserId: memberId,
      downloadURL: url,
    );
    return url;
  }

  /// iOS `TeamService.createInvite` — pending row in `invites`.
  Future<void> createTeamInvite({
    required String developmentId,
    required String email,
    required DevelopmentTeamRole role,
    String? roleTitle,
    required String invitedByUserId,
    String? developmentDisplayName,
    String? ownerUserId,
  }) async {
    if (!DevelopmentTeamRole.invitableRoles.contains(role)) {
      throw ArgumentError('Invalid invite role');
    }
    final devId = developmentId.trim();
    final normalizedEmail = email.trim().toLowerCase();
    if (devId.isEmpty || normalizedEmail.isEmpty) {
      throw ArgumentError('developmentId and email required');
    }
    final displayName = developmentDisplayName?.trim();
    final owner = ownerUserId?.trim() ?? '';
    if (displayName != null &&
        displayName.isNotEmpty &&
        owner.isNotEmpty) {
      await ensureDevelopmentMetadata(
        developmentId: devId,
        name: displayName,
        ownerId: owner,
      );
    }
    final title = roleTitle?.trim() ?? '';
    final payload = <String, dynamic>{
      'developmentId': devId,
      'email': normalizedEmail,
      'role': role.firestoreValue,
      'status': 'pending',
      'invitedBy': invitedByUserId,
      'createdAt': FieldValue.serverTimestamp(),
    };
    if (title.isNotEmpty) {
      payload['roleTitle'] = title.length > 120 ? title.substring(0, 120) : title;
    }
    await _db.collection('invites').doc().set(payload);
  }

  /// Developments where the user is owner, listed developer, or team member — iOS `myDevelopments`.
  Stream<List<ProjectModel>> watchMyPortfolioProjects(
    String uid, {
    required bool isAdmin,
  }) {
    final trimmed = uid.trim();
    if (trimmed.isEmpty) {
      return Stream.value([]);
    }
    final col = _db.collection(AppConstants.projectsCollection);
    if (isAdmin) {
      return col.limit(120).snapshots().map((snap) {
        final out = <ProjectModel>[];
        for (final d in snap.docs) {
          final p = ProjectModel.fromFirestore(d);
          if (!_isSampleOrSeed(p)) out.add(p);
        }
        out.sort(
          (a, b) => (b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0))
              .compareTo(a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0)),
        );
        return out;
      });
    }

    final queries = [
      col.where('developerId', isEqualTo: trimmed).limit(80),
      col.where('ownerId', isEqualTo: trimmed).limit(80),
      col.where('teamMembers', arrayContains: trimmed).limit(80),
    ];

    return Stream.multi((controller) {
      final latest =
          List<QuerySnapshot<Map<String, dynamic>>?>.filled(queries.length, null);
      final subs = <StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>[];

      void emit() {
        final byId = <String, ProjectModel>{};
        for (var i = 0; i < queries.length; i++) {
          final snap = latest[i];
          if (snap == null) continue;
          for (final d in snap.docs) {
            final p = ProjectModel.fromFirestore(d);
            if (!_isSampleOrSeed(p)) byId[d.id] = p;
          }
        }
        final list = byId.values.toList()
          ..sort(
            (a, b) => (b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0))
                .compareTo(a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0)),
          );
        controller.add(list);
      }

      for (var i = 0; i < queries.length; i++) {
        final idx = i;
        subs.add(
          queries[i].snapshots().listen(
            (snap) {
              latest[idx] = snap;
              emit();
            },
            onError: controller.addError,
          ),
        );
      }

      controller.onCancel = () {
        for (final s in subs) {
          s.cancel();
        }
      };
    });
  }

  /// Minimal `projects/{id}` for Android editor — iOS `ProjectEditorView` create flow.
  Future<String> createDraftProject({
    required String developerUserId,
    required String developerDisplayName,
  }) async {
    final uid = developerUserId.trim();
    if (uid.isEmpty) {
      throw ArgumentError('developerUserId required');
    }
    final ref = _db.collection(AppConstants.projectsCollection).doc();
    await ref.set({
      'id': ref.id,
      'projectName': 'New development',
      'developerId': uid,
      'ownerId': uid,
      'developerName': developerDisplayName.trim().isEmpty
          ? 'Developer'
          : developerDisplayName.trim(),
      'location': '',
      'description': '',
      'isActive': true,
      'status': 'planning',
      'moderationStatus': 'pending',
      'teamMembers': <String>[uid],
      'createdAt': FieldValue.serverTimestamp(),
      'heroImages': <String>[],
      'amenities': <String>[],
      'developmentFeatureTypes': <String>[],
    });
    return ref.id;
  }

  /// Registers a seeker's interest in a project — mirrors iOS `RegisterInterestView`.
  /// Writes to `projects/{projectId}/interests` with status `new`.
  /// Each authenticated user is restricted to one interest per project —
  /// a duplicate submission throws [AlreadyRegisteredException] so the
  /// UI can surface a clear message instead of silently spamming the developer.
  Future<void> submitInterest({
    required String projectId,
    required String name,
    required String email,
    String? phone,
    String? message,
    String? userId,
    String? projectName,
  }) async {
    final pid = projectId.trim();
    if (pid.isEmpty || name.trim().isEmpty || email.trim().isEmpty) return;

    // Guard: one interest per authenticated user per project.
    if (userId != null && userId.trim().isNotEmpty) {
      final existing = await _db
          .collection(AppConstants.usersCollection)
          .doc(userId.trim())
          .collection('project_interests')
          .doc(pid)
          .get();
      if (existing.exists) {
        throw AlreadyRegisteredException();
      }
    }

    // Write the developer-facing interest doc and capture its ID.
    final interestRef = await _db
        .collection(AppConstants.projectsCollection)
        .doc(pid)
        .collection('interests')
        .add({
      'projectId': pid,
      if (userId != null && userId.isNotEmpty) 'userId': userId,
      'name': name.trim(),
      'email': email.trim(),
      if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
      if (message != null && message.trim().isNotEmpty)
        'message': message.trim(),
      'conversionStatus': 'new',
      'contactUnlocked': false,
      'createdAt': FieldValue.serverTimestamp(),
      'lastUpdated': FieldValue.serverTimestamp(),
    });

    // Mirror to the user's own subcollection so the dashboard and
    // _RegisterInterestBar can show the persisted "already registered" state
    // across restarts.  Doc ID = projectId keeps it idempotent.
    if (userId != null && userId.trim().isNotEmpty) {
      await _db
          .collection(AppConstants.usersCollection)
          .doc(userId.trim())
          .collection('project_interests')
          .doc(pid)
          .set({
        'projectId': pid,
        if (projectName != null && projectName.trim().isNotEmpty)
          'projectName': projectName.trim(),
        'interestId': interestRef.id,
        'conversionStatus': 'new',
        'createdAt': FieldValue.serverTimestamp(),
        if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
        if (message != null && message.trim().isNotEmpty)
          'notes': message.trim(),
      }, SetOptions(merge: true));
    }
  }

  /// Updates `conversionStatus` on `projects/{projectId}/interests/{interestId}`.
  Future<void> updateProjectInterestConversionStatus({
    required String projectId,
    required String interestId,
    required String conversionStatus,
  }) async {
    final pid = projectId.trim();
    final iid = interestId.trim();
    if (pid.isEmpty || iid.isEmpty) return;

    final ref = _db
        .collection(AppConstants.projectsCollection)
        .doc(pid)
        .collection('interests')
        .doc(iid);

    await _db.runTransaction((txn) async {
      final snap = await txn.get(ref);
      final prev = snap.data();
      final updates = <String, dynamic>{
        'conversionStatus': conversionStatus,
        'lastUpdated': FieldValue.serverTimestamp(),
      };
      final hadContact = prev?['contactedAt'] != null;
      if (!hadContact && conversionStatus.toLowerCase() != 'new') {
        updates['contactedAt'] = FieldValue.serverTimestamp();
      }
      txn.set(ref, updates, SetOptions(merge: true));
    });
  }

  /// Public developer portfolio — `projects` where `developerId` matches (iOS `fetchProjectsByDeveloper`).
  Future<List<ProjectModel>> fetchProjectsByDeveloper(String developerId) async {
    final trimmed = developerId.trim();
    if (trimmed.isEmpty) return [];
    final snap = await _db
        .collection(AppConstants.projectsCollection)
        .where('developerId', isEqualTo: trimmed)
        .limit(80)
        .get();
    final out = <ProjectModel>[];
    for (final d in snap.docs) {
      final p = ProjectModel.fromFirestore(d);
      if (_isSampleOrSeed(p)) continue;
      if (p.isPublicHomeVisible) out.add(p);
    }
    out.sort(
      (a, b) => (b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0))
          .compareTo(a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0)),
    );
    return out;
  }

  /// Merges `developments/{projectDocId}/team` across [projects] (dedupe by user id).
  Future<List<AggregatedPublicTeamMember>> aggregateTeamAcrossDeveloperProjects(
    List<ProjectModel> projects,
  ) async {
    final acc = <String, _TeamAgg>{};
    for (final proj in projects.take(40)) {
      final devId = proj.firestoreDocumentId.trim().isNotEmpty
          ? proj.firestoreDocumentId
          : proj.id;
      if (devId.isEmpty) continue;
      final snap = await _db
          .collection(AppConstants.developmentsCollection)
          .doc(devId)
          .collection('team')
          .get();
      for (final doc in snap.docs) {
        final m = DevelopmentTeamMemberModel.fromFirestore(doc);
        if (m == null) continue;
        final uid = m.userId.trim();
        if (uid.isEmpty) continue;
        final existing = acc[uid];
        if (existing == null) {
          acc[uid] = _TeamAgg(
            userId: uid,
            role: m.role,
            roleTitle: m.roleTitle,
            photoUrl: m.displayPhotoURL,
            projects: {proj.projectName},
          );
        } else {
          existing.projects.add(proj.projectName);
          if (_developmentTeamRoleRank(m.role) >
              _developmentTeamRoleRank(existing.role)) {
            existing.role = m.role;
            existing.roleTitle = m.roleTitle ?? existing.roleTitle;
          }
          final p = m.displayPhotoURL?.trim();
          if (p != null && p.isNotEmpty) {
            existing.photoUrl = m.displayPhotoURL;
          }
        }
      }
    }
    if (acc.isEmpty) return [];
    final names = await _fetchPublicDisplayNames(acc.keys);
    final out = <AggregatedPublicTeamMember>[];
    for (final e in acc.values) {
      final name = names[e.userId]?.trim();
      final roleLabel = (e.roleTitle?.trim().isNotEmpty == true)
          ? e.roleTitle!
          : e.role.title;
      out.add(
        AggregatedPublicTeamMember(
          userId: e.userId,
          displayName:
              (name != null && name.isNotEmpty) ? name : 'Team member',
          photoUrl: e.photoUrl,
          roleLabel: roleLabel,
          projectNames: e.projects.toList()
            ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase())),
        ),
      );
    }
    out.sort(
      (a, b) =>
          a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
    );
    return out;
  }

  Future<Map<String, String>> _fetchPublicDisplayNames(
    Iterable<String> userIds,
  ) async {
    final out = <String, String>{};
    for (final uid in userIds) {
      final id = uid.trim();
      if (id.isEmpty) continue;
      final doc = await _db
          .collection(AppConstants.userPublicCollection)
          .doc(id)
          .get();
      if (!doc.exists) continue;
      final d = doc.data() ?? {};
      final raw = (d['displayName'] ?? d['name'] ?? '').toString().trim();
      if (raw.isNotEmpty) out[id] = raw;
    }
    return out;
  }

  /// iOS `ProjectService.markInterestContacted`.
  Future<void> markInterestContacted({
    required String projectId,
    required String interestId,
  }) async {
    final pid = projectId.trim();
    final iid = interestId.trim();
    if (pid.isEmpty || iid.isEmpty) return;
    await _db
        .collection(AppConstants.projectsCollection)
        .doc(pid)
        .collection('interests')
        .doc(iid)
        .set(
      {
        'contactedAt': FieldValue.serverTimestamp(),
        'conversionStatus': 'contacted',
        'lastUpdated': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  /// iOS `ProjectService.updateLeadNotes`.
  Future<void> updateLeadNotes({
    required String projectId,
    required String leadId,
    String? notes,
  }) async {
    final pid = projectId.trim();
    final lid = leadId.trim();
    if (pid.isEmpty || lid.isEmpty) return;
    final normalized = notes?.trim();
    final payload = <String, dynamic>{
      'lastUpdated': FieldValue.serverTimestamp(),
    };
    if (normalized != null && normalized.isNotEmpty) {
      payload['notes'] = normalized;
    } else {
      payload['notes'] = FieldValue.delete();
    }
    await _db
        .collection(AppConstants.projectsCollection)
        .doc(pid)
        .collection('interests')
        .doc(lid)
        .set(payload, SetOptions(merge: true));
  }

  /// iOS `ProjectService.updateLeadConversionStatus` — pipeline + optional unit inventory sync.
  Future<void> updateLeadConversionStatus({
    required String projectId,
    required String leadId,
    required String statusRaw,
  }) async {
    final pid = projectId.trim();
    final lid = leadId.trim();
    if (pid.isEmpty || lid.isEmpty) return;

    final leadRef = _db
        .collection(AppConstants.projectsCollection)
        .doc(pid)
        .collection('interests')
        .doc(lid);
    final devUnits = _db
        .collection(AppConstants.developmentsCollection)
        .doc(pid)
        .collection('units');

    await _db.runTransaction((txn) async {
      final leadDoc = await txn.get(leadRef);
      final leadData = leadDoc.data();
      if (leadData == null) {
        throw StateError('Lead not found.');
      }

      final lower = statusRaw.trim().toLowerCase();
      final updates = <String, dynamic>{
        'conversionStatus': lower,
        'lastUpdated': FieldValue.serverTimestamp(),
      };
      if (lower == 'contacted') {
        updates['contactedAt'] = FieldValue.serverTimestamp();
      }
      txn.set(leadRef, updates, SetOptions(merge: true));

      final unitIdRaw = leadData['unitId'] as String?;
      final unitId = unitIdRaw?.trim();
      if (unitId == null || unitId.isEmpty) return;

      if (lower != 'reserved' && lower != 'closed') return;

      final unitRef = devUnits.doc(unitId);
      final unitDoc = await txn.get(unitRef);
      final unitData = unitDoc.data();
      if (unitData == null) return;

      final currentStatus = DevelopmentUnitStatus.fromRaw(
        unitData['status'] as String?,
      );
      if (lower == 'closed' && currentStatus == DevelopmentUnitStatus.sold) {
        throw StateError(
          'This unit is already sold and cannot be closed again.',
        );
      }

      final nextSold = lower == 'closed';
      final unitPayload = <String, dynamic>{
        'status': nextSold ? 'sold' : 'reserved',
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (nextSold) {
        unitPayload['reservedForInterestId'] = FieldValue.delete();
      }
      txn.set(unitRef, unitPayload, SetOptions(merge: true));
    });
  }

  /// iOS `ProjectService.assignLeadToUnit` — `[unitId]` empty clears assignment.
  Future<void> assignLeadToUnit({
    required String projectId,
    required String leadId,
    required String unitId,
  }) async {
    final pid = projectId.trim();
    final lid = leadId.trim();
    final uid = unitId.trim();
    if (pid.isEmpty || lid.isEmpty) {
      throw ArgumentError('Missing project or lead for unit assignment.');
    }

    final leadRef = _db
        .collection(AppConstants.projectsCollection)
        .doc(pid)
        .collection('interests')
        .doc(lid);
    final unitsCol = _db
        .collection(AppConstants.developmentsCollection)
        .doc(pid)
        .collection('units');

    await _db.runTransaction((txn) async {
      final leadSnap = await txn.get(leadRef);
      if (!leadSnap.exists) {
        throw StateError('Lead not found.');
      }
      final leadData = leadSnap.data() ?? {};
      final previousRaw = (leadData['unitId'] as String?)?.trim();
      final previousUnitId =
          (previousRaw != null && previousRaw.isNotEmpty) ? previousRaw : null;

      if (uid.isEmpty) {
        if (previousUnitId != null) {
          final oldRef = unitsCol.doc(previousUnitId);
          final oldDoc = await txn.get(oldRef);
          if (oldDoc.exists) {
            final oldData = oldDoc.data() ?? {};
            if (_shouldReleaseUnitAfterRemovingLeadData(oldData, leadId: lid)) {
              txn.set(
                oldRef,
                {
                  'status': 'available',
                  'reservedForInterestId': FieldValue.delete(),
                  'updatedAt': FieldValue.serverTimestamp(),
                },
                SetOptions(merge: true),
              );
            }
          }
        }
        txn.set(
          leadRef,
          {
            'unitId': FieldValue.delete(),
            'lastUpdated': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
        return;
      }

      final newRef = unitsCol.doc(uid);
      final newDoc = await txn.get(newRef);
      if (!newDoc.exists) {
        throw StateError('Unit not found for assignment.');
      }
      final newData = newDoc.data() ?? {};
      final newStatus = DevelopmentUnitStatus.fromRaw(
        newData['status'] as String?,
      );
      if (newStatus == null) {
        throw StateError('Invalid unit status.');
      }
      if (newStatus == DevelopmentUnitStatus.sold) {
        throw StateError('Cannot assign a sold unit.');
      }

      final reservedForRaw =
          (newData['reservedForInterestId'] as String?)?.trim();
      final reservedForOther =
          (reservedForRaw != null && reservedForRaw.isNotEmpty)
              ? reservedForRaw
              : null;
      if (reservedForOther != null && reservedForOther != lid) {
        throw StateError('This unit is reserved for another lead.');
      }
      if (newStatus == DevelopmentUnitStatus.reserved &&
          reservedForOther == null &&
          previousUnitId != uid) {
        throw StateError('This unit is already reserved.');
      }

      if (previousUnitId != null && previousUnitId != uid) {
        final oldRef = unitsCol.doc(previousUnitId);
        final oldDoc = await txn.get(oldRef);
        if (oldDoc.exists) {
          final oldData = oldDoc.data() ?? {};
          if (_shouldReleaseUnitAfterRemovingLeadData(oldData, leadId: lid)) {
            txn.set(
              oldRef,
              {
                'status': 'available',
                'reservedForInterestId': FieldValue.delete(),
                'updatedAt': FieldValue.serverTimestamp(),
              },
              SetOptions(merge: true),
            );
          }
        }
      }

      txn.set(
        newRef,
        {
          'status': 'reserved',
          'reservedForInterestId': lid,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      txn.set(
        leadRef,
        {
          'unitId': uid,
          'lastUpdated': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    });
  }
}

bool _shouldReleaseUnitAfterRemovingLeadData(
  Map<String, dynamic> unitData, {
  required String leadId,
}) {
  final status = DevelopmentUnitStatus.fromRaw(unitData['status'] as String?);
  if (status == null) return false;
  if (status == DevelopmentUnitStatus.sold) return false;
  final r = unitData['reservedForInterestId'] as String?;
  final rt = r?.trim();
  if (rt != null && rt.isNotEmpty) return rt == leadId;
  return status == DevelopmentUnitStatus.reserved;
}
