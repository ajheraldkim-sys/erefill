import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:erefill/core/widgets/brand/erefill_logo.dart';
import 'package:erefill/features/onboarding/screens/welcome_onboarding_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('WelcomeOnboardingScreen human-grade UX tests', () {
    testWidgets('renders official ERefillLogo, local badge, and value chips', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: WelcomeOnboardingScreen(onFinish: () {}),
        ),
      );

      // Verify official ERefill logo lockup
      expect(find.byType(ERefillLogo), findsOneWidget);

      // Verify localized municipality badge
      expect(find.text('Cantilan & Madrid, Surigao del Sur'), findsOneWidget);

      // Verify domain-specific headline and body
      expect(find.text('Clean Water,\nRight to Your Door'), findsOneWidget);
      expect(
        find.text(
          'Order refills from certified stations with live delivery tracking and convenient gallon swaps.',
        ),
        findsOneWidget,
      );

      // Verify feature chips
      expect(find.text('Certified Stations'), findsOneWidget);
      expect(find.text('Local Delivery Riders'), findsOneWidget);
      expect(find.text('Gallon Swaps'), findsOneWidget);

      // Verify skip button and dual-interaction CTA
      expect(find.text('Skip'), findsOneWidget);
      expect(find.text('Swipe or Tap to Start'), findsOneWidget);
    });

    testWidgets('tapping Skip saves preferences and invokes onFinish', (tester) async {
      bool finished = false;

      await tester.pumpWidget(
        MaterialApp(
          home: WelcomeOnboardingScreen(onFinish: () => finished = true),
        ),
      );

      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();

      expect(finished, isTrue);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('onboarding_complete'), isTrue);
    });

    testWidgets('tapping slider button directly triggers onFinish (accessible fallback)', (tester) async {
      bool finished = false;

      await tester.pumpWidget(
        MaterialApp(
          home: WelcomeOnboardingScreen(onFinish: () => finished = true),
        ),
      );

      // Tap anywhere on the slider CTA
      await tester.tap(find.text('Swipe or Tap to Start'));
      await tester.pumpAndSettle();

      expect(finished, isTrue);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('onboarding_complete'), isTrue);
    });

    testWidgets('dragging slider thumb across threshold triggers onFinish', (tester) async {
      bool finished = false;

      await tester.pumpWidget(
        MaterialApp(
          home: WelcomeOnboardingScreen(onFinish: () => finished = true),
        ),
      );

      final thumb = find.byIcon(Icons.arrow_forward_rounded);
      expect(thumb, findsOneWidget);

      // Drag thumb across threshold to the right
      await tester.drag(thumb, const Offset(550.0, 0.0));
      await tester.pumpAndSettle();

      expect(finished, isTrue);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('onboarding_complete'), isTrue);
    });
  });
}
