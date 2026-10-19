import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:erefill/core/constants.dart';
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
        backgroundColor: const Color(0xFF0A0F1A),
        body: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              'assets/images/onboarding_bg.png',
              fit: BoxFit.cover,
              alignment: Alignment.center,
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    const Color(0xFF0A0F1A).withValues(alpha: 0.6),
                    Colors.transparent,
                    Colors.transparent,
                    const Color(0xFF0A0F1A).withValues(alpha: 0.8),
                  ],
                  stops: const [0.0, 0.2, 0.7, 1.0],
                ),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'eRefill',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 36),
                    const Text(
                      'Order Refills\nin 1-Click',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 48,
                        fontWeight: FontWeight.w700,
                        height: 1.05,
                        letterSpacing: -1.5,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Pristine purified water, right to\nyour doorstep.',
                      style: TextStyle(
                        color: AppUi.borderLight,
                        fontSize: 16,
                        fontWeight: FontWeight.w400,
                        height: 1.4,
                      ),
                    ),
                    const Spacer(),
                    SwipeToStartButton(onSwipe: _finishOnboarding),
                    const SizedBox(height: 16),
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

class SwipeToStartButton extends StatefulWidget {
  final VoidCallback onSwipe;
  const SwipeToStartButton({super.key, required this.onSwipe});

  @override
  State<SwipeToStartButton> createState() => _SwipeToStartButtonState();
}

class _SwipeToStartButtonState extends State<SwipeToStartButton> {
  double _dragPosition = 0.0;
  bool _isDragging = false;
  bool _isSwiped = false;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final trackWidth = constraints.maxWidth;
        const thumbSize = 64.0;
        final maxDrag = trackWidth - thumbSize - 8.0;

        return Container(
          height: thumbSize + 8.0,
          padding: const EdgeInsets.all(4.0),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(AppUi.radiusFull),
            border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
          ),
          child: Stack(
            children: [
              AnimatedContainer(
                duration: _isDragging ? Duration.zero : const Duration(milliseconds: 300),
                width: _dragPosition + thumbSize,
                height: thumbSize,
                decoration: BoxDecoration(
                  color: AppUi.infoFgDark.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(AppUi.radiusFull),
                ),
              ),
              Center(
                child: AnimatedOpacity(
                  opacity: _dragPosition > 50 || _isSwiped ? 0.0 : 1.0,
                  duration: const Duration(milliseconds: 200),
                  child: const Text(
                    'Swipe to Get Started',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
              AnimatedPositioned(
                duration: _isDragging ? Duration.zero : const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
                left: _dragPosition,
                top: 0,
                bottom: 0,
                child: GestureDetector(
                  onHorizontalDragStart: (details) {
                    if (_isSwiped) return;
                    setState(() => _isDragging = true);
                  },
                  onHorizontalDragUpdate: (details) {
                    if (_isSwiped) return;
                    setState(() {
                      _dragPosition += details.delta.dx;
                      if (_dragPosition < 0) _dragPosition = 0;
                      if (_dragPosition > maxDrag) _dragPosition = maxDrag;
                    });
                  },
                  onHorizontalDragEnd: (details) {
                    if (_isSwiped) return;
                    setState(() => _isDragging = false);
                    if (_dragPosition > maxDrag * 0.75) {
                      setState(() {
                        _dragPosition = maxDrag;
                        _isSwiped = true;
                      });
                      Future.delayed(const Duration(milliseconds: 400), widget.onSwipe);
                    } else {
                      setState(() {
                        _dragPosition = 0.0;
                      });
                    }
                  },
                  child: Container(
                    width: thumbSize,
                    decoration: const BoxDecoration(
                      color: AppUi.infoFgDark,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.arrow_forward_ios_rounded,
                      color: Color(0xFF020617),
                      size: 20,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
