/// Helpers for Supabase/PostgREST edge cases.
abstract final class SupabaseHelpers {
  static bool isMissingColumnError(Object error, String column) {
    final message = _errorMessage(error).toLowerCase();
    final col = column.toLowerCase();
    final hasCol = message.contains("'$col'") ||
        message.contains('"$col"') ||
        message.contains('`$col`') ||
        message.contains('.$col') ||
        message.contains('$col ') ||
        message.contains(' $col') ||
        message.contains(col);
    final isSchemaError = message.contains('column') ||
        message.contains('schema cache') ||
        message.contains('pgrst204') ||
        message.contains('42703');
    return hasCol && isSchemaError;
  }

  static String _errorMessage(Object error) {
    try {
      final dynamic e = error;
      final details = e.message;
      if (details is String && details.isNotEmpty) return details;
    } catch (_) {}
    return error.toString();
  }
}
