import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as shadcn;
import 'package:erefill/core/theme/app_theme.dart';
import 'package:erefill/models/cart_model.dart';
import 'package:erefill/core/widgets/shadcn_widgets.dart';
import 'package:erefill/features/dashboard/customer/cart_screen.dart';

Widget _buildTestApp(Widget child) {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    localizationsDelegates: const [
      shadcn.ShadcnLocalizations.delegate,
    ],
    builder: (context, child) => shadcn.ShadcnLayer(
      theme: const shadcn.ThemeData(
        colorScheme: shadcn.ColorSchemes.lightZinc,
        radius: 0.5,
      ),
      child: child,
    ),
    home: Scaffold(
      body: child,
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Button Component Tests', () {
    testWidgets('ShadcnPrimaryButton responds to tap and displays loading state',
        (tester) async {
      bool tapped = false;

      await tester.pumpWidget(
        _buildTestApp(
          Center(
            child: ShadcnPrimaryButton(
              text: 'Click Me',
              onPressed: () => tapped = true,
            ),
          ),
        ),
      );

      expect(find.text('Click Me'), findsOneWidget);
      await tester.tap(find.text('Click Me'));
      await tester.pump(const Duration(milliseconds: 50));
      expect(tapped, isTrue);

      // Loading state test: text should be replaced with spinner
      await tester.pumpWidget(
        _buildTestApp(
          Center(
            child: ShadcnPrimaryButton(
              text: 'Click Me',
              isLoading: true,
              onPressed: () => tapped = true,
            ),
          ),
        ),
      );

      expect(find.text('Click Me'), findsNothing);
    });

    testWidgets('ShadcnOutlineButton responds to tap and respects disabled state',
        (tester) async {
      bool tapped = false;

      await tester.pumpWidget(
        _buildTestApp(
          Center(
            child: ShadcnOutlineButton(
              text: 'Outline Action',
              onPressed: () => tapped = true,
            ),
          ),
        ),
      );

      expect(find.text('Outline Action'), findsOneWidget);
      await tester.tap(find.text('Outline Action'));
      await tester.pump(const Duration(milliseconds: 50));
      expect(tapped, isTrue);

      // Disabled state
      tapped = false;
      await tester.pumpWidget(
        _buildTestApp(
          const Center(
            child: ShadcnOutlineButton(
              text: 'Disabled Action',
              enabled: false,
              onPressed: null,
            ),
          ),
        ),
      );

      await tester.tap(find.text('Disabled Action'));
      await tester.pump(const Duration(milliseconds: 50));
      expect(tapped, isFalse);
    });
  });

  group('CartScreen Buttons & Stepper Tests', () {
    testWidgets('CartScreen displays empty state when cart is empty', (tester) async {
      final cart = CartProvider();

      await tester.pumpWidget(
        ChangeNotifierProvider<CartProvider>.value(
          value: cart,
          child: _buildTestApp(
            const CartScreen(
              station: {'id': 'stn-1', 'station_name': 'Pure Water'},
            ),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Your cart is empty'), findsOneWidget);
      expect(find.text('Browse stations'), findsOneWidget);
    });

    testWidgets('CartScreen quantity steppers and clear cart buttons respond correctly',
        (tester) async {
      final cart = CartProvider();
      cart.setStation('stn-1', 'Pure Water Station');
      cart.addItem('item-1', '5-Gallon Purified Water', 35.0);
      cart.addItem('item-2', 'Non-Spill Cap', 5.0);

      await tester.pumpWidget(
        ChangeNotifierProvider<CartProvider>.value(
          value: cart,
          child: _buildTestApp(
            const CartScreen(
              station: {'id': 'stn-1', 'station_name': 'Pure Water Station'},
            ),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 100));

      // Verify cart items are displayed
      expect(find.text('5-Gallon Purified Water'), findsOneWidget);
      expect(find.text('Non-Spill Cap'), findsOneWidget);
      expect(find.text('Checkout'), findsOneWidget);
      expect(find.text('Add more'), findsOneWidget);

      // Test incrementing quantity using the + stepper
      final addButtons = find.byTooltip('Increase quantity');
      expect(addButtons, findsNWidgets(2));

      await tester.tap(addButtons.first);
      await tester.pump(const Duration(milliseconds: 50));
      expect(cart.items['item-1']?.quantity, 2);

      // Test decrementing quantity using the - stepper (only item-1 is > 1)
      final removeButtons = find.byTooltip('Decrease quantity');
      expect(removeButtons, findsOneWidget);

      await tester.tap(removeButtons.first);
      await tester.pump(const Duration(milliseconds: 50));
      expect(cart.items['item-1']?.quantity, 1);

      // At quantity 1 the minus becomes a remove action with undo
      await tester.tap(find.byTooltip('Remove Non-Spill Cap'));
      await tester.pump(const Duration(milliseconds: 50));
      expect(cart.items.containsKey('item-2'), isFalse);
      expect(find.text('Undo'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.text('Undo'));
      await tester.pump(const Duration(milliseconds: 50));
      expect(cart.items['item-2']?.quantity, 1);

      // Test Clear Cart button in header
      final clearCartIcon = find.byIcon(Icons.delete_sweep_outlined);
      expect(clearCartIcon, findsOneWidget);

      await tester.tap(clearCartIcon);
      await tester.pump(const Duration(milliseconds: 50));

      // Verify confirmation dialog appeared
      expect(find.text('Clear cart?'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);

      // Tap confirmation Clear Cart button
      final dialogClearBtn = find.widgetWithText(FilledButton, 'Clear cart');
      expect(dialogClearBtn, findsOneWidget);
      await tester.tap(dialogClearBtn);
      await tester.pump(const Duration(milliseconds: 100));

      // Verify cart is now completely empty
      expect(cart.items.isEmpty, isTrue);
      expect(find.text('Your cart is empty'), findsOneWidget);
    });
  });

  group('Owner Dashboard Quick Buttons Tests', () {
    testWidgets('Utang ledger button is properly configured with icon and label',
        (tester) async {
      bool utangTapped = false;

      await tester.pumpWidget(
        _buildTestApp(
          OutlinedButton.icon(
            onPressed: () => utangTapped = true,
            icon: const Icon(
              Icons.receipt_long_outlined,
              size: 18,
              color: Color(0xFFF59E0B),
            ),
            label: const Text('Customer Credits & Utang Ledger'),
          ),
        ),
      );

      expect(find.text('Customer Credits & Utang Ledger'), findsOneWidget);
      expect(find.byIcon(Icons.receipt_long_outlined), findsOneWidget);

      await tester.tap(find.text('Customer Credits & Utang Ledger'));
      await tester.pump(const Duration(milliseconds: 50));
      expect(utangTapped, isTrue);
    });
  });
}

