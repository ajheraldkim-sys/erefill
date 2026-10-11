enum PaymentAccountScope { customerPaymentMethods, ownerPayoutAccounts }

class PaymentAccount {
  final String id;
  final String type;
  final String label;
  final String maskedValue;
  final String status;
  final bool isDefault;

  const PaymentAccount({
    required this.id,
    required this.type,
    required this.label,
    required this.maskedValue,
    required this.status,
    required this.isDefault,
  });

  factory PaymentAccount.fromJson(Map<String, dynamic> json) {
    return PaymentAccount(
      id: json['id']?.toString() ?? '',
      type: json['type']?.toString() ?? '',
      label:
          json['label']?.toString() ??
          json['provider_name']?.toString() ??
          json['account_name']?.toString() ??
          'Account',
      maskedValue:
          json['masked_value']?.toString() ??
          json['masked_account']?.toString() ??
          'Hidden',
      status: json['status']?.toString() ?? 'active',
      isDefault: json['is_default'] == true,
    );
  }
}
