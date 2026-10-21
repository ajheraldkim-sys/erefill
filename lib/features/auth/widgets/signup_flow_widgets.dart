import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:erefill/core/constants.dart';
import 'package:erefill/core/widgets/brand/water_fill_mark.dart';
import 'package:erefill/core/widgets/motion/motion.dart';

/// Bottom bar shared by the multi-step sign-up flows: Back (after step 1), a
/// primary Continue/finish button, and a sign-in link on the first step.
class SignupActionBar extends StatelessWidget {
  const SignupActionBar({
    super.key,
    required this.step,
    required this.lastStep,
    required this.finishLabel,
    required this.onBack,
    required this.onNext,
    required this.onSignIn,
  });

  final int step;
  final int lastStep;
  final String finishLabel;
  final VoidCallback onBack;
  final VoidCallback onNext;
  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    final isLast = step == lastStep;
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
      decoration: BoxDecoration(
        color: AppUi.surfaceOf(context),
        border: Border(top: BorderSide(color: AppUi.borderOf(context))),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                AnimatedSize(
                  duration: AppUi.motion(context, AppUi.motionBase),
                  curve: Curves.easeOut,
                  child: step > 0
                      ? Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: SizedBox(
                            height: 56,
                            child: OutlinedButton.icon(
                              onPressed: () {
                                HapticFeedback.selectionClick();
                                onBack();
                              },
                              icon: const Icon(
                                Icons.arrow_back_rounded,
                                size: 18,
                              ),
                              label: const Text(
                                'Back',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppUi.textPrimaryOf(context),
                                side: BorderSide(
                                  color: AppUi.borderOf(context),
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: AppUi.controlRadius,
                                ),
                              ),
                            ),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
                Expanded(
                  child: TapScale(
                    child: SizedBox(
                      height: 56,
                      child: FilledButton(
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          onNext();
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: AppUi.brandOf(context),
                          foregroundColor: AppUi.surfaceOf(context),
                          shape: RoundedRectangleBorder(
                            borderRadius: AppUi.controlRadius,
                          ),
                        ),
                        child: AnimatedSwitcher(
                          duration: AppUi.motion(context, AppUi.motionFast),
                          child: Text(
                            isLast ? finishLabel : 'Continue',
                            key: ValueKey(isLast),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (step == 0)
              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    'Already have an account?',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppUi.textSecondaryOf(context),
                    ),
                  ),
                  TextButton(
                    onPressed: onSignIn,
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, AppUi.kMinTouchTarget),
                    ),
                    child: Text(
                      'Sign in',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppUi.brandOf(context),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// Full-screen wait state while an account is being created.
class SignupSubmittingView extends StatelessWidget {
  const SignupSubmittingView({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          WaterFillMark(
            size: 64,
            fillColor: AppUi.brandOf(context),
            outlineColor: AppUi.borderOf(context),
          ),
          const SizedBox(height: 20),
          Text(
            message,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppUi.textPrimaryOf(context),
            ),
          ),
        ],
      ),
    );
  }
}
