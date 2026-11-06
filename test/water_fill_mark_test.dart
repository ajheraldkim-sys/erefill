import 'package:erefill/core/widgets/brand/water_fill_mark.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('animates the fill and stops cleanly when removed', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Center(child: WaterFillMark())),
    );
    expect(find.bySemanticsLabel('Loading'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 700));
    expect(tester.hasRunningAnimations, isTrue);

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('renders a still, full drop with reduced motion', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: MaterialApp(home: Center(child: WaterFillMark())),
      ),
    );
    await tester.pump();
    expect(tester.hasRunningAnimations, isFalse);
  });
}
