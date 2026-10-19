import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Source-level accessibility guards for rules the analyzer cannot check.
/// See design-system/erefill/MASTER.md ("Icon buttons", "Accessibility").
void main() {
  final dartFiles = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();

  /// Returns the source of every call to [name] in [source], parentheses
  /// matched, so multi-line argument lists are inspected as a whole.
  Iterable<(int line, String call)> callsTo(String source, RegExp name) sync* {
    for (final match in name.allMatches(source)) {
      var i = match.end, depth = 1;
      while (i < source.length && depth > 0) {
        final c = source[i++];
        if (c == '(') depth++;
        if (c == ')') depth--;
      }
      final line = '\n'.allMatches(source.substring(0, match.start)).length + 1;
      yield (line, source.substring(match.start, i));
    }
  }

  test('every IconButton has a tooltip (its screen-reader label)', () {
    final missing = <String>[];
    for (final file in dartFiles) {
      final source = file.readAsStringSync();
      for (final (line, call) in callsTo(
        source,
        RegExp(r'\bIconButton(\.(filled|outlined|filledTonal))?\('),
      )) {
        if (!RegExp(r'\btooltip\s*:').hasMatch(call)) {
          missing.add('${file.path}:$line');
        }
      }
    }
    expect(missing, isEmpty, reason: 'Add tooltip: to:\n${missing.join('\n')}');
  });

  test('text colors are theme-aware (dark mode readable)', () {
    // AppUi.textPrimary/textSecondary/textMuted are the LIGHT-mode values and
    // fall below 4.5:1 on dark surfaces. Use textPrimaryOf(context) etc.
    // Allowed: inside an explicit isDark ternary, on a line marked
    // `// fixed-light: <reason>`, or in a file marked `// fixed-light-file:`.
    final token = RegExp(
      r'AppUi\.(textPrimary|textSecondary|textMuted)\b(?!Of|Dark)',
    );
    final darkGuard = RegExp(r'isDark|Brightness\.dark|dark\s*\?|isOutdoor');
    final offenders = <String>[];
    for (final file in dartFiles) {
      final path = file.path.replaceAll(r'\', '/');
      if (path.startsWith('lib/core/theme/') ||
          path == 'lib/core/constants.dart') {
        continue;
      }
      final source = file.readAsStringSync();
      if (source.contains('// fixed-light-file:')) continue;
      final lines = source.split('\n');
      for (var i = 0; i < lines.length; i++) {
        if (!token.hasMatch(lines[i]) || lines[i].contains('// fixed-light:')) {
          continue;
        }
        final window = lines.sublist(i < 3 ? 0 : i - 3, i + 1).join(' ');
        if (darkGuard.hasMatch(window)) continue;
        offenders.add('$path:${i + 1}');
      }
    }
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });

  test('no raw Colors.grey for text or icons (fails 4.5:1 on white)', () {
    // Colors.grey is ~2.7:1 on white and Colors.grey.shade600 fails on dark
    // surfaces. Use AppUi.textMutedOf(context). Translucent tints are fine.
    final greyInk = RegExp(
      r'\b(color|foregroundColor|disabledForegroundColor|'
      r'unselectedLabelColor|iconColor):\s*(const\s+)?'
      r'Colors\.grey(\[\d+\]|\.shade\d+)?\s*[,)]',
    );
    final offenders = <String>[];
    for (final file in dartFiles) {
      final path = file.path.replaceAll(r'\', '/');
      if (path.startsWith('lib/core/theme/')) continue;
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (!greyInk.hasMatch(lines[i]) || lines[i].contains('fixed-light')) {
          continue;
        }
        final window = lines.sublist(i < 3 ? 0 : i - 3, i + 1).join(' ');
        if (RegExp(r'isDark|Brightness\.dark').hasMatch(window)) continue;
        offenders.add('$path:${i + 1}');
      }
    }
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });

  test('no emoji or check-mark glyphs used as UI icons in widget text', () {
    final glyph = RegExp(r"Text\(\s*'[^']*[✓✔✅❌]");
    final offenders = [
      for (final file in dartFiles)
        if (glyph.hasMatch(file.readAsStringSync())) file.path,
    ];
    expect(offenders, isEmpty, reason: 'Use an Icon instead of a glyph');
  });
}
