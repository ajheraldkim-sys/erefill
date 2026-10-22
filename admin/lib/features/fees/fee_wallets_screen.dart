import 'package:erefill/core/constants.dart';
import 'package:erefill/core/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../services/admin_api_service.dart';
import '../../widgets/admin_ui.dart';

/// Every station's prepaid service fee wallet. Top-ups and COD fee deductions
/// are automatic; the admin watches balances and makes manual adjustments.
class FeeWalletsScreen extends StatefulWidget {
  const FeeWalletsScreen({super.key, this.loadWallets, this.adjustWallet});

  /// Overrides for tests; default to [AdminApiService].
  final Future<List<FeeWalletRow>> Function()? loadWallets;
  final Future<double> Function(String ownerId, double amount, String reason)?
  adjustWallet;

  static const payoutNote =
      'Payouts of online sales to stations are not automated yet.';

  @override
  State<FeeWalletsScreen> createState() => _FeeWalletsScreenState();
}

class _FeeWalletsScreenState extends State<FeeWalletsScreen> {
  List<FeeWalletRow> _rows = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<List<FeeWalletRow>> _fetch() =>
      widget.loadWallets?.call() ??
      context.read<AdminApiService>().listFeeWallets();

  Future<double> _adjust(String ownerId, double amount, String reason) =>
      widget.adjustWallet?.call(ownerId, amount, reason) ??
      context.read<AdminApiService>().adjustFeeWallet(
        ownerId: ownerId,
        amount: amount,
        reason: reason,
      );

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await _fetch();
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _openAdjust(FeeWalletRow row) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _AdjustDialog(
        row: row,
        onSave: (amount, reason) => _adjust(row.ownerId, amount, reason),
      ),
    );
    if (saved == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final totalFees = _rows.fold<double>(0, (sum, r) => sum + r.feesCollected);
    final totalTopups = _rows.fold<double>(0, (sum, r) => sum + r.topupsReceived);
    final codOff = _rows.where((r) => r.codLocked).length;

    return AdminPageScaffold(
      onRefresh: _load,
      header: const AdminSectionHeader(
        title: 'Service Fees',
        subtitle:
            'Station wallets for Cash on Delivery service fees. Online orders pay their fee through PayMongo.',
      ),
      child: _loading
          ? const AdminLoadingState()
          : _error != null
          ? AdminErrorState(message: _error!, onRetry: _load)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: AppUi.spacingLg,
                  runSpacing: AppUi.spacingLg,
                  children: [
                    _Total(label: 'Service fees collected', value: formatPeso(totalFees)),
                    _Total(label: 'Top-ups received', value: formatPeso(totalTopups)),
                    _Total(label: 'Stations with COD off', value: '$codOff'),
                  ],
                ),
                AppUi.vGapMd,
                Text(
                  FeeWalletsScreen.payoutNote,
                  style: TextStyle(color: AppUi.textSecondaryOf(context)),
                ),
                AppUi.vGapLg,
                AdminCard(
                  padding: EdgeInsets.zero,
                  child: _rows.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(24),
                          child: Text('No stations yet.'),
                        )
                      : Column(
                          children: [
                            for (final row in _rows)
                              ListTile(
                                title: Text(row.stationName),
                                subtitle: Text(
                                  'Fees ${formatPeso(row.feesCollected)} · Top-ups ${formatPeso(row.topupsReceived)}',
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (row.codLocked) ...[
                                      const AdminBadge(
                                        label: 'COD off',
                                        color: AppColors.uiError,
                                      ),
                                      AppUi.hGapSm,
                                    ],
                                    Text(
                                      formatPeso(row.balance),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    AppUi.hGapSm,
                                    TextButton(
                                      onPressed: () => _openAdjust(row),
                                      child: const Text('Adjust'),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                ),
              ],
            ),
    );
  }
}

class _Total extends StatelessWidget {
  const _Total({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 240,
      child: AdminCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(color: AppUi.textSecondaryOf(context))),
            AppUi.vGapXs,
            Text(
              value,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdjustDialog extends StatefulWidget {
  const _AdjustDialog({required this.row, required this.onSave});

  final FeeWalletRow row;
  final Future<double> Function(double amount, String reason) onSave;

  @override
  State<_AdjustDialog> createState() => _AdjustDialogState();
}

class _AdjustDialogState extends State<_AdjustDialog> {
  final _amount = TextEditingController();
  final _reason = TextEditingController();
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _amount.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amount.text.trim());
    final reason = _reason.text.trim();
    if (amount == null || amount == 0) {
      setState(() => _error = 'Enter a non-zero amount.');
      return;
    }
    if (reason.isEmpty) {
      setState(() => _error = 'A reason is required.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(amount, reason);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Adjust ${widget.row.stationName}'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Current balance: ${formatPeso(widget.row.balance)}'),
            AppUi.vGapMd,
            TextField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^-?\d*\.?\d{0,2}'))],
              decoration: const InputDecoration(
                labelText: 'Amount (₱)',
                helperText: 'Use a negative amount to debit.',
              ),
            ),
            AppUi.vGapMd,
            TextField(
              controller: _reason,
              decoration: const InputDecoration(labelText: 'Reason'),
            ),
            if (_error != null) ...[
              AppUi.vGapMd,
              Text(_error!, style: const TextStyle(color: AppColors.uiError)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          child: const Text('Save adjustment'),
        ),
      ],
    );
  }
}
