import 'dart:math' as math;

/// Recommends stations by rating quality, not just the raw average.
///
/// Uses a Bayesian (weighted) average so a station with two 5-star reviews
/// does not outrank one with eighty 4.7-star reviews:
///
///   score = (C * m + avg * n) / (C + n)
///
/// where n is the review count, m the mean rating across the loaded stations
/// and C the number of "virtual" mean-rated reviews every station starts with.
/// When the customer's location is known, a small distance penalty (capped)
/// breaks near-ties in favour of closer stations.
class StationRanking {
  StationRanking._();

  /// Virtual reviews at the mean rating.
  static const double priorWeight = 5;

  /// Mean used when no loaded station has reviews yet.
  static const double fallbackMean = 4.0;

  /// Fewer reviews than this shows a "New" badge instead of stars.
  static const int newStationThreshold = 3;

  /// Added to the score while the station has a valid approved lab test
  /// (profiles.water_tested_until, water_tested_badge.sql). Enough to break
  /// near-ties, too small to lift a clearly worse-rated station.
  static const double waterTestedBonus = 0.1;

  /// True while [s]'s latest approved lab test has not expired on [today].
  static bool isWaterTested(Map<String, dynamic> s, DateTime today) {
    final until = DateTime.tryParse('${s['water_tested_until'] ?? ''}');
    if (until == null) return false;
    final d = DateTime(today.year, today.month, today.day);
    return DateTime(until.year, until.month, until.day).isAfter(d);
  }

  static const double _penaltyPerKm = 0.02;
  static const double _maxDistancePenalty = 0.3;

  static double rating(Map<String, dynamic> s) =>
      _num(s['average_rating']) ?? 0;

  static int reviewCount(Map<String, dynamic> s) =>
      (_num(s['review_count']) ?? 0).round();

  static bool isNew(Map<String, dynamic> s) =>
      reviewCount(s) < newStationThreshold;

  /// Weighted rating for one station.
  static double score(Map<String, dynamic> s, {required double mean}) {
    final n = reviewCount(s);
    if (n <= 0) return mean;
    return (priorWeight * mean + rating(s) * n) / (priorWeight + n);
  }

  /// Mean rating over the stations that have reviews.
  static double meanRating(Iterable<Map<String, dynamic>> stations) {
    var sum = 0.0;
    var count = 0;
    for (final s in stations) {
      if (reviewCount(s) > 0) {
        sum += rating(s);
        count++;
      }
    }
    return count == 0 ? fallbackMean : sum / count;
  }

  /// Returns a new list, best recommendation first. [include] drops stations
  /// that should not be recommended (closed to orders, unverified, ...).
  static List<Map<String, dynamic>> rank(
    Iterable<Map<String, dynamic>> stations, {
    double? customerLat,
    double? customerLng,
    bool Function(Map<String, dynamic> station)? include,
    double Function(Map<String, dynamic> station)? bonus,
    DateTime? today,
  }) {
    final pool = [
      for (final s in stations)
        if (include == null || include(s)) s,
    ];
    final mean = meanRating(pool);
    final now = today ?? DateTime.now();
    double total(Map<String, dynamic> s) {
      var v = score(s, mean: mean) + (bonus?.call(s) ?? 0);
      if (isWaterTested(s, now)) v += waterTestedBonus;
      final km = distanceKm(s, customerLat, customerLng);
      if (km != null) {
        v -= math.min(km * _penaltyPerKm, _maxDistancePenalty);
      }
      return v;
    }

    final scored = [for (final s in pool) (s, total(s))];
    scored.sort((a, b) => b.$2.compareTo(a.$2));
    return [for (final e in scored) e.$1];
  }

  /// Straight-line distance from the customer, or null if either point is
  /// unknown.
  static double? distanceKm(Map<String, dynamic> s, double? lat, double? lng) {
    final sLat = _num(s['latitude']) ?? _num(s['lat']);
    final sLng = _num(s['longitude']) ?? _num(s['lng']);
    if (lat == null || lng == null || sLat == null || sLng == null) {
      return null;
    }
    const r = 6371.0;
    double rad(double d) => d * math.pi / 180;
    final dLat = rad(sLat.toDouble() - lat);
    final dLng = rad(sLng.toDouble() - lng);
    final a =
        math.pow(math.sin(dLat / 2), 2) +
        math.cos(rad(lat)) *
            math.cos(rad(sLat.toDouble())) *
            math.pow(math.sin(dLng / 2), 2);
    return 2 * r * math.asin(math.sqrt(a));
  }

  static double? _num(Object? v) => switch (v) {
    num n => n.toDouble(),
    String t => double.tryParse(t),
    _ => null,
  };
}
