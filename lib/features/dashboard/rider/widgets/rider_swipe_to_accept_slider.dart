import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/constants.dart';

class RiderSwipeToAcceptSlider extends StatefulWidget {
  final VoidCallback onAccepted;
  final String label;

  const RiderSwipeToAcceptSlider({
    super.key,
    required this.onAccepted,
    this.label = 'Slide to Accept Order',
  });

  @override
  State<RiderSwipeToAcceptSlider> createState() =>
      _RiderSwipeToAcceptSliderState();
}

class _RiderSwipeToAcceptSliderState extends State<RiderSwipeToAcceptSlider> {
  double _position = 0.0;
  bool _accepted = false;

  @override
  Widget build(BuildContext context) {
    if (_accepted) {
      return Container(
        height: AppUi.kRiderTouchTarget,
        decoration: BoxDecoration(
          color: AppUi.accentGreen,
          borderRadius: AppUi.controlRadius,
        ),
        alignment: Alignment.center,
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_rounded, color: Colors.white, size: 22),
            SizedBox(width: 8),
            Text(
              'Accepted & Starting!',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxSlide = (constraints.maxWidth - AppUi.kRiderTouchTarget).clamp(
          0.0,
          500.0,
        );

        return Container(
          height: AppUi.kRiderTouchTarget,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppUi.bluePrimary,
                AppUi.bluePrimary.withValues(alpha: 0.85),
              ],
            ),
            borderRadius: AppUi.controlRadius,
          ),
          child: Stack(
            children: [
              Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: Colors.white70,
                      size: 20,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      widget.label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                left: _position,
                top: 2,
                bottom: 2,
                child: GestureDetector(
                  onHorizontalDragUpdate: (details) {
                    setState(() {
                      _position = (_position + details.delta.dx).clamp(
                        0.0,
                        maxSlide,
                      );
                    });
                  },
                  onHorizontalDragEnd: (details) {
                    if (_position >= maxSlide * 0.72) {
                      setState(() {
                        _position = maxSlide;
                        _accepted = true;
                      });
                      HapticFeedback.heavyImpact();
                      widget.onAccepted();
                    } else {
                      setState(() {
                        _position = 0.0;
                      });
                    }
                  },
                  child: Container(
                    width: AppUi.kRiderTouchTarget - 4,
                    height: AppUi.kRiderTouchTarget - 4,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(AppUi.radiusControl),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x33000000),
                          blurRadius: 6,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.double_arrow_rounded,
                      color: AppUi.brandOf(context),
                      size: 22,
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
