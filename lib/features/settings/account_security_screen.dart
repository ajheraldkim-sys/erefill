import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/constants.dart';
import '../../core/routing/app_routes.dart';
import '../../core/widgets/app_form_fields.dart';
import '../../core/services/external_notification_service.dart';
import '../auth/widgets/gmail_binding_card.dart';

import 'package:erefill/core/utils/friendly_errors.dart';

enum AccountSecuritySection { email, changePassword }

class AccountSecurityScreen extends StatefulWidget {
  const AccountSecurityScreen({
    super.key,
    required this.role,
    this.section,
  });

  final String role;
  final AccountSecuritySection? section;

  @override
  State<AccountSecurityScreen> createState() => _AccountSecurityScreenState();
}

class _AccountSecurityScreenState extends State<AccountSecurityScreen> {
  final _formKey = GlobalKey<FormState>();
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isSavingPassword = false;
  bool _isDeleting = false;
  bool _isResendingVerification = false;
  int _resendCooldown = 0;
  Timer? _cooldownTimer;

  String? _currentPasswordError;

  User? get _currentUser => Supabase.instance.client.auth.currentUser;

  bool get _isEmailVerified => _currentUser?.emailConfirmedAt != null;

  bool get _isGoogleOAuth {
    final user = _currentUser;
    if (user == null) return false;
    final provider = user.appMetadata['provider']?.toString().toLowerCase();
    if (provider == 'google') return true;
    final identities = user.identities;
    if (identities != null &&
        identities.any((id) => id.provider.toLowerCase() == 'google')) {
      return true;
    }
    return false;
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _startCooldownTimer() {
    setState(() => _resendCooldown = 60);
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        if (_resendCooldown > 1) {
          _resendCooldown--;
        } else {
          _resendCooldown = 0;
          timer.cancel();
        }
      });
    });
  }

  Future<void> _resendVerificationEmail() async {
    final user = _currentUser;
    final email = user?.email;
    if (email == null || email.isEmpty) return;

    setState(() => _isResendingVerification = true);
    HapticFeedback.lightImpact();

    try {
      await Supabase.instance.client.auth.resend(
        type: OtpType.signup,
        email: email,
      );
      _startCooldownTimer();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Verification link resent to $email. Please check your inbox.'),
          backgroundColor: AppUi.bluePrimary,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to resend email: ${FriendlyErrors.message(e)}'),
          backgroundColor: AppUi.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isResendingVerification = false);
    }
  }

  Future<void> _updatePassword() async {
    setState(() => _currentPasswordError = null);
    if (!_formKey.currentState!.validate()) return;

    final user = _currentUser;
    if (user == null || user.email == null) return;

    setState(() => _isSavingPassword = true);
    HapticFeedback.lightImpact();

    final client = Supabase.instance.client;

    try {
      // 1. If not Google OAuth user, validate current password against backend first
      if (!_isGoogleOAuth) {
        try {
          await client.auth.signInWithPassword(
            email: user.email!,
            password: _currentPasswordController.text,
          );
        } on AuthException {
          setState(() {
            _currentPasswordError = 'Current password is incorrect.';
          });
          _formKey.currentState?.validate();
          return;
        } catch (_) {
          setState(() {
            _currentPasswordError = 'Failed to verify current password.';
          });
          _formKey.currentState?.validate();
          return;
        }
      }

      // 2. Update to new password
      await client.auth.updateUser(
        UserAttributes(password: _newPasswordController.text),
      );

      // 3. Dispatch external security alert & delivery log
      await ExternalNotificationService.instance.notifySecurityAlert(
        event: 'password_updated',
        details: 'Password was updated from your device security settings.',
      );

      if (!mounted) return;
      _currentPasswordController.clear();
      _newPasswordController.clear();
      _confirmPasswordController.clear();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Password updated successfully.'),
          backgroundColor: AppUi.successFg,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } on AuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: AppUi.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update password: ${FriendlyErrors.message(e)}'),
          backgroundColor: AppUi.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSavingPassword = false);
    }
  }

  Future<void> _promptAccountDeletion() async {
    final confirmationTextController = TextEditingController();
    final authPasswordController = TextEditingController();
    bool confirmedText = false;
    bool isAuthenticating = false;
    String? authError;

    final shouldDelete = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: AppUi.surfaceOf(dialogCtx),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppUi.radiusSheet)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppUi.error.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppUi.radiusControl),
                ),
                child: const Icon(Icons.warning_amber_rounded, color: AppUi.error, size: 24),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Delete Account',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Are you sure you want to delete your account? This action is permanent and cannot be undone.',
                  style: TextStyle(fontWeight: FontWeight.w600, height: 1.4),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppUi.error.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(AppUi.radiusControl),
                    border: Border.all(color: AppUi.error.withValues(alpha: 0.2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        'Consequences of deletion:',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppUi.error,
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        '• Your account credentials and active sessions will be revoked.\n'
                        '• Active pending orders will be cancelled.\n'
                        '• Financial transaction records will be retained for regulatory compliance, but personal identity will be erased.',
                        style: TextStyle(fontSize: 12, height: 1.4),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (!_isGoogleOAuth) ...[
                  const Text(
                    'Re-enter your password to authenticate:',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: authPasswordController,
                    obscureText: true,
                    decoration: InputDecoration(
                      hintText: 'Current Password',
                      errorText: authError,
                      isDense: true,
                      prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppUi.radiusControl),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                const Text(
                  'Type DELETE to confirm:',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: confirmationTextController,
                  autocorrect: false,
                  decoration: InputDecoration(
                    hintText: 'DELETE',
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppUi.radiusControl),
                      borderSide: const BorderSide(color: AppUi.error),
                    ),
                  ),
                  onChanged: (text) {
                    setDialogState(() {
                      confirmedText = text.trim() == 'DELETE';
                    });
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isAuthenticating ? null : () => Navigator.pop(dialogCtx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppUi.error,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppUi.radiusControl)),
              ),
              onPressed: (!confirmedText || isAuthenticating)
                  ? null
                  : () async {
                      if (!_isGoogleOAuth) {
                        setDialogState(() {
                          isAuthenticating = true;
                          authError = null;
                        });
                        try {
                          await Supabase.instance.client.auth.signInWithPassword(
                            email: _currentUser!.email!,
                            password: authPasswordController.text,
                          );
                        } on AuthException {
                          setDialogState(() {
                            isAuthenticating = false;
                            authError = 'Password incorrect. Verification failed.';
                          });
                          return;
                        } catch (_) {
                          setDialogState(() {
                            isAuthenticating = false;
                            authError = 'Authentication failed. Please retry.';
                          });
                          return;
                        }
                      }
                      if (dialogCtx.mounted) {
                        Navigator.pop(dialogCtx, true);
                      }
                    },
              child: isAuthenticating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : const Text('Permanently Delete'),
            ),
          ],
        ),
      ),
    );

    confirmationTextController.dispose();
    authPasswordController.dispose();

    if (!mounted || shouldDelete != true) return;

    setState(() => _isDeleting = true);
    HapticFeedback.heavyImpact();

    try {
      final client = Supabase.instance.client;
      await client.rpc('delete_user_account');
      await client.auth.signOut(scope: SignOutScope.local);

      if (!mounted) return;
      context.go(AppRoutes.login);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Your account has been permanently deleted.'),
          backgroundColor: AppUi.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      debugPrint('Error deleting account: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e.toString().contains('deliveries in transit')
                  ? 'Cannot delete account while you have active deliveries in transit. Please wait until they are completed.'
                  : 'Failed to delete account: $e',
            ),
            backgroundColor: AppUi.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = switch (widget.section) {
      AccountSecuritySection.email => 'Email',
      AccountSecuritySection.changePassword => 'Change password',
      null => '${widget.role[0].toUpperCase()}${widget.role.substring(1)} Security',
    };
    final user = _currentUser;
    final email = user?.email ?? 'No email associated';
    final showEmail =
        widget.section == null || widget.section == AccountSecuritySection.email;
    final showPassword =
        widget.section == null ||
        widget.section == AccountSecuritySection.changePassword;

    return Scaffold(
      backgroundColor: AppUi.pageBgOf(context),
      appBar: AppBar(
        title: Text(title),
        centerTitle: true,
        backgroundColor: AppUi.pageBgOf(context),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: AppUi.pagePadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
                if (showEmail) ...[
                // ── A. EMAIL SECURITY ──────────────────────────────────────────
                Container(
                width: double.infinity,
                padding: AppUi.cardPadding,
                decoration: AppUi.cardDecorationOf(context),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const AppFormSectionHeader(
                      title: 'EMAIL SECURITY',
                      subtitle:
                          'Your primary account email is used for sign-in, orders, and security communications.',
                    ),
                    AppUi.vGapLg,
                    // Read-only email display card
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: AppUi.surfaceOf(context),
                        borderRadius: BorderRadius.circular(AppUi.radiusCard),
                        border: Border.all(color: AppUi.borderOf(context)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'ACCOUNT EMAIL ADDRESS',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.8,
                              color: AppUi.textSecondaryOf(context),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Icon(
                                Icons.email_outlined,
                                size: 20,
                                color: AppUi.brandOf(context),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  email,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: AppUi.textPrimaryOf(context),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          // Authoritative verification status badge
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: _isEmailVerified
                                      ? AppUi.successBg
                                      : AppUi.warningBg,
                                  borderRadius: BorderRadius.circular(AppUi.radiusSheet),
                                  border: Border.all(
                                    color: _isEmailVerified
                                        ? AppUi.successFg.withValues(alpha: 0.3)
                                        : AppUi.warningFg.withValues(alpha: 0.3),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      _isEmailVerified
                                          ? Icons.verified_rounded
                                          : Icons.warning_amber_rounded,
                                      size: 15,
                                      color: _isEmailVerified
                                          ? AppUi.successFg
                                          : AppUi.warningFg,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      _isEmailVerified
                                          ? 'Email verified'
                                          : 'Email not verified',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: _isEmailVerified
                                            ? AppUi.successFg
                                            : AppUi.warningFg,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          if (!_isEmailVerified) ...[
                            const SizedBox(height: 14),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  side: BorderSide(color: AppUi.bluePrimary),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(AppUi.radiusControl),
                                  ),
                                ),
                                onPressed: (_isResendingVerification || _resendCooldown > 0)
                                    ? null
                                    : _resendVerificationEmail,
                                icon: _isResendingVerification
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : const Icon(Icons.send_rounded, size: 18),
                                label: Text(
                                  _resendCooldown > 0
                                      ? 'Resend Verification in ${_resendCooldown}s'
                                      : 'Resend Verification Email',
                                  style: const TextStyle(fontWeight: FontWeight.w700),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              const GmailBindingCard(),
              const SizedBox(height: 20),
              ],

              if (showPassword) ...[
              // ── B. UPDATE PASSWORD ─────────────────────────────────────────
              Form(
                key: _formKey,
                child: Container(
                  width: double.infinity,
                  padding: AppUi.cardPadding,
                  decoration: AppUi.cardDecorationOf(context),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const AppFormSectionHeader(
                        title: 'UPDATE PASSWORD',
                        subtitle:
                            'Maintain a secure password with at least 8 characters. You will need your current password to confirm changes.',
                      ),
                      AppUi.vGapLg,

                      if (_isGoogleOAuth) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppUi.brandSoftOf(context),
                            borderRadius: BorderRadius.circular(AppUi.radiusControl),
                            border: Border.all(color: AppUi.blueBorder),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.g_mobiledata_rounded, size: 28, color: AppUi.brandOf(context)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Your account is signed in with Google. You can set a password below to allow sign-in with email and password as well.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    height: 1.4,
                                    color: AppUi.textPrimaryOf(context),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        AppUi.vGapLg,
                      ],

                      // 1. Current Password (required for password-based accounts)
                      if (!_isGoogleOAuth) ...[
                        AppFormField(
                          controller: _currentPasswordController,
                          label: 'Current Password',
                          prefixIcon: Icons.lock_outline_rounded,
                          isPassword: true,
                          onChanged: (_) {
                            if (_currentPasswordError != null) {
                              setState(() => _currentPasswordError = null);
                            }
                          },
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Enter your current password.';
                            }
                            if (_currentPasswordError != null) {
                              return _currentPasswordError;
                            }
                            return null;
                          },
                        ),
                        AppUi.vGapLg,
                      ],

                      // 2. New Password
                      AppFormField(
                        controller: _newPasswordController,
                        label: 'New Password',
                        prefixIcon: Icons.lock_reset_rounded,
                        isPassword: true,
                        validator: (value) {
                          if (value == null || value.length < 8) {
                            return 'Password must be at least 8 characters.';
                          }
                          return null;
                        },
                      ),
                      AppUi.vGapLg,

                      // 3. Confirm New Password
                      AppFormField(
                        controller: _confirmPasswordController,
                        label: 'Confirm New Password',
                        prefixIcon: Icons.check_circle_outline_rounded,
                        isPassword: true,
                        validator: (value) {
                          if (value == null || value.length < 8) {
                            return 'Confirm password must be at least 8 characters.';
                          }
                          if (value != _newPasswordController.text) {
                            return 'Passwords do not match.';
                          }
                          return null;
                        },
                      ),
                      AppUi.vGapXl,

                      AppFormSubmitButton(
                        text: _isGoogleOAuth ? 'Set Password' : 'Update Password',
                        icon: Icons.lock_reset_rounded,
                        isLoading: _isSavingPassword,
                        onPressed: _updatePassword,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              ],

              if (widget.section == null) ...[
              // ── C. DANGER ZONE (DELETE ACCOUNT) ───────────────────────────
              Container(
                width: double.infinity,
                padding: AppUi.cardPadding,
                decoration: BoxDecoration(
                  color: AppUi.surfaceOf(context),
                  borderRadius: AppUi.radiusLg,
                  border: Border.all(color: AppUi.error.withValues(alpha: 0.35)),
                  boxShadow: [
                    BoxShadow(
                      color: AppUi.error.withValues(alpha: 0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: AppUi.error.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(AppUi.radiusControl),
                          ),
                          child: const Icon(
                            Icons.delete_forever_rounded,
                            color: AppUi.error,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'DANGER ZONE',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.0,
                            color: AppUi.error,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Permanently delete your user account and all personal information. This process cannot be reversed.',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppUi.textSecondaryOf(context),
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '• Orders in transit must be completed or settled prior to deletion.\n'
                      '• Audit histories will be unlinked and personal identity will be scrubbed.',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppUi.textSecondaryOf(context),
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppUi.error,
                          side: const BorderSide(color: AppUi.error),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppUi.radiusControl),
                          ),
                        ),
                        icon: _isDeleting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppUi.error,
                                ),
                              )
                            : const Icon(Icons.delete_outline_rounded, size: 20),
                        label: Text(
                          _isDeleting ? 'Deleting Account...' : 'Delete Account',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        onPressed: _isDeleting ? null : _promptAccountDeletion,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
