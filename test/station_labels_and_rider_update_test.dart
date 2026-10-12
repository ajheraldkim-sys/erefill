import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:erefill/core/widgets/account/account_ui.dart';

void main() {
  group('Station Category Labels and Rider Updates Tests', () {
    testWidgets('AccountSectionLabel aligns right when textAlign is TextAlign.right',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                AccountSectionLabel(
                  'Station identity',
                  textAlign: TextAlign.right,
                ),
                AccountSectionLabel(
                  'Pricing & delivery',
                  textAlign: TextAlign.right,
                ),
                AccountSectionLabel(
                  'Catalog & operations',
                  textAlign: TextAlign.right,
                ),
                AccountSectionLabel(
                  'Preferences',
                  textAlign: TextAlign.right,
                ),
                AccountSectionLabel(
                  'Security & account',
                  textAlign: TextAlign.right,
                ),
              ],
            ),
          ),
        ),
      );

      final labelFinder = find.text('STATION IDENTITY');
      expect(labelFinder, findsOneWidget);

      final textWidget = tester.widget<Text>(labelFinder);
      expect(textWidget.textAlign, TextAlign.right);

      final containerFinder = find.ancestor(
        of: labelFinder,
        matching: find.byType(Container),
      );
      expect(containerFinder, findsWidgets);

      final container = tester.widget<Container>(containerFinder.first);
      expect(container.alignment, Alignment.centerRight);
    });

    test('Rider name composition handles name parts, suffix and MI correctly', () {
      final parts = ['Juan', 'R.', 'Dela Cruz', 'Jr.'];
      final composed = parts.where((s) => s.trim().isNotEmpty).join(' ').trim();
      expect(composed, 'Juan R. Dela Cruz Jr.');

      final partsNoMi = ['Maria', '', 'Santos', ''];
      final composedNoMi = partsNoMi.where((s) => s.trim().isNotEmpty).join(' ').trim();
      expect(composedNoMi, 'Maria Santos');
    });
  });
}

