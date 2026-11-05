import 'package:erefill/features/dashboard/customer/widgets/refill_reminder_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('shows only when due and nothing is on the way', () {
    expect(RefillReminderBanner.shouldShow(null), isFalse);
    expect(RefillReminderBanner.shouldShow({'has_rhythm': false}), isFalse);
    expect(
      RefillReminderBanner.shouldShow(
          {'has_rhythm': true, 'is_due': true, 'has_active_order': true}),
      isFalse,
    );
    expect(
      RefillReminderBanner.shouldShow(
          {'has_rhythm': true, 'is_due': true, 'has_active_order': false}),
      isTrue,
    );
  });

  testWidgets('explains the rhythm and reorders on tap', (tester) async {
    var tapped = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RefillReminderBanner(
          rhythm: const {
            'has_rhythm': true,
            'is_due': true,
            'has_active_order': false,
            'median_days': 5.0,
            'station_name': 'AquaPure',
          },
          onReorder: () => tapped = true,
        ),
      ),
    ));
    expect(find.text('Time for a refill?'), findsOneWidget);
    expect(find.textContaining('every 5 days'), findsOneWidget);
    expect(find.textContaining('AquaPure'), findsOneWidget);
    await tester.tap(find.text('Reorder'));
    expect(tapped, isTrue);
  });
}
