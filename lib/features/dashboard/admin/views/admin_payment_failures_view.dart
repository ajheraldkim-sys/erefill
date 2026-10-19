import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:erefill/core/constants.dart';
import 'package:erefill/core/theme/app_colors.dart';
import 'package:erefill/core/utils/app_haptics.dart';

import 'package:erefill/core/utils/friendly_errors.dart';
class AdminPaymentFailuresView extends StatefulWidget {
  const AdminPaymentFailuresView({super.key});

  @override
  State<AdminPaymentFailuresView> createState() => _AdminPaymentFailuresViewState();
}

class _AdminPaymentFailuresViewState extends State<AdminPaymentFailuresView> {
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _failures = [];
  bool _loading = true;
  String? _error;

  final currencyFormat = NumberFormat.currency(
    locale: 'en_PH',
    symbol: '₱',
    decimalDigits: 2,
  );

  @override
  void initState() {
    super.initState();
    _loadFailures();
  }

  Future<void> _loadFailures() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final res = await supabase
          .from('orders')
          .select('id, customer_name, customer_phone, total_amount, payment_method, payment_status, notes, created_at')
          .eq('payment_status', 'failed')
          .order('created_at', ascending: false)
          .limit(50);

      if (!mounted) return;
      setState(() {
        _failures = List<Map<String, dynamic>>.from(res);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _reconcilePayment(Map<String, dynamic> order) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reconcile Payment?'),
        content: Builder(
          builder: (context) {
            final id = order['id']?.toString() ?? '';
            final shortId = id.length >= 8 ? id.substring(0, 8) : id;
            return Text(
              'Mark payment for Order #$shortId as PAID? Use this if customer provided manual proof of payment.',
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.statusDelivered,
              foregroundColor: Colors.white,
            ),
            child: const Text('Confirm Reconciled'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      AppHaptics.medium();
      await supabase
          .from('orders')
          .update({'payment_status': 'paid'})
          .eq('id', order['id']);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Payment reconciled successfully as PAID.'),
          backgroundColor: AppColors.statusDelivered,
        ),
      );
      _loadFailures();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${FriendlyErrors.message(e)}'), backgroundColor: AppUi.error),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppUi.pageBgOf(context),
      appBar: AppBar(
        backgroundColor: AppUi.surfaceOf(context),
        elevation: 0,
        title: Text(
          'Payment Failures & Discrepancies',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppUi.textPrimaryOf(context),
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () {
              AppHaptics.light();
              _loadFailures();
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppUi.bluePrimary))
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline_rounded, color: AppUi.error, size: 40),
                        const SizedBox(height: 8),
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        ElevatedButton(onPressed: _loadFailures, child: const Text('Retry')),
                      ],
                    ),
                  ),
                )
              : _failures.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.check_circle_rounded, size: 52, color: AppColors.statusDelivered),
                          const SizedBox(height: 12),
                          Text(
                            'Zero payment failures',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                              color: AppUi.textPrimaryOf(context),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'All payment gateway and COD transactions are reconciled.',
                            style: TextStyle(color: AppUi.textMuted, fontSize: 12),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _failures.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final f = _failures[index];
                        final rawAmt = f['total_amount'];
                        final amt = rawAmt is num
                            ? rawAmt.toDouble()
                            : (double.tryParse(rawAmt?.toString() ?? '') ?? 0.0);
                        final date = (f['created_at']?.toString() ?? '').split('T').first;

                        return Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppUi.surfaceOf(context),
                            borderRadius: AppUi.radiusLg,
                            border: Border.all(color: AppUi.error.withValues(alpha: 0.3)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: AppUi.error.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(AppUi.radiusSm),
                                    ),
                                    child: const Text(
                                      'PAYMENT FAILED',
                                      style: TextStyle(
                                        color: AppUi.error,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Builder(
                                    builder: (context) {
                                      final id = f['id']?.toString() ?? '';
                                      final shortId = id.length >= 8 ? id.substring(0, 8) : id;
                                      return Text(
                                        'Order #$shortId',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13,
                                          color: AppUi.textPrimaryOf(context),
                                        ),
                                      );
                                    },
                                  ),
                                  const Spacer(),
                                  Text(
                                    currencyFormat.format(amt),
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                      color: AppUi.textPrimaryOf(context),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Customer: ${f['customer_name'] ?? "Unknown"} (${f['customer_phone'] ?? "No phone"})',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppUi.textPrimaryOf(context),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Method: ${f['payment_method'] ?? "Online"} • Placed on $date',
                                style: TextStyle(fontSize: 11, color: AppUi.textMuted),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.statusDelivered,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                    ),
                                    icon: const Icon(Icons.check_rounded, size: 16),
                                    label: const Text('Reconcile as Paid'),
                                    onPressed: () => _reconcilePayment(f),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
    );
  }
}
