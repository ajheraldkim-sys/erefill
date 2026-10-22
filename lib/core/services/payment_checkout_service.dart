import 'package:supabase_flutter/supabase_flutter.dart';

/// Result of asking the payment gateway whether an order has been paid.
class PaymentVerification {
  const PaymentVerification({
    required this.isPaid,
    required this.paymentStatus,
    this.livemode = false,
  });

  final bool isPaid;

  /// False while the gateway runs on PayMongo test keys (no real money).
  final bool livemode;

  /// Lower-cased `payment_status` reported by the server, e.g. `processing`.
  final String paymentStatus;
}

/// A hosted checkout page for an order or a wallet top-up.
class CheckoutSession {
  const CheckoutSession({
    required this.url,
    this.livemode = false,
    this.topupId,
  });

  final String url;

  /// Set for a service fee wallet top-up.
  final String? topupId;

  /// False while the gateway runs on PayMongo test keys (no real money).
  final bool livemode;
}

/// A payment-gateway failure; [message] is safe to show to the customer.
class PaymentCheckoutException implements Exception {
  const PaymentCheckoutException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Client for the `create-payment-checkout` edge function, shared by checkout,
/// order details and the payment return screen.
///
/// Failures are thrown as [PaymentCheckoutException] carrying the server's
/// message.
class PaymentCheckoutService {
  PaymentCheckoutService([SupabaseClient? client])
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  static const _function = 'create-payment-checkout';

  /// The gateway knows Maya as `maya`; older rows and UI labels say `paymaya`.
  static String normalizeMethod(String method) =>
      method.trim().toLowerCase().replaceAll('paymaya', 'maya');

  static bool isPaidStatus(String? status) => const {
    'success',
    'paid',
    'succeeded',
  }.contains((status ?? '').trim().toLowerCase());

  /// Creates (or, unless [forceNewCheckout], reuses) a checkout session for
  /// [orderId] and returns its URL.
  Future<String> createCheckout({
    required String orderId,
    required String paymentMethod,
    bool forceNewCheckout = false,
  }) async {
    final session = await createCheckoutSession(
      orderId: orderId,
      paymentMethod: paymentMethod,
      forceNewCheckout: forceNewCheckout,
    );
    return session.url;
  }

  /// Like [createCheckout], but also reports whether the gateway is live.
  Future<CheckoutSession> createCheckoutSession({
    required String orderId,
    required String paymentMethod,
    bool forceNewCheckout = false,
  }) async {
    return sessionFrom(
      await _invoke({
        'order_id': orderId,
        'payment_method': normalizeMethod(paymentMethod),
        if (forceNewCheckout) 'force_new_checkout': true,
      }),
    );
  }

  /// Reads a checkout response from the `create-payment-checkout` function.
  static CheckoutSession sessionFrom(Object? data) {
    if (data is Map) {
      final url = data['checkout_url']?.toString().trim();
      if (url != null && url.isNotEmpty) {
        return CheckoutSession(
          url: url,
          livemode: data['livemode'] == true,
          topupId: data['topup_id']?.toString(),
        );
      }
      if (data['error'] != null) throw PaymentCheckoutException(data['error'].toString());
    }
    throw PaymentCheckoutException('Payment checkout session was not created.');
  }

  /// Asks the gateway for the current payment state of [orderId]. The server
  /// also records a confirmed payment on the order.
  Future<PaymentVerification> verify(String orderId) async {
    final data = await _invoke({'action': 'verify', 'order_id': orderId});
    final map = data is Map ? data : const {};
    final status = (map['payment_status'] ?? '').toString().toLowerCase();
    return PaymentVerification(
      isPaid: map['verified'] == true || isPaidStatus(status),
      paymentStatus: status,
      livemode: map['livemode'] == true,
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
      if (details is String && details.isNotEmpty) throw PaymentCheckoutException(details);
      final reason = e.reasonPhrase;
      if (reason != null && reason.isNotEmpty) throw PaymentCheckoutException(reason);
      throw PaymentCheckoutException('Payment gateway returned status ${e.status}.');
    }
  }
}
