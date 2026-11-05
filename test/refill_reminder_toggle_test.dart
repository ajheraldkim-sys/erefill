import 'package:erefill/features/settings/customer/refill_reminder_toggle.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('loads the saved choice and saves changes', (tester) async {
    bool? saved;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RefillReminderToggle(
          load: () async => true,
          save: (v) async => saved = v,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value, isTrue);

    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(saved, isFalse);
    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value, isFalse);
  });

  testWidgets('reverts when saving fails', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RefillReminderToggle(
          load: () async => true,
          save: (v) async => throw Exception('offline'),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value, isTrue);
  });
}
