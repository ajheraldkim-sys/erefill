import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../core/utils/friendly_errors.dart';
import '../../core/widgets/app_header.dart';
import '../../core/widgets/skeleton.dart';
import '../../core/widgets/app_form_fields.dart';
import 'payment_account_models.dart';
import 'payment_settings_service.dart';

class PaymentAccountsScreen extends StatefulWidget {
  final PaymentAccountScope scope;

  const PaymentAccountsScreen({super.key, required this.scope});

  @override
  State<PaymentAccountsScreen> createState() => _PaymentAccountsScreenState();
}

class _PaymentAccountsScreenState extends State<PaymentAccountsScreen> {
  final _service = PaymentSettingsService();
  late Future<List<PaymentAccount>> _accountsFuture;

  bool get _isCustomer =>
      widget.scope == PaymentAccountScope.customerPaymentMethods;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _accountsFuture = _service.list(widget.scope);
  }

  Future<void> _refresh() async {
    setState(_reload);
    await _accountsFuture;
  }

  String get _title => _isCustomer ? 'Payment Methods' : 'Payout Accounts';

  String get _emptyText => _isCustomer
      ? 'Add a preferred GCash, Maya, or tokenized card reference for faster checkout.'
      : 'Add a GCash, Maya, or bank payout account to receive completed-order earnings.';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppUi.pageBgOf(context),
      appBar: AppTopBar(
        title: _title,
        subtitle: _isCustomer
            ? 'Manage saved checkout options'
            : 'Manage station payout destinations',
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<PaymentAccount>>(
          future: _accountsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const SkeletonList(itemCount: 5);
            }
            if (snapshot.hasError) {
              return ListView(
                padding: AppUi.pagePaddingLoose,
                children: [
                  _securityNotice(),
                  AppUi.vGapLg,
                  _buildMessage(
                    icon: Icons.payments_outlined,
                    title: _isCustomer
                        ? 'Cash on Delivery is Active'
                        : 'Direct Station Payouts Active',
                    message: _isCustomer
                        ? 'You can pay using Cash on Delivery upon refill arrival. Online payment accounts will synchronize automatically once connected.'
                        : 'Station orders are settled via Cash on Delivery by your riders. Online payout channels will synchronize automatically once connected.',
                  ),
                  AppUi.vGapLg,
                  SizedBox(
                    height: 52,
                    child: OutlinedButton.icon(
                      onPressed: _refresh,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Check connection again'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppUi.bluePrimary,
                        side: BorderSide(color: AppUi.borderOf(context)),
                        shape: RoundedRectangleBorder(
                          borderRadius: AppUi.controlRadius,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            }
            final accounts = snapshot.data ?? [];
            return ListView(
              padding: AppUi.pagePaddingLoose,
              children: [
                _securityNotice(),
                AppUi.vGapLg,
                if (accounts.isEmpty)
                  _buildMessage(
                    icon: Icons.account_balance_wallet_outlined,
                    title: 'No saved accounts yet',
                    message: _emptyText,
                  )
                else
                  ...accounts.map(_accountTile),
                AppUi.vGapXl,
                SizedBox(
                  height: 56,
                  child: ElevatedButton.icon(
                    onPressed: _showAddSheet,
                    icon: const Icon(Icons.add_rounded),
                    label: Text(
                      _isCustomer ? 'Add Payment Method' : 'Add Payout Account',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppUi.bluePrimary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: AppUi.cardRadius,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _securityNotice() {
    return Container(
      padding: AppUi.cardPadding,
      decoration: AppUi.flatCardDecorationOf(context),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.lock_outline_rounded, color: AppUi.bluePrimary),
          AppUi.hGapMd,
          Expanded(
            child: Text(
              _isCustomer
                  ? 'Card numbers and CVV are never stored in eRefill. Card support must use gateway tokenization or hosted checkout.'
                  : 'Payout details are masked in the app and encrypted by the backend before storage.',
              style: TextStyle(
                color: AppUi.textSecondaryOf(context),
                fontSize: 13,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _accountTile(PaymentAccount account) {
    final color = account.isDefault
        ? AppUi.bluePrimary
        : AppUi.textSecondaryOf(context);
    return Material(
      color: AppUi.surfaceOf(context),
      borderRadius: AppUi.radiusLg,
      clipBehavior: Clip.antiAlias,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: color.withValues(alpha: 0.1),
            foregroundColor: color,
            child: Icon(_iconFor(account.type)),
          ),
          title: Text(
            account.label,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          subtitle: Text('${account.maskedValue} • ${account.status}'),
          trailing: PopupMenuButton<String>(
            onSelected: (value) => _handleAccountAction(value, account),
            itemBuilder: (_) => [
              if (!account.isDefault)
                const PopupMenuItem(
                  value: 'default',
                  child: Text('Set as default'),
                ),
              const PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ),
      ),
    );
  }

  IconData _iconFor(String type) {
    return switch (type) {
      'gcash' => Icons.account_balance_wallet_outlined,
      'maya' => Icons.account_balance_outlined,
      'bank' => Icons.account_balance_rounded,
      'card' => Icons.credit_card_rounded,
      _ => Icons.payments_outlined,
    };
  }

  Future<void> _handleAccountAction(
    String action,
    PaymentAccount account,
  ) async {
    try {
      if (action == 'default') {
        await _service.setDefault(scope: widget.scope, id: account.id);
      } else if (action == 'delete') {
        await _service.delete(scope: widget.scope, id: account.id);
      }
      await _refresh();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not update this account. Please try again.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildMessage({
    required IconData icon,
    required String title,
    required String message,
  }) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: AppUi.flatCardDecorationOf(context),
      child: Column(
        children: [
          Icon(icon, size: 42, color: AppUi.textSecondaryOf(context)),
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppUi.textSecondaryOf(context),
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  void _showAddSheet() {
    final formKey = GlobalKey<FormState>();
    final accountNameController = TextEditingController();
    final accountRefController = TextEditingController();
    final gatewayTokenController = TextEditingController();
    final cardLast4Controller = TextEditingController();
    String type = 'gcash';
    bool isSaving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          final isCard = type == 'card';
          final isBank = type == 'bank';
          return Container(
            padding: EdgeInsets.fromLTRB(
              AppUi.screenPaddingWide,
              AppUi.spacingLg,
              AppUi.screenPaddingWide,
              MediaQuery.of(context).viewInsets.bottom + AppUi.spacingXl,
            ),
            decoration: BoxDecoration(
              color: AppUi.surfaceOf(context),
              borderRadius: AppUi.radiusSheetTop,
            ),
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 42,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppUi.borderOf(context),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      _isCustomer ? 'Add Payment Method' : 'Add Payout Account',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _isCustomer
                          ? 'Configure a payment method for streamlined checkout'
                          : 'Configure a verified payout account for order settlements',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppUi.textSecondaryOf(context),
                      ),
                    ),
                    AppUi.vGapLg,
                    AppDropdownField<String>(
                      label: 'Account Type',
                      value: type,
                      prefixIcon: Icons.account_balance_wallet_outlined,
                      compact: true,
                      items: [
                        const DropdownMenuItem(
                          value: 'gcash',
                          child: Text('GCash'),
                        ),
                        const DropdownMenuItem(
                          value: 'maya',
                          child: Text('Maya'),
                        ),
                        if (_isCustomer)
                          const DropdownMenuItem(
                            value: 'card',
                            child: Text('Tokenized Card'),
                          ),
                        if (!_isCustomer)
                          const DropdownMenuItem(
                            value: 'bank',
                            child: Text('Bank Account'),
                          ),
                      ],
                      onChanged: (value) => setSheetState(() => type = value!),
                    ),
                    AppUi.vGapMd,
                    AppFormField(
                      controller: accountNameController,
                      label: isCard
                          ? 'Card Label (e.g. Visa Personal)'
                          : 'Account Name',
                      prefixIcon: Icons.badge_outlined,
                      compact: true,
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                              ? 'Required'
                              : null,
                    ),
                    AppUi.vGapMd,
                    if (isCard) ...[
                      AppFormField(
                        controller: gatewayTokenController,
                        label: 'Gateway Payment Method Token',
                        prefixIcon: Icons.vpn_key_outlined,
                        compact: true,
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                                ? 'Token required'
                                : null,
                      ),
                      AppUi.vGapMd,
                      AppFormField(
                        controller: cardLast4Controller,
                        maxLength: 4,
                        keyboardType: TextInputType.number,
                        label: 'Last 4 Digits Only',
                        prefixIcon: Icons.credit_card_outlined,
                        compact: true,
                        validator: (value) =>
                            RegExp(r'^\d{4}$').hasMatch(value?.trim() ?? '')
                                ? null
                                : 'Enter last 4 digits',
                      ),
                    ] else ...[
                      AppFormField(
                        controller: accountRefController,
                        keyboardType: isBank
                            ? TextInputType.number
                            : TextInputType.phone,
                        label: isBank ? 'Bank Account Number' : 'Mobile Number',
                        prefixIcon: isBank
                            ? Icons.account_balance_outlined
                            : Icons.phone_android_rounded,
                        compact: true,
                        validator: (value) => _validateAccountRef(value, type),
                      ),
                    ],
                    AppUi.vGapSm,
                    Text(
                      isCard
                          ? 'Do not enter a full card number or CVV. Use only a token returned by the payment gateway.'
                          : 'This value will be encrypted by the backend and shown only in masked form.',
                      style: TextStyle(
                        color: AppUi.textSecondaryOf(context),
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                    AppUi.vGapXl,
                    AppFormSubmitButton(
                      text: 'Save Securely',
                      icon: Icons.shield_outlined,
                      isLoading: isSaving,
                      onPressed: () async {
                        if (!formKey.currentState!.validate()) return;
                        setSheetState(() => isSaving = true);
                        try {
                          await _service.create(
                            scope: widget.scope,
                            type: type,
                            accountName: accountNameController.text.trim(),
                            accountRef: isCard
                                ? cardLast4Controller.text.trim()
                                : accountRefController.text.trim(),
                            providerName: isBank
                                ? 'Bank Account'
                                : type.toUpperCase(),
                            gatewayPaymentMethodId: isCard
                                ? gatewayTokenController.text.trim()
                                : null,
                            cardLast4: isCard
                                ? cardLast4Controller.text.trim()
                                : null,
                          );
                          if (!mounted) return;
                          Navigator.of(this.context).pop();
                          await _refresh();
                        } catch (e) {
                          if (!mounted) return;
                          ScaffoldMessenger.of(this.context).showSnackBar(
                            SnackBar(
                              content: Text(
                                FriendlyErrors.message(
                                  e,
                                  fallback:
                                      'Could not save account. Please try again.',
                                ),
                              ),
                              backgroundColor: Colors.red,
                            ),
                          );
                        } finally {
                          if (mounted) setSheetState(() => isSaving = false);
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  String? _validateAccountRef(String? value, String type) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return 'Required';
    if (type == 'gcash' || type == 'maya') {
      if (!RegExp(r'^(09|\+639)\d{9}$').hasMatch(trimmed)) {
        return 'Enter a valid PH mobile number.';
      }
    }
    if (type == 'bank') {
      if (!RegExp(r'^\d{6,20}$').hasMatch(trimmed)) {
        return 'Use 6 to 20 digits.';
      }
    }
    return null;
  }
}
