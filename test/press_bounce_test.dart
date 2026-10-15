import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:erefill/core/widgets/press_bounce.dart';

void main() {
  testWidgets('PressBounce renders child widget and responds to tap', (tester) async {
    bool tapped = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PressBounce(
            onTap: () {
              tapped = true;
            },
            child: const Text('Bounce Me'),
          ),
        ),
      ),
    );

    expect(find.text('Bounce Me'), findsOneWidget);

    // Tap and verify tap trigger
    await tester.tap(find.text('Bounce Me'));
    await tester.pumpAndSettle();

    expect(tapped, isTrue);
  });

  testWidgets('PressBounce scales down on tap down and springs back', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: PressBounce(
              pressedScale: 0.95,
              onTap: () {},
              child: Container(
                key: const Key('target'),
                color: Colors.blue,
                width: 100,
                height: 100,
              ),
            ),
          ),
        ),
      ),
    );

    // Initial scale is 1.0
    final scaleFinder = find.descendant(
      of: find.byType(PressBounce),
      matching: find.byType(ScaleTransition),
    );
    expect(scaleFinder, findsOneWidget);
    final ScaleTransition scaleWidgetInitial = tester.widget(scaleFinder);
    expect(scaleWidgetInitial.scale.value, equals(1.0));

    // Pointer down (start press)
    final gesture = await tester.startGesture(tester.getCenter(find.byKey(const Key('target'))));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));

    // Should scale down toward 0.95
    final ScaleTransition scaleWidgetPressed = tester.widget(scaleFinder);
    expect(scaleWidgetPressed.scale.value, lessThan(1.0));

    // Pointer up (release press)
    await gesture.up();
    await tester.pumpAndSettle();

    // Scale returns to 1.0
    final ScaleTransition scaleWidgetReleased = tester.widget(scaleFinder);
    expect(scaleWidgetReleased.scale.value, equals(1.0));
  });
}
