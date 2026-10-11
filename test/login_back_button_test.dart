import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:erefill/core/widgets/auth/minimal_login_panel.dart';
import 'package:erefill/features/auth/screens/auth_entry_screen.dart';

void main() {
  group('Login screen back button to onboarding tests', () {
    testWidgets('MinimalLoginPanel renders back button pill when showBackButton is true', (tester) async {
      bool backTapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MinimalLoginPanel(
              showBackButton: true,
              backButtonLabel: 'Onboarding',
              onBack: () => backTapped = true,
            ),
          ),
        ),
      );

      // Verify the back button is visible with "Onboarding" text and arrow icon
      expect(find.text('Onboarding'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_back_ios_new_rounded), findsOneWidget);

      // Tap the back button
      await tester.tap(find.text('Onboarding'));
      await tester.pump();

      expect(backTapped, isTrue);
    });

    testWidgets('MinimalLoginPanel hides back button when showBackButton is false', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: MinimalLoginPanel(
              showBackButton: false,
            ),
          ),
        ),
      );

      expect(find.text('Onboarding'), findsNothing);
      expect(find.byIcon(Icons.arrow_back_ios_new_rounded), findsNothing);
    });

    testWidgets('AuthEntryScreen includes back button to onboarding', (tester) async {
      bool wentBackToOnboarding = false;

      await tester.pumpWidget(
        MaterialApp(
          home: AuthEntryScreen(
            onBackToOnboarding: () => wentBackToOnboarding = true,
          ),
        ),
      );

      // Verify the back button appears
      expect(find.text('Onboarding'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_back_ios_new_rounded), findsOneWidget);

      // Tap back button to go back to onboarding
      await tester.tap(find.text('Onboarding'));
      await tester.pump();

      expect(wentBackToOnboarding, isTrue);
    });
  });
}

