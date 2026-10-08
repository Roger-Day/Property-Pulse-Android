import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:property_pulse/services/property_analytics_recorder.dart';

void main() {
  late FakeFirebaseFirestore db;
  setUp(() => db = FakeFirebaseFirestore());

  Future<Map<String, dynamic>?> viewer(String property, String uid) async =>
      (await db.doc('property_analytics/$property/viewers/$uid').get()).data();

  test('a view is one record per viewer, with no counter in it', () async {
    await PropertyAnalyticsRecorder.record(db,
        propertyId: 'P1', userId: 'u1', event: PropertyAnalyticsEvent.view);
    final data = await viewer('P1', 'u1');
    expect(data!.keys.toSet(), {'userId', 'viewedAt'});
    expect(data['userId'], 'u1');
    // The parent document is never written by the app.
    expect((await db.doc('property_analytics/P1').get()).exists, isFalse);
  });

  test('each event sets its own timestamp and keeps the others', () async {
    for (final e in PropertyAnalyticsEvent.values) {
      await PropertyAnalyticsRecorder.record(db,
          propertyId: 'P1', userId: 'u1', event: e);
    }
    final data = await viewer('P1', 'u1');
    expect(data!.keys.toSet(),
        {'userId', 'viewedAt', 'inquiredAt', 'sharedAt', 'contactClickedAt'});
  });

  test('viewing twice is still one record', () async {
    for (var i = 0; i < 3; i++) {
      await PropertyAnalyticsRecorder.record(db,
          propertyId: 'P1', userId: 'u1', event: PropertyAnalyticsEvent.view);
    }
    final snap = await db.collection('property_analytics/P1/viewers').get();
    expect(snap.docs, hasLength(1));
  });

  test('different viewers each get their own record', () async {
    for (final u in ['a', 'b', 'c']) {
      await PropertyAnalyticsRecorder.record(db,
          propertyId: 'P1', userId: u, event: PropertyAnalyticsEvent.view);
    }
    final snap = await db.collection('property_analytics/P1/viewers').get();
    expect(snap.docs.map((d) => d.id).toSet(), {'a', 'b', 'c'});
  });

  test('view time is whole seconds within an hour', () {
    expect(PropertyAnalyticsRecorder.clampedSeconds(42.4), 42);
    expect(PropertyAnalyticsRecorder.clampedSeconds(42.6), 43);
    expect(PropertyAnalyticsRecorder.clampedSeconds(-5), 0);
    expect(PropertyAnalyticsRecorder.clampedSeconds(86400), 3600);
    expect(PropertyAnalyticsRecorder.clampedSeconds(double.infinity), 0);
    expect(PropertyAnalyticsRecorder.clampedSeconds(double.nan), 0);
  });

  test('view time payload carries the server time the rules require', () async {
    await PropertyAnalyticsRecorder.recordViewTime(db,
        propertyId: 'P1', userId: 'u1', seconds: 12.2);
    final data = await viewer('P1', 'u1');
    expect(data!['viewSeconds'], 12);
    expect(data.keys.toSet(), {'userId', 'viewSeconds', 'viewTimeAt'});
  });

  test('missing ids are ignored, not thrown', () async {
    await PropertyAnalyticsRecorder.record(db,
        propertyId: '', userId: 'u1', event: PropertyAnalyticsEvent.view);
    await PropertyAnalyticsRecorder.record(db,
        propertyId: 'P1', userId: '', event: PropertyAnalyticsEvent.view);
    expect((await db.collection('property_analytics').get()).docs, isEmpty);
  });

  test('the payload never contains a counter field', () {
    for (final e in PropertyAnalyticsEvent.values) {
      final keys = PropertyAnalyticsRecorder.payload(e, 'u').keys.toSet();
      expect(
          keys.intersection(
              {'views', 'inquiries', 'shares', 'contactClicks', 'savedCount', 'likedCount'}),
          isEmpty);
    }
    expect(FieldValue.serverTimestamp, isNotNull);
  });
}
