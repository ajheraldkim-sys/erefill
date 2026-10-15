import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import '../../constants.dart';

/// Available pre-bundled Lottie animations in eRefill.
enum RefillAnimation {
  axoBob('assets/animations/axo_bob.json'),
  orderSuccess('assets/animations/order_success.json'),
  waterDrop('assets/animations/water_drop.json'),
  deliveryRider('assets/animations/delivery_rider.json');

  final String assetPath;
  const RefillAnimation(this.assetPath);
}

/// Centralized, high-performance Lottie animation widget for eRefill.
///
/// Features:
/// - Fully offline-ready (uses bundled vector JSON assets in 0ms).
/// - Fallback error handling so invalid frames never crash the screen.
/// - Adaptive sizing and theme awareness.
class RefillLottie extends StatelessWidget {
  final RefillAnimation animation;
  final double? width;
  final double? height;
  final bool repeat;
  final bool reverse;
  final BoxFit fit;
  final Alignment alignment;
  final AnimationController? controller;
  final void Function(LottieComposition)? onLoaded;
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

  /// Factory constructor for the bobbing Axo mascot.
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

  /// Factory constructor for celebratory order success checkmark.
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

  /// Factory constructor for water droplet & refill animations.
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

  /// Factory constructor for out-for-delivery rider animation.
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

  @override
  Widget build(BuildContext context) {
    return Lottie.asset(
      animation.assetPath,
      width: width,
      height: height,
      repeat: repeat,
      reverse: reverse,
      fit: fit,
      alignment: alignment,
      controller: controller,
      onLoaded: onLoaded,
      errorBuilder: (context, error, stackTrace) {
        debugPrint('RefillLottie load error for ${animation.assetPath}: $error');
        return fallback ??
            SizedBox(
              width: width ?? 48,
              height: height ?? 48,
              child: Center(
                child: Icon(
                  Icons.water_drop_rounded,
                  color: AppUi.bluePrimary,
                  size: (width != null ? width! * 0.5 : 24),
                ),
              ),
            );
      },
    );
  }

  /// Displays an attractive, celebratory order confirmation sheet with Lottie.
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
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppUi.borderOf(context)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.08),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ],
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
                fontWeight: FontWeight.w900,
                color: AppUi.textPrimaryOf(context),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Your refill order #$orderNumber has been sent to $stationName.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
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
                    borderRadius: BorderRadius.circular(14),
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

