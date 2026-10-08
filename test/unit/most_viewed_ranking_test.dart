import 'package:flutter_test/flutter_test.dart';
import 'package:property_pulse/logic/most_viewed_ranking.dart';

({String id, num views, bool isDeleted}) doc(String id, num views, {bool deleted = false}) =>
    (id: id, views: views, isDeleted: deleted);

void main() {
  group('rankedIds', () {
    test('most viewed first, only listings that have been viewed', () {
      final ids = MostViewedRanking.rankedIds(
          [doc('a', 3), doc('b', 50), doc('c', 0), doc('d', 12)],
          limit: 10);
      expect(ids, ['b', 'd', 'a']);
    });

    test('skips analytics for deleted listings', () {
      expect(
          MostViewedRanking.rankedIds([doc('a', 99, deleted: true), doc('b', 1)],
              limit: 10),
          ['b']);
    });

    test('stops at the limit', () {
      final docs = [for (var i = 1; i <= 50; i++) doc('p$i', i)];
      final ids = MostViewedRanking.rankedIds(docs, limit: 5);
      expect(ids, ['p50', 'p49', 'p48', 'p47', 'p46']);
    });

    test('equal counts keep their original order', () {
      final ids = MostViewedRanking.rankedIds(
          [doc('a', 5), doc('b', 5), doc('c', 5), doc('d', 9)],
          limit: 10);
      expect(ids, ['d', 'a', 'b', 'c']);
    });

    test('fractional or odd counts do not break sorting', () {
      expect(MostViewedRanking.rankedIds([doc('a', 2.5), doc('b', 2)], limit: 5),
          ['a', 'b']);
    });

    test('nothing viewed means nothing ranked', () {
      expect(MostViewedRanking.rankedIds([doc('a', 0)], limit: 5), isEmpty);
      expect(MostViewedRanking.rankedIds([], limit: 5), isEmpty);
    });
  });

  group('inRankOrder', () {
    test('follows the ranking and drops listings that could not be loaded', () {
      final out = MostViewedRanking.inRankOrder<String>(
          ['x', 'y', 'z'], {'z': 'Z', 'x': 'X'});
      expect(out, ['X', 'Z']);
    });
  });

  group('paddedTo', () {
    String idOf(String s) => s;

    test('tops up a short list from the fallback without repeats', () {
      final out = MostViewedRanking.paddedTo<String>(
          ['a', 'b'], ['b', 'c', 'd', 'e'],
          minimum: 4, limit: 10, idOf: idOf);
      expect(out, ['a', 'b', 'c', 'd']);
    });

    test('leaves an already long enough list alone', () {
      final out = MostViewedRanking.paddedTo<String>(
          ['a', 'b', 'c'], ['x', 'y'],
          minimum: 2, limit: 10, idOf: idOf);
      expect(out, ['a', 'b', 'c']);
    });

    test('never exceeds the limit', () {
      final out = MostViewedRanking.paddedTo<String>(
          ['a', 'b', 'c', 'd'], ['x'],
          minimum: 2, limit: 3, idOf: idOf);
      expect(out, ['a', 'b', 'c']);
    });

    test('with no views at all it shows the fallback', () {
      final out = MostViewedRanking.paddedTo<String>([], ['n1', 'n2', 'n3'],
          minimum: 2, limit: 10, idOf: idOf);
      expect(out, ['n1', 'n2']);
    });
  });
}
