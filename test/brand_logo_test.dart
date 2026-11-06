import 'package:erefill/core/widgets/brand/erefill_logo.dart';
import 'package:erefill/core/widgets/brand/erefill_mark.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child, {Brightness brightness = Brightness.light}) =>
    MaterialApp(
      theme: ThemeData(brightness: brightness),
      home: Scaffold(body: Center(child: child)),
    );

Color? _wordmarkColor(WidgetTester tester) =>
    tester.widget<Text>(find.text('eRefill')).style?.color;

void main() {
  testWidgets('full lockup shows mark, wordmark and tagline', (tester) async {
    await tester.pumpWidget(_host(const ERefillLogo(showTagline: true)));

    expect(find.byType(ERefillMark), findsOneWidget);
    expect(find.text('eRefill'), findsOneWidget);
    expect(find.text(BrandColors.tagline), findsOneWidget);
    expect(_wordmarkColor(tester), BrandColors.navy);
  });

  testWidgets('wordmark turns white in dark mode', (tester) async {
    await tester.pumpWidget(
      _host(const ERefillLogo(), brightness: Brightness.dark),
    );
    expect(_wordmarkColor(tester), Colors.white);
  });

  testWidgets('mark-only and wordmark-only variants', (tester) async {
    await tester.pumpWidget(_host(const ERefillLogo(showWordmark: false)));
    expect(find.byType(ERefillMark), findsOneWidget);
    expect(find.text('eRefill'), findsNothing);

    await tester.pumpWidget(_host(const ERefillLogo(showMark: false)));
    expect(find.byType(ERefillMark), findsNothing);
    expect(find.text('eRefill'), findsOneWidget);
  });

  testWidgets('one-color mark paints without the gradient', (tester) async {
    await tester.pumpWidget(
      _host(const ERefillMark(size: 64, color: Colors.white)),
    );
    final paint = tester.widget<CustomPaint>(
      find.descendant(
        of: find.byType(ERefillMark),
        matching: find.byType(CustomPaint),
      ),
    );
    expect((paint.painter! as ERefillMarkPainter).color, Colors.white);
    expect(find.bySemanticsLabel('eRefill'), findsOneWidget);
  });
}
