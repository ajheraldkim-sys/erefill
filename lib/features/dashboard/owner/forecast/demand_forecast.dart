/// Gallons sold on one past day.
class DemandPoint {
  const DemandPoint(this.date, this.gallons);
  final DateTime date;
  final int gallons;
}

class ForecastDay {
  const ForecastDay({
    required this.date,
    required this.gallons,
    required this.isPayday,
    this.holiday,
  });

  final DateTime date;
  final int gallons;
  final bool isPayday;
  final String? holiday;
}

class DemandForecastResult {
  const DemandForecastResult({required this.hasEnoughHistory, required this.days});

  final bool hasEnoughHistory;
  final List<ForecastDay> days;

  int get weekTotal => days.fold(0, (s, d) => s + d.gallons);

  ForecastDay get peak => days.reduce((a, b) => b.gallons > a.gallons ? b : a);

  /// True when the coming week needs more gallons than are in stock.
  bool isShort({required int stock}) => weekTotal > stock;
}

/// Statistical 7-day demand forecast from a station's own order history:
///   * weekday baseline: weighted average of the same weekday over the last
///     8 weeks (last week weight 8 … 8 weeks ago weight 1), paydays excluded
///   * payday lift (around the 15th and 30th / month end), learned from the
///     station's history and clamped to 1.0–1.6x
///   * Philippine holidays are flagged (not adjusted)
/// Needs at least 4 weeks of history. No weather or external data.
abstract final class DemandForecast {
  static const int minHistoryDays = 28;
  static const int lookbackWeeks = 8;
  static const double maxPaydayLift = 1.6;

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  static int _lastDay(DateTime d) => DateTime(d.year, d.month + 1, 0).day;

  /// Paydays: 14th–16th, ±1 day around the 30th (or month end), month end,
  /// and the 1st (the day after month-end pay).
  static bool isPayday(DateTime d) {
    final last = _lastDay(d);
    final thirtieth = last < 30 ? last : 30;
    return (d.day - 15).abs() <= 1 ||
        (d.day - thirtieth).abs() <= 1 ||
        d.day == last ||
        d.day == 1;
  }

  static const _holidays = <String, String>{
    '01-01': "New Year's Day",
    '04-09': 'Araw ng Kagitingan',
    '05-01': 'Labor Day',
    '06-12': 'Independence Day',
    '08-21': 'Ninoy Aquino Day',
    '11-01': "All Saints' Day",
    '11-30': 'Bonifacio Day',
    '12-08': 'Immaculate Conception',
    '12-25': 'Christmas Day',
    '12-30': 'Rizal Day',
    '12-31': "New Year's Eve",
    '2026-04-02': 'Maundy Thursday',
    '2026-04-03': 'Good Friday',
    '2026-08-31': 'National Heroes Day',
    '2027-03-25': 'Maundy Thursday',
    '2027-03-26': 'Good Friday',
    '2027-08-30': 'National Heroes Day',
  };

  static String? holidayName(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return _holidays['${d.year}-${two(d.month)}-${two(d.day)}'] ??
        _holidays['${two(d.month)}-${two(d.day)}'];
  }

  /// Water gallons in an order row (accessories excluded).
  static int gallonsOf(Map<String, dynamic> order) {
    final items = order['items'];
    if (items is List && items.isNotEmpty) {
      var n = 0;
      for (final i in items) {
        if (i is Map && i['kind'] != 'accessory') {
          n += (i['quantity'] as num?)?.toInt() ?? 0;
        }
      }
      return n;
    }
    return (order['quantity'] as num?)?.toInt() ?? 1;
  }

  static DemandForecastResult compute(
    List<DemandPoint> history, {
    required DateTime today,
    int days = 7,
  }) {
    final t = _day(today);
    if (history.isEmpty) {
      return const DemandForecastResult(hasEnoughHistory: false, days: []);
    }
    final byDay = <DateTime, int>{};
    var earliest = t;
    for (final p in history) {
      final d = _day(p.date);
      if (!d.isBefore(t)) continue;
      byDay[d] = (byDay[d] ?? 0) + p.gallons;
      if (d.isBefore(earliest)) earliest = d;
    }
    if (t.difference(earliest).inDays < minHistoryDays) {
      return const DemandForecastResult(hasEnoughHistory: false, days: []);
    }
    int g(DateTime d) => byDay[d] ?? 0;

    // Payday lift from the whole history window.
    var payTotal = 0, payCount = 0, otherTotal = 0, otherCount = 0;
    for (var d = earliest; d.isBefore(t); d = d.add(const Duration(days: 1))) {
      if (isPayday(d)) {
        payTotal += g(d);
        payCount++;
      } else {
        otherTotal += g(d);
        otherCount++;
      }
    }
    final otherMean = otherCount == 0 ? 0 : otherTotal / otherCount;
    final payMean = payCount == 0 ? 0 : payTotal / payCount;
    final lift = otherMean <= 0
        ? 1.0
        : (payMean / otherMean).clamp(1.0, maxPaydayLift).toDouble();

    final out = <ForecastDay>[];
    for (var i = 1; i <= days; i++) {
      final date = t.add(Duration(days: i));
      double weighted(bool skipPaydays) {
        var sum = 0.0, weights = 0.0;
        for (var k = 1; k <= lookbackWeeks; k++) {
          final past = date.subtract(Duration(days: 7 * k));
          if (!past.isBefore(t) || past.isBefore(earliest)) continue;
          if (skipPaydays && isPayday(past)) continue;
          final w = (lookbackWeeks + 1 - k).toDouble();
          sum += w * g(past);
          weights += w;
        }
        return weights == 0 ? double.nan : sum / weights;
      }

      var base = weighted(true);
      if (base.isNaN) base = weighted(false);
      if (base.isNaN) base = 0;
      final payday = isPayday(date);
      out.add(ForecastDay(
        date: date,
        gallons: (payday ? base * lift : base).round(),
        isPayday: payday,
        holiday: holidayName(date),
      ));
    }
    return DemandForecastResult(hasEnoughHistory: true, days: out);
  }
}
