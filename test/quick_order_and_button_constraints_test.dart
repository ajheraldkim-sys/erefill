import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:erefill/core/theme/app_theme.dart';

void main() {
  group('Theme Constraints and Button Tests', () {
    testWidgets('ElevatedButton in Row does not throw infinite width assertion with light theme',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: Row(
              children: [
                const Text('Label'),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () {},
                  child: const Text('Action'),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.share),
                  label: const Text('Share'),
                ),
              ],
            ),
          ),
        ),
      );

      // Verify buttons render successfully without layout exceptions
      expect(find.text('Action'), findsOneWidget);
      expect(find.text('Share'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Loyalty rewards sheet widgets render buttons in rows without unbounded constraints',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  Row(
                    children: [
                      const Expanded(child: TextField()),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () {},
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(0, 42),
                        ),
                        child: const Text('Redeem Code'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Expanded(child: Text('Reward Name')),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () {},
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(0, 36),
                        ),
                        child: const Text('Claim'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      expect(find.text('Redeem Code'), findsOneWidget);
      expect(find.text('Claim'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
