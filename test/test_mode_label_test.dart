import 'package:erefill/features/dashboard/customer/widgets/test_mode_label.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('shows the test-mode notice', (tester) async {
    await tester.pumpWidget(host(const TestModeLabel(qrph: false)));
    expect(find.text('Test mode — no real money'), findsOneWidget);
    expect(find.text('Do not scan with a banking app.'), findsNothing);
  });

  testWidgets('warns not to scan a QR Ph test code', (tester) async {
    await tester.pumpWidget(host(const TestModeLabel(qrph: true)));
    expect(find.text('Test mode — no real money'), findsOneWidget);
    expect(find.text('Do not scan with a banking app.'), findsOneWidget);
  });
}
