import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../utils/app_haptics.dart';

import 'package:erefill/core/constants.dart';
/// Interactive, animated timeline representing the live stages of a refill order.
class LiveOrderProgressTracker extends StatefulWidget {
  final String status;
  final String stationName;
  final String? riderName;
  final VoidCallback? onTrackMap;
  final VoidCallback? onChat;
  final VoidCallback? onCall;

  const LiveOrderProgressTracker({
    super.key,
    required this.status,
    required this.stationName,
    this.riderName,
    this.onTrackMap,
    this.onChat,
    this.onCall,
  });

  @override
  State<LiveOrderProgressTracker> createState() => _LiveOrderProgressTrackerState();
}

class _LiveOrderProgressTrackerState extends State<LiveOrderProgressTracker>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );
  late final Animation<double> _pulseAnimation = Tween<double>(
    begin: 0.92,
    end: 1.08,
  ).animate(CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut));

  static const List<_StepDef> _steps = [
    _StepDef(title: 'Placed', icon: Icons.receipt_long_rounded),
    _StepDef(title: 'Accepted', icon: Icons.thumb_up_alt_outlined),
    _StepDef(title: 'Preparing', icon: Icons.water_drop_rounded),
    _StepDef(title: 'On the Way', icon: Icons.delivery_dining_rounded),
    _StepDef(title: 'Delivered', icon: Icons.check_circle_rounded),
  ];

  int _currentStepIndex(String raw) {
    final s = OrderStatusColors.normalize(raw);
    switch (s) {
      case 'pending':
      case 'pending_sync':
        return 0;
      case 'accepted':
      case 'confirmed':
        return 1;
      case 'preparing':
        return 2;
      case 'ready':
      case 'ready_for_pickup':
      case 'out_for_delivery':
        return 3;
      case 'delivered':
      case 'completed':
        return 4;
      default:
        return 0;
    }
  }

  /// The current step pulses while the order is in progress; it stops once
  /// delivered and never runs with reduced motion.
  void _syncPulse() {
    final shouldPulse =
        !AppUi.reduceMotion(context) &&
        _currentStepIndex(widget.status) < _steps.length - 1;
    if (shouldPulse && !_pulseController.isAnimating) {
      _pulseController.repeat(reverse: true);
    } else if (!shouldPulse && _pulseController.isAnimating) {
      _pulseController
        ..stop()
        ..value = 0.5;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncPulse();
  }

  @override
  void didUpdateWidget(LiveOrderProgressTracker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_currentStepIndex(widget.status) > _currentStepIndex(oldWidget.status)) {
      AppHaptics.success();
    }
    _syncPulse();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeIndex = _currentStepIndex(widget.status);
    final statusStyle = OrderStatusStyle.resolve(widget.status, isDark: isDark);
    final isOutForDelivery = activeIndex == 3;
    final brand = AppUi.brandOf(context);
    final idle = AppUi.surfaceRaisedOf(context);
    final muted = AppUi.textMutedOf(context);
    final slow = AppUi.motion(context, AppUi.motionSlow);

    return Container(
      decoration: BoxDecoration(
        color: AppUi.surfaceOf(context),
        borderRadius: BorderRadius.circular(AppUi.radiusSheet),
        border: Border.all(color: AppUi.borderOf(context)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AnimatedContainer(
                duration: slow,
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: statusStyle.primaryColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.stationName,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppUi.textPrimaryOf(context),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              AnimatedSwitcher(
                duration: slow,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(scale: animation, child: child),
                ),
                child: Container(
                  key: ValueKey(statusStyle.label),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: statusStyle.subtleBackground,
                    borderRadius: BorderRadius.circular(AppUi.radiusFull),
                    border: Border.all(color: statusStyle.subtleBorder),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        statusStyle.icon,
                        size: 13,
                        color: statusStyle.primaryColor,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        statusStyle.label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: statusStyle.primaryColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Progress rail and steps
          LayoutBuilder(
            builder: (context, constraints) {
              return Stack(
                alignment: Alignment.center,
                children: [
                  Positioned(
                    top: 15,
                    left: 20,
                    right: 20,
                    child: Container(
                      height: 4,
                      decoration: BoxDecoration(
                        color: idle,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 15,
                    left: 20,
                    child: AnimatedContainer(
                      duration: AppUi.motion(
                        context,
                        const Duration(milliseconds: 600),
                      ),
                      curve: Curves.easeOutCubic,
                      height: 4,
                      width:
                          (constraints.maxWidth - 40) *
                          (activeIndex / (_steps.length - 1)),
                      decoration: BoxDecoration(
                        color: brand,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: List.generate(_steps.length, (i) {
                      final isPassed = i < activeIndex;
                      final isCurrent = i == activeIndex;
                      final step = _steps[i];
                      final filled = isPassed || isCurrent;

                      Widget nodeCircle = AnimatedContainer(
                        duration: slow,
                        curve: Curves.easeOut,
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: isPassed
                              ? brand
                              : isCurrent
                              ? statusStyle.primaryColor
                              : idle,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isCurrent
                                ? AppUi.surfaceOf(context)
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                        child: Center(
                          child: AnimatedSwitcher(
                            duration: slow,
                            transitionBuilder: (child, animation) =>
                                ScaleTransition(scale: animation, child: child),
                            child: Icon(
                              isPassed ? Icons.check_rounded : step.icon,
                              key: ValueKey(isPassed),
                              size: 15,
                              color: filled ? Colors.white : muted,
                            ),
                          ),
                        ),
                      );

                      if (isCurrent) {
                        nodeCircle = ScaleTransition(
                          scale: _pulseAnimation,
                          child: nodeCircle,
                        );
                      }

                      return Semantics(
                        excludeSemantics: true,
                        label:
                            '${step.title}: ${isPassed ? 'done' : isCurrent ? 'current' : 'upcoming'}',
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            nodeCircle,
                            const SizedBox(height: 6),
                            Text(
                              step.title,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: isCurrent
                                    ? FontWeight.w700
                                    : FontWeight.w600,
                                color: isCurrent
                                    ? AppUi.textPrimaryOf(context)
                                    : isPassed
                                    ? AppUi.textSecondaryOf(context)
                                    : muted,
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ),
                ],
              );
            },
          ),

          // Rider card while out for delivery
          AnimatedSize(
            duration: slow,
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: isOutForDelivery && widget.riderName != null
                ? Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: _buildRiderCard(context),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  Widget _buildRiderCard(BuildContext context) {
    final brand = AppUi.brandOf(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppUi.brandSoftOf(context),
        borderRadius: BorderRadius.circular(AppUi.radiusCard),
        border: Border.all(color: brand.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: brand, shape: BoxShape.circle),
            child: Icon(
              Icons.two_wheeler_rounded,
              color: AppUi.surfaceOf(context),
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your delivery rider',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppUi.textMutedOf(context),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  widget.riderName!,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppUi.textPrimaryOf(context),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (widget.onTrackMap != null)
            IconButton.filledTonal(
              onPressed: () {
                AppHaptics.light();
                widget.onTrackMap!();
              },
              style: IconButton.styleFrom(
                backgroundColor: brand.withValues(alpha: 0.15),
                foregroundColor: brand,
              ),
              icon: const Icon(Icons.map_rounded, size: 18),
              tooltip: 'Live Map',
            ),
          if (widget.onChat != null)
            IconButton.filledTonal(
              onPressed: () {
                AppHaptics.light();
                widget.onChat!();
              },
              style: IconButton.styleFrom(
                backgroundColor: brand.withValues(alpha: 0.15),
                foregroundColor: brand,
              ),
              icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
              tooltip: 'Message',
            ),
        ],
      ),
    );
  }
}

class _StepDef {
  final String title;
  final IconData icon;
  const _StepDef({required this.title, required this.icon});
}
