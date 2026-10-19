import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/brand/axo_states.dart';

import 'package:erefill/core/utils/money.dart';
class CustomerCreditSheet extends StatefulWidget {
  const CustomerCreditSheet({
    super.key,
    required this.customerName,
    this.customerId,
  });

  final String customerName;
  final String? customerId;

  static Future<void> show(
    BuildContext context, {
    required String customerName,
    String? customerId,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => CustomerCreditSheet(
        customerName: customerName,
        customerId: customerId,
      ),
    );
  }

  @override
  State<CustomerCreditSheet> createState() => _CustomerCreditSheetState();
}

class _CustomerCreditSheetState extends State<CustomerCreditSheet> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _credits = [];
  double _totalDebt = 0.0;
  int _unpaidCount = 0;

  @override
  void initState() {
    super.initState();
    _fetchCredits();
  }

  Future<void> _fetchCredits() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      List<dynamic> rows = [];

      // 1. Try secure RPC
      try {
        final res = await _supabase.rpc('get_customer_credits');
        if (res is List) rows = res;
      } catch (_) {
        // Fallback: direct query matching debtor_name
        try {
          final res = await _supabase
              .from('dm_credits')
              .select('*')
              .ilike('debtor_name', '%${widget.customerName.trim()}%')
              .order('created_at', ascending: false);
          rows = res;
        } catch (_) {}
      }

      // Also check online orders with payment_method = 'credit'
      final userId = widget.customerId ?? _supabase.auth.currentUser?.id;
      if (userId != null) {
        try {
          final creditOrders = await _supabase
              .from('orders')
              .select('id, total_amount, station_name, created_at, payment_status, notes')
              .eq('customer_id', userId)
              .eq('payment_method', 'credit')
              .order('created_at', ascending: false);

          if (creditOrders.isNotEmpty) {
            for (final o in creditOrders) {
              final shortOId = o['id'].toString().substring(0, 8);
              final exists = rows.any(
                (r) => (r['notes']?.toString().contains(shortOId) ?? false),
              );
              if (!exists) {
                final isPaid = o['payment_status'] == 'success' || o['payment_status'] == 'paid';
                final amt = (o['total_amount'] as num?)?.toDouble() ?? 0.0;
                rows.add({
                  'id': o['id'],
                  'debtor_name': widget.customerName,
                  'amount': amt,
                  'paid_amount': isPaid ? amt : 0.0,
                  'remaining': isPaid ? 0.0 : amt,
                  'is_paid': isPaid,
                  'notes': 'Online Order #${shortOId.toUpperCase()} - ${o['station_name'] ?? 'Station'}',
                  'created_at': o['created_at'],
                });
              }
            }
          }
        } catch (_) {}
      }

      final list = rows.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      list.sort((a, b) {
        final da = DateTime.tryParse(a['created_at']?.toString() ?? '') ?? DateTime.now();
        final db = DateTime.tryParse(b['created_at']?.toString() ?? '') ?? DateTime.now();
        return db.compareTo(da);
      });

      double debt = 0;
      int unpaid = 0;
      for (final r in list) {
        final amt = (r['amount'] as num?)?.toDouble() ?? 0.0;
        final p = (r['paid_amount'] as num?)?.toDouble() ?? 0.0;
        final isPaid = r['is_paid'] == true || (amt - p) <= 0.01;
        if (!isPaid) {
          debt += (amt - p);
          unpaid++;
        }
      }

      if (mounted) {
        setState(() {
          _credits = list;
          _totalDebt = debt;
          _unpaidCount = unpaid;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Unable to load credit ledger. Please check your connection.';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = AppUi.surfaceOf(context);

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: AppUi.radiusSheetTop,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppUi.dividerOf(context),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.brandPrimary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppUi.radiusControl),
                  ),
                  child: Icon(
                    Icons.receipt_long_rounded,
                    color: AppUi.brandOf(context),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Store Credits & Utang',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppUi.textPrimaryOf(context),
                        ),
                      ),
                      Text(
                        'Refill credit balance and payment logs',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppUi.textSecondaryOf(context),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Total outstanding balance summary banner
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: _totalDebt > 0
                      ? [
                          AppColors.uiError.withValues(alpha: 0.1),
                          const Color(0xFFF97316).withValues(alpha: 0.08),
                        ]
                      : [
                          AppColors.uiSuccess.withValues(alpha: 0.1),
                          AppColors.uiSuccess.withValues(alpha: 0.05),
                        ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(AppUi.radiusSheet),
                border: Border.all(
                  color: _totalDebt > 0
                      ? AppColors.uiError.withValues(alpha: 0.3)
                      : AppColors.uiSuccess.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'TOTAL OUTSTANDING BALANCE',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                            color: _totalDebt > 0
                                ? AppColors.uiError
                                : AppColors.uiSuccess,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          formatPeso(_totalDebt),
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w700,
                            color: _totalDebt > 0
                                ? AppColors.uiError
                                : AppColors.uiSuccess,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: _totalDebt > 0
                          ? AppColors.uiError.withValues(alpha: 0.15)
                          : AppColors.uiSuccess.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(AppUi.radiusSheet),
                    ),
                    child: Text(
                      _totalDebt > 0 ? '$_unpaidCount Unpaid' : 'All Settled',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _totalDebt > 0
                            ? AppColors.uiError
                            : AppColors.uiSuccess,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          Expanded(
            child: _isLoading
                ? const AxoLoader(message: 'Checking credit ledger...')
                : _error != null
                    ? Center(
                        child: AxoEmptyState(
                          pose: AxoPose.thinking,
                          title: 'Could not load credits',
                          message: _error!,
                          actionLabel: 'Retry',
                          onAction: _fetchCredits,
                          compact: true,
                        ),
                      )
                    : _credits.isEmpty
                        ? Center(
                            child: AxoEmptyState(
                              pose: AxoPose.happy,
                              title: 'Zero outstanding utang',
                              message:
                                  'You have no pending credits or utang balances with your refilling stations.',
                              compact: true,
                              actionLabel: 'Order water',
                              onAction: () => Navigator.pop(context),
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _fetchCredits,
                            child: ListView.separated(
                              padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                              itemCount: _credits.length,
                              separatorBuilder: (_, _) => const SizedBox(height: 10),
                              itemBuilder: (context, index) {
                                final item = _credits[index];
                                final amt = (item['amount'] as num?)?.toDouble() ?? 0.0;
                                final paid = (item['paid_amount'] as num?)?.toDouble() ?? 0.0;
                                final remaining = (amt - paid).clamp(0.0, amt);
                                final isSettled = item['is_paid'] == true || remaining <= 0.01;
                                final isPartial = !isSettled && paid > 0;
                                final dateStr = item['created_at']?.toString() ?? '';
                                final parsedDate = DateTime.tryParse(dateStr);
                                final formattedDate = parsedDate != null
                                    ? '${parsedDate.month}/${parsedDate.day}/${parsedDate.year}'
                                    : 'Recent';

                                return Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: isDark ? AppUi.darkSurfaceRaised : Colors.white,
                                    borderRadius: BorderRadius.circular(AppUi.radiusCard),
                                    border: Border.all(
                                      color: isDark ? AppUi.borderDark : AppUi.borderLight,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: isSettled
                                              ? AppColors.uiSuccess.withValues(alpha: 0.1)
                                              : (isPartial
                                                  ? AppColors.uiWarning.withValues(alpha: 0.1)
                                                  : AppColors.uiError.withValues(alpha: 0.1)),
                                          borderRadius: BorderRadius.circular(AppUi.radiusCard),
                                        ),
                                        child: Icon(
                                          isSettled
                                              ? Icons.check_circle_outline_rounded
                                              : (isPartial
                                                  ? Icons.timelapse_rounded
                                                  : Icons.error_outline_rounded),
                                          size: 20,
                                          color: isSettled
                                              ? AppColors.uiSuccess
                                              : (isPartial
                                                  ? AppColors.uiWarning
                                                  : AppColors.uiError),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              item['notes']?.toString() ?? 'Water Refill Credit',
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w700,
                                                color: AppUi.textPrimaryOf(context),
                                              ),
                                            ),
                                            const SizedBox(height: 3),
                                            Text(
                                              '$formattedDate · Total ${formatPeso(amt)}${paid > 0 ? ' (Paid ${formatPeso(paid)})' : ''}',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: AppUi.textSecondaryOf(context),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.end,
                                        children: [
                                          Text(
                                            isSettled
                                                ? 'PAID'
                                                : formatPeso(remaining),
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w700,
                                              color: isSettled
                                                  ? AppColors.uiSuccess
                                                  : AppColors.uiError,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            isSettled
                                                ? 'Settled'
                                                : (isPartial ? 'Partial' : 'Unpaid'),
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              color: isSettled
                                                  ? AppColors.uiSuccess
                                                  : (isPartial
                                                      ? AppColors.uiWarning
                                                      : AppColors.uiError),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}

