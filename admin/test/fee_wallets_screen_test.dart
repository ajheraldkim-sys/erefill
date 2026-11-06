import 'package:erefill_admin/features/fees/fee_wallets_screen.dart';
import 'package:erefill_admin/services/admin_api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _rows = [
  FeeWalletRow.fromJson({
    'owner_id': 'o1',
    'station_name': 'Aqua One',
    'balance': 0,
    'cod_locked': true,
    'fees_collected': 12.5,
    'topups_received': 100,
  }),
  FeeWalletRow.fromJson({
    'owner_id': 'o2',
    'station_name': 'Blue Spring',
    'balance': 250,
    'cod_locked': false,
    'fees_collected': 3,
    'topups_received': 300,
  }),
];

Future<void> _pump(
  WidgetTester tester, {
  Future<double> Function(String ownerId, double amount, String reason)? adjust,
}) async {
  tester.view.physicalSize = const Size(2400, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: FeeWalletsScreen(
          loadWallets: () async => _rows,
          adjustWallet: adjust ?? (_, _, _) async => 0,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('lists every station wallet with its COD state', (tester) async {
    await _pump(tester);
    expect(find.text('Aqua One'), findsOneWidget);
    expect(find.text('Blue Spring'), findsOneWidget);
    expect(find.text('₱250'), findsOneWidget);
    expect(find.text('COD off'), findsOneWidget);
    expect(
      find.text('Payouts of online sales to stations are not automated yet.'),
      findsOneWidget,
    );
  });

  testWidgets('totals fees collected across stations', (tester) async {
    await _pump(tester);
    expect(find.text('₱15.50'), findsOneWidget);
  });

  testWidgets('an adjustment needs a reason', (tester) async {
    final calls = <(String, double, String)>[];
    await _pump(
      tester,
      adjust: (id, amount, reason) async {
        calls.add((id, amount, reason));
        return amount;
      },
    );
    await tester.tap(find.text('Adjust').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Amount (₱)'), '50');
    await tester.tap(find.text('Save adjustment'));
    await tester.pumpAndSettle();
    expect(find.text('A reason is required.'), findsOneWidget);
    expect(calls, isEmpty);

    await tester.enterText(find.widgetWithText(TextField, 'Reason'), 'Demo credit');
    await tester.tap(find.text('Save adjustment'));
    await tester.pumpAndSettle();
    expect(calls, [('o1', 50.0, 'Demo credit')]);
  });
}
