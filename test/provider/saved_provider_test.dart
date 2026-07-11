// Provider tests for SavedProvider.
// iOS parity: PropertyViewModel+UserContent.swift — save/unsave toggle with
// optimistic update and rollback on error.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:property_pulse/models/property_model.dart';
import 'package:property_pulse/providers/saved_provider.dart';
import 'package:property_pulse/repositories/property_repository.dart';

// ── Minimal fake repository ───────────────────────────────────────────────────

class _FakeRepo implements PropertyRepository {
  final StreamController<Set<String>> _ctrl =
      StreamController<Set<String>>.broadcast();
  Set<String> savedIds = {};
  bool throwOnToggle = false;

  void emitSaved(Set<String> ids) {
    savedIds = ids;
    _ctrl.add(ids);
  }

  @override
  Stream<Set<String>> watchSavedIds(String userId) => _ctrl.stream;

  @override
  Future<bool> toggleSaved({
    required String userId,
    required PropertyModel property,
  }) async {
    if (throwOnToggle) throw Exception('Network error');
    final wasSaved = savedIds.contains(property.id);
    if (wasSaved) {
      savedIds = {...savedIds}..remove(property.id);
    } else {
      savedIds = {...savedIds, property.id};
    }
    return !wasSaved;
  }

  @override
  Future<void> removeSavedById({
    required String userId,
    required String propertyId,
  }) async {
    savedIds = {...savedIds}..remove(propertyId);
  }

  // All other PropertyRepository methods are not needed for these tests.
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

// ── Test helper ───────────────────────────────────────────────────────────────

PropertyModel _prop(String id) => PropertyModel(
      id: id,
      title: 'Property $id',
      description: '',
      price: 100000,
      currencyCode: 'USD',
      street: '1 Main St',
      city: 'Miami',
      state: 'FL',
      zipCode: '33101',
      bedrooms: 2,
      bathrooms: 1,
      squareFootage: 1000,
      deleted: false,
      heroImageUrl: null,
      imageUrls: const [],
      features: const [],
      propertyType: 'house',
      realtorName: null,
      realtorEmail: null,
      realtorPhone: null,
    );

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  late _FakeRepo repo;
  late SavedProvider provider;

  setUp(() {
    repo = _FakeRepo();
    provider = SavedProvider(repository: repo, userId: 'user1');
  });

  tearDown(() {
    provider.dispose();
  });

  group('SavedProvider — initial state', () {
    test('starts loading', () {
      // Before any stream event the provider is in loading state
      expect(provider.loading, isTrue);
    });

    test('no property is saved initially', () {
      expect(provider.isSaved('p1'), isFalse);
    });

    test('savedIds is empty initially', () {
      expect(provider.savedIds, isEmpty);
    });
  });

  group('SavedProvider — stream', () {
    test('updates savedIds when stream emits', () async {
      repo.emitSaved({'p1', 'p2'});
      // Allow microtasks to run
      await Future<void>.delayed(Duration.zero);

      expect(provider.isSaved('p1'), isTrue);
      expect(provider.isSaved('p2'), isTrue);
      expect(provider.isSaved('p3'), isFalse);
      expect(provider.loading, isFalse);
    });

    test('clears savedIds when stream emits empty set', () async {
      repo.emitSaved({'p1'});
      await Future<void>.delayed(Duration.zero);
      repo.emitSaved({});
      await Future<void>.delayed(Duration.zero);

      expect(provider.isSaved('p1'), isFalse);
    });
  });

  group('SavedProvider — toggle (optimistic update)', () {
    test('toggle saves an unsaved property immediately (optimistic)', () async {
      repo.emitSaved({});
      await Future<void>.delayed(Duration.zero);

      final property = _prop('p1');
      // Don't await — check state immediately after scheduling
      final future = provider.toggle(property);
      // Optimistic state: already saved
      expect(provider.isSaved('p1'), isTrue);
      await future;
      expect(provider.isSaved('p1'), isTrue);
    });

    test('toggle unsaves a saved property (optimistic)', () async {
      repo.emitSaved({'p1'});
      await Future<void>.delayed(Duration.zero);

      final property = _prop('p1');
      final future = provider.toggle(property);
      expect(provider.isSaved('p1'), isFalse);
      await future;
      expect(provider.isSaved('p1'), isFalse);
    });

    test('rollback on error — save rolled back to unsaved', () async {
      repo.emitSaved({});
      await Future<void>.delayed(Duration.zero);

      repo.throwOnToggle = true;
      final property = _prop('p1');
      await provider.toggle(property);

      // Should roll back to original state
      expect(provider.isSaved('p1'), isFalse);
    });

    test('rollback on error — unsave rolled back to saved', () async {
      repo.emitSaved({'p1'});
      await Future<void>.delayed(Duration.zero);

      repo.throwOnToggle = true;
      await provider.toggle(_prop('p1'));

      expect(provider.isSaved('p1'), isTrue);
    });

    test('toggle is no-op when userId is null', () async {
      final nullProvider =
          SavedProvider(repository: repo, userId: null);
      await nullProvider.toggle(_prop('p1'));
      expect(nullProvider.isSaved('p1'), isFalse);
      nullProvider.dispose();
    });

    test('lister cannot save their own listing', () async {
      // Property owned by user1 — toggle should be a no-op
      final ownListing = PropertyModel(
        id: 'myListing',
        title: 'My Listing',
        description: '',
        price: 100000,
        currencyCode: 'USD',
        street: '1 Main',
        city: 'Miami',
        state: 'FL',
        zipCode: '33101',
        bedrooms: 2,
        bathrooms: 1,
        squareFootage: 1000,
        deleted: false,
        heroImageUrl: null,
        imageUrls: const [],
        features: const [],
        propertyType: 'house',
        realtorName: null,
        realtorEmail: null,
        realtorPhone: null,
        realtorId: 'user1', // same as provider userId
      );

      repo.emitSaved({});
      await Future<void>.delayed(Duration.zero);
      await provider.toggle(ownListing);
      expect(provider.isSaved('myListing'), isFalse);
    });
  });

  group('SavedProvider — updateUser', () {
    test('updateUser to same uid is a no-op', () async {
      repo.emitSaved({'p1'});
      await Future<void>.delayed(Duration.zero);

      provider.updateUser('user1'); // same uid
      await Future<void>.delayed(Duration.zero);
      // State should be unchanged
      expect(provider.isSaved('p1'), isTrue);
    });

    test('updateUser to null clears saved state', () async {
      repo.emitSaved({'p1'});
      await Future<void>.delayed(Duration.zero);

      provider.updateUser(null);
      await Future<void>.delayed(Duration.zero);
      expect(provider.isSaved('p1'), isFalse);
      expect(provider.loading, isFalse);
    });
  });

  group('SavedProvider — removeById', () {
    test('removes a property by id', () async {
      repo.emitSaved({'p1', 'p2'});
      await Future<void>.delayed(Duration.zero);

      await provider.removeById('p1');
      expect(provider.isSaved('p1'), isFalse);
      expect(provider.isSaved('p2'), isTrue);
    });
  });

  group('SavedProvider — notifyListeners', () {
    test('emits change notification on toggle', () async {
      repo.emitSaved({});
      await Future<void>.delayed(Duration.zero);

      var notified = false;
      provider.addListener(() => notified = true);
      await provider.toggle(_prop('p1'));
      expect(notified, isTrue);
    });
  });
}
