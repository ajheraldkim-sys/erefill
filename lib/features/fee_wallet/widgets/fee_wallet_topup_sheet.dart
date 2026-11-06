import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:erefill/core/constants.dart';
import 'package:erefill/core/utils/money.dart';
import 'package:erefill/features/dashboard/customer/checkout_rules.dart';
import 'package:erefill/features/dashboard/customer/widgets/test_mode_label.dart';

import '../models/fee_wallet_models.dart';

/// Picks a whole-peso top-up amount and an online payment method, then hands
/// them to [onSubmit] (which opens the PayMongo checkout).
class FeeWalletTopupSheet extends StatefulWidget {
  const FeeWalletTopupSheet({
    super.key,
    required this.config,
    required this.onSubmit,
    this.livemode = false,
  });

  final FeeWalletConfig config;
  final Future<void> Function(int amount, String paymentMethod) onSubmit;
  final bool livemode;

  static const presets = [100, 300, 500];
  static const methods = ['gcash', 'maya', 'card', 'qrph'];

  @override
  State<FeeWalletTopupSheet> createState() => _FeeWalletTopupSheetState();
}

class _FeeWalletTopupSheetState extends State<FeeWalletTopupSheet> {
  final _customController = TextEditingController();
  int? _preset = FeeWalletTopupSheet.presets.first;
  String _method = 'gcash';
  bool _submitting = false;

  @override
  void dispose() {
    _customController.dispose();
    super.dispose();
  }

  int? get _amount => _preset ?? int.tryParse(_customController.text);

  String? get _amountError {
    final amount = _amount;
    if (_preset != null || _customController.text.isEmpty) return null;
    if (amount == null || amount < widget.config.minTopup) {
      return 'Minimum top-up is ${formatPeso(widget.config.minTopup)}.';
    }
    return null;
  }

  bool get _canPay {
    final amount = _amount;
    return !_submitting && amount != null && amount >= widget.config.minTopup;
  }

  Future<void> _pay() async {
    final amount = _amount;
    if (amount == null) return;
    setState(() => _submitting = true);
    try {
      await widget.onSubmit(amount, _method);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final amount = _amount;
    return Padding(
      padding: AppUi.sheetPadding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Top up service fee balance',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          AppUi.vGapSm,
          Text(
            'Cash on Delivery orders take their service fee from this balance.',
            style: TextStyle(color: AppUi.textSecondaryOf(context)),
          ),
          if (!widget.livemode) ...[
            AppUi.vGapMd,
            TestModeLabel(qrph: _method == 'qrph'),
          ],
          AppUi.vGapLg,
          Wrap(
            spacing: AppUi.spacingSm,
            children: [
              for (final preset in FeeWalletTopupSheet.presets)
                ChoiceChip(
                  label: Text(formatPeso(preset)),
                  selected: _preset == preset,
                  onSelected: (_) => setState(() {
                    _preset = preset;
                    _customController.clear();
                  }),
                ),
            ],
          ),
          AppUi.vGapMd,
          TextField(
            controller: _customController,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: 'Other amount (₱)',
              errorText: _amountError,
            ),
            onChanged: (value) =>
                setState(() => _preset = value.isEmpty ? _preset : null),
          ),
          AppUi.vGapLg,
          Wrap(
            spacing: AppUi.spacingSm,
            children: [
              for (final method in FeeWalletTopupSheet.methods)
                ChoiceChip(
                  label: Text(CheckoutRules.paymentLabel(method)),
                  selected: _method == method,
                  onSelected: (_) => setState(() => _method = method),
                ),
            ],
          ),
          AppUi.vGapXl,
          ElevatedButton(
            onPressed: _canPay ? _pay : null,
            child: Text(
              amount == null ? 'Pay' : 'Pay ${formatPeso(amount)}',
            ),
          ),
        ],
      ),
    );
  }
}
