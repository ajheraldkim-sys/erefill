import 'package:erefill/core/constants.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/admin_api_service.dart';
import '../../widgets/admin_ui.dart';

import 'package:erefill/core/theme/app_colors.dart';
import 'package:erefill/core/utils/friendly_errors.dart';
Future<bool?> showUserManageDialog(
  BuildContext context, {
  required String userId,
  Map<String, dynamic>? initial,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => _UserManageDialog(userId: userId, initial: initial),
  );
}

class _UserManageDialog extends StatefulWidget {
  const _UserManageDialog({required this.userId, this.initial});

  final String userId;
  final Map<String, dynamic>? initial;

  @override
  State<_UserManageDialog> createState() => _UserManageDialogState();
}

class _UserManageDialogState extends State<_UserManageDialog> {
  bool _loading = true;
  bool _saving = false;
  String? _error;
  Map<String, dynamic>? _detail;

  late TextEditingController _fullName;
  late TextEditingController _phone;
  String? _town;
  bool _needsTownCorrection = false;
  late String _role;

  @override
  void initState() {
    super.initState();
    _fullName = TextEditingController();
    _phone = TextEditingController();
    _role = widget.initial?['role']?.toString().toLowerCase() ?? 'customer';
    _load();
  }

  @override
  void dispose() {
    _fullName.dispose();
    _phone.dispose();
    super.dispose();
  }

  Map<String, dynamic> get _profile {
    final p = _detail?['profile'];
    if (p is Map) return Map<String, dynamic>.from(p);
    return widget.initial ?? {};
  }

  bool get _isSuspended => _profile['is_suspended'] == true;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detail = await context.read<AdminApiService>().getUserDetail(
        widget.userId,
      );
      if (!mounted) return;
      _detail = detail;
      _bindFields(_profile);
    } catch (e) {
      if (!mounted) return;
      if (widget.initial != null) {
        _detail = {'profile': widget.initial};
        _bindFields(widget.initial!);
      } else {
        _error = e.toString();
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _bindFields(Map<String, dynamic> p) {
    _fullName.text = p['full_name']?.toString() ?? '';
    _phone.text = p['phone']?.toString() ?? '';
    final rawTown = p['town']?.toString().trim();
    _town = null;
    for (final town in AppConstants.municipalityData.keys) {
      if (town.toLowerCase() == rawTown?.toLowerCase()) {
        _town = town;
        break;
      }
    }
    _needsTownCorrection =
        rawTown != null && rawTown.isNotEmpty && _town == null;
    final r = p['role']?.toString().toLowerCase() ?? 'customer';
    _role = ['customer', 'owner', 'rider', 'admin'].contains(r)
        ? r
        : 'customer';
  }

  Future<void> _saveChanges() async {
    if (_needsTownCorrection && _town == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Select Cantilan or Madrid before saving this user.'),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    final api = context.read<AdminApiService>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      await api.updateUserProfile(
        userId: widget.userId,
        fullName: _fullName.text.trim(),
        phone: _phone.text.trim(),
        town: _town,
        role: _role,
        reason: 'Updated from admin user manager',
      );
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text('User profile updated successfully'),
          backgroundColor: AppUi.accentGreen,
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Error: ${FriendlyErrors.message(e)}'), backgroundColor: AppUi.error),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _toggleSuspend() async {
    final api = context.read<AdminApiService>();
    final messenger = ScaffoldMessenger.of(context);
    final name = _fullName.text.isNotEmpty ? _fullName.text : 'User';

    if (_isSuspended) {
      final confirmed = await showAdminConfirmDialog(
        context,
        title: 'Unsuspend $name?',
        message: 'This will restore their ability to log in and place orders.',
        confirmLabel: 'Unsuspend',
        icon: LucideIcons.lockOpen,
        iconColor: AppUi.accentGreen,
      );
      if (confirmed != true || !mounted) return;

      setState(() => _saving = true);
      try {
        await api.unsuspendUser(widget.userId, reason: 'Reactivated by admin');
        if (!mounted) return;
        messenger.showSnackBar(
          SnackBar(
            content: Text('$name is now active'),
            backgroundColor: AppUi.accentGreen,
          ),
        );
        Navigator.pop(context, true);
      } catch (e) {
        if (!mounted) return;
        messenger.showSnackBar(
          SnackBar(content: Text('Error: ${FriendlyErrors.message(e)}'), backgroundColor: AppUi.error),
        );
      } finally {
        if (mounted) setState(() => _saving = false);
      }
    } else {
      final reason = await showAdminPromptDialog(
        context,
        title: 'Suspend $name?',
        subtitle: 'User will immediately lose access to place orders',
        icon: LucideIcons.ban,
        iconColor: adminSemanticErrorColor(context),
        label: 'Suspension reason',
        hint: 'Why is this account being suspended?',
        confirmLabel: 'Suspend User',
      );
      if (reason == null || !mounted) return;

      setState(() => _saving = true);
      try {
        await api.suspendUser(
          widget.userId,
          reason: reason.isEmpty ? 'Suspended by admin' : reason,
        );
        if (!mounted) return;
        messenger.showSnackBar(
          SnackBar(
            content: Text('$name has been suspended'),
            backgroundColor: AppUi.error,
          ),
        );
        Navigator.pop(context, true);
      } catch (e) {
        if (!mounted) return;
        messenger.showSnackBar(
          SnackBar(content: Text('Error: ${FriendlyErrors.message(e)}'), backgroundColor: AppUi.error),
        );
      } finally {
        if (mounted) setState(() => _saving = false);
      }
    }
  }

  Future<void> _deleteUser() async {
    final name = _fullName.text.isNotEmpty ? _fullName.text : 'this user';
    final confirmed = await showAdminConfirmDialog(
      context,
      title: 'Delete user permanently?',
      message:
          'This will remove $name from the system. This action cannot be undone.',
      confirmLabel: 'Delete',
      isDestructive: true,
      icon: LucideIcons.trash2,
    );
    if (confirmed != true || !mounted) return;

    setState(() => _saving = true);
    try {
      await context.read<AdminApiService>().deleteUser(
        widget.userId,
        reason: 'Deleted by admin',
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${FriendlyErrors.message(e)}'), backgroundColor: AppUi.error),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = _profile['email']?.toString() ?? 'No email';
    final name = _fullName.text.isNotEmpty
        ? _fullName.text
        : (_profile['full_name']?.toString() ?? 'User Profile');
    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'U';

    return AdminModalDialog(
      title: 'Manage User',
      subtitle: email,
      icon: LucideIcons.userCog,
      maxWidth: 480,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            'Cancel',
            style: TextStyle(color: AppUi.textSecondaryOf(context)),
          ),
        ),
        const SizedBox(width: 8),
        AdminManageButton(
          height: 38,
          text: 'Save Changes',
          isLoading: _saving,
          onPressed: _saving ? null : _saveChanges,
        ),
      ],
      child: _loading
          ? const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            )
          : _error != null && _detail == null
          ? Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Text(_error!, style: TextStyle(color: AppUi.error)),
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header Card with Avatar, Name, Email and Status
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(AppUi.radiusCard),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 24,
                          backgroundColor: AppUi.bluePrimary.withValues(
                            alpha: 0.15,
                          ),
                          child: Text(
                            initial,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: AppUi.brandOf(context),
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                ),
                              ),
                              Text(
                                email,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: AppUi.textSecondaryOf(context),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (_isSuspended)
                          const AdminBadge(
                            label: 'SUSPENDED',
                            color: AppColors.uiError,
                            icon: LucideIcons.ban,
                          )
                        else
                          const AdminBadge(
                            label: 'ACTIVE',
                            color: AppColors.uiSuccess,
                            icon: LucideIcons.circleCheck,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Simple Form Fields
                  AdminTextField(
                    controller: _fullName,
                    label: 'Full Name',
                    icon: LucideIcons.user,
                  ),
                  const SizedBox(height: 14),

                  AdminTextField(
                    controller: _phone,
                    label: 'Phone Number',
                    icon: LucideIcons.phone,
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 14),

                  AdminDropdownFormField<String>(
                    label: 'User Role',
                    value: _role,
                    icon: LucideIcons.shield,
                    items: const [
                      DropdownMenuItem(
                        value: 'customer',
                        child: Text('Customer (Buyer)'),
                      ),
                      DropdownMenuItem(
                        value: 'owner',
                        child: Text('Station Owner'),
                      ),
                      DropdownMenuItem(
                        value: 'rider',
                        child: Text('Delivery Rider'),
                      ),
                      DropdownMenuItem(
                        value: 'admin',
                        child: Text('System Administrator'),
                      ),
                    ],
                    onChanged: (val) {
                      if (val != null) setState(() => _role = val);
                    },
                  ),
                  const SizedBox(height: 14),

                  AdminDropdownFormField<String>(
                    label: 'Municipality',
                    hint: _needsTownCorrection
                        ? 'Choose Cantilan or Madrid'
                        : 'Select municipality',
                    value: _town,
                    icon: LucideIcons.mapPin,
                    items: AppConstants.municipalityData.keys
                        .map(
                          (town) =>
                              DropdownMenuItem(value: town, child: Text(town)),
                        )
                        .toList(),
                    onChanged: (town) => setState(() {
                      _town = town;
                      if (town != null) _needsTownCorrection = false;
                    }),
                  ),
                  const SizedBox(height: 24),

                  // Prominent Suspend / Unsuspend Button
                  if (_isSuspended)
                    AdminActivateButton(
                      height: 42,
                      text: 'Unsuspend Account',
                      isLoading: _saving,
                      onPressed: _saving ? null : _toggleSuspend,
                    )
                  else
                    AdminSuspendButton(
                      height: 42,
                      text: 'Suspend Account',
                      isLoading: _saving,
                      onPressed: _saving ? null : _toggleSuspend,
                    ),

                  const SizedBox(height: 16),
                  Center(
                    child: TextButton.icon(
                      onPressed: _saving ? null : _deleteUser,
                      icon: const Icon(
                        LucideIcons.trash2,
                        size: 14,
                        color: AppColors.uiError,
                      ),
                      label: const Text(
                        'Delete User Permanently',
                        style: TextStyle(
                          color: AppColors.uiError,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
