import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as shadcn;
import 'package:erefill/core/constants.dart';
import 'package:erefill/core/theme/app_theme.dart';
import 'package:erefill/core/widgets/shadcn_widgets.dart';
import 'package:erefill/core/widgets/map_tiles.dart';

Widget _buildTestApp(Widget child) {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    localizationsDelegates: const [
      shadcn.ShadcnLocalizations.delegate,
    ],
    builder: (context, child) => shadcn.ShadcnLayer(
      theme: const shadcn.ThemeData(
        colorScheme: shadcn.ColorSchemes.lightZinc,
        radius: 0.5,
      ),
      child: child,
    ),
    home: Scaffold(
      body: child,
    ),
  );
}

void main() {
  group('Shadcn UI Integration Tests', () {
    testWidgets('ShadcnPrimaryButton renders and responds to tap', (tester) async {
      var tapped = false;

      await tester.pumpWidget(
        _buildTestApp(
          ShadcnPrimaryButton(
            text: 'Confirm Order',
            onPressed: () => tapped = true,
          ),
        ),
      );

      expect(find.text('Confirm Order'), findsOneWidget);
      await tester.tap(find.text('Confirm Order'));
      await tester.pump();
      expect(tapped, isTrue);
    });

    testWidgets('ShadcnDestructiveButton renders delete action text', (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          const ShadcnDestructiveButton(
            text: 'Delete Account',
          ),
        ),
      );

      expect(find.text('Delete Account'), findsOneWidget);
    });

    testWidgets('ShadcnCard renders with flat border container', (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          const ShadcnCard(
            child: Text('Card Content'),
          ),
        ),
      );

      expect(find.text('Card Content'), findsOneWidget);
    });

    testWidgets('ShadcnBadge renders variant states', (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          const Column(
            children: [
              ShadcnBadge(label: 'Verified', variant: ShadcnBadgeVariant.success),
              ShadcnBadge(label: 'Busy', variant: ShadcnBadgeVariant.warning),
            ],
          ),
        ),
      );

      expect(find.text('Verified'), findsOneWidget);
      expect(find.text('Busy'), findsOneWidget);
    });

    test('AppUi tokens conform to Shadcn design system', () {
      expect(AppUi.radiusControl, 8.0);
      expect(AppUi.radiusCard, 12.0);
      expect(AppUi.cardElevation, 0.0);
      expect(AppUi.borderLight, const Color(0xFFF1F4F5));
      expect(AppUi.borderDark, const Color(0xFF243237));
    });

    testWidgets('NavigationBar with NavigationDestination resolves MaterialLocalizations successfully', (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          NavigationBar(
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home),
                label: 'Home',
              ),
              NavigationDestination(
                icon: Icon(Icons.person),
                label: 'Profile',
              ),
            ],
          ),
        ),
      );

      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Profile'), findsOneWidget);
    });

    testWidgets('ShadcnOutlineButton renders with icon and text in tight width without RenderFlex overflow', (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          const Center(
            child: SizedBox(
              width: 69,
              height: 38,
              child: ShadcnOutlineButton(
                icon: Icons.store,
                text: 'Station Fleet',
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Station Fleet'), findsOneWidget);
    });

    test('AppMapTiles defaults to satellite mode across app and admin', () {
      expect(AppMapTiles.defaultStyle, AppMapStyle.satelliteHybrid);
      final tileLayer = AppMapTiles.layer();
      expect(tileLayer.urlTemplate?.contains('lyrs=y'), isTrue);
      expect(tileLayer.maxZoom, 20);
      expect(tileLayer.maxNativeZoom, 19);
    });
  });
}

