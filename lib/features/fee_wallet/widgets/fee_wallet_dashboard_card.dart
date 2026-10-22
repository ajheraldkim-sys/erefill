import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:erefill/core/routing/app_routes.dart';

import '../models/fee_wallet_models.dart';
import '../services/fee_wallet_service.dart';
import 'fee_wallet_card.dart';

/// Loads the owner's wallet for the dashboard and opens the wallet screen for
/// top-ups and history. Renders nothing until (or unless) it loads.
class FeeWalletDashboardCard extends StatefulWidget {
  const FeeWalletDashboardCard({super.key});

  @override
  State<FeeWalletDashboardCard> createState() => _FeeWalletDashboardCardState();
}

class _FeeWalletDashboardCardState extends State<FeeWalletDashboardCard> {
  FeeWalletSummary? _summary;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final summary = await FeeWalletService().load();
      if (mounted) setState(() => _summary = summary);
    } catch (e) {
      debugPrint('Fee wallet unavailable: $e');
    }
  }

  Future<void> _openWallet() async {
    await context.push(AppRoutes.feeWallet);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final summary = _summary;
    if (summary == null) return const SizedBox.shrink();
    return FeeWalletCard(
      summary: summary,
      onTopUp: _openWallet,
      onHistory: _openWallet,
    );
  }
}
