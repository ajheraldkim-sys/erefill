import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../../../core/constants.dart';
import '../../../core/utils/friendly_errors.dart';
import '../../../core/widgets/app_form_fields.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailController = TextEditingController();
  final _authService = AuthService();
  bool _isLoading = false;
  bool _sent = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _handleReset() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) return;

    setState(() => _isLoading = true);
    try {
      await _authService.sendPasswordResetEmail(email);
      setState(() => _sent = true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            FriendlyErrors.message(
              e,
              fallback: 'Could not send reset instructions. Please try again.',
            ),
          ),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
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
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
        child: Column(
          children: [
            Text(
              _sent ? 'Check your email' : 'Forgot password?',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: AppUi.textPrimaryOf(context),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _sent
                  ? 'We sent password reset instructions to ${_emailController.text.trim()}.'
                  : 'Enter your email address and we will send password reset instructions.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppUi.textSecondaryOf(context),
                height: 1.5,
              ),
            ),
            const SizedBox(height: 32),
            if (!_sent) ...[
              AppFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                label: 'Email Address',
                prefixIcon: Icons.email_outlined,
              ),
              const SizedBox(height: 20),
              AppFormSubmitButton(
                text: 'Send Reset Link',
                icon: Icons.send_rounded,
                isLoading: _isLoading,
                onPressed: _handleReset,
              ),
            ] else
              AppFormSubmitButton(
                text: 'Back to Sign In',
                icon: Icons.arrow_back_rounded,
                onPressed: () => Navigator.pop(context),
              ),
          ],
        ),
      ),
    );
  }
}
