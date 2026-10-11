import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:erefill/core/constants.dart';
import 'package:erefill/core/theme/app_theme.dart';
import 'package:erefill/core/widgets/app_form_fields.dart';

void main() {
  testWidgets('shared text styles inherit theme-aware foreground colors', (
    tester,
  ) async {
    Color? lightTextColor;
    Color? darkTextColor;
    Color? darkSurfaceColor;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Builder(
          builder: (context) {
            lightTextColor = AppUi.textPrimaryOf(context);
            return Text('Light section', style: AppUi.sectionTitle);
          },
        ),
      ),
    );
    expect(lightTextColor, AppTheme.lightTheme.textTheme.bodyLarge?.color);

    await tester.pumpWidget(
      MaterialApp(
        home: Theme(
          data: AppTheme.darkTheme,
          child: Builder(
            builder: (context) {
              darkTextColor = AppUi.textPrimaryOf(context);
              darkSurfaceColor = AppUi.surfaceOf(context);
              return Text('Dark section', style: AppUi.sectionTitle);
            },
          ),
        ),
      ),
    );

    expect(AppUi.sectionTitle.color, isNull);
    expect(darkTextColor, AppTheme.darkTheme.textTheme.bodyLarge?.color);
    expect(darkTextColor!.computeLuminance(), greaterThan(0.7));
    expect(darkSurfaceColor, AppUi.darkSurface);
  });

  testWidgets('shared card and form colors follow the dark theme', (
    tester,
  ) async {
    late BoxDecoration cardDecoration;
    late InputDecoration sharedFieldDecoration;
    late InputDecoration appFormDecoration;
    late Color secondaryTextColor;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Builder(
          builder: (context) {
            cardDecoration = AppUi.flatCardDecorationOf(context);
            sharedFieldDecoration = AppUi.fieldDecorationOf(context, 'Search');
            appFormDecoration = AppFormDecoration.inputDecoration(
              context,
              label: 'Email',
            );
            secondaryTextColor = AppUi.textSecondaryOf(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(cardDecoration.color, AppUi.darkSurface);
    expect(sharedFieldDecoration.fillColor, AppUi.darkSurface);
    expect(sharedFieldDecoration.hintStyle?.color, secondaryTextColor);
    expect(appFormDecoration.fillColor, AppUi.darkSurface);
    expect(appFormDecoration.hintStyle?.color, secondaryTextColor);
  });
}
