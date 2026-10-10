import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:property_pulse/repositories/admin_repository.dart';
import 'package:property_pulse/services/verification_service.dart';

void main() {
  group('section statuses', () {
    test('every backend status maps to itself and has a label', () {
      for (final raw in [
        'not_started', 'pending', 'approved', 'rejected', 'requires_resubmission', 'expired'
      ]) {
        final s = VerificationSectionStatus.parse(raw);
        expect(s.raw, raw);
        expect(s.label, isNotEmpty);
      }
    });

    test('unknown or missing is "not started", never approved', () {
      expect(VerificationSectionStatus.parse(null), VerificationSectionStatus.notStarted);
      expect(VerificationSectionStatus.parse('verified-ish'), VerificationSectionStatus.notStarted);
      expect(VerificationSection.fromMap(null).status, VerificationSectionStatus.notStarted);
    });

    test('pending is never shown as verified', () {
      expect(VerificationSection.fromMap({'status': 'pending'}).status, VerificationSectionStatus.pending);
      expect(VerificationSectionStatus.pending.label, isNot(VerificationSectionStatus.approved.label));
    });

    test('an approval past its end date shows as expired', () {
      final now = DateTime(2026, 10, 9);
      final past = Timestamp.fromDate(now.subtract(const Duration(minutes: 1)));
      final future = Timestamp.fromDate(now.add(const Duration(days: 1)));
      expect(VerificationSection.fromMap({'status': 'approved', 'expiresAt': past}, now: now).status,
          VerificationSectionStatus.expired);
      expect(VerificationSection.fromMap({'status': 'approved', 'expiresAt': future}, now: now).status,
          VerificationSectionStatus.approved);
      expect(VerificationSection.fromMap({'status': 'approved'}, now: now).status,
          VerificationSectionStatus.approved);
    });

    test('only unfinished sections can be submitted', () {
      expect(VerificationSectionStatus.notStarted.canSubmit, isTrue);
      expect(VerificationSectionStatus.rejected.canSubmit, isTrue);
      expect(VerificationSectionStatus.requiresResubmission.canSubmit, isTrue);
      expect(VerificationSectionStatus.expired.canSubmit, isTrue);
      expect(VerificationSectionStatus.pending.canSubmit, isFalse);
      expect(VerificationSectionStatus.approved.canSubmit, isFalse);
    });
  });

  group('the record', () {
    VerificationRecord rec(String email, String phone) => VerificationRecord.fromMap({
          'email': {'status': email},
          'phone': {'status': phone},
        });

    test('contact is verified only when BOTH email and phone are', () {
      expect(rec('not_started', 'not_started').contactVerified, isFalse);
      expect(rec('approved', 'not_started').contactVerified, isFalse);
      expect(rec('not_started', 'approved').contactVerified, isFalse);
      expect(rec('approved', 'approved').contactVerified, isTrue);
    });

    test('an empty record is entirely not started', () {
      final r = VerificationRecord.fromMap(null);
      expect(r.identity.status, VerificationSectionStatus.notStarted);
      expect(r.professional.status, VerificationSectionStatus.notStarted);
      expect(r.level, isNull);
    });
  });

  group('requirements come from the backend', () {
    test('documents and counts parse; front+back of an ID are one document', () {
      final req = VerificationRequirements.fromMap({
        'levels': [
          {'id': 'basic', 'available': true, 'documents': []},
          {
            'id': 'standard',
            'available': true,
            'documents': [
              {'type': 'government_id', 'label': 'Government-issued photo ID', 'minFiles': 1, 'maxFiles': 2, 'filesHint': 'Front, and back'}
            ],
          },
          {'id': 'elite', 'available': false, 'documents': []},
        ],
        'maxFileBytes': 5242880,
      })!;
      expect(req.level('basic')!.documents, isEmpty, reason: 'Basic needs no documents');
      expect(req.level('standard')!.documents, hasLength(1));
      expect(req.level('standard')!.documents.first.maxFiles, 2);
      expect(req.level('elite')!.available, isFalse);
    });

    test('the fallback matches the backend defaults', () {
      final req = VerificationRequirements.fallback;
      expect(req.level('basic')!.documents, isEmpty);
      expect(req.level('standard')!.documents.map((d) => d.type), ['government_id']);
      expect(req.level('elite')!.available, isFalse);
    });

    test('malformed input is rejected', () {
      expect(VerificationRequirements.fromMap({'nope': 1}), isNull);
      expect(VerificationRequirements.fromMap('x'), isNull);
    });
  });

  group('admin queue', () {
    test('a backend request is recognised and always shown for review', () {
      final d = {'source': 'v2', 'type': 'identity', 'userId': 'u'};
      expect(AdminRepository.isBackendRequest(d), isTrue);
      expect(AdminRepository.isIdentityVerification(d), isTrue);
    });

    test('both older submission shapes still show; the multi-document shape no longer disappears', () {
      expect(AdminRepository.isIdentityVerification({'documentUrl': 'https://x/y.jpg'}), isTrue);
      expect(AdminRepository.isIdentityVerification({'documentUrls': ['https://x/y.jpg']}), isTrue);
    });

    test('empty requests and admin-role applications are not identity requests', () {
      expect(AdminRepository.isIdentityVerification({'userId': 'u'}), isFalse);
      expect(AdminRepository.isIdentityVerification({'documentUrls': []}), isFalse);
      expect(AdminRepository.isIdentityVerification({'type': 'admin_role_interest', 'documentUrl': 'x'}), isFalse);
    });
  });
}
