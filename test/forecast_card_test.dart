import 'package:erefill/features/dashboard/owner/forecast/demand_forecast.dart';
import 'package:erefill/features/dashboard/owner/forecast/forecast_card.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  DemandForecastResult week() => DemandForecastResult(
        hasEnoughHistory: true,
        days: [
          for (var i = 0; i < 7; i++)
            ForecastDay(
              date: DateTime(2026, 11, 6 + i), // Fri..Thu
              gallons: i == 1 ? 42 : 10,
              isPayday: false,
              holiday: null,
            ),
        ],
      );

  Future<void> pump(WidgetTester t, DemandForecastResult f, {int? stock}) =>
      t.pumpWidget(MaterialApp(
        home: Scaffold(body: ForecastCard(forecast: f, stock: stock)),
      ));

  testWidgets('shows the peak day and a 7-bar chart', (tester) async {
    await pump(tester, week());
    expect(find.text('Next 7 days · ~102 gallons'), findsOneWidget);
    expect(find.text('Peak: Sat ~42 gallons'), findsOneWidget);
    final chart = tester.widget<BarChart>(find.byType(BarChart));
    expect(chart.data.barGroups, hasLength(7));
  });

  testWidgets('warns when stock will run short', (tester) async {
    await pump(tester, week(), stock: 80);
    expect(find.textContaining('Stock may run short'), findsOneWidget);
  });

  testWidgets('explains when history is too short', (tester) async {
    await pump(tester, const DemandForecastResult(hasEnoughHistory: false, days: []));
    expect(find.textContaining('Not enough history yet'), findsOneWidget);
    expect(find.byType(BarChart), findsNothing);
  });
}
