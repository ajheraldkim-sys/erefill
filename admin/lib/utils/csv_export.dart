import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Export tabular data as CSV (copy to clipboard or save on desktop).
class CsvExport {
  static String build(List<String> headers, List<List<String>> rows) {
    final buffer = StringBuffer();
    buffer.writeln(_escapeRow(headers));
    for (final row in rows) {
      buffer.writeln(_escapeRow(row));
    }
    return buffer.toString();
  }

  static String _escapeRow(List<String> cells) {
    return cells.map(_escapeCell).join(',');
  }

  static String _escapeCell(String cell) {
    if (cell.contains(',') || cell.contains('"') || cell.contains('\n')) {
      return '"${cell.replaceAll('"', '""')}"';
    }
    return cell;
  }

  static Future<void> copyToClipboard(String csv) async {
    await Clipboard.setData(ClipboardData(text: csv));
  }

  static Future<String?> saveToFile(String csv, String filename) async {
    if (kIsWeb) return null;
    try {
      final dir = Directory('${Platform.environment['USERPROFILE'] ?? '.'}\\Downloads');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final file = File('${dir.path}\\$filename');
      await file.writeAsString(csv);
      return file.path;
    } catch (_) {
      return null;
    }
  }
}
