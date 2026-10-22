import 'package:flutter/material.dart';

import 'package:erefill/core/constants.dart';
import 'package:erefill/core/services/payment_launch_service.dart';
import 'package:erefill/core/utils/friendly_errors.dart';
import 'package:erefill/core/widgets/app_ui_kit.dart';

import 'models/fee_wallet_models.dart';
import 'services/fee_wallet_service.dart';
import 'widgets/fee_wallet_card.dart';
import 'widgets/fee_wallet_topup_sheet.dart';

/// The owner's service fee wallet: balance, top-up and history.
///
/// [verifyTopupId] is set when the app reopens from a PayMongo top-up
/// checkout; the screen then confirms that payment with the gateway.
class FeeWalletScreen extends StatefulWidget {
  const FeeWalletScreen({super.key, this.verifyTopupId, this.service});

  final String? verifyTopupId;
  final FeeWalletService? service;

  @override
  State<FeeWalletScreen> createState() => _FeeWalletScreenState();
}

class _FeeWalletScreenState extends State<FeeWalletScreen> {
  late final FeeWalletService _service = widget.service ?? FeeWalletService();
  FeeWalletSummary? _summary;
  List<FeeWalletEntry> _entries = const [];
  String? _error;
  bool _loading = true;
  String? _pendingTopupId;

  @override
  void initState() {
    super.initState();
    _pendingTopupId = widget.verifyTopupId;
    _load(verify: widget.verifyTopupId != null);
  }

  Future<void> _load({bool verify = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (verify && _pendingTopupId != null) {
        final result = await _service.verifyTopup(_pendingTopupId!);
        if (result.paid) _pendingTopupId = null;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                result.paid
                    ? 'Top-up received. Balance: ${formatPeso(result.balance)}'
                    : 'Payment not confirmed yet. Try again in a moment.',
              ),
            ),
          );
        }
      }
      final summary = await _service.load();
      final entries = await _service.history();
      if (!mounted) return;
      setState(() {
        _summary = summary;
        _entries = entries;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = FriendlyErrors.message(e);
        _loading = false;
      });
    }
  }

  Future<void> _openTopup() async {
    final config = _summary?.config ?? FeeWalletConfig.defaults;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: FeeWalletTopupSheet(
          config: config,
          onSubmit: (amount, method) async {
            try {
              final session = await _service.startTopup(
                amount: amount,
                paymentMethod: method,
              );
              if (sheetContext.mounted) Navigator.of(sheetContext).pop();
              await PaymentLaunchService.launchCheckoutUrl(session.url);
              if (mounted) setState(() => _pendingTopupId = session.topupId);
            } catch (e) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(FriendlyErrors.message(e))),
                );
              }
            }
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final summary = _summary;
    return Scaffold(
      backgroundColor: AppUi.pageBgOf(context),
      appBar: AppBar(title: const Text('Service fee wallet')),
      body: _loading && summary == null
          ? const Center(child: CircularProgressIndicator())
          : _error != null && summary == null
          ? AppErrorState(message: _error!, onRetry: _load)
          : RefreshIndicator(
              onRefresh: () => _load(verify: _pendingTopupId != null),
              child: ListView(
                padding: const EdgeInsets.all(AppUi.spacingLg),
                children: [
                  if (summary != null)
                    FeeWalletCard(summary: summary, onTopUp: _openTopup),
                  if (_pendingTopupId != null) ...[
                    AppUi.vGapMd,
                    OutlinedButton.icon(
                      onPressed: () => _load(verify: true),
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text("I've paid — check top-up"),
                    ),
                  ],
                  AppUi.vGapXl,
                  Text(
                    'History',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  AppUi.vGapSm,
                  if (_entries.isEmpty)
                    Text(
                      'No top-ups or service fees yet.',
                      style: TextStyle(color: AppUi.textSecondaryOf(context)),
                    ),
                  for (final entry in _entries)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(entry.label),
                      subtitle: Text(
                        MaterialLocalizations.of(
                          context,
                        ).formatMediumDate(entry.createdAt.toLocal()),
                      ),
                      trailing: Text(
                        '${entry.amount >= 0 ? '+' : '−'}${formatPeso(entry.amount.abs())}',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: entry.amount >= 0
                              ? AppUi.brandOf(context)
                              : AppUi.textPrimaryOf(context),
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}
