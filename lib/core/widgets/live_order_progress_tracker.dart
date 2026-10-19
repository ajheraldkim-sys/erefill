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
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

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

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.85, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
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

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF132029) : Colors.white,
        borderRadius: BorderRadius.circular(AppUi.radiusSheet),
        border: Border.all(
          color: isDark ? AppColors.borderDark : AppUi.borderLight,
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.05),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with live pulse badge
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: statusStyle.primaryColor,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: statusStyle.primaryColor.withValues(alpha: 0.5),
                            blurRadius: 6,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        widget.stationName,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.white : AppUi.textPrimary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusStyle.subtleBackground,
                  borderRadius: BorderRadius.circular(AppUi.radiusSheet),
                  border: Border.all(color: statusStyle.subtleBorder, width: 1),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(statusStyle.icon, size: 13, color: statusStyle.primaryColor),
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
            ],
          ),

          const SizedBox(height: 16),

          // Animated Progress Bar & Steps
          LayoutBuilder(
            builder: (context, constraints) {
              return Stack(
                alignment: Alignment.center,
                children: [
                  // Background rail line
                  Positioned(
                    top: 15,
                    left: 20,
                    right: 20,
                    child: Container(
                      height: 4,
                      decoration: BoxDecoration(
                        color: isDark ? AppUi.darkSurfaceRaised : AppUi.borderLight,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),

                  // Active filled rail line
                  Positioned(
                    top: 15,
                    left: 20,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 600),
                      curve: Curves.easeOutCubic,
                      height: 4,
                      width: (constraints.maxWidth - 40) * (activeIndex / (_steps.length - 1)),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [AppColors.brandPrimary, AppColors.statusReady],
                        ),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),

                  // Step nodes
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: List.generate(_steps.length, (i) {
                      final isPassed = i < activeIndex;
                      final isCurrent = i == activeIndex;
                      final step = _steps[i];

                      Widget nodeCircle = Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: isPassed
                              ? AppColors.brandPrimary
                              : isCurrent
                                  ? statusStyle.primaryColor
                                  : (isDark ? AppUi.darkSurfaceRaised : AppUi.borderLight),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isCurrent ? Colors.white : Colors.transparent,
                            width: 2,
                          ),
                          boxShadow: isCurrent
                              ? [
                                  BoxShadow(
                                    color: statusStyle.primaryColor.withValues(alpha: 0.4),
                                    blurRadius: 8,
                                    spreadRadius: 2,
                                  ),
                                ]
                              : null,
                        ),
                        child: Center(
                          child: Icon(
                            isPassed ? Icons.check_rounded : step.icon,
                            size: 15,
                            color: (isPassed || isCurrent)
                                ? Colors.white
                                : (isDark ? AppUi.textMuted : const Color(0xFF94A3B8)),
                          ),
                        ),
                      );

                      if (isCurrent) {
                        nodeCircle = ScaleTransition(
                          scale: _pulseAnimation,
                          child: nodeCircle,
                        );
                      }

                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          nodeCircle,
                          const SizedBox(height: 6),
                          Text(
                            step.title,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w600,
                              color: isCurrent
                                  ? (isDark ? Colors.white : AppColors.brandPrimary)
                                  : isPassed
                                      ? (isDark ? AppUi.darkTextSecondary : AppUi.textMuted)
                                      : (isDark ? AppUi.textSecondary : const Color(0xFF94A3B8)),
                            ),
                          ),
                        ],
                      );
                    }),
                  ),
                ],
              );
            },
          ),

          // Out for Delivery interactive actions card
          if (isOutForDelivery && widget.riderName != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1A2C38) : AppColors.brandSoft,
                borderRadius: BorderRadius.circular(AppUi.radiusCard),
                border: Border.all(
                  color: AppColors.brandPrimary.withValues(alpha: 0.25),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: const BoxDecoration(
                      color: AppColors.brandPrimary,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.two_wheeler_rounded, color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Your Delivery Rider',
                          style: TextStyle(fontSize: 11, color: AppUi.textMutedOf(context), fontWeight: FontWeight.w600),
                        ),
                        Text(
                          widget.riderName!,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white : AppUi.textPrimary,
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
                        backgroundColor: AppColors.brandPrimary.withValues(alpha: 0.15),
                        foregroundColor: AppUi.brandOf(context),
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
                        backgroundColor: AppColors.brandPrimary.withValues(alpha: 0.15),
                        foregroundColor: AppUi.brandOf(context),
                      ),
                      icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
                      tooltip: 'Message',
                    ),
                ],
              ),
            ),
          ],
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

