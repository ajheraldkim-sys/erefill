import 'package:erefill/core/widgets/live_order_progress_tracker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(String status, {bool reduceMotion = false}) => MediaQuery(
  data: MediaQueryData(disableAnimations: reduceMotion),
  child: MaterialApp(
    home: Scaffold(
      body: LiveOrderProgressTracker(
        status: status,
        stationName: 'Aqua Pure',
        riderName: 'Ana',
      ),
    ),
  ),
);

void main() {
  testWidgets('marks done, current, and upcoming steps', (tester) async {
    await tester.pumpWidget(_app('preparing'));

    expect(find.bySemanticsLabel('Accepted: done'), findsOneWidget);
    expect(find.bySemanticsLabel('Preparing: current'), findsOneWidget);
    expect(find.bySemanticsLabel('Delivered: upcoming'), findsOneWidget);
    expect(tester.hasRunningAnimations, isTrue, reason: 'current step pulses');
  });

  testWidgets('stops pulsing once delivered', (tester) async {
    await tester.pumpWidget(_app('preparing'));
    await tester.pumpWidget(_app('delivered'));
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('Delivered: current'), findsOneWidget);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('never pulses with reduced motion', (tester) async {
    await tester.pumpWidget(_app('out_for_delivery', reduceMotion: true));
    await tester.pump();

    expect(tester.hasRunningAnimations, isFalse);
    expect(find.text('Ana'), findsOneWidget);
  });
}
