import 'package:flutter/material.dart';

import '../../constants.dart';
import '../experience_widgets.dart';
import '../skeleton.dart';
import 'refill_lottie.dart';

enum AxoPose { wave, happy, thinking, delivery, empty, success }

/// Empty, loading, and success state widgets used across the app.
class EmptyStateCard extends StatelessWidget {
  final AxoPose pose;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool compact;

  const EmptyStateCard({
    super.key,
    this.pose = AxoPose.empty,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final axoSize = compact ? 80.0 : 110.0;
    return Padding(
      padding: EdgeInsets.all(compact ? AppUi.spacingLg : AppUi.spacing2xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: compact ? 140 : 190,
            child: Stack(
              alignment: Alignment.center,
              children: [
                ExperienceIllustration(
                  scene: pose == AxoPose.success
                      ? ExperienceScene.success
                      : ExperienceScene.empty,
                  height: compact ? 94 : 126,
                ),
                if (pose == AxoPose.success)
                  RefillLottie.success(width: axoSize, height: axoSize)
                else if (pose == AxoPose.delivery)
                  RefillLottie.rider(width: axoSize * 1.2, height: axoSize)
                else
                  RefillLottie.mascot(width: axoSize, height: axoSize),
              ],
            ),
          ),
          SizedBox(height: compact ? 12 : 20),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 20),
            SizedBox(
              height: 48,
              child: ElevatedButton(
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class LoadingStateCard extends StatelessWidget {
  final String? message;

  const LoadingStateCard({super.key, this.message});

  @override
  Widget build(BuildContext context) {
    return SkeletonList(
      itemCount: 6,
      itemDelegate: (context, index) => const Padding(
        padding: EdgeInsets.only(bottom: 12),
        child: CardSkeleton(),
      ),
    );
  }
}

class QuickTipCard extends StatelessWidget {
  final String title;
  final String message;
  final VoidCallback? onTap;
  final IconData? trailingIcon;

  const QuickTipCard({
    super.key,
    required this.title,
    required this.message,
    this.onTap,
    this.trailingIcon,
  });

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      child: Material(
        color: AppUi.surfaceOf(context),
        borderRadius: BorderRadius.circular(AppUi.radiusCard),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: AppUi.cardDecorationOf(
            context,
            borderColor: AppUi.bluePrimary.withValues(alpha: 0.12),
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppUi.brandSoftOf(context),
                ),
                child: Icon(
                  Icons.water_drop_rounded,
                  color: AppUi.brandOf(context),
                  size: 26,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Quick tip',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppUi.brandOf(context),
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      title,
                      style: AppUi.sectionTitle.copyWith(fontSize: 13),
                    ),
                    const SizedBox(height: 2),
                    Text(message, style: AppUi.captionText),
                  ],
                ),
              ),
              if (trailingIcon != null)
                Icon(trailingIcon, color: AppUi.brandOf(context), size: 22),
            ],
          ),
        ),
      ),
    );
  }
}

@Deprecated('Use EmptyStateCard instead')
typedef AxoEmptyState = EmptyStateCard;

@Deprecated('Use LoadingStateCard instead')
typedef AxoLoader = LoadingStateCard;

@Deprecated('Use QuickTipCard instead')
typedef AxoTipCard = QuickTipCard;
