import 'package:flutter/material.dart';
import 'package:erefill/core/constants.dart';
import 'package:erefill/core/routing/app_navigation.dart';

class AuthDialogs {
  static void showSignInRequired(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: AppUi.dialogRadius),
        title: Row(
          children: [
            Icon(Icons.lock_person_rounded, color: AppUi.brandOf(context)),
            SizedBox(width: 12),
            Text(
              'Sign In Required',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
        content: const Text(
          'You need an account to place orders, message stations, or save favorites. Join the eRefill community today!',
          style: TextStyle(color: AppUi.textSecondary, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Maybe Later',
              style: TextStyle(
                color: AppUi.textMuted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              context.resetToAuth();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppUi.bluePrimary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppUi.radiusCard),
              ),
              elevation: 0,
            ),
            child: const Text(
              'Sign In / Sign Up',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
