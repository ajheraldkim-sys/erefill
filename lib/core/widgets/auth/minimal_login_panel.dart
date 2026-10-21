import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:erefill/core/constants.dart';
import 'package:erefill/core/theme/app_colors.dart';
import 'package:erefill/core/theme/app_theme.dart';
import 'package:erefill/core/utils/friendly_errors.dart';
import 'package:erefill/core/widgets/brand/erefill_logo.dart';
import 'package:erefill/core/widgets/motion/motion.dart';
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
    this.onEmailPasswordLogin,
  });

  final VoidCallback? onSignedIn;
  final bool showBackButton;
  final VoidCallback? onBack;
  final String? backButtonLabel;
  final bool showGuestBrowse;
  final VoidCallback? onGuestBrowse;
  final VoidCallback? onForgotPassword;
  final VoidCallback? onCreateAccount;
  final Future<void> Function(String identifier, String password)?
  onEmailPasswordLogin;

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
      () => (widget.onEmailPasswordLogin ?? AuthService().login)(
        _idController.text.trim(),
        _passController.text,
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

                          // Brand mark and wordmark, matching the splash
                          Reveal(
                            child: Center(
                              child: ERefillLogo(
                                size: compact ? 40 : 46,
                                stacked: true,
                                color: titleColor,
                                markColor: accentColor,
                              ),
                            ),
                          ),
                          SizedBox(height: compact ? 24 : 36),

                          Reveal(
                            delay: const Duration(milliseconds: 60),
                            child: Column(
                              children: [
                                Text(
                                  'Welcome back',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: compact ? 26 : 30,
                                    fontWeight: FontWeight.w700,
                                    color: titleColor,
                                    letterSpacing: -0.8,
                                    height: 1.1,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Sign in to order refills or manage your station',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 15,
                                    color: secondaryColor,
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(height: compact ? 28 : 40),

                          // Inline error, animated in and out
                          AnimatedSize(
                            duration: AppUi.motion(context, AppUi.motionBase),
                            curve: Curves.easeOut,
                            alignment: Alignment.topCenter,
                            child: _errorMessage == null
                                ? const SizedBox(width: double.infinity)
                                : Padding(
                                    padding: const EdgeInsets.only(bottom: 20),
                                    child: _LoginErrorBanner(
                                      message: _errorMessage!,
                                      onDismiss: () =>
                                          setState(() => _errorMessage = null),
                                    ),
                                  ),
                          ),

                          // Login Form
                          Reveal(
                            delay: const Duration(milliseconds: 120),
                            child: Column(
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
                                TapScale(
                                  enabled: !_isLoading,
                                  child: SizedBox(
                                    width: double.infinity,
                                    height: 56,
                                    child: FilledButton(
                                      onPressed: _isLoading
                                          ? null
                                          : () {
                                              HapticFeedback.lightImpact();
                                              _handleLogin();
                                            },
                                      style: FilledButton.styleFrom(
                                        backgroundColor: accentColor,
                                        foregroundColor: buttonForeground,
                                        disabledBackgroundColor: accentColor
                                            .withValues(alpha: 0.7),
                                        elevation: 0,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            AppUi.radiusControl,
                                          ),
                                        ),
                                      ),
                                      child: AnimatedSwitcher(
                                        duration: AppUi.motion(
                                          context,
                                          AppUi.motionFast,
                                        ),
                                        child: _isLoading
                                            ? SizedBox(
                                                key: const ValueKey('loading'),
                                                width: 24,
                                                height: 24,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2.5,
                                                      color: buttonForeground,
                                                    ),
                                              )
                                            : const Text(
                                                'Sign in',
                                                key: ValueKey('label'),
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 18,
                                                ),
                                              ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 28),

                          Reveal(
                            delay: const Duration(milliseconds: 180),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
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
                                                () => AuthService()
                                                    .signInWithGoogle(),
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
                                Wrap(
                                  alignment: WrapAlignment.center,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  spacing: 4,
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
                                          fontWeight: FontWeight.w700,
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
                              ],
                            ),
                          ),
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
                            borderRadius: BorderRadius.circular(
                              AppUi.radiusPill,
                            ),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? Colors.white.withValues(alpha: 0.08)
                                    : Colors.black.withValues(alpha: 0.04),
                                borderRadius: BorderRadius.circular(
                                  AppUi.radiusPill,
                                ),
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
        final isValid =
            text.isNotEmpty && validator != null && validator!(text) == null;

        Widget? suffix;
        if (isPassword) {
          suffix = IconButton(
            tooltip: obscure ? 'Show password' : 'Hide password',
            icon: Icon(
              obscure ? Icons.visibility_off_rounded : Icons.visibility_rounded,
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
          textCapitalization: TextCapitalization.none,
          autocorrect: false,
          enableSuggestions: !isPassword,
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
            prefixIcon: Icon(icon, size: 22, color: primaryAccent),
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
              borderSide: BorderSide(color: primaryAccent, width: 2),
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
    return TapScale(
      enabled: onPressed != null,
      child: SizedBox(
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
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: AppUi.textPrimaryOf(context),
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

class _LoginErrorBanner extends StatelessWidget {
  const _LoginErrorBanner({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final style = StatusToneStyle.of(
      StatusTone.danger,
      isDark: Theme.of(context).brightness == Brightness.dark,
    );
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
        decoration: BoxDecoration(
          color: style.background,
          borderRadius: BorderRadius.circular(AppUi.radiusCard),
          border: Border.all(color: style.border),
        ),
        child: Row(
          children: [
            Icon(
              Icons.error_outline_rounded,
              color: style.foreground,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: style.foreground,
                  height: 1.3,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Dismiss',
              onPressed: onDismiss,
              icon: Icon(
                Icons.close_rounded,
                size: 18,
                color: style.foreground,
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
      child: CustomPaint(
        painter: _GooglePainter(cutoutColor: AppUi.surfaceOf(context)),
      ),
    );
  }
}

class _GooglePainter extends CustomPainter {
  _GooglePainter({required this.cutoutColor});

  /// Matches the button surface so the "G" reads in light and dark mode.
  final Color cutoutColor;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final radius = size.width / 2;
    final ringRadius = radius * 0.9;
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = radius * 0.38
      ..strokeCap = StrokeCap.round;

    final rect = Rect.fromCircle(center: Offset(cx, cy), radius: ringRadius);

    ringPaint.color = const Color(0xFF4285F4);
    canvas.drawArc(rect, 1.9 * math.pi, 1.0 * math.pi, false, ringPaint);

    ringPaint.color = const Color(0xFF34A853);
    canvas.drawArc(rect, 0.1 * math.pi, 0.9 * math.pi, false, ringPaint);

    ringPaint.color = const Color(0xFFFBBC05);
    canvas.drawArc(rect, 0.95 * math.pi, 0.9 * math.pi, false, ringPaint);

    ringPaint.color = const Color(0xFFEA4335);
    canvas.drawArc(rect, -0.9 * math.pi, 0.9 * math.pi, false, ringPaint);

    final cutout = Paint()..color = cutoutColor;
    canvas.drawCircle(Offset(cx + radius * 0.08, cy), radius * 0.58, cutout);

    final accentBar = Paint()..color = const Color(0xFF4285F4);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          cx + radius * 0.12,
          cy - radius * 0.18,
          radius * 0.68,
          radius * 0.36,
        ),
        Radius.circular(radius * 0.12),
      ),
      accentBar,
    );
  }

  @override
  bool shouldRepaint(_GooglePainter oldDelegate) =>
      oldDelegate.cutoutColor != cutoutColor;
}
