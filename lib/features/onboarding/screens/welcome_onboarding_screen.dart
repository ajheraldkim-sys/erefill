import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:erefill/core/constants.dart';
import 'package:erefill/core/utils/app_haptics.dart';
import 'package:erefill/core/widgets/brand/erefill_logo.dart';

class WelcomeOnboardingScreen extends StatelessWidget {
  final VoidCallback onFinish;
  const WelcomeOnboardingScreen({super.key, required this.onFinish});

  Future<void> _finishOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_complete', true);
    onFinish();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
      ),
      child: Scaffold(
        backgroundColor: AppUi.darkPageBg,
        body: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              'assets/images/onboarding_bg.png',
              fit: BoxFit.cover,
              alignment: Alignment.center,
              errorBuilder: (context, error, stackTrace) => const ColoredBox(
                color: AppUi.darkPageBg,
              ),
            ),
            // Flat scrim (surfaces stay gradient-free, see MASTER.md): dark
            // enough for legible text, light enough to keep the photo.
            ColoredBox(color: AppUi.darkPageBg.withValues(alpha: 0.85)),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppUi.spacingXl,
                  vertical: AppUi.spacingLg,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top header with official eRefill logo and accessible Skip button
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const ERefillLogo(
                          size: 34,
                          showTagline: false,
                          color: Colors.white,
                        ),
                        TextButton(
                          onPressed: () {
                            AppHaptics.light();
                            _finishOnboarding();
                          },
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white70,
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppUi.spacingMd,
                              vertical: AppUi.spacingSm,
                            ),
                          ),
                          child: const Text(
                            'Skip',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Spacer(flex: 2),

                    // Geographic & Operational badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppUi.spacingMd,
                        vertical: 6.0,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(AppUi.radiusFull),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.16),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.location_on_rounded,
                            size: 14,
                            color: AppUi.accentCyan,
                          ),
                          const SizedBox(width: AppUi.spacingSm),
                          Text(
                            'Cantilan & Madrid, Surigao del Sur',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.92),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppUi.spacingLg),

                    // Authentic domain-specific headline
                    const Text(
                      'Clean Water,\nRight to Your Door',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 40,
                        fontWeight: FontWeight.w700,
                        height: 1.1,
                        letterSpacing: -1.0,
                      ),
                    ),
                    const SizedBox(height: AppUi.spacingMd),

                    // Clear value proposition
                    const Text(
                      'Order refills from certified stations with live delivery tracking and convenient gallon swaps.',
                      style: TextStyle(
                        color: AppUi.borderLight,
                        fontSize: 15,
                        fontWeight: FontWeight.w400,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: AppUi.spacingXl),

                    // Operational feature chips
                    const Wrap(
                      spacing: AppUi.spacingSm,
                      runSpacing: AppUi.spacingSm,
                      children: [
                        _ValueChip(
                          icon: Icons.verified_outlined,
                          label: 'Certified Stations',
                        ),
                        _ValueChip(
                          icon: Icons.two_wheeler_rounded,
                          label: 'Local Delivery Riders',
                        ),
                        _ValueChip(
                          icon: Icons.swap_horiz_rounded,
                          label: 'Gallon Swaps',
                        ),
                      ],
                    ),

                    const Spacer(flex: 3),

                    // Accessible dual-interaction start button (swipe or tap)
                    SwipeToStartButton(onSwipe: _finishOnboarding),
                    const SizedBox(height: AppUi.spacingSm),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ValueChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _ValueChip({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10.0,
        vertical: 6.0,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppUi.radiusControl),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.12),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: AppUi.accentCyan,
          ),
          const SizedBox(width: 6.0),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class SwipeToStartButton extends StatefulWidget {
  final VoidCallback onSwipe;
  const SwipeToStartButton({super.key, required this.onSwipe});

  @override
  State<SwipeToStartButton> createState() => _SwipeToStartButtonState();
}

class _SwipeToStartButtonState extends State<SwipeToStartButton> {
  double _dragPosition = 0.0;
  bool _isDragging = false;
  bool _isActivated = false;

  void _triggerStart() {
    if (_isActivated) return;
    setState(() => _isActivated = true);
    AppHaptics.success();
    widget.onSwipe();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = AppUi.reduceMotion(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final trackWidth = constraints.maxWidth;
        const thumbSize = 56.0; // Ergonomic 56dp touch target
        final maxDrag = (trackWidth - thumbSize - 8.0).clamp(0.0, trackWidth);

        return Semantics(
          button: true,
          label: 'Get started and enter eRefill',
          onTap: _triggerStart,
          child: GestureDetector(
            onTap: _triggerStart,
            behavior: HitTestBehavior.opaque,
            child: Container(
              height: thumbSize + 8.0,
              padding: const EdgeInsets.all(4.0),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(AppUi.radiusFull),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.20),
                ),
              ),
              child: Stack(
                children: [
                  // Progress fill
                  AnimatedContainer(
                    duration: _isDragging || reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 250),
                    curve: Curves.easeOutCubic,
                    width: _isActivated
                        ? trackWidth
                        : (_dragPosition + thumbSize).clamp(0.0, trackWidth),
                    height: thumbSize,
                    decoration: BoxDecoration(
                      color: AppUi.bluePrimary.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(AppUi.radiusFull),
                    ),
                  ),

                  // Center guidance label
                  Center(
                    child: AnimatedOpacity(
                      opacity: (_dragPosition > 40 || _isActivated) ? 0.0 : 1.0,
                      duration: reduceMotion
                          ? Duration.zero
                          : const Duration(milliseconds: 180),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'Swipe or Tap to Start',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.3,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(
                            Icons.keyboard_arrow_right_rounded,
                            size: 18,
                            color: Colors.white.withValues(alpha: 0.7),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Draggable Thumb
                  AnimatedPositioned(
                    duration: _isDragging || reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 250),
                    curve: Curves.easeOutCubic,
                    left: _isActivated ? maxDrag : _dragPosition,
                    top: 0,
                    bottom: 0,
                    child: GestureDetector(
                      onHorizontalDragStart: (details) {
                        if (_isActivated) return;
                        setState(() => _isDragging = true);
                        AppHaptics.light();
                      },
                      onHorizontalDragUpdate: (details) {
                        if (_isActivated) return;
                        setState(() {
                          _dragPosition += details.delta.dx;
                          if (_dragPosition < 0) _dragPosition = 0;
                          if (_dragPosition > maxDrag) _dragPosition = maxDrag;
                        });
                      },
                      onHorizontalDragEnd: (details) {
                        if (_isActivated) return;
                        setState(() => _isDragging = false);
                        if (_dragPosition > maxDrag * 0.65) {
                          _triggerStart();
                        } else {
                          setState(() => _dragPosition = 0.0);
                        }
                      },
                      child: Container(
                        width: thumbSize,
                        height: thumbSize,
                        decoration: BoxDecoration(
                          color: AppUi.accentCyan,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: AppUi.accentCyan.withValues(alpha: 0.35),
                              blurRadius: 10,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.arrow_forward_rounded,
                          color: Color(0xFF0F172A),
                          size: 22,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
