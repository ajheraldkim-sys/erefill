import 'package:intl/intl.dart';

final NumberFormat _peso = NumberFormat.currency(
  locale: 'en_US',
  symbol: '₱',
  decimalDigits: 2,
);

final NumberFormat _pesoWhole = NumberFormat.currency(
  locale: 'en_US',
  symbol: '₱',
  decimalDigits: 0,
);

/// Formats an amount the same way on every surface: `₱1,234.50`.
///
/// Use [whole] only for compact KPI tiles where centavos add noise; anything
/// a customer pays or an owner is credited should keep both decimals.
String formatPeso(num? amount, {bool whole = false}) {
  final value = amount ?? 0;
  return whole ? _pesoWhole.format(value) : _peso.format(value);
}
