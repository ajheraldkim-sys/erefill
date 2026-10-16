import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/constants.dart';
import '../../core/routing/app_routes.dart';
import '../../core/widgets/app_form_fields.dart';
import '../auth/widgets/gmail_binding_card.dart';

class AccountSecurityScreen extends StatefulWidget {
  const AccountSecurityScreen({super.key, required this.role});

  final String role;

  @override
  State<AccountSecurityScreen> createState() => _AccountSecurityScreenState();
}

class _AccountSecurityScreenState extends State<AccountSecurityScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmationController = TextEditingController();
  bool _isSaving = false;
  bool _isDeleting = false;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmationController.dispose();
    super.dispose();
  }

  Future<void> _updatePassword() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: _passwordController.text),
      );
      if (!mounted) return;
      _passwordController.clear();
      _confirmationController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Password updated.'),
          backgroundColor: AppUi.successFg,
        ),
      );
    } on AuthException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message), backgroundColor: AppUi.error),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _promptAccountDeletion() async {
    final confirmationController = TextEditingController();
    bool confirmed = false;

    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: AppUi.surfaceOf(dialogCtx),
          title: Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: AppUi.error),
              const SizedBox(width: 8),
              const Text('Delete Account'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Are you sure you want to delete your account? This action is permanent and cannot be undone.',
                style: TextStyle(height: 1.4),
              ),
              const SizedBox(height: 12),
              const Text(
                'All personal data, order histories, and saved preferences will be wiped or anonymized.',
                style: TextStyle(
                  fontSize: 12,
                  color: AppUi.textSecondary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Type DELETE to confirm:',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: AppUi.textPrimaryOf(context),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: confirmationController,
                decoration: InputDecoration(
                  hintText: 'DELETE',
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: AppUi.error),
                  ),
                ),
                onChanged: (text) {
                  setDialogState(() {
                    confirmed = text.trim() == 'DELETE';
                  });
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppUi.error,
                foregroundColor: Colors.white,
              ),
              onPressed: confirmed
                  ? () => Navigator.pop(dialogCtx, true)
                  : null,
              child: const Text('Permanently Delete'),
            ),
          ],
        ),
      ),
    );

    if (!mounted || shouldDelete != true) {
      confirmationController.dispose();
      return;
    }

    setState(() => _isDeleting = true);
    HapticFeedback.heavyImpact();

    try {
      final client = Supabase.instance.client;
      await client.rpc('delete_user_account');
      await client.auth.signOut(scope: SignOutScope.local);

      if (!mounted) return;
      context.go(AppRoutes.login);
    } catch (e) {
      debugPrint('Error deleting account: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete account: $e'),
            backgroundColor: AppUi.error,
          ),
        );
      }
    } finally {
      confirmationController.dispose();
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title =
        '${widget.role[0].toUpperCase()}${widget.role.substring(1)} Security';
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
            children: [
              const GmailBindingCard(),
              const SizedBox(height: 20),
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
                        title: 'PASSWORD UPDATE',
                        subtitle:
                            'Use a strong password with at least 8 characters that you do not reuse elsewhere.',
                      ),
                      AppUi.vGapLg,
                      AppFormField(
                        controller: _passwordController,
                        label: 'New Password',
                        prefixIcon: Icons.lock_outline_rounded,
                        isPassword: true,
                        validator: (value) {
                          if (value == null || value.length < 8) {
                            return 'Use at least 8 characters.';
                          }
                          return null;
                        },
                      ),
                      AppUi.vGapLg,
                      AppFormField(
                        controller: _confirmationController,
                        label: 'Confirm New Password',
                        prefixIcon: Icons.lock_reset_rounded,
                        isPassword: true,
                        validator: (value) {
                          if (value == null || value.length < 8) {
                            return 'Use at least 8 characters.';
                          }
                          if (value != _passwordController.text) {
                            return 'Passwords do not match.';
                          }
                          return null;
                        },
                      ),
                      AppUi.vGapXl,
                      AppFormSubmitButton(
                        text: 'Update Password',
                        icon: Icons.lock_reset_rounded,
                        isLoading: _isSaving,
                        onPressed: _updatePassword,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Danger Zone / Account Deletion
              Container(
                width: double.infinity,
                padding: AppUi.cardPadding,
                decoration: BoxDecoration(
                  color: AppUi.surfaceOf(context),
                  borderRadius: AppUi.radiusLg,
                  border: Border.all(color: AppUi.error.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.delete_forever_rounded,
                          color: AppUi.error,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'DANGER ZONE',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.0,
                            color: AppUi.error,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Permanently remove your account, profile credentials, and associated authentication history.',
                      style: TextStyle(
                        fontSize: 13,
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
                            borderRadius: BorderRadius.circular(10),
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
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        onPressed: _isDeleting ? null : _promptAccountDeletion,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
