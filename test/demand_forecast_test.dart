import 'package:erefill/features/dashboard/owner/forecast/demand_forecast.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Thursday 2026-11-05 (no payday nearby: 15th/30th are not within ±1 day
  // of the next 7 days except Nov 14-16 and the 29/30th).
  final today = DateTime(2026, 11, 5);

  List<DemandPoint> history({
    int weeks = 8,
    int Function(DateTime d)? gallons,
    DateTime? from,
  }) {
    final anchor = from ?? today;
    return [
      for (var i = 1; i <= weeks * 7; i++)
        DemandPoint(
          anchor.subtract(Duration(days: i)),
          (gallons ?? (d) => d.weekday == DateTime.saturday ? 40 : 10)(
              anchor.subtract(Duration(days: i))),
        ),
    ];
  }

  test('needs four weeks of history', () {
    final f = DemandForecast.compute(history(weeks: 3), today: today);
    expect(f.hasEnoughHistory, isFalse);
    expect(f.days, isEmpty);
  });

  test('forecasts each weekday from the same weekday in past weeks', () {
    final f = DemandForecast.compute(
      history(gallons: (d) => d.weekday == DateTime.saturday ? 40 : 10),
      today: today,
    );
    expect(f.days, hasLength(7));
    final sat = f.days.firstWhere((d) => d.date.weekday == DateTime.saturday);
    final mon = f.days.firstWhere((d) => d.date.weekday == DateTime.monday);
    expect(sat.gallons, 40);
    expect(mon.gallons, 10);
    expect(f.peak.date.weekday, DateTime.saturday);
  });

  test('recent weeks weigh more than old ones', () {
    // Saturdays grew from 10 (8 weeks ago) to 80 (last week).
    final f = DemandForecast.compute(
      history(gallons: (d) {
        if (d.weekday != DateTime.saturday) return 10;
        final weeksAgo = today.difference(d).inDays ~/ 7;
        return 10 * (8 - weeksAgo);
      }),
      today: today,
    );
    final sat = f.days.firstWhere((d) => d.date.weekday == DateTime.saturday);
    final plainAverage = (10 + 20 + 30 + 40 + 50 + 60 + 70 + 80) / 8;
    expect(sat.gallons, greaterThan(plainAverage));
  });

  test('paydays get the station\'s own payday lift, capped at 1.6x', () {
    final f = DemandForecast.compute(
      history(
        weeks: 10,
        from: DateTime(2026, 11, 12),
        gallons: (d) => DemandForecast.isPayday(d) ? 50 : 10,
      ),
      today: DateTime(2026, 11, 12),
    );
    final payday = f.days.firstWhere((d) => d.date.day == 15);
    expect(payday.isPayday, isTrue);
    expect(payday.gallons, 16); // 10 x 1.6 cap
  });

  test('payday and holiday calendar', () {
    expect(DemandForecast.isPayday(DateTime(2026, 11, 15)), isTrue);
    expect(DemandForecast.isPayday(DateTime(2026, 11, 16)), isTrue);
    expect(DemandForecast.isPayday(DateTime(2026, 11, 30)), isTrue);
    expect(DemandForecast.isPayday(DateTime(2026, 2, 28)), isTrue); // last day
    expect(DemandForecast.isPayday(DateTime(2026, 11, 20)), isFalse);
    expect(DemandForecast.holidayName(DateTime(2026, 12, 25)), 'Christmas Day');
    expect(DemandForecast.holidayName(DateTime(2026, 12, 24)), isNull);
  });

  test('gallonsOf reads order items, falling back to quantity', () {
    expect(
      DemandForecast.gallonsOf({
        'items': [
          {'quantity': 3},
          {'quantity': 2, 'kind': 'accessory'},
        ],
      }),
      3,
    );
    expect(DemandForecast.gallonsOf({'quantity': 4}), 4);
  });

  test('stock alert when the week needs more than stock', () {
    final f = DemandForecast.compute(history(), today: today);
    expect(f.weekTotal, 10 * 6 + 40);
    expect(f.isShort(stock: 90), isTrue);
    expect(f.isShort(stock: 200), isFalse);
  });
}
