import 'dart:async';

import 'package:erefill/core/theme/app_fonts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  for (final entry in {
    'light': () => AppFonts.textTheme(Brightness.light),
    'dark': () => AppFonts.textTheme(Brightness.dark),
    'outdoor': AppFonts.outdoorTextTheme,
  }.entries) {
    test('${entry.key} type scale is large enough to read', () {
      // Font files load asynchronously and are absent in tests; only the
      // sizes matter here, so font-load errors are ignored in this zone.
      final t = runZonedGuarded(entry.value, (_, _) {})!;
      expect(t.labelSmall!.fontSize, 12);
      expect(t.bodySmall!.fontSize, 13);
      expect(t.labelMedium!.fontSize, 13);
      expect(t.titleSmall!.fontSize, 13);
      expect(t.bodyMedium!.fontSize, 15);
      expect(t.titleMedium!.fontSize, 15);
      expect(t.titleLarge!.fontSize, 18);
      expect(t.headlineSmall!.fontSize, 20);
    });
  }
}
