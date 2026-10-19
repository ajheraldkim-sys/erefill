import 'package:flutter/material.dart';

import '../constants.dart';
import '../theme/app_colors.dart';
import '../water_types.dart';
import 'order_card.dart';

import 'package:erefill/core/utils/money.dart';
export '../theme/app_colors.dart';
export 'order_card.dart';

class OrderStatusPresentation {
  final String label;
  final Color color;
  final IconData icon;

  const OrderStatusPresentation({
    required this.label,
    required this.color,
    required this.icon,
  });

  /// Delegates to [OrderStatusColors] so labels, colors and icons are
  /// identical in every role.
  static OrderStatusPresentation fromStatus(String? status) {
    return OrderStatusPresentation(
      label: OrderStatusColors.getLabel(status),
      color: OrderStatusColors.getColor(status),
      icon: OrderStatusColors.getIcon(status),
    );
  }
}

class OrderStatusBadge extends StatelessWidget {
  final String? status;
  final bool showIcon;
  final bool uppercase;

  const OrderStatusBadge({
    super.key,
    required this.status,
    this.showIcon = true,
    this.uppercase = false,
  });

  @override
  Widget build(BuildContext context) {
    return OrderStatusChip(
      status: status,
      showIcon: showIcon,
      uppercase: uppercase,
    );
  }
}

class AvailabilityPresentation {
  final String label;
  final Color color;

  const AvailabilityPresentation({required this.label, required this.color});

  static AvailabilityPresentation fromAvailability(String? availability) {
    switch ((availability ?? 'closed').toLowerCase()) {
      case 'open':
        return const AvailabilityPresentation(
          label: 'Open',
          color: AppColors.uiSuccess,
        );
      case 'busy':
        return const AvailabilityPresentation(
          label: 'Busy',
          color: AppColors.uiWarning,
        );
      case 'maintenance':
        return const AvailabilityPresentation(
          label: 'Maintenance',
          color: AppColors.uiError,
        );
      default:
        return const AvailabilityPresentation(
          label: 'Closed',
          color: AppUi.textSecondary, // fixed-light: status tone, rendered on its own tint
        );
    }
  }
}

class AvailabilityBadge extends StatelessWidget {
  final String? availability;
  final bool compact;

  const AvailabilityBadge({
    super.key,
    required this.availability,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final state = AvailabilityPresentation.fromAvailability(availability);
    final key = state.label.toLowerCase();
    final (tone, iconData) = switch (key) {
      'open' => (StatusTone.success, Icons.check_circle_rounded),
      'busy' => (StatusTone.warning, Icons.access_time_filled_rounded),
      'maintenance' => (StatusTone.danger, Icons.build_circle_rounded),
      _ => (StatusTone.neutral, Icons.remove_circle_outline_rounded),
    };
    final style = StatusToneStyle.of(tone, isDark: AppUi.isDark(context));

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: style.background,
        borderRadius: AppUi.fullRadius,
        border: Border.all(color: style.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(iconData, size: compact ? 12 : 14, color: style.foreground),
          const SizedBox(width: 4),
          Text(
            state.label,
            style: TextStyle(
              fontSize: compact ? 11 : 12,
              color: style.foreground,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class DashboardMetricCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const DashboardMetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppUi.cardDecorationOf(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppUi.radiusCard),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppUi.textPrimaryOf(context),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppUi.textSecondaryOf(context),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class WaterTypeCard extends StatelessWidget {
  final WaterTypeInfo type;
  final String? description;
  final double? price;
  final String? containerSize;
  final int? preparationMinutes;
  final bool selected;
  final bool available;
  final bool compact;
  final VoidCallback? onTap;

  const WaterTypeCard({
    super.key,
    required this.type,
    this.description,
    this.price,
    this.containerSize,
    this.preparationMinutes,
    this.selected = false,
    this.available = true,
    this.compact = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final content = Container(
      width: compact ? 196 : double.infinity,
      margin: compact ? EdgeInsets.zero : const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: selected ? AppUi.brandSoftOf(context) : AppUi.surfaceOf(context),
        borderRadius: AppUi.cardRadius,
        border: Border.all(
          color: selected ? AppUi.bluePrimary : AppUi.borderOf(context),
          width: selected ? 2 : 1,
        ),
      ),
      child: compact ? _compactContent(context) : _fullContent(context),
    );

    if (onTap == null) {
      return content;
    }

    return InkWell(
      onTap: available ? onTap : null,
      borderRadius: AppUi.cardRadius,
      child: content,
    );
  }

  Widget _compactContent(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: type.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppUi.radiusControl),
              ),
              child: Icon(type.icon, size: 16, color: type.color),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                type.shortName,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: AppUi.textPrimaryOf(context),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        _TypeBadge(label: type.badge, color: type.color),
        const SizedBox(height: 6),
        Text(
          type.tagline,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppUi.textPrimaryOf(context),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          description ?? type.description,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11,
            height: 1.25,
            color: AppUi.textSecondaryOf(context),
          ),
        ),
      ],
    );
  }

  Widget _fullContent(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: type.color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(AppUi.radiusCard),
              ),
              child: Icon(type.icon, color: type.color, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          type.name,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                            color: selected
                                ? AppUi.brandOf(context)
                                : AppUi.textPrimaryOf(context),
                          ),
                        ),
                      ),
                      _TypeBadge(label: type.badge, color: type.color),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    type.tagline,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppUi.accentTextOf(context, type.color),
                    ),
                  ),
                ],
              ),
            ),
            if (price != null) ...[
              const SizedBox(width: 8),
              Text(
                formatPeso(price!, whole: true),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppUi.brandOf(context),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        Text(
          description ?? type.description,
          style: TextStyle(
            fontSize: 12,
            color: AppUi.textSecondaryOf(context),
            fontWeight: FontWeight.w500,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: type.benefits
              .map(
                (b) => Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.check_rounded,
                      size: 12,
                      color: AppUi.textSecondaryOf(context),
                    ),
                    const SizedBox(width: 2),
                    Text(
                      b,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppUi.textSecondaryOf(context),
                      ),
                    ),
                  ],
                ),
              )
              .toList(),
        ),
        if (containerSize != null || preparationMinutes != null) ...[
          const SizedBox(height: 8),
          Text(
            [
              ?containerSize,
              if (preparationMinutes != null)
                'Ready in ~$preparationMinutes min',
            ].join(' · '),
            style: TextStyle(
              fontSize: 11,
              color: AppUi.textMutedOf(context),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ],
    );
  }
}

class _TypeBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _TypeBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: AppUi.pillRadius,
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppUi.accentTextOf(
            context,
            color,
            background: Color.alphaBlend(
              color.withValues(alpha: 0.12),
              AppUi.surfaceOf(context),
            ),
          ),
        ),
      ),
    );
  }
}

class RefillOrderStatusTimeline extends StatelessWidget {
  final String status;

  const RefillOrderStatusTimeline({super.key, required this.status});

  static const _stages = [
    _TimelineStage(
      status: 'pending',
      title: 'Pending',
      subtitle: 'The station has received your refill request.',
      icon: Icons.receipt_long_rounded,
    ),
    _TimelineStage(
      status: 'accepted',
      title: 'Accepted',
      subtitle: 'The station confirmed your order.',
      icon: Icons.check_circle_rounded,
    ),
    _TimelineStage(
      status: 'preparing',
      title: 'Preparing',
      subtitle: 'Your selected water refill is being prepared.',
      icon: Icons.water_drop_rounded,
    ),
    _TimelineStage(
      status: 'ready_for_pickup',
      title: 'Ready for Pickup',
      subtitle: 'Your gallons are ready at the station.',
      icon: Icons.inventory_2_outlined,
    ),
    _TimelineStage(
      status: 'assigned_to_rider',
      title: 'Assigned to Rider',
      subtitle: 'A rider will collect and deliver your water.',
      icon: Icons.person_pin_circle_outlined,
    ),
    _TimelineStage(
      status: 'out_for_delivery',
      title: 'Out for Delivery',
      subtitle: 'Rider is heading to your location.',
      icon: Icons.delivery_dining_rounded,
    ),
    _TimelineStage(
      status: 'delivered',
      title: 'Delivered',
      subtitle: 'Enjoy your fresh water!',
      icon: Icons.celebration_rounded,
    ),
  ];

  static int statusIndex(String status) {
    final raw = status.trim().toLowerCase().replaceAll('-', '_');
    // Keep the rider-assigned step distinct; everything else uses the
    // canonical normalizer so synonyms (completed, confirmed, in_prep,
    // dispatched, …) never fall through to "Cancelled".
    final normalized = switch (raw) {
      'assigned_to_rider' || 'rider_assigned' => 'assigned_to_rider',
      _ =>
        OrderStatusColors.normalize(raw) == 'pending_sync'
            ? 'pending'
            : (OrderStatusColors.normalize(raw) == 'ready'
                  ? 'ready_for_pickup'
                  : OrderStatusColors.normalize(raw)),
    };
    return _stages.indexWhere((stage) => stage.status == normalized);
  }

  @override
  Widget build(BuildContext context) {
    final currentIndex = statusIndex(status);
    final progressIndex = currentIndex < 0
        ? -1
        : currentIndex <= 1
        ? 0
        : currentIndex < 3
        ? 1
        : currentIndex < 6
        ? 2
        : 3;
    final isRejected = OrderStatusColors.normalize(status) == 'rejected';
    final stage = currentIndex >= 0
        ? _stages[currentIndex]
        : isRejected
        ? const _TimelineStage(
            status: 'rejected',
            title: 'Declined',
            subtitle: 'The station could not take this order.',
            icon: Icons.block_rounded,
          )
        : const _TimelineStage(
            status: 'cancelled',
            title: 'Cancelled',
            subtitle: 'This order has been cancelled.',
            icon: Icons.cancel_outlined,
          );
    final milestones = [
      (label: 'Order', icon: Icons.receipt_long_rounded),
      (label: 'Preparing', icon: Icons.water_drop_rounded),
      (label: 'On the way', icon: Icons.delivery_dining_rounded),
      (label: 'Delivered', icon: Icons.check_rounded),
    ];

    final statusColor = OrderStatusColors.getColor(status);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppUi.surfaceOf(context),
        borderRadius: BorderRadius.circular(AppUi.radiusSheet),
        border: Border.all(color: AppUi.dividerOf(context)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final content = Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppUi.radiusCard),
                    ),
                    child: Icon(stage.icon, color: statusColor, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          stage.title,
                          style: TextStyle(
                            color: AppUi.textPrimaryOf(context),
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          stage.subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppUi.textSecondaryOf(context),
                            fontSize: 11,
                            height: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  for (var i = 0; i < milestones.length; i++) ...[
                    // Labels get 3x the width of the connectors so
                    // "Preparing" / "On the way" never truncate on phones.
                    Expanded(
                      flex: 3,
                      child: _ProgressMilestone(
                        label: milestones[i].label,
                        icon: milestones[i].icon,
                        isComplete: i < progressIndex,
                        isCurrent: i == progressIndex,
                        statusColor: statusColor,
                      ),
                    ),
                    if (i < milestones.length - 1)
                      Expanded(
                        flex: 1,
                        child: Container(
                          height: 3,
                          margin: const EdgeInsets.only(bottom: 20),
                          decoration: BoxDecoration(
                            color: i < progressIndex
                                ? statusColor
                                : AppUi.dividerOf(context),
                            borderRadius: BorderRadius.circular(
                              AppUi.radiusFull,
                            ),
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ],
          );

          if (constraints.hasBoundedHeight && constraints.maxHeight < 120) {
            return SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              child: content,
            );
          }
          return content;
        },
      ),
    );
  }
}

class _ProgressMilestone extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isComplete;
  final bool isCurrent;
  final Color statusColor;

  const _ProgressMilestone({
    required this.label,
    required this.icon,
    required this.isComplete,
    required this.isCurrent,
    this.statusColor = AppUi.bluePrimary,
  });

  @override
  Widget build(BuildContext context) {
    final isReached = isComplete || isCurrent;
    return Column(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: isReached ? statusColor : AppUi.surfaceOf(context),
            shape: BoxShape.circle,
            border: Border.all(
              color: isReached ? statusColor : AppUi.dividerOf(context),
              width: 2,
            ),
          ),
          child: Icon(
            isComplete ? Icons.check_rounded : icon,
            color: isReached ? Colors.white : AppUi.textMutedOf(context),
            size: 15,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: isCurrent ? statusColor : AppUi.textSecondaryOf(context),
            fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w600,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}

class _TimelineStage {
  final String status;
  final String title;
  final String subtitle;
  final IconData icon;

  const _TimelineStage({
    required this.status,
    required this.title,
    required this.subtitle,
    required this.icon,
  });
}
