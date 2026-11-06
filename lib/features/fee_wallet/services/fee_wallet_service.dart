import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:erefill/core/services/payment_checkout_service.dart';

import '../models/fee_wallet_models.dart';

/// Result of asking the gateway whether a wallet top-up was paid.
class TopupVerification {
  const TopupVerification({
    required this.paid,
    required this.status,
    required this.balance,
  });

  final bool paid;
  final String status;
  final double balance;
}

/// The owner's service fee wallet: balance and history come straight from the
/// RLS-protected tables; top-ups go through the `create-payment-checkout`
/// edge function.
class FeeWalletService {
  FeeWalletService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  static const _function = 'create-payment-checkout';

  Future<FeeWalletSummary> load() async {
    final ownerId = _client.auth.currentUser?.id;
    if (ownerId == null) throw const PaymentCheckoutException('Please sign in again.');

    final results = await Future.wait<dynamic>([
      _client.rpc('service_fee_wallet_config'),
      _client
          .from('station_fee_wallets')
          .select('balance')
          .eq('owner_id', ownerId)
          .maybeSingle(),
      _client
          .from('station_fee_topups')
          .select('paid_at')
          .eq('owner_id', ownerId)
          .eq('status', 'paid')
          .order('paid_at', ascending: false)
          .limit(1)
          .maybeSingle(),
    ]);

    final config = FeeWalletConfig.fromJson(
      results[0] is Map ? Map<String, dynamic>.from(results[0] as Map) : null,
    );
    final wallet = results[1] as Map<String, dynamic>?;
    final lastTopup = results[2] as Map<String, dynamic>?;
    return FeeWalletSummary.fromBalance(
      balance: (wallet?['balance'] as num?)?.toDouble() ?? 0,
      config: config,
      lastTopupAt: DateTime.tryParse(lastTopup?['paid_at']?.toString() ?? ''),
    );
  }

  Future<List<FeeWalletEntry>> history({int limit = 50}) async {
    final ownerId = _client.auth.currentUser?.id;
    if (ownerId == null) return const [];
    final rows = await _client
        .from('station_fee_wallet_entries')
        .select('amount, kind, order_id, note, created_at')
        .eq('owner_id', ownerId)
        .order('created_at', ascending: false)
        .limit(limit);
    return rows.map(FeeWalletEntry.fromJson).toList();
  }

  Future<CheckoutSession> startTopup({
    required int amount,
    required String paymentMethod,
  }) async {
    return PaymentCheckoutService.sessionFrom(
      await _invoke({
        'action': 'topup',
        'amount': amount,
        'payment_method': PaymentCheckoutService.normalizeMethod(paymentMethod),
      }),
    );
  }

  Future<TopupVerification> verifyTopup(String topupId) async {
    final data = await _invoke({'action': 'verify_topup', 'topup_id': topupId});
    final map = data is Map ? data : const {};
    return TopupVerification(
      paid: map['verified'] == true,
      status: (map['status'] ?? '').toString(),
      balance: (map['balance'] as num?)?.toDouble() ?? 0,
    );
  }

  Future<Object?> _invoke(Map<String, dynamic> body) async {
    try {
      return (await _client.functions.invoke(_function, body: body)).data;
    } on FunctionException catch (e) {
      final details = e.details;
      if (details is Map && details['error'] != null) {
        throw PaymentCheckoutException(details['error'].toString());
      }
      throw PaymentCheckoutException(
        e.reasonPhrase ?? 'Payment gateway returned status ${e.status}.',
      );
    }
  }
}
