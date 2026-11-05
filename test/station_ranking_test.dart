import 'package:erefill/core/utils/station_ranking.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> st(String id, num rating, int count,
        {double? lat, double? lng}) =>
    {
      'id': id,
      'average_rating': rating,
      'review_count': count,
      'latitude': ?lat,
      'longitude': ?lng,
    };

void main() {
  group('StationRanking.score', () {
    test('a few perfect reviews do not beat many great ones', () {
      final mean = 4.0;
      final fewPerfect = StationRanking.score(st('a', 5.0, 2), mean: mean);
      final manyGreat = StationRanking.score(st('b', 4.7, 80), mean: mean);
      expect(manyGreat, greaterThan(fewPerfect));
    });

    test('no reviews scores the mean', () {
      expect(StationRanking.score(st('a', 0, 0), mean: 4.1), closeTo(4.1, 1e-9));
    });

    test('tolerates strings and nulls from the database', () {
      final s = StationRanking.score(
        {'id': 'x', 'average_rating': '4.5', 'review_count': null},
        mean: 4.0,
      );
      expect(s, closeTo(4.0, 1e-9));
    });
  });

  group('StationRanking.rank', () {
    test('orders by weighted score, best first', () {
      final ranked = StationRanking.rank([
        st('low', 3.0, 40),
        st('top', 4.9, 60),
        st('new', 5.0, 1),
      ]);
      expect(ranked.map((s) => s['id']), ['top', 'new', 'low']);
    });

    test('nearer station wins a near tie when the customer location is known',
        () {
      final ranked = StationRanking.rank(
        [
          st('far', 4.6, 30, lat: 9.40, lng: 126.0),
          st('near', 4.6, 30, lat: 9.00, lng: 126.0),
        ],
        customerLat: 9.0,
        customerLng: 126.0,
      );
      expect(ranked.first['id'], 'near');
    });

    test('distance never outweighs a clearly better rating', () {
      final ranked = StationRanking.rank(
        [
          st('nearPoor', 3.2, 50, lat: 9.0, lng: 126.0),
          st('farGreat', 4.8, 50, lat: 9.1, lng: 126.0),
        ],
        customerLat: 9.0,
        customerLng: 126.0,
      );
      expect(ranked.first['id'], 'farGreat');
    });

    test('excluded stations are dropped', () {
      final ranked = StationRanking.rank(
        [st('a', 4.0, 10), st('b', 5.0, 10)],
        include: (s) => s['id'] != 'b',
      );
      expect(ranked.map((s) => s['id']), ['a']);
    });

    test('does not mutate the input list', () {
      final input = [st('a', 3.0, 10), st('b', 5.0, 10)];
      StationRanking.rank(input);
      expect(input.first['id'], 'a');
    });
  });

  test('isNew is true below 3 reviews', () {
    expect(StationRanking.isNew(st('a', 5, 2)), isTrue);
    expect(StationRanking.isNew(st('a', 5, 3)), isFalse);
  });
}
