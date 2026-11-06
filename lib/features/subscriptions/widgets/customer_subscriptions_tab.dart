import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants.dart';
import '../models/subscription_model.dart';
import '../services/subscription_service.dart';

import 'package:erefill/core/theme/app_colors.dart';
import 'package:erefill/core/utils/money.dart';
import 'package:erefill/core/utils/friendly_errors.dart';
import 'package:erefill/core/routing/app_navigation.dart';

class CustomerSubscriptionsTab extends StatefulWidget {
  final VoidCallback? onBrowseStations;
  const CustomerSubscriptionsTab({super.key, this.onBrowseStations});

  @override
  State<CustomerSubscriptionsTab> createState() =>
      _CustomerSubscriptionsTabState();
}

class _CustomerSubscriptionsTabState extends State<CustomerSubscriptionsTab> {
  final SubscriptionService _service = SubscriptionService();
  List<CustomerSubscription> _subscriptions = [];
  bool _isLoading = true;
  bool _isProcessingDue = false;

  bool get _hasDueSubscriptions => _subscriptions.any(
    (s) =>
        s.isActive &&
        s.nextDeliveryDate.isBefore(
          DateTime.now().add(const Duration(hours: 12)),
        ),
  );

  @override
  void initState() {
    super.initState();
    _loadSubscriptions();
  }

  Future<void> _loadSubscriptions() async {
    final customerId = Supabase.instance.client.auth.currentUser?.id;
    if (customerId == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    final list = await _service.getCustomerSubscriptions(customerId);
    if (mounted) {
      setState(() {
        _subscriptions = list;
        _isLoading = false;
      });
    }
  }

  Future<void> _processDueNow() async {
    final customerId = Supabase.instance.client.auth.currentUser?.id;
    if (customerId == null) return;

    setState(() => _isProcessingDue = true);
    try {
      final result = await _service.processDueSubscriptions(
        customerId: customerId,
      );
      if (mounted) {
        if (result.skipped.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                result.skipped.length == 1
                    ? 'An auto-refill was not placed: ${result.skipped.single.message}. It will retry automatically.'
                    : '${result.skipped.length} auto-refills were not placed because the station could not accept them. They will retry automatically.',
              ),
              backgroundColor: AppColors.uiWarning,
            ),
          );
        } else if (result.created.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Created ${result.created.length} auto-refill order(s) successfully!',
              ),
              backgroundColor: AppColors.uiSuccess,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('All subscriptions are up to date.')),
          );
        }
      }
      await _loadSubscriptions();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to process subscriptions: ${FriendlyErrors.message(e)}',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessingDue = false);
    }
  }

  void _showActionError(String action, Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Could not $action this routine: ${FriendlyErrors.message(error)}',
        ),
        backgroundColor: AppColors.uiError,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      color: AppUi.bluePrimary,
      onRefresh: _loadSubscriptions,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        children: [
          // Banner introducing Auto-Refill
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppUi.bluePrimary,
              borderRadius: BorderRadius.circular(AppUi.radiusSheet),
              boxShadow: [
                BoxShadow(
                  color: AppUi.bluePrimary.withValues(alpha: 0.25),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.autorenew_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Scheduled Auto-Refill',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Never run out of clean drinking water. Set a refill routine once, and stations will deliver automatically.',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Add subscription button
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: () => context.openStationList(),
              icon: const Icon(Icons.add_task_rounded, size: 20),
              label: const Text('Pick a station to schedule'),
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
          if (_hasDueSubscriptions) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppUi.warningBg,
                borderRadius: BorderRadius.circular(AppUi.radiusCard),
                border: Border.all(color: AppColors.uiWarning),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.alarm_on_rounded,
                    color: AppColors.uiWarning,
                    size: 26,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          'Refill Routine Due Today!',
                          style: TextStyle(
                            color: AppUi.warningFg,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Tap below to immediately trigger your scheduled orders.',
                          style: TextStyle(
                            color: AppColors.uiWarning,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _isProcessingDue ? null : _processDueNow,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.uiWarning,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: _isProcessingDue
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'Order Now',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 20),

          // Active Subscriptions
          if (_subscriptions.isEmpty)
            Container(
              padding: const EdgeInsets.all(36),
              decoration: BoxDecoration(
                color: AppUi.surfaceOf(context),
                borderRadius: BorderRadius.circular(AppUi.radiusSheet),
                border: Border.all(color: AppUi.borderOf(context)),
              ),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.event_repeat_rounded,
                      size: 48,
                      color: AppUi.textMutedOf(context).withValues(alpha: 0.6),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'No scheduled refills yet',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Tap "Schedule New Auto-Refill" to automate your home or office water delivery.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppUi.textSecondaryOf(context),
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            ..._subscriptions.map(_buildSubscriptionCard),
        ],
      ),
    );
  }

  Widget _buildSubscriptionCard(CustomerSubscription sub) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppUi.surfaceOf(context),
        borderRadius: BorderRadius.circular(AppUi.radiusCard),
        border: Border.all(
          color: sub.isActive
              ? AppUi.bluePrimary.withValues(alpha: 0.3)
              : AppUi.borderOf(context),
          width: sub.isActive ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      sub.stationName,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${sub.quantity}x ${sub.waterType} · ${formatPeso(sub.estimatedPrice)}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppUi.brandOf(context),
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: sub.isActive,
                activeThumbColor: AppUi.bluePrimary,
                onChanged: (val) async {
                  try {
                    await _service.toggleSubscription(
                      subscriptionId: sub.id,
                      customerId: sub.customerId,
                      isActive: val,
                    );
                  } catch (e) {
                    _showActionError(val ? 'resume' : 'pause', e);
                  }
                  _loadSubscriptions();
                },
              ),
            ],
          ),
          const Divider(height: 18),
          Row(
            children: [
              Icon(
                Icons.repeat_rounded,
                size: 16,
                color: AppUi.textMutedOf(context),
              ),
              const SizedBox(width: 6),
              Text(
                CustomerSubscription.formatFrequencyLabel(sub.frequency),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Icon(
                Icons.schedule_rounded,
                size: 16,
                color: AppUi.textMutedOf(context),
              ),
              const SizedBox(width: 6),
              Text(
                sub.preferredTimeSlot.toUpperCase(),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppUi.textMutedOf(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: sub.isActive
                  ? AppColors.uiSuccess.withValues(alpha: 0.1)
                  : Colors.grey.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppUi.radiusControl),
            ),
            child: Row(
              children: [
                Icon(
                  sub.isActive
                      ? Icons.check_circle_outline_rounded
                      : Icons.pause_circle_outline_rounded,
                  size: 14,
                  color: sub.isActive ? AppColors.uiSuccess : Colors.grey,
                ),
                const SizedBox(width: 6),
                Text(
                  sub.isActive
                      ? 'Next Delivery: ${_formatDate(sub.nextDeliveryDate)}'
                      : 'Schedule Paused',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: sub.isActive
                        ? AppColors.uiSuccess
                        : Colors.grey.shade600,
                  ),
                ),
                const Spacer(),
                InkWell(
                  onTap: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        backgroundColor: AppUi.surfaceOf(context),
                        title: const Text('Cancel Schedule?'),
                        content: const Text(
                          'Are you sure you want to cancel this recurring auto-refill?',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Keep'),
                          ),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.uiError,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('Cancel Schedule'),
                          ),
                        ],
                      ),
                    );

                    if (confirmed == true) {
                      try {
                        await _service.deleteSubscription(
                          subscriptionId: sub.id,
                          customerId: sub.customerId,
                        );
                      } catch (e) {
                        _showActionError('cancel', e);
                      }
                      _loadSubscriptions();
                    }
                  },
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Text(
                      'Cancel',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.uiError,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  String _formatDate(DateTime dt) {
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }
}
