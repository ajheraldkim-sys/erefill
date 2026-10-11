import 'dart:convert';
import 'dart:isolate';

/// Utility class for offloading heavy JSON encoding and decoding
/// to background threads using [Isolate.run].
///
/// Prevents micro-stutters and frame drops on the main UI thread
/// when handling large station catalogs, orders, or analytics payloads.
class IsolateJsonParser {
  /// Decodes a JSON string into a `List<Map<String, dynamic>>` on a background isolate.
  static Future<List<Map<String, dynamic>>> parseJsonList(String rawJson) async {
    if (rawJson.trim().isEmpty) return <Map<String, dynamic>>[];
    return await Isolate.run(() {
      final decoded = jsonDecode(rawJson);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
      return <Map<String, dynamic>>[];
    });
  }

  /// Decodes a JSON string into a `Map<String, dynamic>` on a background isolate.
  static Future<Map<String, dynamic>> parseJsonMap(String rawJson) async {
    if (rawJson.trim().isEmpty) return <String, dynamic>{};
    return await Isolate.run(() {
      final decoded = jsonDecode(rawJson);
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
      return <String, dynamic>{};
    });
  }

  /// Encodes a large object structure into a JSON string on a background isolate.
  static Future<String> encodeJson(dynamic object) async {
    return await Isolate.run(() => jsonEncode(object));
  }
}

