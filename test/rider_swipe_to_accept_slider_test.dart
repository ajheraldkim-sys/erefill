import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:erefill/features/dashboard/rider/widgets/rider_swipe_to_accept_slider.dart';

void main() {
  testWidgets('RiderSwipeToAcceptSlider fits narrow 126px width without overflow', (tester) async {
    bool accepted = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 126.0,
              child: RiderSwipeToAcceptSlider(
                label: 'Slide to Accept Order',
                onAccepted: () => accepted = true,
              ),
            ),
          ),
        ),
      ),
    );

    // Verify it pumps without any RenderFlex overflow exceptions
    expect(tester.takeException(), isNull);
    expect(find.byType(RiderSwipeToAcceptSlider), findsOneWidget);

    // Drag to accept on narrow slider
    await tester.drag(find.byIcon(Icons.double_arrow_rounded), const Offset(70.0, 0.0));
    await tester.pumpAndSettle();
    expect(accepted, isTrue);
    expect(find.text('Accepted & Starting!'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('RiderSwipeToAcceptSlider slides to accept on standard widths', (tester) async {
    bool accepted = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320.0,
              child: RiderSwipeToAcceptSlider(
                label: 'Slide to Accept Order',
                onAccepted: () => accepted = true,
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Slide to Accept Order'), findsOneWidget);

    // Drag slider thumb across
    await tester.drag(find.byIcon(Icons.double_arrow_rounded), const Offset(280.0, 0.0));
    await tester.pumpAndSettle();

    expect(accepted, isTrue);
    expect(find.text('Accepted & Starting!'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
