import 'package:flutter/material.dart';
import '../../constants.dart';

/// Compatibility enum retained for safe static references.
enum RefillAnimation {
  axoBob(''),
  orderSuccess(''),
  waterDrop(''),
  deliveryRider('');

  final String assetPath;
  const RefillAnimation(this.assetPath);
}

/// Static brand icon replacement used when motion-based Lottie assets are removed.
class RefillLottie extends StatelessWidget {
  final RefillAnimation animation;
  final double? width;
  final double? height;
  final bool repeat;
  final bool reverse;
  final BoxFit fit;
  final Alignment alignment;
  final AnimationController? controller;
  final void Function(Object)? onLoaded;
  final Widget? fallback;

  const RefillLottie({
    super.key,
    required this.animation,
    this.width,
    this.height,
    this.repeat = true,
    this.reverse = false,
    this.fit = BoxFit.contain,
    this.alignment = Alignment.center,
    this.controller,
    this.onLoaded,
    this.fallback,
  });

  const RefillLottie.mascot({
    super.key,
    this.width = 110,
    this.height = 110,
    this.repeat = true,
    this.fit = BoxFit.contain,
    this.fallback,
  })  : animation = RefillAnimation.axoBob,
        reverse = false,
        alignment = Alignment.center,
        controller = null,
        onLoaded = null;

  const RefillLottie.success({
    super.key,
    this.width = 120,
    this.height = 120,
    this.repeat = false,
    this.fit = BoxFit.contain,
    this.controller,
    this.onLoaded,
    this.fallback,
  })  : animation = RefillAnimation.orderSuccess,
        reverse = false,
        alignment = Alignment.center;

  const RefillLottie.waterDrop({
    super.key,
    this.width = 90,
    this.height = 90,
    this.repeat = true,
    this.fit = BoxFit.contain,
    this.fallback,
  })  : animation = RefillAnimation.waterDrop,
        reverse = false,
        alignment = Alignment.center,
        controller = null,
        onLoaded = null;

  const RefillLottie.rider({
    super.key,
    this.width = 130,
    this.height = 100,
    this.repeat = true,
    this.fit = BoxFit.contain,
    this.fallback,
  })  : animation = RefillAnimation.deliveryRider,
        reverse = false,
        alignment = Alignment.center,
        controller = null,
        onLoaded = null;

  IconData _iconForAnimation() {
    switch (animation) {
      case RefillAnimation.axoBob:
        return Icons.water_drop_rounded;
      case RefillAnimation.orderSuccess:
        return Icons.check_circle_rounded;
      case RefillAnimation.waterDrop:
        return Icons.water_drop_rounded;
      case RefillAnimation.deliveryRider:
        return Icons.delivery_dining_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final icon = _iconForAnimation();
    final resolvedFallback = fallback ??
        SizedBox(
          width: width ?? 48,
          height: height ?? 48,
          child: Center(
            child: Icon(
              icon,
              color: AppUi.brandOf(context),
              size: (width != null ? width! * 0.5 : 24),
            ),
          ),
        );

    return resolvedFallback;
  }

  static Future<void> showOrderSuccessDialog(
    BuildContext context, {
    required String orderNumber,
    required String stationName,
    required VoidCallback onTrackOrder,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return showModalBottomSheet<void>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        decoration: BoxDecoration(
          color: isDark ? AppUi.surfaceRaisedOf(context) : AppUi.surfaceOf(context),
          borderRadius: BorderRadius.circular(AppUi.radiusPill),
          border: Border.all(color: AppUi.borderOf(context)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const RefillLottie.success(width: 100, height: 100),
            const SizedBox(height: 12),
            Text(
              'Order Placed!',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppUi.textPrimaryOf(context),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Your refill order #$orderNumber has been sent to $stationName.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: AppUi.textSecondaryOf(context),
                height: 1.35,
              ),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  onTrackOrder();
                },
                style: FilledButton.styleFrom(
                  backgroundColor: AppUi.bluePrimary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppUi.radiusCard),
                  ),
                ),
                child: const Text(
                  'Track Delivery',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

