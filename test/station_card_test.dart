import 'package:erefill/core/widgets/refill_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('station list card shows real price, location, and status', (
    tester,
  ) async {
    var favoriteTapped = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StationCard(
            station: {
              'station_name': 'Cantilan Pure Water',
              'barangay': 'Poblacion',
              'town': 'Cantilan',
              'price_per_gallon': 35.5,
              'station_availability': 'open',
              'average_rating': 4.7,
              'review_count': 12,
            },
            showFavorite: true,
            onFavoriteToggle: () => favoriteTapped = true,
          ),
        ),
      ),
    );

    expect(find.text('Cantilan Pure Water'), findsOneWidget);
    expect(find.text('Poblacion, Cantilan'), findsOneWidget);
    expect(find.text('₱35.50 / gallon'), findsOneWidget);
    expect(find.text('Open'), findsOneWidget);
    expect(find.text('4.7 · 12 reviews'), findsOneWidget);

    await tester.tap(find.byTooltip('Add favorite'));
    expect(favoriteTapped, isTrue);
  });

  testWidgets('station card does not show a fabricated zero price', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: StationCard(
            station: {
              'station_name': 'New Station',
              'price_per_gallon': 0,
              'station_availability': 'closed',
            },
          ),
        ),
      ),
    );

    expect(find.text('Price not listed'), findsOneWidget);
    expect(find.text('₱0 / gallon'), findsNothing);
  });
}
