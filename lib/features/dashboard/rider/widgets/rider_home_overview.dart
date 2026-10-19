import 'dart:async';
import 'package:flutter/material.dart';
import 'package:erefill/core/widgets/brand/hero_header.dart';
import 'package:erefill/core/widgets/brand/axo_states.dart';
import 'package:erefill/core/widgets/experience_widgets.dart';
import 'package:erefill/core/widgets/refill_components.dart';
import 'package:erefill/core/widgets/refill_status_widgets.dart';
import 'package:erefill/core/widgets/notification_preview_sheet.dart';
import 'package:erefill/core/widgets/rider_active_delivery_card.dart';
import '../../../../core/constants.dart';
import 'package:erefill/core/widgets/offline_sync_status_pill.dart';
import 'package:erefill/core/routing/app_navigation.dart';
import 'package:erefill/core/utils/money.dart';

class RiderHomeOverview extends StatelessWidget {
  final Map<String, dynamic>? profile;
  final int completedCount;
  final double totalEarnings;
  final List<Map<String, dynamic>> activeOrders;
  final ValueChanged<int> onNavigate;
  final Future<void> Function()? onRefresh;
  final Future<void> Function(bool)? onToggleOnline;

  const RiderHomeOverview({
    super.key,
    required this.profile,
    required this.completedCount,
    required this.totalEarnings,
    required this.activeOrders,
    required this.onNavigate,
    this.onRefresh,
    this.onToggleOnline,
  });

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  Widget _buildOnlineStatusCard(BuildContext context, bool isOnline) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppUi.surfaceOf(context),
        borderRadius: BorderRadius.circular(AppUi.radiusSheet),
        border: Border.all(
          color: isOnline
              ? AppUi.accentGreen.withValues(alpha: 0.3)
              : AppUi.borderOf(context),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: (isOnline ? AppUi.accentGreen : Colors.black).withValues(
              alpha: 0.04,
            ),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isOnline ? AppUi.accentGreen : AppUi.textMutedOf(context),
              boxShadow: isOnline
                  ? [
                      BoxShadow(
                        color: AppUi.accentGreen.withValues(alpha: 0.4),
                        blurRadius: 6,
                        spreadRadius: 2,
                      ),
                    ]
                  : null,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isOnline ? "YOU'RE ONLINE" : "YOU'RE OFFLINE",
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: isOnline
                        ? AppUi.accentGreen
                        : AppUi.textSecondaryOf(context),
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isOnline
                      ? 'Ready to receive station deliveries'
                      : 'Switch online to accept dispatches',
                  style: AppUi.captionText,
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: isOnline,
            activeTrackColor: AppUi.accentGreen,
            onChanged: onToggleOnline != null
                ? (v) => onToggleOnline!(v)
                : null,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fullName = profile?['full_name'] ?? 'Rider';
    final firstName = fullName.split(' ').first;
    final isOnline = profile?['is_online'] == true;
    final active = activeOrders.isNotEmpty ? activeOrders.first : null;

    return Scaffold(
      backgroundColor: AppUi.pageBgOf(context),
      body: Column(
        children: [
          RiderHeroHeader(
            greeting: '$_greeting, $firstName',
            subtitle:
                '$completedCount completed · ${formatPeso(totalEarnings, whole: true)} earned',
            onNotificationTap: () => showNotificationPreviewSheet(
              context,
              onViewAll: () => context.openInbox(),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: onRefresh ?? () async {},
              color: AppUi.bluePrimary,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverPadding(
                    padding: AppUi.pagePaddingLoose.copyWith(
                      top: AppUi.spacingMd,
                    ),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        const OfflineSyncStatusPill(),
                        _buildOnlineStatusCard(context, isOnline),
                        AppUi.vGapMd,
                        if (active != null) ...[
                          RiderActiveDeliveryCard(
                            order: active,
                            onTap: () => onNavigate(1),
                          ),
                          AppUi.vGapLg,
                        ] else ...[
                          FriendlyHeroCard(
                            role: ExperienceRole.rider,
                            scene: ExperienceScene.delivery,
                            eyebrow: 'Ready mode',
                            title: 'Dispatches will land here',
                            message:
                                'When your station assigns a refill, you will see pickup, customer, and route details immediately.',
                            actionLabel: 'Open dispatch',
                            actionIcon: Icons.delivery_dining_rounded,
                            onAction: () => onNavigate(1),
                          ),
                          AppUi.vGapLg,
                        ],
                        Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: DashboardStatCard(
                                    label: 'Total earnings',
                                    value: formatPeso(
                                      totalEarnings,
                                      whole: true,
                                    ),
                                    icon: Icons.payments_rounded,
                                    color: AppUi.accentGreen,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: DashboardStatCard(
                                    label: 'Completed',
                                    value: '$completedCount',
                                    icon: Icons.check_circle_rounded,
                                    color: OrderStatusColors.getColor(
                                      'completed',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: DashboardStatCard(
                                    label: 'Active jobs',
                                    value: '${activeOrders.length}',
                                    icon: Icons.local_shipping_rounded,
                                    color: OrderStatusColors.getColor(
                                      'out_for_delivery',
                                    ),
                                    onTap: () => onNavigate(1),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: DashboardStatCard(
                                    label: 'Pending pickup',
                                    value:
                                        '${activeOrders.where((o) => o['status'] == 'assigned_to_rider').length}',
                                    icon: Icons.inventory_2_outlined,
                                    color: OrderStatusColors.getColor(
                                      'ready_for_pickup',
                                    ),
                                    onTap: () => onNavigate(1),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        AppUi.vGapLg,
                        AxoTipCard(
                          title: 'Deliver fast, earn more',
                          message:
                              'Quick deliveries and proof-of-delivery photos help you get priority jobs from your station.',
                          trailingIcon: Icons.bolt_rounded,
                        ),
                      ]),
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
}

/// Interactive swipe-to-accept slider for riders with haptic feedback
