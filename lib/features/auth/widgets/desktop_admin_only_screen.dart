import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:erefill/core/constants.dart';
import 'package:erefill/core/routing/app_routes.dart';
import 'package:erefill/core/theme/app_colors.dart';

class DesktopAdminOnlyScreen extends StatefulWidget {
  const DesktopAdminOnlyScreen({super.key});

  @override
  State<DesktopAdminOnlyScreen> createState() => _DesktopAdminOnlyScreenState();
}

class _DesktopAdminOnlyScreenState extends State<DesktopAdminOnlyScreen> {
  bool _isSigningOut = false;

  Future<void> _signOut() async {
    setState(() => _isSigningOut = true);
    try {
      await Supabase.instance.client.auth.signOut(scope: SignOutScope.local);
      if (mounted) context.go(AppRoutes.home);
    } catch (error) {
      debugPrint('Desktop-only admin sign-out failed: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not sign out. Please try again.'),
            backgroundColor: AppColors.uiError,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSigningOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppUi.pageBgOf(context),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Container(
                padding: const EdgeInsets.all(28),
                decoration: AppUi.cardDecorationOf(context, elevated: true),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: AppUi.brandSoftOf(context),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.desktop_windows_rounded,
                        size: 34,
                        color: AppUi.brandOf(context),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Admin access is desktop-only',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w700,
                        color: AppUi.textPrimaryOf(context),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Administrative tools are available in the eRefill Admin desktop app. This mobile app is for customers, station owners, and riders.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        height: 1.5,
                        color: AppUi.textSecondaryOf(context),
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _isSigningOut ? null : _signOut,
                        icon: _isSigningOut
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.logout_rounded),
                        label: Text(
                          _isSigningOut ? 'Signing out…' : 'Sign out',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
