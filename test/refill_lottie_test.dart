import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:erefill/core/widgets/brand/refill_lottie.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('RefillLottie Widget Tests', () {
    testWidgets('renders RefillLottie.mascot successfully', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: RefillLottie.mascot(width: 80, height: 80),
          ),
        ),
      );
      expect(find.byType(RefillLottie), findsOneWidget);
    });

    testWidgets('renders RefillLottie.success successfully', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: RefillLottie.success(width: 100, height: 100),
          ),
        ),
      );
      expect(find.byType(RefillLottie), findsOneWidget);
    });

    testWidgets('renders RefillLottie.waterDrop successfully', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: RefillLottie.waterDrop(width: 60, height: 60),
          ),
        ),
      );
      expect(find.byType(RefillLottie), findsOneWidget);
    });

    testWidgets('renders RefillLottie.rider successfully', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: RefillLottie.rider(width: 100, height: 80),
          ),
        ),
      );
      expect(find.byType(RefillLottie), findsOneWidget);
    });

    testWidgets('RefillAnimation tracks removed motion assets as static placeholders', (tester) async {
      expect(RefillAnimation.values.length, 4);
      expect(RefillAnimation.axoBob.assetPath, isEmpty);
      expect(RefillAnimation.orderSuccess.assetPath, isEmpty);
      expect(RefillAnimation.waterDrop.assetPath, isEmpty);
      expect(RefillAnimation.deliveryRider.assetPath, isEmpty);
    });
  });
}

