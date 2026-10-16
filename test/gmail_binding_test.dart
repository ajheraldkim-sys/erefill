import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:erefill/features/auth/widgets/gmail_binding_card.dart';

void main() {
  group('Gmail Binding & Verification Tests', () {
    testWidgets('GmailBindingCard renders properly in test environment', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: GmailBindingCard()),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Should render the title, input field and action button
      expect(find.text('Verify your email'), findsOneWidget);
      expect(find.text('Send 6-Digit Code'), findsOneWidget);
      expect(find.byType(TextFormField), findsOneWidget);
    });

    testWidgets('GmailBindingCard requires a Gmail address', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: GmailBindingCard()),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Tap Send 6-Digit Code without entering email
      await tester.tap(find.text('Send 6-Digit Code'));
      await tester.pumpAndSettle();

      // Form validation error should appear
      expect(find.text('Enter your Gmail address.'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField), 'invalid-email');
      await tester.tap(find.text('Send 6-Digit Code'));
      await tester.pumpAndSettle();

      expect(find.text('Enter a valid Gmail address.'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField), 'person@example.com');
      await tester.tap(find.text('Send 6-Digit Code'));
      await tester.pumpAndSettle();

      expect(find.text('Enter a valid Gmail address.'), findsOneWidget);
    });
  });
}
