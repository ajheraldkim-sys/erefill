import 'package:erefill/core/utils/money.dart';
import 'package:erefill/core/utils/safe_supabase.dart';

/// Display helpers shared by the owner's order board and order detail sheet.

/// Peso amount from a numeric or string column value (null shows ₱0).
String formatOrderPeso(dynamic value) {
  final numVal = value is num ? value : num.tryParse('${value ?? 0}') ?? 0;
  return formatPeso(numVal);
}

/// `#1A2B3C4D` style reference from an order UUID.
String shortOrderId(String orderId) => orderId.length > 8
    ? '#${orderId.substring(0, 8).toUpperCase()}'
    : '#${orderId.toUpperCase()}';

/// Relative age such as `just now`, `5m ago`, `3h ago`, `2d ago`.
String orderElapsedLabel(dynamic createdAt) {
  final dt = SafeParse.dateTime(createdAt);
  if (dt == null) return 'recent';

  final diff = DateTime.now().difference(dt.toLocal());
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}
