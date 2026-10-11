import 'package:flutter/material.dart';
import 'package:erefill/core/routing/app_navigation.dart';
import 'package:erefill/core/constants.dart';
import 'package:erefill/core/widgets/auth/minimal_login_panel.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppUi.pageBgOf(context),
      body: MinimalLoginPanel(
        showBackButton: true,
        backButtonLabel: 'Onboarding',
        onBack: () => context.openOnboarding(),
        onSignedIn: () => context.goHome(),
        onForgotPassword: () => context.openForgotPassword(),
        onCreateAccount: () => context.openSignup(),
        showGuestBrowse: true,
        onGuestBrowse: () => context.openStationList(),
      ),
    );
  }
}
