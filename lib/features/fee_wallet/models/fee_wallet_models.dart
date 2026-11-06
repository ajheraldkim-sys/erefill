/// Thresholds from `system_config.service_fee_wallet` (PHP).
class FeeWalletConfig {
  const FeeWalletConfig({
    required this.minTopup,
    required this.lowBalanceAlert,
    required this.codLockAtOrBelow,
  });

  static const defaults = FeeWalletConfig(
    minTopup: 100,
    lowBalanceAlert: 100,
    codLockAtOrBelow: 0,
  );

  final int minTopup;
  final double lowBalanceAlert;
  final double codLockAtOrBelow;

  factory FeeWalletConfig.fromJson(Map<String, dynamic>? json) {
    double read(String key, double fallback) =>
        (json?[key] as num?)?.toDouble() ?? fallback;
    return FeeWalletConfig(
      minTopup: read('min_topup', defaults.minTopup.toDouble()).round(),
      lowBalanceAlert: read('low_balance_alert', defaults.lowBalanceAlert),
      codLockAtOrBelow: read('cod_lock_at_or_below', defaults.codLockAtOrBelow),
    );
  }
}

/// [codOff] mirrors `public.station_cod_locked`: customers cannot choose Cash
/// on Delivery until the station tops up.
enum FeeWalletStatus { ok, low, codOff }

class FeeWalletSummary {
  const FeeWalletSummary({
    required this.balance,
    required this.status,
    required this.config,
    this.lastTopupAt,
  });

  factory FeeWalletSummary.fromBalance({
    required double balance,
    required FeeWalletConfig config,
    DateTime? lastTopupAt,
  }) {
    final status = balance <= config.codLockAtOrBelow
        ? FeeWalletStatus.codOff
        : balance < config.lowBalanceAlert
        ? FeeWalletStatus.low
        : FeeWalletStatus.ok;
    return FeeWalletSummary(
      balance: balance,
      status: status,
      config: config,
      lastTopupAt: lastTopupAt,
    );
  }

  final double balance;
  final FeeWalletStatus status;
  final FeeWalletConfig config;
  final DateTime? lastTopupAt;
}

class FeeWalletEntry {
  const FeeWalletEntry({
    required this.amount,
    required this.kind,
    required this.createdAt,
    this.orderId,
    this.note,
  });

  factory FeeWalletEntry.fromJson(Map<String, dynamic> json) => FeeWalletEntry(
    amount: (json['amount'] as num?)?.toDouble() ?? 0,
    kind: json['kind']?.toString() ?? '',
    orderId: json['order_id']?.toString(),
    note: json['note']?.toString(),
    createdAt:
        DateTime.tryParse(json['created_at']?.toString() ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0),
  );

  final double amount;
  final String kind;
  final String? orderId;
  final String? note;
  final DateTime createdAt;

  String get label => switch (kind) {
    'topup' => 'Top-up',
    'service_fee' =>
      'Service fee · Order #${(orderId ?? '').split('-').first.toUpperCase()}',
    _ => note == null || note!.isEmpty ? 'Adjustment' : 'Adjustment · $note',
  };
}
