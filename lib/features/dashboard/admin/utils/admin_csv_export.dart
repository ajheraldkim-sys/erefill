import 'package:flutter/services.dart';

/// CSV Export helper for mobile & desktop admin consoles.
class AdminCsvExport {
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
}

