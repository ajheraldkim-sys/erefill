import 'package:flutter/material.dart';

import 'package:erefill/core/constants.dart';
import 'package:erefill/core/theme/app_colors.dart';
import 'package:erefill/core/utils/money.dart';

import '../models/fee_wallet_models.dart';

/// Owner dashboard card for the prepaid service fee wallet.
class FeeWalletCard extends StatelessWidget {
  const FeeWalletCard({
    super.key,
    required this.summary,
    required this.onTopUp,
    this.onHistory,
  });

  final FeeWalletSummary summary;
  final VoidCallback onTopUp;
  final VoidCallback? onHistory;

  static const codOffMessage =
      'Cash on Delivery is off — top up your service fee balance to turn it back on.';

  @override
  Widget build(BuildContext context) {
    final (statusLabel, statusColor) = switch (summary.status) {
      FeeWalletStatus.ok => ('OK', AppColors.uiSuccess),
      FeeWalletStatus.low => ('Low', AppColors.uiWarning),
      FeeWalletStatus.codOff => ('COD off', AppColors.uiError),
    };

    return Container(
      padding: const EdgeInsets.all(AppUi.spacingLg),
      decoration: AppUi.cardDecorationOf(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.account_balance_wallet_outlined,
                color: AppUi.brandOf(context),
              ),
              AppUi.hGapSm,
              Expanded(
                child: Text(
                  'Service fee balance',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppUi.textSecondaryOf(context),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppUi.radiusFull),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          AppUi.vGapSm,
          Text(
            formatPeso(summary.balance),
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: AppUi.textPrimaryOf(context),
            ),
          ),
          if (summary.status == FeeWalletStatus.codOff) ...[
            AppUi.vGapSm,
            Text(
              codOffMessage,
              style: TextStyle(
                color: AppColors.uiError,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          AppUi.vGapMd,
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: onTopUp,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Top up'),
                ),
              ),
              if (onHistory != null) ...[
                AppUi.hGapSm,
                OutlinedButton(
                  onPressed: onHistory,
                  child: const Text('History'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
