import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:erefill/core/widgets/animations/animated_counter.dart';
import 'package:erefill/core/widgets/animations/pulsing_dot.dart';
import 'package:erefill/core/widgets/animations/animated_favorite_button.dart';
import 'package:erefill/core/widgets/animations/staggered_entrance.dart';

void main() {
  group('AnimatedCounter Widget Tests', () {
    testWidgets('renders initial value and animates to target', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AnimatedCounter(
              value: 100,
              prefix: '₱',
              suffix: '+',
            ),
          ),
        ),
      );

      // Initially at 0
      expect(find.text('₱0+'), findsOneWidget);

      // Settle animation to target 100
      await tester.pumpAndSettle();
      expect(find.text('₱100+'), findsOneWidget);
    });
  });

  group('PulsingDot Widget Tests', () {
    testWidgets('renders breathing dot and ripple layers', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PulsingDot(
              color: Colors.green,
              size: 12,
            ),
          ),
        ),
      );

      expect(find.byType(PulsingDot), findsOneWidget);
      expect(find.byType(Stack), findsWidgets);
    });
  });

  group('AnimatedFavoriteButton Widget Tests', () {
    testWidgets('renders outline icon when inactive and filled icon when active', (tester) async {
      bool isFav = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return AnimatedFavoriteButton(
                  isFavorite: isFav,
                  onToggle: (val) {
                    setState(() {
                      isFav = val;
                    });
                  },
                );
              },
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);

      // Tap to toggle favorite
      await tester.tap(find.byType(AnimatedFavoriteButton));
      await tester.pumpAndSettle();

      expect(isFav, isTrue);
      expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
    });
  });

  group('StaggeredEntrance Widget Tests', () {
    testWidgets('fades and slides child into view', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: StaggeredEntrance(
              index: 0,
              child: Text('Card Content'),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('Card Content'), findsOneWidget);
    });
  });
}

