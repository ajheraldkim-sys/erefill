import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../models/payout_model.dart';
import '../services/payout_service.dart';

import 'package:erefill/core/constants.dart';
import 'package:erefill/core/utils/money.dart';
class OwnerWalletSheet extends StatefulWidget {
  final String ownerId;
  final VoidCallback? onManageRiderPayouts;

  const OwnerWalletSheet({
    super.key,
    required this.ownerId,
    this.onManageRiderPayouts,
  });

  static Future<void> show(
    BuildContext context, {
    required String ownerId,
    VoidCallback? onManageRiderPayouts,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => OwnerWalletSheet(
        ownerId: ownerId,
        onManageRiderPayouts: onManageRiderPayouts,
      ),
    );
  }

  @override
  State<OwnerWalletSheet> createState() => _OwnerWalletSheetState();
}

class _OwnerWalletSheetState extends State<OwnerWalletSheet> {
  final PayoutService _payoutService = PayoutService();
  OwnerWalletSummary? _summary;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSummary();
  }

  Future<void> _loadSummary() async {
    final res = await _payoutService.getOwnerWalletSummary(widget.ownerId);
    if (mounted) {
      setState(() {
        _summary = res;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppUi.textPrimary : Colors.white;
    final cardBg = isDark ? AppUi.darkSurfaceRaised : AppUi.pageBg;
    final borderColor = isDark ? AppUi.borderDark : AppUi.borderLight;

    return DraggableScrollableSheet(
      initialChildSize: 0.78,
      minChildSize: 0.45,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(AppUi.radiusPill)),
          ),
          child: Column(
            children: [
              // Drag Handle
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 8),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.brandPrimary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(AppUi.radiusCard),
                      ),
                      child: Icon(
                        Icons.account_balance_wallet_rounded,
                        color: AppUi.brandOf(context),
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Digital Station Wallet',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : AppUi.textPrimary,
                            ),
                          ),
                          Text(
                            'Online payments, rider obligations & net balance',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? Colors.grey[400] : AppUi.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),

              // Body Content
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : RefreshIndicator(
                        onRefresh: _loadSummary,
                        child: ListView(
                          controller: scrollController,
                          padding: const EdgeInsets.all(20),
                          children: [
                            // 1. Balance Banner
                            _buildAvailableBalanceCard(isDark),
                            const SizedBox(height: 16),

                            // 2. Metrics Row
                            Row(
                              children: [
                                Expanded(
                                  child: _buildMetricTile(
                                    title: 'Total Digital',
                                    value: formatPeso((_summary?.totalDigitalEarnings ?? 0)),
                                    subtitle: '${_summary?.totalDigitalOrders ?? 0} orders',
                                    icon: Icons.payments_rounded,
                                    color: Colors.teal,
                                    cardBg: cardBg,
                                    borderColor: borderColor,
                                    isDark: isDark,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _buildMetricTile(
                                    title: 'Pending Riders',
                                    value: formatPeso((_summary?.pendingRiderDisbursements ?? 0)),
                                    subtitle: 'Payout requests',
                                    icon: Icons.pending_actions_rounded,
                                    color: AppColors.uiWarning,
                                    cardBg: cardBg,
                                    borderColor: borderColor,
                                    isDark: isDark,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),

                            // 3. Action button for Rider Payouts
                            if (widget.onManageRiderPayouts != null)
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  side: BorderSide(color: AppColors.brandPrimary.withValues(alpha: 0.5)),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(AppUi.radiusCard),
                                  ),
                                ),
                                icon: Icon(Icons.two_wheeler_rounded, size: 20, color: AppUi.brandOf(context)),
                                label: Text(
                                  'Review & Disburse Rider Payouts',
                                  style: TextStyle(fontWeight: FontWeight.w600, color: AppUi.brandOf(context)),
                                ),
                                onPressed: () {
                                  Navigator.of(context).pop();
                                  widget.onManageRiderPayouts?.call();
                                },
                              ),
                            const SizedBox(height: 20),

                            // 4. Digital Transactions Section
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Recent Online Orders',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: isDark ? Colors.white : AppUi.textPrimary,
                                  ),
                                ),
                                Text(
                                  '${_summary?.recentTransactions.length ?? 0} records',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isDark ? Colors.grey[400] : AppUi.textMuted,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),

                            if (_summary?.recentTransactions.isEmpty ?? true)
                              Container(
                                padding: const EdgeInsets.all(24),
                                decoration: BoxDecoration(
                                  color: cardBg,
                                  borderRadius: BorderRadius.circular(AppUi.radiusSheet),
                                  border: Border.all(color: borderColor),
                                ),
                                child: Column(
                                  children: [
                                    Icon(
                                      Icons.receipt_long_outlined,
                                      size: 40,
                                      color: isDark ? Colors.grey[600] : Colors.grey[400],
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'No online payment orders yet',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: isDark ? Colors.grey[300] : AppUi.textSecondary,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Orders paid with GCash, Maya, or Card will appear here automatically.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: isDark ? Colors.grey[500] : const Color(0xFF94A3B8),
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            else
                              ...(_summary!.recentTransactions.map((tx) {
                                final amt = (tx['amount'] as num?)?.toDouble() ?? 0.0;
                                final method = (tx['payment_method'] ?? 'digital').toString().toUpperCase();
                                final status = (tx['status'] ?? 'pending').toString();
                                final dateStr = tx['created_at'] != null
                                    ? DateTime.tryParse(tx['created_at'].toString())
                                            ?.toLocal()
                                            .toString()
                                            .substring(0, 16) ??
                                        ''
                                    : '';

                                return Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: cardBg,
                                    borderRadius: BorderRadius.circular(AppUi.radiusCard),
                                    border: Border.all(color: borderColor),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: Colors.teal.withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(AppUi.radiusControl),
                                        ),
                                        child: const Icon(
                                          Icons.arrow_downward_rounded,
                                          color: Colors.teal,
                                          size: 18,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Order Payment via $method',
                                              style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600,
                                                color: isDark ? Colors.white : AppUi.textPrimary,
                                              ),
                                            ),
                                            Text(
                                              '$status • $dateStr',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: isDark ? Colors.grey[400] : AppUi.textMuted,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Text(
                                        '+${formatPeso(amt)}',
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.teal,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              })),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAvailableBalanceCard(bool isDark) {
    final balance = _summary?.availableBalance ?? 0.0;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.brandPrimary,
        borderRadius: BorderRadius.circular(AppUi.radiusSheet),
        boxShadow: [
          BoxShadow(
            color: AppColors.brandPrimary.withValues(alpha: 0.3),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Estimated Net Digital Balance',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(AppUi.radiusControl),
                ),
                child: const Text(
                  'Auto-Calculated',
                  style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            formatPeso(balance),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Net digital revenue after deducting rider payouts',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricTile({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
    required Color cardBg,
    required Color borderColor,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(AppUi.radiusSheet),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.grey[400] : AppUi.textMuted,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : AppUi.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 11,
              color: isDark ? Colors.grey[500] : const Color(0xFF94A3B8),
            ),
          ),
        ],
      ),
    );
  }
}
