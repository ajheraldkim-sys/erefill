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

  test('no emoji or check-mark glyphs used as UI icons in widget text', () {
    final glyph = RegExp(r"Text\(\s*'[^']*[✓✔✅❌]");
    final offenders = [
      for (final file in dartFiles)
        if (glyph.hasMatch(file.readAsStringSync())) file.path,
    ];
    expect(offenders, isEmpty, reason: 'Use an Icon instead of a glyph');
  });
}
