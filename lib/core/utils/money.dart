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

/// Formats an amount the same way on every surface. Prices are whole pesos,
/// so whole amounts print without decimals (`₱120`); an amount carrying the
/// service fee's centavos keeps two (`₱141.40`).
///
/// [whole] always rounds to pesos, for compact KPI tiles where centavos add
/// noise.
String formatPeso(num? amount, {bool whole = false}) {
  final value = amount ?? 0;
  if (whole) return _pesoWhole.format(value);
  final hasCentavos = (value * 100).round() % 100 != 0;
  return hasCentavos ? _peso.format(value) : _pesoWhole.format(value);
}

final NumberFormat _amount = NumberFormat('#,##0.00', 'en_US');
final NumberFormat _amountWhole = NumberFormat('#,##0', 'en_US');

/// [formatPeso] without the symbol, for PDF receipts and exports whose fonts
/// cannot render `₱` and print `PHP` instead.
String formatAmount(num? amount) {
  final value = amount ?? 0;
  final hasCentavos = (value * 100).round() % 100 != 0;
  return hasCentavos ? _amount.format(value) : _amountWhole.format(value);
}
