import 'package:erefill/features/disputes/disputes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Repo implements DisputeRepository {
  Map<String, Object?>? opened;
  Map<String, Object?>? responded;
  List<Dispute> forOwner = [];

  @override
  Future<String> uploadEvidence(List<int> bytes, String ext) async => 'uid/e1.$ext';

  @override
  Future<void> open(String orderId, String reason, String description, List<String> evidence) async =>
      opened = {'order': orderId, 'reason': reason, 'desc': description, 'evidence': evidence};

  @override
  Future<List<Dispute>> ownerInbox() async => forOwner;

  @override
  Future<void> respond(String disputeId, {required bool accept, required String reply, double refund = 0}) async =>
      responded = {'id': disputeId, 'accept': accept, 'reply': reply, 'refund': refund};
}

void main() {
  final now = DateTime(2026, 11, 5, 12);

  test('can report within 48 hours of delivery only', () {
    expect(Dispute.canReport(status: 'delivered', deliveredAt: now.subtract(const Duration(hours: 47)), now: now), isTrue);
    expect(Dispute.canReport(status: 'delivered', deliveredAt: now.subtract(const Duration(hours: 49)), now: now), isFalse);
    expect(Dispute.canReport(status: 'out_for_delivery', deliveredAt: now, now: now), isFalse);
  });

  testWidgets('customer reports a problem with a photo', (tester) async {
    final repo = _Repo();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ReportProblemSheet(
          orderId: 'o1',
          repository: repo,
          pickPhoto: () async => ([1], 'jpeg'),
        ),
      ),
    ));
    await tester.tap(find.text('Missing items'));
    await tester.enterText(find.byType(TextField), 'Only 2 of 3 gallons');
    await tester.tap(find.text('Add photo'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Send report'));
    await tester.tap(find.text('Send report'));
    await tester.pumpAndSettle();
    expect(repo.opened, {
      'order': 'o1',
      'reason': 'missing_items',
      'desc': 'Only 2 of 3 gallons',
      'evidence': ['uid/e1.jpeg'],
    });
  });

  testWidgets('report needs a description', (tester) async {
    final repo = _Repo();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: ReportProblemSheet(orderId: 'o1', repository: repo)),
    ));
    await tester.ensureVisible(find.text('Send report'));
    await tester.tap(find.text('Send report'));
    await tester.pumpAndSettle();
    expect(repo.opened, isNull);
    expect(find.text('Tell the station what went wrong.'), findsOneWidget);
  });

  testWidgets('owner refunds from the inbox', (tester) async {
    final repo = _Repo()
      ..forOwner = [
        Dispute(
          id: 'd1',
          orderId: 'o1',
          reason: 'missing_items',
          description: 'Only 2 of 3 gallons',
          status: 'open',
          createdAt: now,
          orderTotal: 75,
        ),
      ];
    await tester.pumpWidget(MaterialApp(home: OwnerDisputesScreen(repository: repo)));
    await tester.pumpAndSettle();
    expect(find.textContaining('Only 2 of 3 gallons'), findsOneWidget);

    await tester.tap(find.text('Respond'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('dispute-reply')), 'Sorry! Refunding one gallon.');
    await tester.enterText(find.byKey(const Key('dispute-refund')), '25');
    await tester.tap(find.text('Refund'));
    await tester.pumpAndSettle();
    expect(repo.responded, {'id': 'd1', 'accept': true, 'reply': 'Sorry! Refunding one gallon.', 'refund': 25.0});
  });
}
