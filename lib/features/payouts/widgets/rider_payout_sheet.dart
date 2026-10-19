import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants.dart';
import '../../../core/theme/app_colors.dart';
import '../models/payout_model.dart';
import '../services/payout_service.dart';

import 'package:erefill/core/utils/money.dart';
import 'package:erefill/core/utils/friendly_errors.dart';
class RiderPayoutSheet extends StatefulWidget {
  final double totalEarnings;
  final int completedDeliveries;
  final Map<String, dynamic>? profile;

  const RiderPayoutSheet({
    super.key,
    required this.totalEarnings,
    required this.completedDeliveries,
    this.profile,
  });

  static void show(
    BuildContext context, {
    required double totalEarnings,
    required int completedDeliveries,
    Map<String, dynamic>? profile,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => RiderPayoutSheet(
        totalEarnings: totalEarnings,
        completedDeliveries: completedDeliveries,
        profile: profile,
      ),
    );
  }

  @override
  State<RiderPayoutSheet> createState() => _RiderPayoutSheetState();
}

class _RiderPayoutSheetState extends State<RiderPayoutSheet> {
  final PayoutService _payoutService = PayoutService();
  List<RiderPayoutRequest> _requests = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  Future<void> _loadRequests() async {
    final riderId = Supabase.instance.client.auth.currentUser?.id;
    if (riderId == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    final list = await _payoutService.getRiderPayoutRequests(riderId);
    if (mounted) {
      setState(() {
        _requests = list;
        _isLoading = false;
      });
    }
  }

  double get _totalDisbursed => _requests
      .where((r) => r.status == 'disbursed')
      .fold<double>(0, (sum, r) => sum + r.amount);

  double get _totalPending => _requests
      .where((r) => r.status == 'pending')
      .fold<double>(0, (sum, r) => sum + r.amount);

  double get _availableBalance {
    final bal = widget.totalEarnings - _totalDisbursed - _totalPending;
    return bal > 0 ? bal : 0.0;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      decoration: BoxDecoration(
        color: AppUi.surfaceOf(context),
        borderRadius: AppUi.radiusSheetTop,
      ),
      child: Column(
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppUi.borderOf(context),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Earnings & Payouts',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                // Metrics overview
                Row(
                  children: [
                    Expanded(
                      child: _buildMetricCard(
                        'Available Balance',
                        formatPeso(_availableBalance),
                        AppUi.bluePrimary,
                        Icons.account_balance_wallet_rounded,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildMetricCard(
                        'Total Earned',
                        formatPeso(widget.totalEarnings),
                        AppColors.uiSuccess,
                        Icons.trending_up_rounded,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildMetricCard(
                        'Pending Payout',
                        formatPeso(_totalPending),
                        AppColors.uiWarning,
                        Icons.pending_actions_rounded,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildMetricCard(
                        'Total Disbursed',
                        formatPeso(_totalDisbursed),
                        AppUi.textMuted,
                        Icons.done_all_rounded,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Request Withdrawal Button
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: _availableBalance >= 10
                        ? () => _showRequestPayoutDialog(context)
                        : null,
                    icon: const Icon(Icons.payments_rounded, size: 20),
                    label: Text(
                      _availableBalance >= 10
                          ? 'Request Commission Withdrawal'
                          : 'Insufficient Balance to Withdraw',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppUi.bluePrimary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppUi.radiusCard),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Payout Requests History
                const Text(
                  'Withdrawal History',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                if (_isLoading)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else if (_requests.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: AppUi.surfaceOf(context),
                      borderRadius: BorderRadius.circular(AppUi.radiusCard),
                      border: Border.all(color: AppUi.borderOf(context)),
                    ),
                    child: const Center(
                      child: Column(
                        children: [
                          Icon(
                            Icons.receipt_long_rounded,
                            size: 40,
                            color: AppUi.textMuted,
                          ),
                          SizedBox(height: 8),
                          Text(
                            'No withdrawal requests yet',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppUi.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  ..._requests.map(_buildRequestItem),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCard(
    String label,
    String value,
    Color color,
    IconData icon,
  ) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppUi.surfaceOf(context),
        borderRadius: BorderRadius.circular(AppUi.radiusCard),
        border: Border.all(color: AppUi.borderOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppUi.textMuted,
                ),
              ),
              Icon(icon, size: 16, color: color),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRequestItem(RiderPayoutRequest req) {
    Color statusColor;
    String statusLabel;
    IconData statusIcon;

    switch (req.status) {
      case 'disbursed':
        statusColor = AppColors.statusCompleted;
        statusLabel = 'DISBURSED';
        statusIcon = Icons.check_circle_rounded;
        break;
      case 'approved':
        statusColor = AppColors.statusConfirmed;
        statusLabel = 'APPROVED';
        statusIcon = Icons.thumb_up_rounded;
        break;
      case 'rejected':
        statusColor = AppColors.statusRejected;
        statusLabel = 'DECLINED';
        statusIcon = Icons.cancel_rounded;
        break;
      default:
        statusColor = AppColors.statusPending;
        statusLabel = 'PENDING';
        statusIcon = Icons.hourglass_top_rounded;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppUi.surfaceOf(context),
        borderRadius: BorderRadius.circular(AppUi.radiusCard),
        border: Border.all(color: AppUi.borderOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                formatPeso(req.amount),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppUi.radiusSm),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(statusIcon, size: 12, color: statusColor),
                    const SizedBox(width: 4),
                    Text(
                      statusLabel,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: statusColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(
                '${req.payoutMethod.toUpperCase()} · ${req.accountNumber}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppUi.textMuted,
                ),
              ),
              if (req.accountName.isNotEmpty) ...[
                const Text(' · ', style: TextStyle(color: AppUi.textMuted)),
                Expanded(
                  child: Text(
                    req.accountName,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppUi.textMuted,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ],
          ),
          if (req.referenceNumber != null &&
              req.referenceNumber!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Ref #: ${req.referenceNumber}',
              style: const TextStyle(fontSize: 11, color: AppColors.uiSuccess),
            ),
          ],
          if (req.rejectionReason != null &&
              req.rejectionReason!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Reason: ${req.rejectionReason}',
              style: const TextStyle(fontSize: 11, color: AppColors.uiError),
            ),
          ],
        ],
      ),
    );
  }

  void _showRequestPayoutDialog(BuildContext context) {
    final amountController = TextEditingController();
    final accountNumController = TextEditingController(
      text: widget.profile?['phone']?.toString() ?? '',
    );
    final accountNameController = TextEditingController(
      text: widget.profile?['full_name']?.toString() ?? '',
    );
    String selectedMethod = 'gcash';
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (dlgCtx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          backgroundColor: AppUi.surfaceOf(context),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppUi.radiusSheet)),
          title: Row(
            children: [
              Icon(Icons.payments_rounded, color: AppUi.brandOf(context)),
              SizedBox(width: 8),
              Text(
                'Request Withdrawal',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
              ),
            ],
          ),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Available Balance: ${formatPeso(_availableBalance)}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppUi.brandOf(context),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Amount Input
                  TextFormField(
                    controller: amountController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                    ],
                    decoration: InputDecoration(
                      labelText: 'Withdrawal Amount (₱)',
                      hintText: 'e.g. 500',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppUi.radiusControl),
                      ),
                      prefixText: '₱ ',
                    ),
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) {
                        return 'Please enter an amount';
                      }
                      final amt = double.tryParse(val.trim());
                      if (amt == null || amt <= 0) {
                        return 'Enter a valid amount';
                      }
                      if (amt > _availableBalance) {
                        return 'Amount exceeds available balance';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 8),

                  // Quick fill chips
                  Row(
                    children: [
                      ActionChip(
                        label: const Text('50%'),
                        onPressed: () {
                          final half = (_availableBalance * 0.5);
                          amountController.text = half.toStringAsFixed(2);
                        },
                      ),
                      const SizedBox(width: 8),
                      ActionChip(
                        label: const Text('Max (100%)'),
                        onPressed: () {
                          amountController.text =
                              _availableBalance.toStringAsFixed(2);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Payout Method Selector
                  const Text(
                    'Payout Method',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    initialValue: selectedMethod,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppUi.radiusControl),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'gcash', child: Text('GCash')),
                      DropdownMenuItem(value: 'maya', child: Text('Maya')),
                      DropdownMenuItem(
                        value: 'cash',
                        child: Text('Cash on Hand / Over Counter'),
                      ),
                      DropdownMenuItem(
                        value: 'bank',
                        child: Text('Bank Transfer'),
                      ),
                    ],
                    onChanged: (val) {
                      if (val != null) setDlgState(() => selectedMethod = val);
                    },
                  ),
                  const SizedBox(height: 12),

                  // Account Number
                  TextFormField(
                    controller: accountNumController,
                    decoration: InputDecoration(
                      labelText: selectedMethod == 'cash'
                          ? 'Phone Number'
                          : 'Account / Mobile Number',
                      hintText: '09xxxxxxxxx',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppUi.radiusControl),
                      ),
                    ),
                    validator: (val) => val == null || val.trim().isEmpty
                        ? 'Required'
                        : null,
                  ),
                  const SizedBox(height: 12),

                  // Account Name
                  TextFormField(
                    controller: accountNameController,
                    decoration: InputDecoration(
                      labelText: 'Account / Recipient Name',
                      hintText: 'Full Name',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppUi.radiusControl),
                      ),
                    ),
                    validator: (val) => val == null || val.trim().isEmpty
                        ? 'Required'
                        : null,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dlgCtx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppUi.bluePrimary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppUi.radiusControl),
                ),
              ),
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                final amt = double.parse(amountController.text.trim());
                final riderId =
                    Supabase.instance.client.auth.currentUser?.id ?? '';
                final riderName =
                    widget.profile?['full_name']?.toString() ?? 'Rider';
                final ownerId =
                    widget.profile?['owner_id']?.toString() ?? '';
                final messenger = ScaffoldMessenger.of(context);

                Navigator.pop(dlgCtx);

                try {
                  final newReq = await _payoutService.createPayoutRequest(
                    riderId: riderId,
                    riderName: riderName,
                    ownerId: ownerId,
                    amount: amt,
                    payoutMethod: selectedMethod,
                    accountNumber: accountNumController.text.trim(),
                    accountName: accountNameController.text.trim(),
                  );

                  if (mounted) {
                    setState(() {
                      _requests = [newReq, ..._requests];
                    });
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Withdrawal request submitted successfully! Station owner will process your payout.',
                        ),
                        backgroundColor: AppColors.uiSuccess,
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    messenger.showSnackBar(
                      SnackBar(content: Text('Submission error: ${FriendlyErrors.message(e)}')),
                    );
                  }
                }
              },
              child: const Text('Submit Request'),
            ),
          ],
        ),
      ),
    );
  }
}
