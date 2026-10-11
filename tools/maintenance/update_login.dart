import 'dart:io';

void main() {
  final content = '''
import 'package:flutter/material.dart';
import 'package:erefill/core/constants.dart';
import 'package:erefill/core/utils/friendly_errors.dart';
import 'package:erefill/core/widgets/brand/erefill_logo.dart';
import 'package:erefill/features/auth/services/auth_service.dart';

class MinimalLoginPanel extends StatefulWidget {
  const MinimalLoginPanel({
    super.key,
    this.onSignedIn,
    this.showBackButton = false,
    this.showGuestBrowse = false,
    this.onGuestBrowse,
    this.onForgotPassword,
    this.onCreateAccount,
  });

  final VoidCallback? onSignedIn;
  final bool showBackButton;
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 680;

        return Stack(
          fit: StackFit.expand,
          children: [
            // Dark Slate Background
            Positioned.fill(
              child: const ColoredBox(
                color: Color(0xFF0A0F1A),
              ),
            ),
            // Subtle top radial glow for depth
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
                      const Color(0xFF38BDF8).withValues(alpha: 0.15),
                      const Color(0xFF38BDF8).withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
            
            SafeArea(
              child: Form(
                key: _formKey,
                child: SingleChildScrollView(
                  padding: EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: compact ? 16 : 32,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight:
                          constraints.maxHeight - (compact ? 32 : 64) - MediaQuery.paddingOf(context).top - MediaQuery.paddingOf(context).bottom,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (widget.showBackButton)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: IconButton(
                              onPressed: () => Navigator.maybePop(context),
                              icon: const Icon(
                                Icons.arrow_back_ios_new_rounded,
                              ),
                              color: Colors.white,
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 40,
                                minHeight: 40,
                              ),
                            ),
                          )
                        else
                          SizedBox(
                            height: compact ? 8 : 16,
                          ),

                        // App Logo / Wordmark
                        Center(
                          child: ERefillLogo(
                            size: compact ? 42 : 50,
                            showWordmark: true,
                            showMark: false,
                            color: Colors.white,
                            markColor: const Color(0xFF38BDF8),
                          ),
                        ),
                        SizedBox(
                          height: compact ? 24 : 40,
                        ),

                        // Clear Welcome Message
                        Text(
                          'Welcome back',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: compact ? 26 : 32,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            letterSpacing: -1.0,
                            height: 1.1,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Sign in to order refills or manage your station',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w400,
                            color: Color(0xFF94A3B8),
                            height: 1.4,
                          ),
                        ),
                        SizedBox(
                          height: compact ? 32 : 48,
                        ),

                        // Inline Error Alert Banner
                        if (_errorMessage != null) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF450A0A),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.redAccent.withValues(alpha: 0.5),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.error_outline_rounded,
                                  color: Colors.redAccent,
                                  size: 20,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    ,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.redAccent,
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
                                      color: Colors.redAccent,
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
                                  foregroundColor: const Color(0xFF38BDF8),
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
                                  backgroundColor: const Color(0xFF38BDF8),
                                  foregroundColor: const Color(0xFF020617),
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                ),
                                child: _isLoading
                                    ? const SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.5,
                                          color: Color(0xFF020617),
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
                        const SizedBox(height: 32),

                        // Footer Actions
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text(
                              "Don't have an account?",
                              style: TextStyle(
                                color: Color(0xFF94A3B8),
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            TextButton(
                              onPressed: _isLoading ? null : widget.onCreateAccount,
                              style: TextButton.styleFrom(
                                foregroundColor: const Color(0xFF38BDF8),
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
                                foregroundColor: const Color(0xFF94A3B8),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
                        SizedBox(
                          height: compact ? 8 : 16,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
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
    return TextFormField(
      controller: controller,
      enabled: enabled,
      keyboardType: keyboardType,
      autofillHints: autofillHints,
      obscureText: obscure,
      textInputAction: textInputAction,
      onChanged: onChanged,
      onFieldSubmitted: onFieldSubmitted,
      style: const TextStyle(
        fontWeight: FontWeight.w600,
        fontSize: 16,
        color: Colors.white,
      ),
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(
          color: Color(0xFF64748B),
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
        filled: true,
        fillColor: const Color(0xFF1E293B),
        prefixIcon: Icon(icon, size: 22, color: const Color(0xFF38BDF8)),
        suffixIcon: isPassword
            ? IconButton(
                icon: Icon(
                  obscure
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                  color: const Color(0xFF64748B),
                  size: 22,
                ),
                onPressed: onToggleObscure,
              )
            : null,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFF38BDF8), width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 18,
        ),
      ),
    );
  }
}
''';
  File(
    'lib/core/widgets/auth/minimal_login_panel.dart',
  ).writeAsStringSync(content);
}
