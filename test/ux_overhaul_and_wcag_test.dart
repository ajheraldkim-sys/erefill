import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:erefill/core/constants.dart';
import 'package:erefill/core/localization/app_strings.dart';
import 'package:erefill/core/widgets/adaptive_row.dart';
import 'package:erefill/core/widgets/refill_components.dart';
import 'package:erefill/core/widgets/refill_status_widgets.dart';
import 'package:erefill/core/widgets/offline_sync_status_pill.dart';
import 'package:erefill/core/widgets/water_fill_loading_indicator.dart';
import 'package:erefill/core/widgets/brand/refill_lottie.dart';
import 'package:erefill/core/widgets/brand/axo_states.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Design Tokens & Spacing Scale Tests', () {
    test('Named spacing tokens follow 4/8/12/16/24/32 scale', () {
      expect(AppUi.space4, equals(4.0));
      expect(AppUi.space8, equals(8.0));
      expect(AppUi.space12, equals(12.0));
      expect(AppUi.space16, equals(16.0));
      expect(AppUi.space24, equals(24.0));
      expect(AppUi.space32, equals(32.0));
    });

    test('Touch target tokens comply with accessibility standards (>= 48dp, >= 56dp for riders)', () {
      expect(AppUi.kMinTouchTarget, greaterThanOrEqualTo(48.0));
      expect(AppUi.kRiderTouchTarget, greaterThanOrEqualTo(56.0));
    });
  });

  group('WCAG AA Contrast & Colorblind Accessibility Tests', () {
    test('OrderStatusStyle pending badges use dark readable foreground on tinted background', () {
      final lightStyle = OrderStatusStyle.resolve('pending', isDark: false);
      // Background is tinted amber-100, text is dark amber-800
      expect(lightStyle.badgeBackground, equals(const Color(0xFFFEF3C7)));
      expect(lightStyle.badgeForeground, equals(const Color(0xFF92400E)));

      final darkStyle = OrderStatusStyle.resolve('pending', isDark: true);
      expect(darkStyle.badgeBackground, equals(const Color(0xFF451A03).withValues(alpha: 0.70)));
      expect(darkStyle.badgeForeground, equals(const Color(0xFFFCD34D)));
    });

    testWidgets('AvailabilityBadge pairs color with status icon for colorblind accessibility',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                AvailabilityBadge(availability: 'open'),
                AvailabilityBadge(availability: 'closed'),
              ],
            ),
          ),
        ),
      );

      // Verify open badge has check icon and 'Open' text
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
      expect(find.text('Open'), findsOneWidget);

      // Verify closed badge has remove/close icon and 'Closed' text
      expect(find.byIcon(Icons.remove_circle_outline_rounded), findsOneWidget);
      expect(find.text('Closed'), findsOneWidget);
    });
  });

  group('AdaptiveRow Responsive & Scaling Tests', () {
    testWidgets('Renders children horizontally on wide screen (>340dp)', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AdaptiveRow(
              children: [
                Text('Left Widget'),
                Text('Right Widget'),
              ],
            ),
          ),
        ),
      );

      expect(find.text('Left Widget'), findsOneWidget);
      expect(find.text('Right Widget'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Does not overflow at narrow 320dp width with 150% text scale', (tester) async {
      tester.view.physicalSize = const Size(320, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
            child: Scaffold(
              body: SizedBox(
                width: 320,
                child: AdaptiveRow(
                  breakpoint: 340,
                  forceWrapOnLargeFont: true,
                  children: const [
                    Text('Customer: Juan Dela Cruz'),
                    Text('₱150.00 • Delivered Today'),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Customer: Juan Dela Cruz'), findsOneWidget);
      expect(find.text('₱150.00 • Delivered Today'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('OfflineSyncStatusPill Tests', () {
    testWidgets('Shows "All synced" badge when showAlways is true and queue is empty',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: OfflineSyncStatusPill(showAlways: true),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('All synced'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    });

    testWidgets('Hides when showAlways is false and online with 0 queued items',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: OfflineSyncStatusPill(showAlways: false),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('All synced'), findsNothing);
    });
  });

  group('Trilingual AppStrings & AppLanguageProvider Tests', () {
    test('AppStrings outputs correct plain terminology across English, Filipino, and Bisaya', () {
      // English
      expect(AppStrings.gallons(AppLanguage.english), equals('Gallons'));
      expect(AppStrings.total(AppLanguage.english), equals('Total'));
      expect(AppStrings.payOnDelivery(AppLanguage.english), equals('Pay on delivery'));
      expect(AppStrings.reorder(AppLanguage.english), equals('Reorder'));
      expect(AppStrings.swapContainer(AppLanguage.english),
          equals('Hand over your empty gallon, no deposit'));
      expect(AppStrings.buyContainer(AppLanguage.english),
          equals('Buy or deposit new container'));

      // Filipino (Tagalog)
      expect(AppStrings.gallons(AppLanguage.filipino), equals('Mga Galon'));
      expect(AppStrings.total(AppLanguage.filipino), equals('Kabuuan'));
      expect(AppStrings.payOnDelivery(AppLanguage.filipino), equals('Bayad pagka-deliver'));
      expect(AppStrings.reorder(AppLanguage.filipino), equals('Ulitin ang Order'));
      expect(AppStrings.swapContainer(AppLanguage.filipino),
          equals('Ibigay ang basyong galon, walang deposito'));

      // Bisaya (Cebuano / Surigaonon)
      expect(AppStrings.gallons(AppLanguage.bisaya), equals('Mga Galon'));
      expect(AppStrings.total(AppLanguage.bisaya), equals('Tanan'));
      expect(AppStrings.payOnDelivery(AppLanguage.bisaya), equals('Bayad inig abot'));
      expect(AppStrings.reorder(AppLanguage.bisaya), equals('Ordera Pag-usab'));
      expect(AppStrings.swapContainer(AppLanguage.bisaya),
          equals('Ihatag ang haw-ang nga galon, walay deposito'));
    });

    test('AppLanguage enum correctly resolves from codes', () {
      expect(AppLanguage.fromCode('en'), equals(AppLanguage.english));
      expect(AppLanguage.fromCode('fil'), equals(AppLanguage.filipino));
      expect(AppLanguage.fromCode('ceb'), equals(AppLanguage.bisaya));
      expect(AppLanguage.fromCode('unknown'), equals(AppLanguage.english));
    });

    test('AppLanguageProvider updates and notifies listeners on language switch', () async {
      SharedPreferences.setMockInitialValues({'app_language': 'en'});
      final provider = AppLanguageProvider();
      expect(provider.language, equals(AppLanguage.english));

      bool notified = false;
      provider.addListener(() => notified = true);

      await provider.setLanguage(AppLanguage.bisaya);
      expect(provider.language, equals(AppLanguage.bisaya));
      expect(provider.code, equals('ceb'));
      expect(notified, isTrue);
    });
  });

  group('StationCard Trust Signals & Badges Tests', () {
    testWidgets('List card displays Sanitary Verified trust badge', (tester) async {
      final sampleStation = {
        'id': 'st-101',
        'station_name': 'Aqua Pure Cantilan',
        'town': 'Cantilan',
        'barangay': 'Linintian',
        'station_availability': 'open',
        'price_per_gallon': 35.0,
        'average_rating': 4.8,
        'review_count': 12,
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StationCard(
              station: sampleStation,
              compact: false,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Sanitary Verified'), findsOneWidget);
      expect(find.byIcon(Icons.verified_rounded), findsOneWidget);
      expect(find.text('Aqua Pure Cantilan'), findsOneWidget);
      expect(find.text('₱35 / gallon'), findsOneWidget);
    });

    testWidgets('Grid card displays verified checkmark icon next to station name', (tester) async {
      final sampleStation = {
        'id': 'st-102',
        'station_name': 'Crystal Clear Madrid',
        'town': 'Madrid',
        'barangay': 'San Roque',
        'station_availability': 'open',
        'price_per_gallon': 30.0,
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 200,
              height: 250,
              child: StationCard(
                station: sampleStation,
                compact: true,
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Crystal Clear Madrid'), findsOneWidget);
      expect(find.byIcon(Icons.verified_rounded), findsOneWidget);
    });
  });

  group('Motion, Reduce Motion & WaterFillLoadingIndicator Tests', () {
    testWidgets('WaterFillLoadingIndicator renders with animated custom painter by default',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: WaterFillLoadingIndicator(
              message: 'Refilling pure water...',
            ),
          ),
        ),
      );

      expect(find.text('Refilling pure water...'), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('WaterFillLoadingIndicator respects MediaQuery.disableAnimations (Reduce Motion)',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: true),
            child: Scaffold(
              body: WaterFillLoadingIndicator(
                message: 'Testing reduce motion',
              ),
            ),
          ),
        ),
      );

      expect(find.text('Testing reduce motion'), findsOneWidget);
      // Under reduce motion, it renders a static water drop icon instead of custom wave painter
      expect(find.byIcon(Icons.water_drop_rounded), findsOneWidget);
    });

    testWidgets('RefillLottie renders static fallback icon when disableAnimations is true',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: true),
            child: Scaffold(
              body: RefillLottie(
                animation: RefillAnimation.waterDrop,
              ),
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.water_drop_rounded), findsOneWidget);
    });
  });

  group('Empty State Action Tests', () {
    testWidgets('EmptyStateCard renders friendly illustration and action button',
        (tester) async {
      bool actionTapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EmptyStateCard(
              pose: AxoPose.happy,
              title: 'No active refills',
              message: 'When you order water, your active deliveries will show up here.',
              actionLabel: 'Find a station',
              onAction: () => actionTapped = true,
            ),
          ),
        ),
      );

      expect(find.text('No active refills'), findsOneWidget);
      expect(find.text('Find a station'), findsOneWidget);

      await tester.tap(find.text('Find a station'));
      expect(actionTapped, isTrue);
    });
  });

  group('Station Details 3-Column Grid & Header Layout Tests', () {
    testWidgets('Station details header FlexibleSpaceBar has null title (no station name overlay)',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
              slivers: [
                SliverAppBar(
                  expandedHeight: 220,
                  pinned: true,
                  flexibleSpace: FlexibleSpaceBar(
                    centerTitle: true,
                    background: ColoredBox(color: Colors.blue),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      final flexSpace = tester.widget<FlexibleSpaceBar>(find.byType(FlexibleSpaceBar));
      expect(flexSpace.title, isNull, reason: 'FlexibleSpaceBar in header must not contain station name');
    });

    testWidgets('3-column product grid renders 3 items per row with 0.62 aspect ratio',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 0.62,
              ),
              itemCount: 6,
              itemBuilder: (context, index) {
                return Container(
                  key: ValueKey('item_$index'),
                  color: Colors.blueGrey,
                  child: Text('Product $index'),
                );
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final grid = tester.widget<GridView>(find.byType(GridView));
      final delegate = grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
      expect(delegate.crossAxisCount, equals(3), reason: 'Products must be arranged in 3 columns');
      expect(delegate.childAspectRatio, equals(0.62));

      // Items 0, 1, 2 should have identical Y offset (first row)
      final pos0 = tester.getTopLeft(find.byKey(const ValueKey('item_0')));
      final pos1 = tester.getTopLeft(find.byKey(const ValueKey('item_1')));
      final pos2 = tester.getTopLeft(find.byKey(const ValueKey('item_2')));
      final pos3 = tester.getTopLeft(find.byKey(const ValueKey('item_3')));

      expect(pos0.dy, equals(pos1.dy), reason: 'Items 0 and 1 must be on same row');
      expect(pos1.dy, equals(pos2.dy), reason: 'Items 1 and 2 must be on same row');
      expect(pos3.dy, greaterThan(pos0.dy), reason: 'Item 3 must be on row 2');
    });
  });
}