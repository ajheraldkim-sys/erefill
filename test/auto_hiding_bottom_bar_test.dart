import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:erefill/core/widgets/auto_hiding_bottom_bar.dart';

void main() {
  group('AutoHidingBottomBar widget', () {
    testWidgets('renders visible state with full opacity and interactive pointer', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomNavigationBar: AutoHidingBottomBar(
              isVisible: true,
              child: Container(
                key: const ValueKey('nav_bar'),
                height: 60,
                color: Colors.blue,
                child: const Text('Nav Bar Content'),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Nav Bar Content'), findsOneWidget);

      final barFinder = find.byType(AutoHidingBottomBar);

      final animatedSlide = tester.widget<AnimatedSlide>(
        find.descendant(of: barFinder, matching: find.byType(AnimatedSlide)),
      );
      expect(animatedSlide.offset, Offset.zero);

      final animatedOpacity = tester.widget<AnimatedOpacity>(
        find.descendant(of: barFinder, matching: find.byType(AnimatedOpacity)),
      );
      expect(animatedOpacity.opacity, 1.0);

      final ignorePointer = tester.widget<IgnorePointer>(
        find.descendant(of: barFinder, matching: find.byType(IgnorePointer)),
      );
      expect(ignorePointer.ignoring, isFalse);

      final excludeFocus = tester.widget<ExcludeFocus>(
        find.descendant(of: barFinder, matching: find.byType(ExcludeFocus)),
      );
      expect(excludeFocus.excluding, isFalse);
    });

    testWidgets('renders hidden state with slide offset, opacity 0, and disabled pointer', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomNavigationBar: AutoHidingBottomBar(
              isVisible: false,
              child: Container(
                key: const ValueKey('nav_bar'),
                height: 60,
                color: Colors.blue,
                child: const Text('Nav Bar Content'),
              ),
            ),
          ),
        ),
      );

      final barFinder = find.byType(AutoHidingBottomBar);

      final animatedSlide = tester.widget<AnimatedSlide>(
        find.descendant(of: barFinder, matching: find.byType(AnimatedSlide)),
      );
      expect(animatedSlide.offset, const Offset(0, 1.4));

      final animatedOpacity = tester.widget<AnimatedOpacity>(
        find.descendant(of: barFinder, matching: find.byType(AnimatedOpacity)),
      );
      expect(animatedOpacity.opacity, 0.0);

      final ignorePointer = tester.widget<IgnorePointer>(
        find.descendant(of: barFinder, matching: find.byType(IgnorePointer)),
      );
      expect(ignorePointer.ignoring, isTrue);

      final excludeFocus = tester.widget<ExcludeFocus>(
        find.descendant(of: barFinder, matching: find.byType(ExcludeFocus)),
      );
      expect(excludeFocus.excluding, isTrue);
    });
  });

  group('onBottomBarScrollNotification handler', () {
    testWidgets('ignores horizontal scroll notifications', (tester) async {
      late BuildContext buildContext;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (ctx) {
              buildContext = ctx;
              return const SizedBox();
            },
          ),
        ),
      );

      bool? updatedVisibility;

      final metrics = FixedScrollMetrics(
        minScrollExtent: 0,
        maxScrollExtent: 500,
        pixels: 200,
        viewportDimension: 300,
        axisDirection: AxisDirection.right,
        devicePixelRatio: 1.0,
      );

      final notification = UserScrollNotification(
        metrics: metrics,
        context: buildContext,
        direction: ScrollDirection.reverse,
      );

      onBottomBarScrollNotification(
        notification: notification,
        isCurrentlyVisible: true,
        onVisibilityChanged: (v) => updatedVisibility = v,
      );

      expect(updatedVisibility, isNull);
    });

    testWidgets('hides bottom bar when scrolling downward (reverse scroll direction)', (
      tester,
    ) async {
      late BuildContext buildContext;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (ctx) {
              buildContext = ctx;
              return const SizedBox();
            },
          ),
        ),
      );

      bool? updatedVisibility;

      final metrics = FixedScrollMetrics(
        minScrollExtent: 0,
        maxScrollExtent: 1000,
        pixels: 300,
        viewportDimension: 400,
        axisDirection: AxisDirection.down,
        devicePixelRatio: 1.0,
      );

      final notification = UserScrollNotification(
        metrics: metrics,
        context: buildContext,
        direction: ScrollDirection.reverse,
      );

      onBottomBarScrollNotification(
        notification: notification,
        isCurrentlyVisible: true,
        onVisibilityChanged: (v) => updatedVisibility = v,
      );

      expect(updatedVisibility, isFalse);
    });

    testWidgets('shows bottom bar when scrolling upward (forward scroll direction)', (
      tester,
    ) async {
      late BuildContext buildContext;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (ctx) {
              buildContext = ctx;
              return const SizedBox();
            },
          ),
        ),
      );

      bool? updatedVisibility;

      final metrics = FixedScrollMetrics(
        minScrollExtent: 0,
        maxScrollExtent: 1000,
        pixels: 300,
        viewportDimension: 400,
        axisDirection: AxisDirection.down,
        devicePixelRatio: 1.0,
      );

      final notification = UserScrollNotification(
        metrics: metrics,
        context: buildContext,
        direction: ScrollDirection.forward,
      );

      onBottomBarScrollNotification(
        notification: notification,
        isCurrentlyVisible: false,
        onVisibilityChanged: (v) => updatedVisibility = v,
      );

      expect(updatedVisibility, isTrue);
    });

    testWidgets('auto-reveals bottom bar at top boundary (pixels <= 0)', (
      tester,
    ) async {
      late BuildContext buildContext;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (ctx) {
              buildContext = ctx;
              return const SizedBox();
            },
          ),
        ),
      );

      bool? updatedVisibility;

      final metrics = FixedScrollMetrics(
        minScrollExtent: 0,
        maxScrollExtent: 1000,
        pixels: 0,
        viewportDimension: 400,
        axisDirection: AxisDirection.down,
        devicePixelRatio: 1.0,
      );

      final notification = ScrollUpdateNotification(
        metrics: metrics,
        context: buildContext,
        scrollDelta: -5,
      );

      onBottomBarScrollNotification(
        notification: notification,
        isCurrentlyVisible: false,
        onVisibilityChanged: (v) => updatedVisibility = v,
      );

      expect(updatedVisibility, isTrue);
    });

    testWidgets('keeps bottom bar hidden near bottom boundary when scrolling downward', (
      tester,
    ) async {
      late BuildContext buildContext;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (ctx) {
              buildContext = ctx;
              return const SizedBox();
            },
          ),
        ),
      );

      bool? updatedVisibility;

      final metrics = FixedScrollMetrics(
        minScrollExtent: 0,
        maxScrollExtent: 1000,
        pixels: 985, // extentAfter = 15 < 20
        viewportDimension: 400,
        axisDirection: AxisDirection.down,
        devicePixelRatio: 1.0,
      );

      final notification = ScrollUpdateNotification(
        metrics: metrics,
        context: buildContext,
        scrollDelta: 5,
      );

      onBottomBarScrollNotification(
        notification: notification,
        isCurrentlyVisible: false,
        onVisibilityChanged: (v) => updatedVisibility = v,
      );

      expect(updatedVisibility, isNull);
    });

    testWidgets('shows bottom bar when scrolling upward near bottom boundary', (
      tester,
    ) async {
      late BuildContext buildContext;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (ctx) {
              buildContext = ctx;
              return const SizedBox();
            },
          ),
        ),
      );

      bool? updatedVisibility;

      final metrics = FixedScrollMetrics(
        minScrollExtent: 0,
        maxScrollExtent: 1000,
        pixels: 985,
        viewportDimension: 400,
        axisDirection: AxisDirection.down,
        devicePixelRatio: 1.0,
      );

      final notification = ScrollUpdateNotification(
        metrics: metrics,
        context: buildContext,
        scrollDelta: -5,
      );

      onBottomBarScrollNotification(
        notification: notification,
        isCurrentlyVisible: false,
        onVisibilityChanged: (v) => updatedVisibility = v,
      );

      expect(updatedVisibility, isTrue);
    });
  });

  group('Auto-hiding integration in scroll view', () {
    testWidgets('hides on scroll down and shows on scroll up', (tester) async {
      bool isNavVisible = true;

      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              return Scaffold(
                extendBody: true,
                body: NotificationListener<ScrollNotification>(
                  onNotification: (notification) => onBottomBarScrollNotification(
                    notification: notification,
                    isCurrentlyVisible: isNavVisible,
                    onVisibilityChanged: (v) => setState(() => isNavVisible = v),
                  ),
                  child: ListView.builder(
                    itemCount: 50,
                    itemBuilder: (context, index) => SizedBox(
                      height: 60,
                      child: Text('Item $index'),
                    ),
                  ),
                ),
                bottomNavigationBar: AutoHidingBottomBar(
                  isVisible: isNavVisible,
                  child: Container(
                    height: 56,
                    color: Colors.blue,
                    child: const Center(child: Text('Floating Bar')),
                  ),
                ),
              );
            },
          ),
        ),
      );

      expect(find.text('Floating Bar'), findsOneWidget);
      final barFinder = find.byType(AutoHidingBottomBar);

      expect(
        tester.widget<AnimatedSlide>(
          find.descendant(of: barFinder, matching: find.byType(AnimatedSlide)),
        ).offset,
        Offset.zero,
      );

      // Scroll down by 300 pixels
      await tester.drag(find.text('Item 2'), const Offset(0, -300));
      await tester.pumpAndSettle();

      expect(
        tester.widget<AnimatedSlide>(
          find.descendant(of: barFinder, matching: find.byType(AnimatedSlide)),
        ).offset,
        const Offset(0, 1.4),
      );
      expect(
        tester.widget<AnimatedOpacity>(
          find.descendant(of: barFinder, matching: find.byType(AnimatedOpacity)),
        ).opacity,
        0.0,
      );

      // Scroll up by 150 pixels (away from boundaries)
      await tester.drag(find.text('Item 7'), const Offset(0, 150));
      await tester.pumpAndSettle();

      expect(
        tester.widget<AnimatedSlide>(
          find.descendant(of: barFinder, matching: find.byType(AnimatedSlide)),
        ).offset,
        Offset.zero,
      );
      expect(
        tester.widget<AnimatedOpacity>(
          find.descendant(of: barFinder, matching: find.byType(AnimatedOpacity)),
        ).opacity,
        1.0,
      );
    });
  });
}
