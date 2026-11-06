import 'package:erefill/core/models/cart_model.dart';
import 'package:erefill/features/assistant/order_assistant.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _proposal = {
  'station_id': 's1',
  'station_name': 'AquaPure',
  'items': [
    {'product_id': 'w1', 'name': 'Purified', 'kind': 'water', 'price': 25, 'quantity': 3},
    {'product_id': 'c1', 'name': 'Cap', 'kind': 'accessory', 'price': 5, 'quantity': 1},
  ],
  'subtotal': 80,
  'delivery_fee': 0,
  'delivery_label': 'Free delivery',
  'delivery_note': 'tomorrow morning',
};

class _Svc implements AssistantService {
  final sent = <List<AssistantMessage>>[];
  @override
  Future<AssistantReply> send(List<AssistantMessage> history) async {
    sent.add(List.of(history));
    return AssistantReply(
      text: 'Here is your usual from AquaPure.',
      proposal: AssistantProposal.fromJson(_proposal),
      remaining: 19,
    );
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('proposal parses and fills the cart for its station', () {
    final p = AssistantProposal.fromJson(_proposal);
    expect(p.gallons, 3);
    final cart = CartProvider()..addItem('old', 'Old', 1);
    p.applyTo(cart);
    expect(cart.stationId, 's1');
    expect(cart.items.keys, unorderedEquals(['w1', 'c1']));
    expect(cart.items['w1']!.quantity, 3);
    expect(cart.items['c1']!.kind, 'accessory');
  });

  testWidgets('chat sends history and shows a reviewable cart', (tester) async {
    final svc = _Svc();
    String? checkedOut;
    await tester.pumpWidget(ChangeNotifierProvider(
      create: (_) => CartProvider(),
      child: MaterialApp(
        home: Scaffold(
          body: AskErefillSheet(
            service: svc,
            onCheckout: (stationId) => checkedOut = stationId,
          ),
        ),
      ),
    ));

    await tester.enterText(find.byType(TextField), '3 gallons sa suki ko bukas');
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();

    expect(svc.sent.single.single.text, '3 gallons sa suki ko bukas');
    expect(find.text('Here is your usual from AquaPure.'), findsOneWidget);
    expect(find.text('AquaPure'), findsOneWidget);
    expect(find.textContaining('3 × Purified'), findsOneWidget);
    expect(find.text('Free delivery'), findsOneWidget);

    await tester.tap(find.text('Review & checkout'));
    await tester.pumpAndSettle();
    expect(checkedOut, 's1');
  });
}
