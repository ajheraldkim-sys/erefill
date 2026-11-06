import 'package:erefill/core/widgets/motion/motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget child, {bool reduceMotion = false}) => MediaQuery(
  data: MediaQueryData(disableAnimations: reduceMotion),
  child: MaterialApp(home: Scaffold(body: Center(child: child))),
);

double _opacityOf(WidgetTester tester) => tester
    .widget<Opacity>(
      find.ancestor(of: find.text('Hello'), matching: find.byType(Opacity)),
    )
    .opacity;

void main() {
  testWidgets('Reveal waits for its delay, then fades in', (tester) async {
    await tester.pumpWidget(
      _app(
        const Reveal(
          delay: Duration(milliseconds: 100),
          child: Text('Hello'),
        ),
      ),
    );
    expect(_opacityOf(tester), 0);

    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    expect(_opacityOf(tester), 1);
  });

  testWidgets('Reveal shows content at once with reduced motion', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const Reveal(delay: Duration(seconds: 1), child: Text('Hello')),
        reduceMotion: true,
      ),
    );
    expect(_opacityOf(tester), 1);
  });

  testWidgets('TapScale shrinks while pressed and restores on release', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        TapScale(
          child: ElevatedButton(onPressed: () {}, child: const Text('Hello')),
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Hello')),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 0.97);

    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);
  });
}
