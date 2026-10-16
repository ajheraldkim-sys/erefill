import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:erefill/core/routing/app_navigation.dart';
import 'package:erefill/core/constants.dart';

class SignupRoleScreen extends StatelessWidget {
  const SignupRoleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppUi.pageBgOf(context),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppUi.textPrimaryOf(context),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.openLogin();
            }
          },
          tooltip: 'Back to Sign In',
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Join eRefill',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: AppUi.textPrimaryOf(context),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Choose your role to start ordering or managing water refills.',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppUi.textSecondaryOf(context),
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 32),
              _premiumRoleCard(
                context: context,
                title: 'Household / Customer',
                subtitle:
                    'Order purified, mineral, or alkaline water to your doorstep.',
                icon: Icons.person_rounded,
                color: AppUi.accentGreen,
                onTap: () => context.openCustomerSignup(),
              ),
              const SizedBox(height: 14),
              _premiumRoleCard(
                context: context,
                title: 'Station Owner',
                subtitle: 'Manage water products, riders, and customer orders.',
                icon: Icons.storefront_rounded,
                color: AppUi.bluePrimary,
                onTap: () => context.openOwnerSignup(),
              ),
              const SizedBox(height: 36),
              Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Already have an account? ',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppUi.textSecondaryOf(context),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    GestureDetector(
                      onTap: () {
                        if (context.canPop()) {
                          context.pop();
                        } else {
                          context.openLogin();
                        }
                      },
                      child: const Text(
                        'Sign In',
                        style: TextStyle(
                          fontSize: 14,
                          color: AppUi.bluePrimary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _premiumRoleCard({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: AppUi.surfaceOf(context),
      borderRadius: AppUi.cardRadius,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppUi.cardRadius,
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: AppUi.cardDecorationOf(
            context,
          ).copyWith(border: Border.all(color: color.withValues(alpha: 0.2))),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: AppUi.textPrimaryOf(context),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: AppUi.textSecondaryOf(context),
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: color),
            ],
          ),
        ),
      ),
    );
  }
}
