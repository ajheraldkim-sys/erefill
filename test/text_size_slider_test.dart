import 'package:erefill/core/providers/theme_provider.dart';
import 'package:erefill/core/widgets/text_size_slider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('ThemeProvider text scale', () {
    test('defaults to 1.0 and loads a saved value', () async {
      SharedPreferences.setMockInitialValues({'text_scale': 1.25});
      final p = ThemeProvider();
      await Future<void>.delayed(Duration.zero);
      expect(p.textScale, 1.25);
    });

    test('setTextScale clamps to 0.85..1.5 and persists', () async {
      SharedPreferences.setMockInitialValues({});
      final p = ThemeProvider();
      await Future<void>.delayed(Duration.zero);
      expect(p.textScale, 1.0);

      await p.setTextScale(3);
      expect(p.textScale, 1.5);
      await p.setTextScale(0.2);
      expect(p.textScale, 0.85);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble('text_scale'), 0.85);
    });

    test('combinedScale multiplies OS and app scale, clamped to 0.85..1.8', () {
      expect(ThemeProvider.combinedScale(1.0, 1.2), closeTo(1.2, 1e-9));
      expect(ThemeProvider.combinedScale(1.5, 1.5), 1.8);
      expect(ThemeProvider.combinedScale(0.8, 0.85), 0.85);
    });
  });

  group('TextSizeSlider', () {
    Future<ThemeProvider> pump(WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      final provider = ThemeProvider();
      await tester.pumpWidget(
        ChangeNotifierProvider<ThemeProvider>.value(
          value: provider,
          child: const MaterialApp(
            home: Scaffold(body: SingleChildScrollView(child: TextSizeSlider())),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return provider;
    }

    testWidgets('shows the current percent and a preview', (tester) async {
      await pump(tester);
      expect(find.text('100%'), findsOneWidget);
      expect(find.byType(Slider), findsOneWidget);
      expect(find.textContaining('preview', findRichText: true), findsWidgets);
    });

    testWidgets('dragging the slider right makes text larger', (tester) async {
      final provider = await pump(tester);
      await tester.drag(find.byType(Slider), const Offset(400, 0));
      await tester.pumpAndSettle();
      expect(provider.textScale, greaterThan(1.0));
      expect(find.text('100%'), findsNothing);
    });

    testWidgets('Reset returns to 100%', (tester) async {
      final provider = await pump(tester);
      await provider.setTextScale(1.3);
      await tester.pumpAndSettle();
      expect(find.text('130%'), findsOneWidget);

      await tester.tap(find.text('Reset'));
      await tester.pumpAndSettle();
      expect(provider.textScale, 1.0);
      expect(find.text('100%'), findsOneWidget);
    });
  });
}
