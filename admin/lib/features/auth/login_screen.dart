import 'package:erefill/core/constants.dart';
import 'package:erefill/core/widgets/brand/erefill_logo.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/admin_auth_provider.dart';
import '../../widgets/admin_ui.dart';

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
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _error = null);
    try {
      await context.read<AdminAuthProvider>().signIn(
        _emailController.text,
        _passwordController.text,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AdminAuthProvider>();
    final errorColor = adminSemanticErrorColor(context);

    return Scaffold(
      body: Row(
        children: [
          Expanded(
            flex: 5,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppUi.deepBlue, AppUi.bluePrimary, AppUi.accentCyan],
                ),
              ),
              child: SafeArea(
                child: Padding(
                  padding: AppUi.pagePaddingLoose,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const ERefillLogo(
                        size: 48,
                        showMark: true,
                        showWordmark: true,
                        color: Colors.white,
                        markColor: Colors.white,
                      ),
                      const Spacer(),
                      const Text(
                        'Platform control\nfor water refill ops',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 36,
                          fontWeight: FontWeight.w700,
                          height: 1.15,
                          letterSpacing: -0.5,
                        ),
                      ),
                      AppUi.vGapMd,
                      Text(
                        'Moderate stations, adjust fees, monitor orders, and keep Cantilan and Madrid running smoothly.',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 15,
                          height: 1.5,
                        ),
                      ),
                      AppUi.vGapXl,
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: const [
                          _FeatureChip(LucideIcons.store, 'Stations'),
                          _FeatureChip(LucideIcons.banknote, 'Revenue'),
                          _FeatureChip(LucideIcons.shieldCheck, 'Audit trail'),
                        ],
                      ),
                      const Spacer(),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            flex: 4,
            child: Container(
              color: AppUi.pageBgOf(context),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Padding(
                    padding: AppUi.pagePaddingLoose,
                    child: Form(
                      key: _formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Admin sign in',
                            style: adminScreenTitleStyle(context),
                          ),
                          AppUi.vGapXs,
                          Text(
                            'Authorized platform administrators only',
                            style: adminBodyTextStyle(context),
                          ),
                          AppUi.vGapXl,
                          AdminTextField(
                            controller: _emailController,
                            label: 'Admin email or username',
                            hint: 'admin@gmail.com or admin',
                            icon: LucideIcons.mail,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? 'Email or username required'
                                : null,
                          ),
                          AppUi.vGapMd,
                          AdminTextField(
                            controller: _passwordController,
                            label: 'Password',
                            hint: '••••••••',
                            icon: LucideIcons.lock,
                            obscureText: _obscure,
                            textInputAction: TextInputAction.done,
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscure ? LucideIcons.eyeOff : LucideIcons.eye,
                                size: 18,
                              ),
                              onPressed: () =>
                                  setState(() => _obscure = !_obscure),
                            ),
                            validator: (v) => (v == null || v.isEmpty)
                                ? 'Password required'
                                : null,
                            onFieldSubmitted: (_) => _submit(),
                          ),
                          if (_error != null) ...[
                            AppUi.vGapMd,
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: errorColor.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(AppUi.radiusCard),
                                border: Border.all(
                                  color: errorColor.withValues(alpha: 0.45),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    LucideIcons.circleAlert,
                                    color: errorColor,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      _error!,
                                      style: TextStyle(
                                        color: errorColor,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          AppUi.vGapLg,
                          ShadcnPrimaryButton(
                            height: 50,
                            isLoading: auth.loading,
                            icon: LucideIcons.logIn,
                            text: 'Enter Admin Console',
                            onPressed: auth.loading ? null : _submit,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FeatureChip extends StatelessWidget {
  const _FeatureChip(this.icon, this.label);

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppUi.radiusFull),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 16),
          AppUi.hGapSm,
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
