import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:erefill/core/routing/app_navigation.dart';
import 'package:erefill/core/constants.dart';

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
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Get Started with eRefill',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: AppUi.textPrimaryOf(context),
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Order clean purified, mineral, or alkaline water refills delivered directly to your home in Cantilan and Madrid.',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppUi.textSecondaryOf(context),
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 28),

              // Primary Full-Width Customer CTA Card (Defaults to customer)
              Material(
                color: AppUi.surfaceOf(context),
                borderRadius: BorderRadius.circular(AppUi.radiusSheet),
                elevation: 0,
                child: InkWell(
                  onTap: () => context.openCustomerSignup(),
                  borderRadius: BorderRadius.circular(AppUi.radiusSheet),
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppUi.surfaceOf(context),
                      borderRadius: BorderRadius.circular(AppUi.radiusSheet),
                      border: Border.all(
                        color: AppUi.bluePrimary.withValues(alpha: 0.3),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppUi.bluePrimary.withValues(alpha: 0.08),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppUi.brandSoftOf(context),
                                borderRadius: BorderRadius.circular(AppUi.radiusCard),
                              ),
                              child: Icon(
                                Icons.water_drop_rounded,
                                color: AppUi.brandOf(context),
                                size: 28,
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
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      Text(
                                        'Customer / Household',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 17,
                                          color: AppUi.textPrimaryOf(context),
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 7,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: AppUi.successBg,
                                          borderRadius: BorderRadius.circular(
                                            99,
                                          ),
                                        ),
                                        child: const Text(
                                          'Recommended',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            color: AppUi.successFg,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    'Order doorstep water refills',
                                    style: TextStyle(
                                      color: AppUi.textSecondaryOf(context),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Track delivery in real-time, 1-to-1 bottle swaps with no deposit, and pay with Cash on Delivery or Maya.',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppUi.textSecondaryOf(context),
                            height: 1.45,
                          ),
                        ),
                        const SizedBox(height: 18),
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: FilledButton.icon(
                            onPressed: () => context.openCustomerSignup(),
                            icon: const Icon(Icons.arrow_forward_rounded),
                            label: const Text(
                              'Continue as Customer',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                            style: FilledButton.styleFrom(
                              backgroundColor: AppUi.bluePrimary,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(AppUi.radiusCard),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 36),

              // Secondary Partner Section
              Row(
                children: [
                  Expanded(
                    child: Divider(
                      color: AppUi.borderOf(context),
                      thickness: 1,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      'Partner with us',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppUi.textMutedOf(context),
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Divider(
                      color: AppUi.borderOf(context),
                      thickness: 1,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Secondary: Station Owner Link
              _buildSecondaryPartnerTile(
                context: context,
                icon: Icons.storefront_rounded,
                title: 'I own a water refilling station',
                subtitle: 'Register your station and manage orders & riders',
                onTap: () => context.openOwnerSignup(),
              ),
              const SizedBox(height: 10),

              // Secondary: Rider Link
              _buildSecondaryPartnerTile(
                context: context,
                icon: Icons.delivery_dining_rounded,
                title: "I'm a delivery rider",
                subtitle: 'Deliver orders dispatched by your station',
                onTap: () => _showRiderInfoModal(context),
              ),

              const SizedBox(height: 36),

              // Sign In Footer
              Center(
                child: SizedBox(
                  height: AppUi.kMinTouchTarget,
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
                      TextButton(
                        onPressed: () {
                          if (context.canPop()) {
                            context.pop();
                          } else {
                            context.openLogin();
                          }
                        },
                        child: Text(
                          'Sign In',
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

  Widget _buildSecondaryPartnerTile({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: AppUi.surfaceOf(context),
      borderRadius: BorderRadius.circular(AppUi.radiusCard),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppUi.radiusCard),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppUi.radiusCard),
            border: Border.all(color: AppUi.borderOf(context)),
          ),
          child: Row(
            children: [
              Icon(icon, color: AppUi.textSecondaryOf(context), size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppUi.textPrimaryOf(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppUi.textMutedOf(context),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: AppUi.textMutedOf(context),
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
