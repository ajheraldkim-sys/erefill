import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants.dart';
import '../../../core/theme/app_colors.dart';
import '../models/payout_model.dart';
import '../services/payout_service.dart';

class OwnerPayoutRequestsTab extends StatefulWidget {
  final String ownerId;
  const OwnerPayoutRequestsTab({super.key, required this.ownerId});

  @override
  State<OwnerPayoutRequestsTab> createState() => _OwnerPayoutRequestsTabState();
}

class _OwnerPayoutRequestsTabState extends State<OwnerPayoutRequestsTab> {
  final PayoutService _payoutService = PayoutService();
  List<RiderPayoutRequest> _requests = [];
  bool _isLoading = true;
  String _filter = 'all'; // 'all', 'pending', 'disbursed'

  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  Future<void> _loadRequests() async {
    final list = await _payoutService.getOwnerPayoutRequests(widget.ownerId);
    if (mounted) {
      setState(() {
        _requests = list;
        _isLoading = false;
      });
    }
  }

  List<RiderPayoutRequest> get _filteredRequests {
    if (_filter == 'pending') {
      return _requests.where((r) => r.status == 'pending').toList();
    }
    if (_filter == 'disbursed') {
      return _requests.where((r) => r.status == 'disbursed').toList();
    }
    return _requests;
  }

  int get _pendingCount =>
      _requests.where((r) => r.status == 'pending').length;

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadRequests,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Filter Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                ChoiceChip(
                  label: Text('All (${_requests.length})'),
                  selected: _filter == 'all',
                  onSelected: (_) => setState(() => _filter = 'all'),
                  selectedColor: AppUi.bluePrimary,
                  labelStyle: TextStyle(
                    color: _filter == 'all'
                        ? Colors.white
                        : AppUi.textSecondaryOf(context),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: Text('Pending ($_pendingCount)'),
                  selected: _filter == 'pending',
                  onSelected: (_) => setState(() => _filter = 'pending'),
                  selectedColor: const Color(0xFFF59E0B),
                  labelStyle: TextStyle(
                    color: _filter == 'pending'
                        ? Colors.white
                        : AppUi.textSecondaryOf(context),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('Disbursed'),
                  selected: _filter == 'disbursed',
                  onSelected: (_) => setState(() => _filter = 'disbursed'),
                  selectedColor: const Color(0xFF10B981),
                  labelStyle: TextStyle(
                    color: _filter == 'disbursed'
                        ? Colors.white
                        : AppUi.textSecondaryOf(context),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          if (_filteredRequests.isEmpty)
            Container(
              padding: const EdgeInsets.all(40),
              decoration: BoxDecoration(
                color: AppUi.surfaceOf(context),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppUi.borderOf(context)),
              ),
              child: Center(
                child: Column(
                  children: [
                    const Icon(
                      Icons.account_balance_wallet_outlined,
                      size: 48,
                      color: AppUi.textMuted,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _filter == 'pending'
                          ? 'No pending withdrawal requests'
                          : 'No payout records found',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppUi.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            ..._filteredRequests.map(_buildRequestCard),
        ],
      ),
    );
  }

  Widget _buildRequestCard(RiderPayoutRequest req) {
    Color statusColor;
    String statusLabel;

    switch (req.status) {
      case 'disbursed':
        statusColor = AppColors.statusCompleted;
        statusLabel = 'DISBURSED';
        break;
      case 'approved':
        statusColor = AppColors.statusConfirmed;
        statusLabel = 'APPROVED';
        break;
      case 'rejected':
        statusColor = AppColors.statusRejected;
        statusLabel = 'DECLINED';
        break;
      default:
        statusColor = AppColors.statusPending;
        statusLabel = 'PENDING';
    }

    final isPending = req.status == 'pending';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppUi.surfaceOf(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppUi.borderOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: AppUi.blueSoft,
                    child: const Icon(
                      Icons.two_wheeler_rounded,
                      color: AppUi.bluePrimary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        req.riderName,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        'Requested: ${_formatDate(req.createdAt)}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppUi.textMuted,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          const Divider(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Amount to Pay',
                    style: TextStyle(fontSize: 11, color: AppUi.textMuted),
                  ),
                  Text(
                    '₱${req.amount.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: AppUi.bluePrimary,
                    ),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    req.payoutMethod.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    req.accountNumber,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppUi.textMuted,
                    ),
                  ),
                  if (req.accountName.isNotEmpty)
                    Text(
                      req.accountName,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppUi.textMuted,
                      ),
                    ),
                ],
              ),
            ],
          ),
          if (req.referenceNumber != null &&
              req.referenceNumber!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Disbursed Ref: ${req.referenceNumber}',
              style: const TextStyle(fontSize: 11, color: Color(0xFF10B981)),
            ),
          ],
          if (req.rejectionReason != null &&
              req.rejectionReason!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Declined Reason: ${req.rejectionReason}',
              style: const TextStyle(fontSize: 11, color: Color(0xFFEF4444)),
            ),
          ],
          if (isPending) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _showRejectDialog(req),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFEF4444),
                      side: const BorderSide(color: Color(0xFFEF4444)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text('Decline'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _showDisburseDialog(req),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text('Mark as Paid'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  void _showDisburseDialog(RiderPayoutRequest req) {
    final refController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppUi.surfaceOf(context),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Confirm Payout Disbursed',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Confirm that ₱${req.amount.toStringAsFixed(2)} was sent to ${req.riderName} via ${req.payoutMethod.toUpperCase()} (${req.accountNumber}).',
              style: const TextStyle(fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: refController,
              decoration: InputDecoration(
                labelText: 'Reference # (Optional)',
                hintText: 'e.g. GCash Ref No.',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              Navigator.pop(ctx);
              final ownerId =
                  Supabase.instance.client.auth.currentUser?.id ?? '';
              await _payoutService.updatePayoutStatus(
                requestId: req.id,
                riderId: req.riderId,
                ownerId: ownerId,
                newStatus: 'disbursed',
                referenceNumber: refController.text.trim(),
              );

              if (mounted) {
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text('Payout marked as disbursed!'),
                    backgroundColor: Color(0xFF10B981),
                  ),
                );
                _loadRequests();
              }
            },
            child: const Text('Confirm Disbursed'),
          ),
        ],
      ),
    );
  }

  void _showRejectDialog(RiderPayoutRequest req) {
    final reasonController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppUi.surfaceOf(context),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Decline Payout Request',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Decline withdrawal request of ₱${req.amount.toStringAsFixed(2)} for ${req.riderName}?',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              decoration: InputDecoration(
                labelText: 'Reason for Declining',
                hintText: 'e.g. Account number mismatch',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              Navigator.pop(ctx);
              final ownerId =
                  Supabase.instance.client.auth.currentUser?.id ?? '';
              await _payoutService.updatePayoutStatus(
                requestId: req.id,
                riderId: req.riderId,
                ownerId: ownerId,
                newStatus: 'rejected',
                rejectionReason: reasonController.text.trim(),
              );

              if (mounted) {
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text('Payout request declined.'),
                    backgroundColor: Color(0xFFEF4444),
                  ),
                );
                _loadRequests();
              }
            },
            child: const Text('Decline'),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }
}
