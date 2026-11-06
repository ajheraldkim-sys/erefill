import 'dart:math' as math;

import 'package:erefill/core/constants.dart';
import 'package:erefill/core/widgets/brand/erefill_logo.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../providers/admin_auth_provider.dart';
import '../../widgets/admin_ui.dart';

/// Below this width the brand panel is dropped and the form stands alone.
const double _kSplitBreakpoint = 960;

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscure = true;
  bool _capsLock = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
    _capsLock = _isCapsLockOn();
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  bool _isCapsLockOn() => HardwareKeyboard.instance.lockModesEnabled
      .contains(KeyboardLockMode.capsLock);

  bool _onKey(KeyEvent event) {
    final on = _isCapsLockOn();
    if (on != _capsLock && mounted) setState(() => _capsLock = on);
    return false;
  }

  void _clearError() {
    if (_error != null) setState(() => _error = null);
  }

  Future<void> _submit() async {
    final auth = context.read<AdminAuthProvider>();
    if (auth.signingIn) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() => _error = null);
    try {
      await auth.signIn(_emailController.text, _passwordController.text);
      TextInput.finishAutofillContext();
    } on AdminAuthException catch (e) {
      if (!mounted) return;
      _passwordController.clear();
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppUi.pageBgOf(context),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final split = constraints.maxWidth >= _kSplitBreakpoint;
          final form = _buildFormPane(context, showLogo: !split);
          if (!split) return form;
          return Row(
            children: [
              const Expanded(flex: 11, child: _BrandPanel()),
              Expanded(flex: 9, child: form),
            ],
          );
        },
      ),
    );
  }

  Widget _buildFormPane(BuildContext context, {required bool showLogo}) {
    final signingIn = context.select<AdminAuthProvider, bool>(
      (a) => a.signingIn,
    );

    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: AutofillGroup(
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (showLogo) ...[
                      Align(
                        alignment: Alignment.centerLeft,
                        child: ERefillLogo(
                          size: 40,
                          showMark: true,
                          showWordmark: true,
                          color: AppUi.textPrimaryOf(context),
                          markColor: AppUi.brandOf(context),
                        ),
                      ),
                      const SizedBox(height: 40),
                    ],
                    _AdminBadge(),
                    AppUi.vGapLg,
                    Text(
                      'Sign in to Admin Console',
                      style: adminScreenTitleStyle(context).copyWith(
                        fontSize: 26,
                        letterSpacing: -0.4,
                      ),
                    ),
                    AppUi.vGapSm,
                    Text(
                      'Restricted to authorized eRefill platform administrators.',
                      style: adminBodyTextStyle(context).copyWith(
                        color: AppUi.textSecondaryOf(context),
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 32),
                    AdminTextField(
                      controller: _emailController,
                      label: 'Email or username',
                      icon: LucideIcons.mail,
                      enabled: !signingIn,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [
                        AutofillHints.username,
                        AutofillHints.email,
                      ],
                      onChanged: (_) => _clearError(),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Enter your email or username'
                          : null,
                    ),
                    AppUi.vGapMd,
                    AdminTextField(
                      controller: _passwordController,
                      label: 'Password',
                      icon: LucideIcons.lock,
                      enabled: !signingIn,
                      obscureText: _obscure,
                      textInputAction: TextInputAction.done,
                      autofillHints: const [AutofillHints.password],
                      suffixIcon: Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: IconButton(
                          tooltip: _obscure ? 'Show password' : 'Hide password',
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            side: BorderSide.none,
                            foregroundColor: AppUi.textSecondaryOf(context),
                          ),
                          icon: Icon(
                            _obscure ? LucideIcons.eye : LucideIcons.eyeOff,
                            size: 18,
                          ),
                          onPressed: () =>
                              setState(() => _obscure = !_obscure),
                        ),
                      ),
                      onChanged: (_) => _clearError(),
                      validator: (v) => (v == null || v.isEmpty)
                          ? 'Enter your password'
                          : null,
                      onFieldSubmitted: (_) => _submit(),
                    ),
                    if (_capsLock) ...[
                      AppUi.vGapSm,
                      _InlineHint(
                        icon: LucideIcons.arrowBigUp,
                        text: 'Caps Lock is on',
                        color: AppUi.isDark(context)
                            ? AppUi.warningFgDark
                            : AppUi.warningFg,
                      ),
                    ],
                    AnimatedSize(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOut,
                      alignment: Alignment.topCenter,
                      child: _error == null
                          ? const SizedBox(width: double.infinity)
                          : Padding(
                              padding: const EdgeInsets.only(top: 16),
                              child: _ErrorBanner(message: _error!),
                            ),
                    ),
                    AppUi.vGapLg,
                    ShadcnPrimaryButton(
                      height: 52,
                      isLoading: signingIn,
                      icon: LucideIcons.logIn,
                      text: signingIn ? 'Signing in…' : 'Sign in',
                      onPressed: signingIn ? null : _submit,
                    ),
                    AppUi.vGapLg,
                    Text(
                      'Locked out? Ask a super admin to reset your access.',
                      textAlign: TextAlign.center,
                      style: adminCaptionTextStyle(context).copyWith(
                        color: adminMutedTextColor(context),
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

class _AdminBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final brand = AppUi.brandOf(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 6, 12, 6),
        decoration: BoxDecoration(
          color: AppUi.brandSoftOf(context),
          borderRadius: BorderRadius.circular(AppUi.radiusFull),
          border: Border.all(color: brand.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.shieldCheck, size: 14, color: brand),
            const SizedBox(width: 6),
            Text(
              'ADMIN ACCESS',
              style: TextStyle(
                color: brand,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InlineHint extends StatelessWidget {
  const _InlineHint({
    required this.icon,
    required this.text,
    required this.color,
  });

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Row(
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final errorColor = adminSemanticErrorColor(context);
    return Semantics(
      liveRegion: true,
      container: true,
      label: 'Sign-in error: $message',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: errorColor.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(AppUi.radiusCard),
          border: Border.all(color: errorColor.withValues(alpha: 0.4)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(LucideIcons.circleAlert, color: errorColor, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: errorColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Brand panel ────────────────────────────────────────────────────────────

class _BrandPanel extends StatelessWidget {
  const _BrandPanel();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppUi.deepBlue,
      ),
      child: Stack(
        children: [
          const Positioned.fill(
            child: IgnorePointer(
              // The painter draws past its bounds; keep it inside the panel.
              child: ClipRect(child: CustomPaint(painter: _RipplePainter())),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(56, 48, 56, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const ERefillLogo(
                    size: 44,
                    showMark: true,
                    showWordmark: true,
                    color: Colors.white,
                    markColor: Colors.white,
                  ),
                  const Spacer(flex: 3),
                  Text(
                    'PLATFORM ADMIN',
                    style: TextStyle(
                      color: AppUi.accentCyan,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.6,
                    ),
                  ),
                  AppUi.vGapMd,
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: const Text(
                      'Every station, order, and peso, in one place.',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 40,
                        fontWeight: FontWeight.w800,
                        height: 1.1,
                        letterSpacing: -0.8,
                      ),
                    ),
                  ),
                  AppUi.vGapLg,
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: Text(
                      'Moderate stations, adjust fees, monitor orders, and keep '
                      'Cantilan and Madrid running smoothly.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.78),
                        fontSize: 16,
                        height: 1.55,
                      ),
                    ),
                  ),
                  const SizedBox(height: 36),
                  const _FeatureRow(
                    icon: LucideIcons.store,
                    title: 'Stations',
                    body: 'Approve, suspend, and review refill stations.',
                  ),
                  AppUi.vGapMd,
                  const _FeatureRow(
                    icon: LucideIcons.banknote,
                    title: 'Revenue',
                    body: 'Track platform fees and station wallets.',
                  ),
                  AppUi.vGapMd,
                  const _FeatureRow(
                    icon: LucideIcons.shieldCheck,
                    title: 'Audit trail',
                    body: 'See who changed what, and when.',
                  ),
                  const Spacer(flex: 4),
                  Text(
                    '© ${DateTime.now().year} eRefill · Cantilan & Madrid',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppUi.accentCyan.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(AppUi.radiusLgValue),
            border: Border.all(
              color: AppUi.accentCyan.withValues(alpha: 0.28),
            ),
          ),
          child: Icon(icon, color: AppUi.accentCyan, size: 19),
        ),
        const SizedBox(width: 14),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                body,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 13.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Concentric "water drop" ripples anchored off the panel's bottom-right.
class _RipplePainter extends CustomPainter {
  const _RipplePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width * 0.92, size.height * 0.9);
    final maxR = math.max(size.width, size.height) * 0.75;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    for (var i = 1; i <= 7; i++) {
      final t = i / 7;
      paint.color = AppUi.accentCyan.withValues(alpha: 0.16 * (1 - t) + 0.02);
      canvas.drawCircle(center, maxR * t, paint);
    }
  }

  @override
  bool shouldRepaint(_RipplePainter oldDelegate) => false;
}
