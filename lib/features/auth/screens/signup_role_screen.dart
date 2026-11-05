import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:erefill/core/routing/app_navigation.dart';
import 'package:erefill/core/constants.dart';
import 'package:erefill/core/widgets/motion/motion.dart';

class SignupRoleScreen extends StatelessWidget {
  const SignupRoleScreen({super.key});

  void _showRiderInfoModal(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: AppUi.radiusSheetTop),
      backgroundColor: AppUi.surfaceOf(context),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppUi.brandSoftOf(context),
                        borderRadius: BorderRadius.circular(AppUi.radiusCard),
                      ),
                      child: Icon(
                        Icons.delivery_dining_rounded,
                        color: AppUi.brandOf(context),
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Delivery Rider Access',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppUi.textPrimaryOf(ctx),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'Delivery riders are registered directly by water refilling station partners in Cantilan and Madrid.',
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.5,
                    color: AppUi.textSecondaryOf(ctx),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'If your station owner has created an account for you, please sign in with your credentials below.',
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.5,
                    color: AppUi.textSecondaryOf(ctx),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: AppUi.kMinTouchTarget,
                  child: FilledButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      context.openLogin();
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: AppUi.bluePrimary,
                      shape: RoundedRectangleBorder(
                        borderRadius: AppUi.controlRadius,
                      ),
                    ),
                    child: const Text(
                      'Sign In to Rider Account',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _back(BuildContext context) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.openLogin();
    }
  }

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
          onPressed: () => _back(context),
          tooltip: 'Back to Sign In',
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Reveal(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Create your account',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: AppUi.textPrimaryOf(context),
                        letterSpacing: -0.6,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'How will you use eRefill?',
                      style: TextStyle(
                        fontSize: 15,
                        color: AppUi.textSecondaryOf(context),
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Reveal(
                delay: const Duration(milliseconds: 70),
                child: _RoleCard(
                  icon: Icons.water_drop_rounded,
                  title: 'I want water delivered',
                  subtitle:
                      'Order refills from stations in Cantilan and Madrid, '
                      'track the rider, and pay by cash or Maya.',
                  badge: 'Most people',
                  primary: true,
                  onTap: () => context.openCustomerSignup(),
                ),
              ),
              const SizedBox(height: 12),
              Reveal(
                delay: const Duration(milliseconds: 140),
                child: _RoleCard(
                  icon: Icons.storefront_rounded,
                  title: 'I run a refilling station',
                  subtitle:
                      'List your station, set your price, and manage '
                      'orders and riders.',
                  onTap: () => context.openOwnerSignup(),
                ),
              ),
              const SizedBox(height: 12),
              Reveal(
                delay: const Duration(milliseconds: 210),
                child: _RoleCard(
                  icon: Icons.delivery_dining_rounded,
                  title: "I'm a delivery rider",
                  subtitle:
                      'Your station creates your account. Tap to see how '
                      'to sign in.',
                  onTap: () => _showRiderInfoModal(context),
                ),
              ),
              const SizedBox(height: 28),
              Reveal(
                delay: const Duration(milliseconds: 280),
                child: Center(
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        'Already have an account?',
                        style: TextStyle(
                          fontSize: 14,
                          color: AppUi.textSecondaryOf(context),
                        ),
                      ),
                      TextButton(
                        onPressed: () => _back(context),
                        style: TextButton.styleFrom(
                          minimumSize: const Size(0, AppUi.kMinTouchTarget),
                        ),
                        child: Text(
                          'Sign in',
                          style: TextStyle(
                            fontSize: 14,
                            color: AppUi.brandOf(context),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.badge,
    this.primary = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final String? badge;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final brand = AppUi.brandOf(context);
    return TapScale(
      child: Material(
        color: primary ? AppUi.brandSoftOf(context) : AppUi.surfaceOf(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppUi.radiusSheet),
          side: BorderSide(
            color: primary ? brand : AppUi.borderOf(context),
            width: primary ? 1.5 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: primary ? brand : AppUi.brandSoftOf(context),
                    borderRadius: BorderRadius.circular(AppUi.radiusCard),
                  ),
                  child: Icon(
                    icon,
                    color: primary ? AppUi.surfaceOf(context) : brand,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            title,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                              color: AppUi.textPrimaryOf(context),
                            ),
                          ),
                          if (badge != null)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppUi.surfaceOf(context),
                                borderRadius: BorderRadius.circular(
                                  AppUi.radiusFull,
                                ),
                              ),
                              child: Text(
                                badge!,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: AppUi.onBrandSoftOf(context),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.4,
                          color: AppUi.textSecondaryOf(context),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Icon(
                    Icons.arrow_forward_rounded,
                    color: primary ? brand : AppUi.textMutedOf(context),
                    size: 20,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
