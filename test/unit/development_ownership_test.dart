import 'package:flutter_test/flutter_test.dart';
import 'package:property_pulse/models/development_team_role.dart';
import 'package:property_pulse/models/project_model.dart';
import 'package:property_pulse/models/user_profile_doc.dart';
import 'package:property_pulse/utils/effective_development_role.dart';

/// Who counts as a development's owner. Only a Developer account does; being named as the owner is
/// not enough for a Realtor, Property Owner, Seeker or Airbnb Host account. People the developer
/// invited keep the team access their invitation gave them. (The security rules enforce the same
/// thing on the server.)
ProjectModel _project({Map<String, String> roles = const {}}) => ProjectModel(
      id: 'p1',
      firestoreDocumentId: 'p1',
      projectName: 'Palm Heights',
      location: 'Kingston',
      description: 'x',
      developerId: 'dev1',
      ownerId: 'dev1',
      teamMembers: const ['dev1'],
      developerName: 'Dev',
      heroImages: const [],
      statusRaw: 'active',
      isActive: true,
      moderationStatusRaw: 'approved',
      roles: roles,
    );

DevelopmentTeamRole? _role(
  String? uid, {
  bool developer = false,
  bool admin = false,
  DevelopmentTeamRole? teamDoc,
  ProjectModel? project,
}) =>
    resolveEffectiveDevelopmentRole(
      isAppAdmin: admin,
      isDeveloperAccount: developer || admin,
      currentUserId: uid,
      project: project ?? _project(),
      firestoreTeamDocRole: teamDoc,
    );

void main() {
  group('account role check', () {
    test('Developer and admin accounts qualify, in any spelling', () {
      for (final r in ['Developer', 'developer', ' DEVELOPER ', 'Admin', 'admin']) {
        expect(UserProfileDoc.isDeveloperAccountRole(r), isTrue, reason: r);
      }
    });

    test('every other account role, and a missing one, does not', () {
      for (final r in [null, '', 'Realtor', 'Property Owner', 'Property Seeker', 'Airbnb Host', 'Developer Assistant']) {
        expect(UserProfileDoc.isDeveloperAccountRole(r), isFalse, reason: '$r');
      }
    });
  });

  group('effective role on a development', () {
    test('the Developer account that owns it is the owner', () {
      expect(_role('dev1', developer: true), DevelopmentTeamRole.owner);
    });

    test('a named owner on any other account role has no owner powers', () {
      expect(_role('dev1'), isNull);
    });

    test("the owner's own team record and roles entry do not bring their powers back", () {
      final p = _project(roles: const {'dev1': 'owner'});
      expect(_role('dev1', teamDoc: DevelopmentTeamRole.owner, project: p), isNull);
      expect(_role('dev1', developer: true, teamDoc: DevelopmentTeamRole.owner, project: p), DevelopmentTeamRole.owner);
    });

    test('an admin is the owner of everything', () {
      expect(_role('someone', admin: true), DevelopmentTeamRole.owner);
    });

    test('an invited team member keeps their access whatever their account role', () {
      final p = _project(roles: const {'dev1': 'owner', 'agent': 'sales', 'mgr': 'manager'});
      expect(_role('agent', project: p), DevelopmentTeamRole.sales);
      expect(_role('mgr', project: p), DevelopmentTeamRole.manager);
      expect(_role('agent', teamDoc: DevelopmentTeamRole.viewer, project: p), DevelopmentTeamRole.viewer);
    });

    test('a stranger, or a signed-out user, has no role', () {
      expect(_role('nobody'), isNull);
      expect(_role(null, developer: true), isNull);
      expect(_role('', developer: true), isNull);
    });
  });
}
