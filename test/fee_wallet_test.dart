import 'package:erefill/core/theme/app_theme.dart';
import 'package:erefill/features/fee_wallet/models/fee_wallet_models.dart';
import 'package:erefill/features/fee_wallet/widgets/fee_wallet_card.dart';
import 'package:erefill/features/fee_wallet/widgets/fee_wallet_topup_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _config = FeeWalletConfig(
  minTopup: 100,
  lowBalanceAlert: 100,
  codLockAtOrBelow: 0,
);

FeeWalletSummary _summary(double balance) =>
    FeeWalletSummary.fromBalance(balance: balance, config: _config);

Widget _host(Widget child) => MaterialApp(
  theme: AppTheme.lightTheme,
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void main() {
  group('FeeWalletStatus', () {
    test('derives from the balance and thresholds', () {
      expect(_summary(150).status, FeeWalletStatus.ok);
      expect(_summary(100).status, FeeWalletStatus.ok);
      expect(_summary(99).status, FeeWalletStatus.low);
      expect(_summary(0).status, FeeWalletStatus.codOff);
      expect(_summary(-3).status, FeeWalletStatus.codOff);
    });

    test('config falls back to the defaults', () {
      final cfg = FeeWalletConfig.fromJson(null);
      expect(cfg.minTopup, 100);
      expect(cfg.lowBalanceAlert, 100);
      expect(cfg.codLockAtOrBelow, 0);
    });
  });

  group('FeeWalletEntry labels', () {
    test('describe each kind', () {
      expect(
        FeeWalletEntry.fromJson({
          'amount': 100,
          'kind': 'topup',
          'created_at': '2026-10-22T00:00:00Z',
        }).label,
        'Top-up',
      );
      expect(
        FeeWalletEntry.fromJson({
          'amount': -1.4,
          'kind': 'service_fee',
          'order_id': 'abcdef12-0000-0000-0000-000000000000',
          'created_at': '2026-10-22T00:00:00Z',
        }).label,
        'Service fee · Order #ABCDEF12',
      );
      expect(
        FeeWalletEntry.fromJson({
          'amount': 20,
          'kind': 'adjustment',
          'note': 'Refund',
          'created_at': '2026-10-22T00:00:00Z',
        }).label,
        'Adjustment · Refund',
      );
    });
  });

  group('FeeWalletCard', () {
    testWidgets('shows the balance when OK', (tester) async {
      await tester.pumpWidget(
        _host(FeeWalletCard(summary: _summary(150), onTopUp: () {})),
      );
      expect(find.text('₱150'), findsOneWidget);
      expect(
        find.text(
          'Cash on Delivery is off — top up your service fee balance to turn it back on.',
        ),
        findsNothing,
      );
    });

    testWidgets('shows the COD-off banner at zero', (tester) async {
      await tester.pumpWidget(
        _host(FeeWalletCard(summary: _summary(0), onTopUp: () {})),
      );
      expect(
        find.text(
          'Cash on Delivery is off — top up your service fee balance to turn it back on.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('top up button calls back', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        _host(FeeWalletCard(summary: _summary(50), onTopUp: () => taps++)),
      );
      await tester.tap(find.text('Top up'));
      expect(taps, 1);
    });
  });

  group('FeeWalletTopupSheet', () {
    Future<List<(int, String)>> pumpSheet(WidgetTester tester) async {
      final submitted = <(int, String)>[];
      tester.view.physicalSize = const Size(1440, 3200);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _host(
          FeeWalletTopupSheet(
            config: _config,
            onSubmit: (amount, method) async => submitted.add((amount, method)),
          ),
        ),
      );
      return submitted;
    }

    testWidgets('offers the presets and the test-mode notice', (tester) async {
      await pumpSheet(tester);
      expect(find.text('₱100'), findsOneWidget);
      expect(find.text('₱300'), findsOneWidget);
      expect(find.text('₱500'), findsOneWidget);
      expect(find.text('Test mode — no real money'), findsOneWidget);
    });

    testWidgets('a preset submits its amount', (tester) async {
      final submitted = await pumpSheet(tester);
      await tester.tap(find.text('₱300'));
      await tester.pump();
      await tester.tap(find.text('Pay ₱300'));
      await tester.pump();
      expect(submitted, [(300, 'gcash')]);
    });

    testWidgets('a custom amount below the minimum cannot be paid', (
      tester,
    ) async {
      final submitted = await pumpSheet(tester);
      await tester.enterText(find.byType(TextField), '99');
      await tester.pump();
      expect(find.text('Minimum top-up is ₱100.'), findsOneWidget);
      final pay = tester.widget<ButtonStyleButton>(
        find.ancestor(
          of: find.textContaining('Pay'),
          matching: find.bySubtype<ButtonStyleButton>(),
        ),
      );
      expect(pay.onPressed, isNull);
      expect(submitted, isEmpty);
    });

    testWidgets('custom amounts accept digits only', (tester) async {
      await pumpSheet(tester);
      await tester.enterText(find.byType(TextField), '100.5');
      await tester.pump();
      expect(find.text('1005'), findsOneWidget);
    });
  });
}
