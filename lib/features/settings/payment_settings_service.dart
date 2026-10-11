import 'package:supabase_flutter/supabase_flutter.dart';

import 'payment_account_models.dart';

class PaymentSettingsService {
  PaymentSettingsService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  String _scopeName(PaymentAccountScope scope) {
    return switch (scope) {
      PaymentAccountScope.customerPaymentMethods => 'customer_payment_methods',
      PaymentAccountScope.ownerPayoutAccounts => 'owner_payout_accounts',
    };
  }

  String _maskAccountRef(String ref, String type) {
    final digits = ref.replaceAll(RegExp(r'\D'), '');
    if (type == 'bank') {
      final last4 =
          digits.length >= 4 ? digits.substring(digits.length - 4) : digits;
      return '**** **** $last4';
    }
    if (digits.length >= 7) {
      final prefix =
          digits.length >= 4 ? digits.substring(0, 4) : '';
      final suffix = digits.substring(digits.length - 3);
      return '$prefix **** $suffix';
    }
    return ref.length > 4 ? '**** ${ref.substring(ref.length - 4)}' : '****';
  }

  Future<List<PaymentAccount>> list(PaymentAccountScope scope) async {
    try {
      final response = await _client.functions.invoke(
        'manage-payment-settings',
        body: {'action': 'list', 'scope': _scopeName(scope)},
      );
      final data = response.data;
      final rows = data is Map ? data['accounts'] : null;
      if (rows is List) {
        return rows
            .whereType<Map>()
            .map((row) => PaymentAccount.fromJson(Map<String, dynamic>.from(row)))
            .toList();
      }
    } catch (_) {
      // Fallback directly to querying table
    }

    final user = _client.auth.currentUser;
    if (user == null) return [];

    final isCustomer = scope == PaymentAccountScope.customerPaymentMethods;
    final table = isCustomer ? 'customer_payment_methods' : 'owner_payout_accounts';
    final ownerCol = isCustomer ? 'customer_id' : 'owner_id';

    final data = await _client
        .from(table)
        .select()
        .eq(ownerCol, user.id)
        .order('is_default', ascending: false)
        .order('created_at', ascending: false);

    return (data as List)
        .whereType<Map>()
        .map((row) => PaymentAccount.fromJson(Map<String, dynamic>.from(row)))
        .toList();
  }

  Future<void> create({
    required PaymentAccountScope scope,
    required String type,
    required String accountName,
    required String accountRef,
    String? providerName,
    String? gatewayPaymentMethodId,
    String? cardBrand,
    String? cardLast4,
  }) async {
    try {
      final response = await _client.functions.invoke(
        'manage-payment-settings',
        body: {
          'action': 'create',
          'scope': _scopeName(scope),
          'type': type,
          'account_name': accountName,
          'account_ref': accountRef,
          'provider_name': providerName,
          'gateway_payment_method_id': gatewayPaymentMethodId,
          'card_brand': cardBrand,
          'card_last4': cardLast4,
        },
      );
      if (response.status == 200) {
        return;
      }
      final data = response.data;
      if (data is Map && data['error'] != null) {
        throw Exception(data['error'].toString());
      }
    } catch (e) {
      final msg = e.toString().toLowerCase();
      // If client input validation failed explicitly, propagate to user
      if (msg.contains('invalid mobile') || msg.contains('invalid bank')) {
        rethrow;
      }

      // Fallback: direct database insertion via authenticated RLS
      final user = _client.auth.currentUser;
      if (user == null) rethrow;

      final isCustomer = scope == PaymentAccountScope.customerPaymentMethods;
      final table = isCustomer ? 'customer_payment_methods' : 'owner_payout_accounts';
      final cleanRef = accountRef.trim();
      final masked = type == 'card'
          ? 'Card **** ${cardLast4 ?? (cleanRef.length >= 4 ? cleanRef.substring(cleanRef.length - 4) : cleanRef)}'
          : _maskAccountRef(cleanRef, type);

      if (isCustomer) {
        final customerData = <String, dynamic>{
          'customer_id': user.id,
          'type': type,
          'label': accountName,
          'masked_value': masked,
          'status': 'active',
        };
        if (gatewayPaymentMethodId != null) {
          customerData['gateway_payment_method_id'] = gatewayPaymentMethodId;
        }
        if (cardBrand != null) {
          customerData['card_brand'] = cardBrand;
        }
        if (cardLast4 != null) {
          customerData['card_last4'] = cardLast4;
        }
        await _client.from(table).insert(customerData);
      } else {
        await _client.from(table).insert({
          'owner_id': user.id,
          'type': type,
          'label': accountName,
          'provider_name': providerName ?? type.toUpperCase(),
          'masked_value': masked,
          'status': 'active',
        });
      }
    }
  }

  Future<void> setDefault({
    required PaymentAccountScope scope,
    required String id,
  }) async {
    try {
      final response = await _client.functions.invoke(
        'manage-payment-settings',
        body: {'action': 'set_default', 'scope': _scopeName(scope), 'id': id},
      );
      if (response.status == 200) return;
    } catch (_) {}

    final user = _client.auth.currentUser;
    if (user == null) return;

    try {
      await _client.rpc('set_payment_account_default', params: {
        'p_user_id': user.id,
        'p_account_id': id,
        'p_scope': _scopeName(scope),
      });
    } catch (_) {
      final isCustomer = scope == PaymentAccountScope.customerPaymentMethods;
      final table = isCustomer ? 'customer_payment_methods' : 'owner_payout_accounts';
      final ownerCol = isCustomer ? 'customer_id' : 'owner_id';

      await _client.from(table).update({'is_default': false}).eq(ownerCol, user.id);
      await _client.from(table).update({'is_default': true}).eq('id', id).eq(ownerCol, user.id);
    }
  }

  Future<void> delete({
    required PaymentAccountScope scope,
    required String id,
  }) async {
    try {
      final response = await _client.functions.invoke(
        'manage-payment-settings',
        body: {'action': 'delete', 'scope': _scopeName(scope), 'id': id},
      );
      if (response.status == 200) return;
    } catch (_) {}

    final user = _client.auth.currentUser;
    if (user == null) return;

    final isCustomer = scope == PaymentAccountScope.customerPaymentMethods;
    final table = isCustomer ? 'customer_payment_methods' : 'owner_payout_accounts';
    final ownerCol = isCustomer ? 'customer_id' : 'owner_id';

    await _client.from(table).delete().eq('id', id).eq(ownerCol, user.id);
  }
}
