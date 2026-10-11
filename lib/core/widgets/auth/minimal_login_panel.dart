import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:erefill/core/constants.dart';
import 'package:erefill/core/theme/app_theme.dart';
import 'package:erefill/core/utils/friendly_errors.dart';
import 'package:erefill/core/widgets/brand/erefill_logo.dart';
import 'package:erefill/features/auth/services/auth_service.dart';

class MinimalLoginPanel extends StatefulWidget {
  const MinimalLoginPanel({
    super.key,
    this.onSignedIn,
    this.showBackButton = false,
    this.onBack,
    this.backButtonLabel = 'Onboarding',
    this.showGuestBrowse = false,
    this.onGuestBrowse,
    this.onForgotPassword,
    this.onCreateAccount,
  });

  final VoidCallback? onSignedIn;
  final bool showBackButton;
  final VoidCallback? onBack;
  final String? backButtonLabel;
  final bool showGuestBrowse;
  final VoidCallback? onGuestBrowse;
  final VoidCallback? onForgotPassword;
  final VoidCallback? onCreateAccount;

  @override
  State<MinimalLoginPanel> createState() => _MinimalLoginPanelState();
}

class _MinimalLoginPanelState extends State<MinimalLoginPanel> {
  final _formKey = GlobalKey<FormState>();
  final _idController = TextEditingController();
  final _passController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  @override
  void dispose() {
    _idController.dispose();
    _passController.dispose();
    super.dispose();
  }

  Future<void> _runAuth(Future<void> Function() action) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      await action();
      if (!mounted) return;
      widget.onSignedIn?.call();
    } catch (e) {
      if (!mounted) return;
      final msg = FriendlyErrors.message(e);
      setState(() => _errorMessage = msg);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleLogin() async {
    setState(() => _errorMessage = null);
    if (!_formKey.currentState!.validate()) return;
    await _runAuth(
      () => AuthService().login(
        _idController.text.trim(),
        _passController.text.trim(),
      ),
    );
  }

  String? _validateIdentifier(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Please enter your email or username.';
    }
    final trimmed = value.trim();
    if (trimmed.contains('@')) {
      return AppValidators.email(trimmed);
    }
    if (trimmed.length < 3) {
      return 'Username must be at least 3 characters.';
    }
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter your password.';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: AppTheme.systemUiOverlayStyle(context),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxHeight < 680;
          final backgroundColor = AppUi.pageBgOf(context);
          final titleColor = AppUi.textPrimaryOf(context);
          final secondaryColor = AppUi.textSecondaryOf(context);
          final accentColor = isDark ? AppUi.accentCyan : AppUi.bluePrimary;
          final buttonForeground = isDark ? AppUi.darkPageBg : Colors.white;

          return Stack(
            fit: StackFit.expand,
            children: [
              Positioned.fill(child: ColoredBox(color: backgroundColor)),
              Positioned(
                top: -100,
                left: -50,
                child: Container(
                  width: 300,
                  height: 300,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        accentColor.withValues(alpha: isDark ? 0.12 : 0.08),
                        accentColor.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),

              SafeArea(
                child: Form(
                  key: _formKey,
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                      24,
                      widget.showBackButton
                          ? (compact ? 44 : 52)
                          : (compact ? 16 : 32),
                      24,
                      compact ? 16 : 32,
                    ),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight:
                            constraints.maxHeight -
                            (compact ? 32 : 64) -
                            MediaQuery.paddingOf(context).top -
                            MediaQuery.paddingOf(context).bottom,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(height: compact ? 8 : 16),

                          // App Logo / Wordmark
                          Center(
                            child: ERefillLogo(
                              size: compact ? 42 : 50,
                              showWordmark: true,
                              showMark: false,
                              color: titleColor,
                              markColor: accentColor,
                            ),
                          ),
                          SizedBox(height: compact ? 24 : 40),

                          // Clear Welcome Message
                          Text(
                            'Welcome back',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: compact ? 26 : 32,
                              fontWeight: FontWeight.w900,
                              color: titleColor,
                              letterSpacing: -1.0,
                              height: 1.1,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Sign in to order refills or manage your station',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w400,
                              color: secondaryColor,
                              height: 1.4,
                            ),
                          ),
                          SizedBox(height: compact ? 32 : 48),

                          // Inline Error Alert Banner
                          if (_errorMessage != null) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? const Color(0xFF3A1B1E)
                                    : const Color(0xFFFCEBED),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: AppUi.error.withValues(alpha: 0.35),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.error_outline_rounded,
                                    color: AppUi.error,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      _errorMessage!,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: AppUi.error,
                                        height: 1.3,
                                      ),
                                    ),
                                  ),
                                  InkWell(
                                    onTap: () =>
                                        setState(() => _errorMessage = null),
                                    borderRadius: BorderRadius.circular(12),
                                    child: const Padding(
                                      padding: EdgeInsets.all(4.0),
                                      child: Icon(
                                        Icons.close_rounded,
                                        size: 18,
                                        color: AppUi.error,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 24),
                          ],

                          // Login Form
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              AuthTextField(
                                controller: _idController,
                                label: 'Email or username',
                                icon: Icons.person_outline_rounded,
                                enabled: !_isLoading,
                                keyboardType: TextInputType.emailAddress,
                                autofillHints: const [
                                  AutofillHints.username,
                                  AutofillHints.email,
                                ],
                                textInputAction: TextInputAction.next,
                                onChanged: (_) {
                                  if (_errorMessage != null) {
                                    setState(() => _errorMessage = null);
                                  }
                                },
                                validator: _validateIdentifier,
                              ),
                              const SizedBox(height: 20),
                              AuthTextField(
                                controller: _passController,
                                label: 'Password',
                                icon: Icons.lock_outline_rounded,
                                enabled: !_isLoading,
                                isPassword: true,
                                obscure: _obscurePassword,
                                autofillHints: const [AutofillHints.password],
                                onToggleObscure: () => setState(
                                  () => _obscurePassword = !_obscurePassword,
                                ),
                                textInputAction: TextInputAction.done,
                                onChanged: (_) {
                                  if (_errorMessage != null) {
                                    setState(() => _errorMessage = null);
                                  }
                                },
                                onFieldSubmitted: (_) => _handleLogin(),
                                validator: _validatePassword,
                              ),
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed: _isLoading
                                      ? null
                                      : widget.onForgotPassword,
                                  style: TextButton.styleFrom(
                                    foregroundColor: accentColor,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                    minimumSize: Size.zero,
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  child: const Text(
                                    'Forgot password?',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                height: 56,
                                child: FilledButton(
                                  onPressed: _isLoading ? null : _handleLogin,
                                  style: FilledButton.styleFrom(
                                    backgroundColor: accentColor,
                                    foregroundColor: buttonForeground,
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(AppUi.radiusControl),
                                    ),
                                  ),
                                  child: _isLoading
                                      ? SizedBox(
                                          width: 24,
                                          height: 24,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2.5,
                                            color: buttonForeground,
                                          ),
                                        )
                                      : const Text(
                                          'Sign in',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 18,
                                          ),
                                        ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 28),

                          // Divider
                          Row(
                            children: [
                              Expanded(
                                child: Divider(
                                  color: AppUi.dividerOf(context),
                                  thickness: 1,
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                                child: Text(
                                  'Or continue with',
                                  style: TextStyle(
                                    color: secondaryColor,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Divider(
                                  color: AppUi.dividerOf(context),
                                  thickness: 1,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),

                          // Social Login Buttons
                          Row(
                            children: [
                              Expanded(
                                child: _SocialLoginButton(
                                  label: 'Google',
                                  icon: _GoogleIcon(),
                                  onPressed: _isLoading
                                      ? null
                                      : () => _runAuth(
                                          () =>
                                              AuthService().signInWithGoogle(),
                                        ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _SocialLoginButton(
                                  label: 'Facebook',
                                  icon: const Icon(
                                    Icons.facebook_rounded,
                                    size: 22,
                                    color: Color(0xFF1877F2),
                                  ),
                                  onPressed: _isLoading
                                      ? null
                                      : () => _runAuth(
                                          () => AuthService()
                                              .signInWithFacebook(),
                                        ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 28),

                          // Footer Actions
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                "Don't have an account?",
                                style: TextStyle(
                                  color: secondaryColor,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              TextButton(
                                onPressed: _isLoading
                                    ? null
                                    : widget.onCreateAccount,
                                style: TextButton.styleFrom(
                                  foregroundColor: accentColor,
                                ),
                                child: const Text(
                                  'Sign Up',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                            ],
                          ),

                          // Browse as Guest Button
                          if (widget.showGuestBrowse) ...[
                            Center(
                              child: TextButton(
                                onPressed: _isLoading
                                    ? null
                                    : widget.onGuestBrowse,
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 8,
                                  ),
                                  foregroundColor: secondaryColor,
                                  minimumSize: Size.zero,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: const Text(
                                  'Browse stations as guest',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ),
                          ],
                          SizedBox(height: compact ? 8 : 16),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              if (widget.showBackButton)
                Positioned(
                  top: 0,
                  left: 0,
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 16, top: 12),
                      child: Tooltip(
                        message:
                            'Back to ${widget.backButtonLabel ?? 'onboarding'}',
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () {
                              HapticFeedback.lightImpact();
                              if (widget.onBack != null) {
                                widget.onBack!();
                              } else if (Navigator.canPop(context)) {
                                Navigator.pop(context);
                              }
                            },
                            borderRadius: BorderRadius.circular(24),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? Colors.white.withValues(alpha: 0.08)
                                    : Colors.black.withValues(alpha: 0.04),
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(
                                  color: AppUi.dividerOf(context),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.arrow_back_ios_new_rounded,
                                    color: titleColor,
                                    size: 14,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    widget.backButtonLabel ?? 'Onboarding',
                                    style: TextStyle(
                                      color: titleColor,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.2,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class AuthTextField extends StatelessWidget {
  const AuthTextField({
    super.key,
    required this.controller,
    required this.label,
    required this.icon,
    this.enabled = true,
    this.keyboardType,
    this.autofillHints,
    this.isPassword = false,
    this.obscure = false,
    this.onToggleObscure,
    this.onChanged,
    this.validator,
    this.textInputAction,
    this.onFieldSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final bool enabled;
  final TextInputType? keyboardType;
  final Iterable<String>? autofillHints;
  final bool isPassword;
  final bool obscure;
  final VoidCallback? onToggleObscure;
  final ValueChanged<String>? onChanged;
  final String? Function(String?)? validator;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onFieldSubmitted;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryAccent = isDark ? AppUi.accentCyan : AppUi.bluePrimary;

    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final text = value.text;
        final isValid = text.isNotEmpty && validator != null && validator!(text) == null;

        Widget? suffix;
        if (isPassword) {
          suffix = IconButton(
            icon: Icon(
              obscure
                  ? Icons.visibility_off_rounded
                  : Icons.visibility_rounded,
              color: AppUi.textSecondaryOf(context),
              size: 22,
            ),
            onPressed: onToggleObscure,
          );
        } else if (isValid) {
          suffix = const Padding(
            padding: EdgeInsets.only(right: 14),
            child: Icon(
              Icons.check_circle_rounded,
              color: AppUi.accentGreen,
              size: 20,
            ),
          );
        }

        return TextFormField(
          controller: controller,
          enabled: enabled,
          keyboardType: keyboardType,
          autofillHints: autofillHints,
          obscureText: obscure,
          textInputAction: textInputAction,
          onChanged: onChanged,
          onFieldSubmitted: onFieldSubmitted,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 16,
            color: AppUi.textPrimaryOf(context),
          ),
          validator: validator,
          decoration: InputDecoration(
            labelText: label,
            floatingLabelBehavior: FloatingLabelBehavior.auto,
            floatingLabelStyle: TextStyle(
              color: primaryAccent,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
            labelStyle: TextStyle(
              color: AppUi.textSecondaryOf(context),
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
            filled: true,
            fillColor: isDark
                ? AppUi.darkSurfaceRaised
                : AppUi.lightSurfaceRaised,
            prefixIcon: Icon(
              icon,
              size: 22,
              color: primaryAccent,
            ),
            suffixIcon: suffix,
            suffixIconConstraints: const BoxConstraints(
              minWidth: 44,
              minHeight: 44,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppUi.radiusControl),
              borderSide: BorderSide(color: AppUi.borderOf(context)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppUi.radiusControl),
              borderSide: BorderSide(
                color: isValid
                    ? AppUi.accentGreen.withValues(alpha: 0.5)
                    : AppUi.borderOf(context),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppUi.radiusControl),
              borderSide: BorderSide(
                color: primaryAccent,
                width: 2,
              ),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppUi.radiusControl),
              borderSide: const BorderSide(color: AppUi.error, width: 1.5),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppUi.radiusControl),
              borderSide: const BorderSide(color: AppUi.error, width: 1.5),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 18,
            ),
          ),
        );
      },
    );
  }
}

// ─── Social Login Button ────────────────────────────────────────────────────

class _SocialLoginButton extends StatelessWidget {
  const _SocialLoginButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final Widget icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: AppUi.surfaceOf(context),
          foregroundColor: AppUi.textPrimaryOf(context),
          side: BorderSide(color: AppUi.dividerOf(context)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppUi.radiusControl),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            icon,
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: AppUi.textPrimaryOf(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Google "G" Icon ────────────────────────────────────────────────────────

class _GoogleIcon extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 22,
      height: 22,
      child: CustomPaint(painter: _GooglePainter()),
    );
  }
}

class _GooglePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width / 2;

    // Draw colored arcs (simplified Google G colors)
    // Red top
    paint.color = const Color(0xFFEA4335);
    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, cy), radius: r),
      -1.4,
      2.0,
      false,
      paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.36,
    );
    // Green bottom-right
    paint.color = const Color(0xFF34A853);
    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, cy), radius: r),
      0.6,
      1.0,
      false,
      paint,
    );
    // Yellow bottom-left
    paint.color = const Color(0xFFFBBC05);
    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, cy), radius: r),
      1.6,
      0.8,
      false,
      paint,
    );
    // Blue left
    paint.color = const Color(0xFF4285F4);
    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, cy), radius: r),
      2.4,
      0.7,
      false,
      paint,
    );

    // White inner circle to make it look like a ring
    paint
      ..color = Colors.white
      ..style = PaintingStyle.fill
      ..strokeWidth = 0;
    canvas.drawCircle(Offset(cx, cy), r * 0.6, paint);

    // Blue "G" bar going right
    paint.color = const Color(0xFF4285F4);
    canvas.drawRect(Rect.fromLTWH(cx, cy - r * 0.18, r * 0.9, r * 0.36), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
