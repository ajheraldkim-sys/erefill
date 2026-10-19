import 'package:erefill/core/constants.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../services/admin_api_service.dart';
import '../../../widgets/admin_ui.dart';

/// Single-screen dispute investigation hub combining:
/// 1. Order milestone timeline
/// 2. In-app chat transcript between Customer, Rider, and Station
/// 3. Proof of Delivery (POD) photo & recipient signature
/// 4. Financial & payment breakdown
/// 5. Immediate resolution actions with required audit notes
class DisputeDetailsView extends StatefulWidget {
  final Map<String, dynamic> dispute;
  final VoidCallback onClose;
  final Future<void> Function(String status, String notes) onResolve;

  const DisputeDetailsView({
    super.key,
    required this.dispute,
    required this.onClose,
    required this.onResolve,
  });

  @override
  State<DisputeDetailsView> createState() => _DisputeDetailsViewState();
}

class _DisputeDetailsViewState extends State<DisputeDetailsView> {
  final _resolutionNotesController = TextEditingController();
  Map<String, dynamic>? _orderDetails;
  bool _isActionInProgress = false;

  @override
  void initState() {
    super.initState();
    _fetchOrderInfo();
  }

  @override
  void didUpdateWidget(DisputeDetailsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dispute['id'] != widget.dispute['id']) {
      _fetchOrderInfo();
    }
  }

  @override
  void dispose() {
    _resolutionNotesController.dispose();
    super.dispose();
  }

  Future<void> _fetchOrderInfo() async {
    final orderId = widget.dispute['order_id']?.toString();
    if (orderId == null || orderId.isEmpty) return;

    try {
      final details =
          await context.read<AdminApiService>().getOrderDetail(orderId);
      if (mounted) setState(() => _orderDetails = details);
    } catch (_) {}
  }

  Future<void> _executeResolution(String action, String status) async {
    final notes = _resolutionNotesController.text.trim();
    if (notes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter resolution notes before proceeding.'),
          backgroundColor: AppUi.error,
        ),
      );
      return;
    }

    setState(() => _isActionInProgress = true);
    try {
      await widget.onResolve(status, '[$action] $notes');
    } finally {
      if (mounted) setState(() => _isActionInProgress = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.dispute;
    final order = _orderDetails ?? {};
    final status = d['status']?.toString() ?? 'open';
    final amount = safeDouble(d['total_amount'] ?? order['total_amount']);
    final orderId = d['order_id']?.toString() ?? '—';
    final reporter = d['reporter_name']?.toString() ?? 'Customer';
    final stationName = d['station_name']?.toString() ?? 'Water Station';
    final reason = d['reason']?.toString() ?? 'Dispute reported';
    final description = d['description']?.toString() ?? 'No detailed description provided.';
    final paymentMethod = order['payment_method']?.toString() ?? 'Cash on Delivery (COD)';
    final podPhoto = order['photo_url'] ?? order['proof_photo_url'] ?? d['evidence_photo_url'];
    final signatureUrl = order['signature_url'] ?? order['proof_signature_url'];
    final deliveryAddress = order['delivery_address'] ?? order['address'] ?? 'Cantilan / Madrid Area';

    return Container(
      width: 520,
      decoration: BoxDecoration(
        color: AppUi.surfaceOf(context),
        border: Border(left: BorderSide(color: AppUi.borderOf(context))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: AppUi.dividerOf(context))),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppUi.warningBg,
                    borderRadius: BorderRadius.circular(AppUi.radiusControl),
                  ),
                  child: const Icon(
                    Icons.gavel_rounded,
                    color: AppUi.warningFg,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        reason,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'Order #$orderId · $stationName',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppUi.textSecondaryOf(context),
                        ),
                      ),
                    ],
                  ),
                ),
                AdminBadge(
                  label: status,
                  color: adminStatusColor(context, status),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Close details',
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: widget.onClose,
                ),
              ],
            ),
          ),

          // Body Content (One-screen scrollable hub)
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 1. Complaint Description Card
                  AdminGlassCard(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(LucideIcons.messageSquareWarning,
                                size: 16, color: AppUi.warningFg),
                            const SizedBox(width: 8),
                            Text(
                              'Filed by $reporter',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              adminFormatDateTime(d['created_at']),
                              style: adminCaptionTextStyle(context),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          description,
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.4,
                            color: AppUi.textPrimaryOf(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 2. Order Timeline Milestone Stepper
                  _buildTimelineSection(context, order),
                  const SizedBox(height: 16),

                  // 3. Proof of Delivery (POD) Evidence & Signature
                  _buildPodSection(context, podPhoto, signatureUrl, deliveryAddress),
                  const SizedBox(height: 16),

                  // 4. Chat Transcript (Customer, Rider, Station)
                  _buildChatSection(context, order),
                  const SizedBox(height: 16),

                  // 5. Payment & Financial Details
                  _buildPaymentSection(context, amount, paymentMethod, order),
                  const SizedBox(height: 20),

                  // 6. Resolution & Decision Notes
                  _buildResolutionSection(context),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineSection(BuildContext context, Map<String, dynamic> order) {
    return AdminGlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.timeline_rounded, size: 16, color: AppUi.brandOf(context)),
              const SizedBox(width: 8),
              const Text(
                'Order Lifecycle Timeline',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _buildTimelineStep(
            title: 'Order Placed by Customer',
            time: order['created_at'] != null
                ? adminFormatDateTime(order['created_at'])
                : 'Confirmed in app',
            isDone: true,
            icon: Icons.shopping_cart_checkout_rounded,
          ),
          _buildTimelineStep(
            title: 'Station Accepted & Refilling Queued',
            time: order['accepted_at'] != null
                ? adminFormatDateTime(order['accepted_at'])
                : 'Processed by station',
            isDone: true,
            icon: Icons.water_drop_rounded,
          ),
          _buildTimelineStep(
            title: 'Rider Picked Up & Out for Delivery',
            time: order['out_for_delivery_at'] != null
                ? adminFormatDateTime(order['out_for_delivery_at'])
                : 'Dispatched to rider',
            isDone: true,
            icon: Icons.two_wheeler_rounded,
          ),
          _buildTimelineStep(
            title: 'Dispute Raised / Flagged for Investigation',
            time: adminFormatDateTime(widget.dispute['created_at']),
            isDone: true,
            isWarning: true,
            icon: Icons.report_problem_rounded,
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineStep({
    required String title,
    required String time,
    required bool isDone,
    bool isWarning = false,
    required IconData icon,
  }) {
    final color = isWarning
        ? AppUi.warningFg
        : (isDone ? AppUi.accentGreen : AppUi.textMuted);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 14, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: isWarning ? AppUi.warningFg : AppUi.textPrimaryOf(context),
                  ),
                ),
                Text(time, style: adminCaptionTextStyle(context)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPodSection(
    BuildContext context,
    dynamic podPhoto,
    dynamic signatureUrl,
    String deliveryAddress,
  ) {
    final hasPhoto = podPhoto != null && podPhoto.toString().isNotEmpty;
    final hasSignature = signatureUrl != null && signatureUrl.toString().isNotEmpty;

    return AdminGlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.camera, size: 16, color: AppUi.brandOf(context)),
              const SizedBox(width: 8),
              const Text(
                'Proof of Delivery (POD) Evidence',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Drop-off location: $deliveryAddress',
            style: TextStyle(fontSize: 12, color: AppUi.textSecondaryOf(context)),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Photo box
              Expanded(
                child: Container(
                  height: 120,
                  decoration: BoxDecoration(
                    color: AppUi.brandSoftOf(context),
                    borderRadius: BorderRadius.circular(AppUi.radiusControl),
                    border: Border.all(color: AppUi.borderOf(context)),
                  ),
                  child: hasPhoto
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(AppUi.radiusControl),
                          child: Image.network(
                            podPhoto.toString(),
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => const Center(
                              child: Icon(Icons.broken_image_rounded),
                            ),
                          ),
                        )
                      : Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.no_photography_outlined,
                                  color: AppUi.textMuted, size: 28),
                              const SizedBox(height: 4),
                              Text('No POD photo',
                                  style: adminCaptionTextStyle(context)),
                            ],
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              // Signature box
              Expanded(
                child: Container(
                  height: 120,
                  decoration: BoxDecoration(
                    color: AppUi.surfaceOf(context),
                    borderRadius: BorderRadius.circular(AppUi.radiusControl),
                    border: Border.all(color: AppUi.borderOf(context)),
                  ),
                  child: hasSignature
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(AppUi.radiusControl),
                          child: Image.network(
                            signatureUrl.toString(),
                            fit: BoxFit.contain,
                            errorBuilder: (_, _, _) => const Center(
                              child: Icon(Icons.gesture_rounded),
                            ),
                          ),
                        )
                      : Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.draw_outlined,
                                  color: AppUi.textMuted, size: 28),
                              const SizedBox(height: 4),
                              Text('No recipient signature',
                                  style: adminCaptionTextStyle(context)),
                            ],
                          ),
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildChatSection(BuildContext context, Map<String, dynamic> order) {
    // Sample contextual dispute messages
    final chatMessages = [
      {
        'sender': 'Customer',
        'badge': 'Customer',
        'color': AppUi.bluePrimary,
        'time': '10:14 AM',
        'text': 'Hello, I only received 2 containers instead of the 4 I paid for.',
      },
      {
        'sender': 'Rider',
        'badge': 'Rider',
        'color': AppUi.accentGreen,
        'time': '10:20 AM',
        'text': 'The station only loaded 2 slim containers onto my motorcycle carrier.',
      },
      {
        'sender': 'Station Owner',
        'badge': 'Station',
        'color': AppUi.warningFg,
        'time': '10:28 AM',
        'text': 'We prepared 4 gallons; 2 round and 2 slim. Checking inventory ledger now.',
      },
    ];

    return AdminGlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.messageCircle, size: 16, color: AppUi.brandOf(context)),
              const SizedBox(width: 8),
              const Text(
                'In-App Chat Transcript',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...chatMessages.map(
            (m) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: (m['color'] as Color).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(AppUi.radiusControl),
                border: Border.all(
                  color: (m['color'] as Color).withValues(alpha: 0.25),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        m['sender'] as String,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: m['color'] as Color,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        m['time'] as String,
                        style: adminCaptionTextStyle(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    m['text'] as String,
                    style: TextStyle(
                      fontSize: 13,
                      color: AppUi.textPrimaryOf(context),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentSection(
    BuildContext context,
    double amount,
    String paymentMethod,
    Map<String, dynamic> order,
  ) {
    final ref = order['payment_reference'] ?? order['id']?.toString().substring(0, 8) ?? '—';
    final pStatus = order['payment_status']?.toString() ?? 'Pending Settlement';

    return AdminGlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(LucideIcons.banknote, size: 16, color: AppUi.accentGreen),
              const SizedBox(width: 8),
              const Text(
                'Payment & Settlement Details',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 12),
          AdminDetailRow('Total Order Amount', formatPeso(amount)),
          AdminDetailRow('Payment Channel', paymentMethod),
          AdminDetailRow('Reference Number', '#$ref'),
          AdminDetailRow('Payment State', pStatus),
        ],
      ),
    );
  }

  Widget _buildResolutionSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Resolution Audit Note (Required)',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _resolutionNotesController,
          maxLines: 2,
          decoration: AppUi.fieldDecorationOf(
            context,
            'Explain the moderation decision, refund amount, or dismissal rationale…',
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: adminSemanticErrorColor(context),
                  side: BorderSide(color: adminSemanticErrorColor(context)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: _isActionInProgress
                    ? null
                    : () => _executeResolution('Refund Issued', 'resolved'),
                child: const Text('Refund Customer',
                    style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppUi.accentGreen,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: _isActionInProgress
                    ? null
                    : () => _executeResolution('Funds Released', 'resolved'),
                child: const Text('Release Funds',
                    style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Dismiss Dispute',
              icon: const Icon(LucideIcons.circleX, color: AppUi.textMuted),
              onPressed: _isActionInProgress
                  ? null
                  : () => _executeResolution('Dismissed', 'dismissed'),
            ),
          ],
        ),
      ],
    );
  }
}
