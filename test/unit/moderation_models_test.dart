// Unit tests for the content-moderation admin models — pure parsing logic,
// no Firebase mocking needed. Mirrors the style of the other test/unit files
// (e.g. ai_listing_draft_test.dart).
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:property_pulse/models/blocked_word.dart';
import 'package:property_pulse/models/moderation_flags.dart';
import 'package:property_pulse/models/moderation_log.dart';
import 'package:property_pulse/models/moderation_stats.dart';

void main() {
  group('BlockedWord', () {
    test('fromFirestore parses required + optional fields', () {
      final w = BlockedWord.fromFirestore('abc123', {
        'word': 'scumbag',
        'severity': 'block',
        'replacement': '****',
        'category': 'profanity',
        'enabled': true,
      });
      expect(w.id, 'abc123');
      expect(w.word, 'scumbag');
      expect(w.severity, 'block');
      expect(w.replacement, '****');
      expect(w.category, 'profanity');
      expect(w.enabled, isTrue);
    });

    test('fromFirestore defaults severity to warn when missing/invalid', () {
      final w = BlockedWord.fromFirestore('x', {'word': 'meh'});
      expect(w.severity, 'warn');
      expect(w.enabled, isTrue); // defaults true
    });

    test('toFirestore lowercases and trims the word', () {
      const w = BlockedWord(id: 'x', word: '  SlurWord  ', severity: 'block');
      final data = w.toFirestore();
      expect(data['word'], 'slurword');
    });

    test('copyWith only overrides provided fields', () {
      const w = BlockedWord(id: 'x', word: 'foo', severity: 'warn', enabled: true);
      final updated = w.copyWith(enabled: false);
      expect(updated.word, 'foo');
      expect(updated.severity, 'warn');
      expect(updated.enabled, isFalse);
    });
  });

  group('ModerationLog', () {
    test('fromFirestore parses violations/matchedTerms lists and timestamps', () {
      final now = DateTime(2026, 7, 30, 12);
      final log = ModerationLog.fromFirestore('log1', {
        'type': 'property',
        'decision': 'block',
        'confidence': 0.92,
        'violations': ['contact_information', 'scam'],
        'matchedTerms': ['whatsapp'],
        'userId': 'u1',
        'listingId': 'p1',
        'source': 'text',
        'latencyMs': 42,
        'createdAt': Timestamp.fromDate(now),
        'falsePositive': false,
      });
      expect(log.decision, 'block');
      expect(log.confidence, 0.92);
      expect(log.violations, ['contact_information', 'scam']);
      expect(log.matchedTerms, ['whatsapp']);
      expect(log.userId, 'u1');
      expect(log.listingId, 'p1');
      expect(log.latencyMs, 42);
      expect(log.createdAt, now);
      expect(log.isReviewed, isFalse);
    });

    test('isReviewed is true once adminReviewedAt is set', () {
      final log = ModerationLog.fromFirestore('log2', {
        'type': 'message',
        'decision': 'warn',
        'confidence': 0.5,
        'violations': <String>[],
        'adminReviewedAt': Timestamp.fromDate(DateTime(2026, 7, 30)),
        'falsePositive': true,
      });
      expect(log.isReviewed, isTrue);
      expect(log.falsePositive, isTrue);
    });

    test('missing decision defaults to pass', () {
      final log = ModerationLog.fromFirestore('log3', {'type': 'review'});
      expect(log.decision, 'pass');
      expect(log.violations, isEmpty);
    });
  });

  group('ModerationStats', () {
    test('fromMap parses nested count lists and nullable fields', () {
      final stats = ModerationStats.fromMap({
        'rejectedToday': 3,
        'mostCommonViolations': [
          {'key': 'contact_information', 'count': 12},
          {'key': 'profanity', 'count': 4},
        ],
        'topOffendingUsers': [
          {'key': 'u1', 'count': 5},
        ],
        'mostBlockedWords': <Map<String, dynamic>>[],
        'mostRejectedImagesCount': 2,
        'averageModerationTimeMs': 210,
        'falsePositiveRate': 0.1,
        'activeBlockedWordsCount': 40,
        'sampleWindowDays': 30,
        'sampleSize': 500,
      });

      expect(stats.rejectedToday, 3);
      expect(stats.mostCommonViolations.length, 2);
      expect(stats.mostCommonViolations.first.key, 'contact_information');
      expect(stats.mostCommonViolations.first.count, 12);
      expect(stats.topOffendingUsers.single.key, 'u1');
      expect(stats.mostBlockedWords, isEmpty);
      expect(stats.averageModerationTimeMs, 210);
      expect(stats.falsePositiveRate, 0.1);
      expect(stats.activeBlockedWordsCount, 40);
    });

    test('fromMap tolerates an empty map (no data yet)', () {
      final stats = ModerationStats.fromMap(const {});
      expect(stats.rejectedToday, 0);
      expect(stats.mostCommonViolations, isEmpty);
      expect(stats.averageModerationTimeMs, isNull);
      expect(stats.falsePositiveRate, isNull);
      expect(stats.sampleWindowDays, 30);
    });
  });

  group('ModerationFlag', () {
    test('wireValue matches the backend field names exactly', () {
      expect(ModerationFlag.textModeration.wireValue, 'textModeration');
      expect(ModerationFlag.imageModeration.wireValue, 'imageModeration');
      expect(ModerationFlag.ocrModeration.wireValue, 'ocrModeration');
      expect(ModerationFlag.propertyImageVerification.wireValue, 'propertyImageVerification');
      expect(ModerationFlag.contactInfoBlocking.wireValue, 'contactInfoBlocking');
      expect(ModerationFlag.adminModerationDashboard.wireValue, 'adminModerationDashboard');
    });

    test('every flag has a non-empty label and description', () {
      for (final flag in ModerationFlag.values) {
        expect(flag.label, isNotEmpty);
        expect(flag.description, isNotEmpty);
      }
    });
  });
}
