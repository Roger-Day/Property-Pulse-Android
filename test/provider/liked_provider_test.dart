// Provider tests for LikedProvider.
// iOS parity: PropertyViewModel+Engagement.swift — like toggle, optimistic update.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:property_pulse/models/property_model.dart';
import 'package:property_pulse/providers/liked_provider.dart';
import 'package:property_pulse/repositories/property_repository.dart';

class _FakeRepo implements PropertyRepository {
  final StreamController<Set<String>> _ctrl =
      StreamController<Set<String>>.broadcast();
  Set<String> likedIds = {};
  bool throwOnToggle = false;

  void emit(Set<String> ids) {
    likedIds = ids;
    _ctrl.add(ids);
  }

  @override
  Stream<Set<String>> watchLikedIds(String userId) => _ctrl.stream;

  @override
  Future<void> toggleLike({
    required String userId,
    required PropertyModel property,
  }) async {
    if (throwOnToggle) throw Exception('Network error');
    if (likedIds.contains(property.id)) {
      likedIds = {...likedIds}..remove(property.id);
    } else {
      likedIds = {...likedIds, property.id};
    }
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

PropertyModel _prop(String id) => PropertyModel(
      id: id,
      title: 'Prop $id',
      description: '',
      price: 100000,
      currencyCode: 'USD',
      street: '1 St',
      city: 'NYC',
      state: 'NY',
      zipCode: '10001',
      bedrooms: 2,
      bathrooms: 1,
      squareFootage: 900,
      deleted: false,
      heroImageUrl: null,
      imageUrls: const [],
      features: const [],
      propertyType: 'apartment',
      realtorName: null,
      realtorEmail: null,
      realtorPhone: null,
    );

void main() {
  late _FakeRepo repo;
  late LikedProvider provider;

  setUp(() {
    repo = _FakeRepo();
    provider = LikedProvider(repository: repo, userId: 'u1');
  });

  tearDown(() => provider.dispose());

  group('LikedProvider — initial state', () {
    test('starts in loading state', () => expect(provider.loading, isTrue));
    test('nothing is liked initially', () => expect(provider.isLiked('p1'), isFalse));
  });

  group('LikedProvider — stream', () {
    test('reflects emitted liked IDs', () async {
      repo.emit({'p1', 'p2'});
      await Future<void>.delayed(Duration.zero);
      expect(provider.isLiked('p1'), isTrue);
      expect(provider.isLiked('p3'), isFalse);
      expect(provider.loading, isFalse);
    });
  });

  group('LikedProvider — toggle', () {
    test('optimistically likes an unliked property', () async {
      repo.emit({});
      await Future<void>.delayed(Duration.zero);
      expect(provider.loading, isFalse); // stream has emitted

      // toggle() sets optimistic state synchronously before awaiting the repo
      final f = provider.toggle(_prop('p1'));
      // Optimistic: immediately liked
      expect(provider.isLiked('p1'), isTrue);
      await f;
      // Still liked after repo confirms
      expect(provider.isLiked('p1'), isTrue);
    });

    test('optimistically unlikes a liked property', () async {
      repo.emit({'p1'});
      await Future<void>.delayed(Duration.zero);
      expect(provider.isLiked('p1'), isTrue);

      final f = provider.toggle(_prop('p1'));
      // Optimistic: immediately unliked
      expect(provider.isLiked('p1'), isFalse);
      await f;
      expect(provider.isLiked('p1'), isFalse);
    });

    test('rolls back on error when liking fails', () async {
      repo.emit({});
      await Future<void>.delayed(Duration.zero);

      repo.throwOnToggle = true;
      await provider.toggle(_prop('p1'));
      expect(provider.isLiked('p1'), isFalse);
    });

    test('rolls back on error when unliking fails', () async {
      repo.emit({'p1'});
      await Future<void>.delayed(Duration.zero);

      repo.throwOnToggle = true;
      await provider.toggle(_prop('p1'));
      expect(provider.isLiked('p1'), isTrue);
    });

    test('no-op when userId is null', () async {
      final p = LikedProvider(repository: repo, userId: null);
      await p.toggle(_prop('p1'));
      expect(p.isLiked('p1'), isFalse);
      p.dispose();
    });
  });

  group('LikedProvider — updateUser', () {
    test('clears on sign-out (null userId)', () async {
      repo.emit({'p1'});
      await Future<void>.delayed(Duration.zero);
      provider.updateUser(null);
      await Future<void>.delayed(Duration.zero);
      expect(provider.isLiked('p1'), isFalse);
    });
  });
}
