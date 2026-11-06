import 'package:erefill/core/providers/theme_provider.dart';
import 'package:erefill/core/widgets/theme_mode_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<ThemeProvider> pump(WidgetTester tester, {String? saved}) async {
    SharedPreferences.setMockInitialValues({
      if (saved != null) 'theme_mode': saved,
    });
    final provider = ThemeProvider();
    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeProvider>.value(
        value: provider,
        child: const MaterialApp(home: Scaffold(body: ThemeModePicker())),
      ),
    );
    await tester.pumpAndSettle();
    return provider;
  }

  testWidgets('shows System, Light and Dark choices', (tester) async {
    await pump(tester);
    expect(find.text('System'), findsOneWidget);
    expect(find.text('Light'), findsOneWidget);
    expect(find.text('Dark'), findsOneWidget);
  });

  testWidgets('tapping Dark then System returns to following the device',
      (tester) async {
    final provider = await pump(tester, saved: 'light');
    expect(provider.themeMode, ThemeMode.light);

    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(provider.themeMode, ThemeMode.dark);

    await tester.tap(find.text('System'));
    await tester.pumpAndSettle();
    expect(provider.themeMode, ThemeMode.system);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('theme_mode'), 'system');
  });

  testWidgets('choosing a theme turns outdoor mode off', (tester) async {
    final provider = await pump(tester);
    await provider.setOutdoorMode(true);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Light'));
    await tester.pumpAndSettle();
    expect(provider.isOutdoorMode, isFalse);
    expect(provider.themeMode, ThemeMode.light);
  });
}
