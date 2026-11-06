import 'package:erefill/core/tour/app_tour.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('tour shows once per role and can be reset for replay', () async {
    expect(await TourStore.shouldShow('customer'), isTrue);
    await TourStore.markSeen('customer');
    expect(await TourStore.shouldShow('customer'), isFalse);
    expect(await TourStore.shouldShow('owner'), isTrue);
    await TourStore.reset('customer');
    expect(await TourStore.shouldShow('customer'), isTrue);
  });

  test('every role has steps for each bottom tab', () {
    expect(AppTourSteps.forRole('customer'), hasLength(5));
    expect(AppTourSteps.forRole('owner'), hasLength(5));
    expect(AppTourSteps.forRole('rider'), hasLength(5));
    expect(AppTourSteps.forRole('admin'), isEmpty);
  });

  testWidgets('walks through steps, then marks the tour seen', (tester) async {
    final navKey = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => AppTour.show(
                context,
                role: 'customer',
                navBarKey: navKey,
                steps: const [
                  TourStep(tab: 0, title: 'Home', body: 'Your dashboard'),
                  TourStep(tab: 1, title: 'Stations', body: 'Find stations'),
                ],
                tabCount: 2,
              ),
              child: const Text('start'),
            ),
          ),
        ),
        bottomNavigationBar: SizedBox(key: navKey, height: 64),
      ),
    ));

    await tester.tap(find.text('start'));
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('1 of 2'), findsOneWidget);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Stations'), findsOneWidget);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Stations'), findsNothing);
    expect(await TourStore.shouldShow('customer'), isFalse);
  });

  testWidgets('skip closes immediately and marks seen', (tester) async {
    final navKey = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => AppTour.show(
              context,
              role: 'rider',
              navBarKey: navKey,
              steps: AppTourSteps.forRole('rider'),
              tabCount: 5,
            ),
            child: const Text('go'),
          ),
        ),
        bottomNavigationBar: SizedBox(key: navKey, height: 64),
      ),
    ));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Skip tour'));
    await tester.pumpAndSettle();
    expect(find.text('Skip tour'), findsNothing);
    expect(await TourStore.shouldShow('rider'), isFalse);
  });
}
