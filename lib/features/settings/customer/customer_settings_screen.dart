import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/providers/theme_provider.dart';
import '../../../core/providers/user_provider.dart';
import '../../../core/widgets/app_form_fields.dart';
import 'user_settings_service.dart';

class CustomerSettingsScreen extends StatefulWidget {
  const CustomerSettingsScreen({super.key});

  @override
  State<CustomerSettingsScreen> createState() => _CustomerSettingsScreenState();
}

class _CustomerSettingsScreenState extends State<CustomerSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _usernameController = TextEditingController();

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _hydrateFromUser();
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _usernameController.dispose();
    super.dispose();
  }

  void _hydrateFromUser() {
    final user = context.read<UserProvider>().user;
    if (user == null) return;

    _firstNameController.text = user.firstName ?? '';
    _lastNameController.text = user.lastName ?? '';
    _phoneController.text = user.phone ?? '';
    _emailController.text = user.email;
    _usernameController.text = user.username ?? '';
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final user = context.read<UserProvider>().user;
    if (user == null) return;

    setState(() => _isSaving = true);

    try {
      await context.read<UserProvider>().updateProfile({
        'first_name': _firstNameController.text.trim(),
        'last_name': _lastNameController.text.trim(),
        'phone': _phoneController.text.trim(),
        'username': _usernameController.text.trim(),
        'email': _emailController.text.trim(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile updated.'),
          backgroundColor: AppUi.successFg,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to update profile. Please try again.'),
          backgroundColor: AppUi.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppUi.pageBgOf(context),
      appBar: AppBar(
        title: const Text('Customer settings'),
        centerTitle: true,
        backgroundColor: AppUi.pageBgOf(context),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: AppUi.pagePadding,
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSection(
                  title: 'Profile',
                  icon: Icons.person_outline_rounded,
                  children: [
                    AppFormField(
                      label: 'First name',
                      prefixIcon: Icons.person_outline_rounded,
                      controller: _firstNameController,
                      compact: true,
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'First name is required.'
                          : null,
                    ),
                    AppUi.vGapMd,
                    AppFormField(
                      label: 'Last name',
                      prefixIcon: Icons.badge_outlined,
                      controller: _lastNameController,
                      compact: true,
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Last name is required.'
                          : null,
                    ),
                    AppUi.vGapMd,
                    AppFormField(
                      label: 'Phone number',
                      prefixIcon: Icons.phone_outlined,
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      compact: true,
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'Phone number is required.';
                        }
                        if (v.replaceAll(RegExp(r'[^0-9+]'), '').length < 8) {
                          return 'Enter a valid phone number.';
                        }
                        return null;
                      },
                    ),
                    AppUi.vGapMd,
                    AppFormField(
                      label: 'Email (Read-only)',
                      prefixIcon: Icons.email_outlined,
                      controller: _emailController,
                      enabled: false,
                      compact: true,
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Email is required.'
                          : null,
                    ),
                    AppUi.vGapMd,
                    AppFormField(
                      label: 'Username',
                      prefixIcon: Icons.alternate_email_rounded,
                      controller: _usernameController,
                      compact: true,
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Username is required.'
                          : null,
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                _buildSection(
                  title: 'Order preferences',
                  icon: Icons.receipt_long_outlined,
                  children: [
                    _buildToggle(
                      title: 'Include delivery notes by default',
                      subtitle:
                          'Keep your saved delivery notes ready at checkout',
                      value: context
                          .watch<UserSettingsService>()
                          .defaultOrderNotes,
                      onChanged: (v) => context
                          .read<UserSettingsService>()
                          .setDefaultOrderNotes(v),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                _buildSection(
                  title: 'Notifications',
                  icon: Icons.notifications_outlined,
                  children: [
                    _buildToggle(
                      title: 'Order updates',
                      subtitle: 'Status changes and delivery alerts',
                      value: context
                          .watch<UserSettingsService>()
                          .notifyOrderUpdates,
                      onChanged: (v) => context
                          .read<UserSettingsService>()
                          .setNotifyOrderUpdates(v),
                    ),
                    _buildToggle(
                      title: 'Promotions',
                      subtitle: 'Nearby station offers and updates',
                      value: context
                          .watch<UserSettingsService>()
                          .notifyPromotions,
                      onChanged: (v) => context
                          .read<UserSettingsService>()
                          .setNotifyPromotions(v),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                _buildSection(
                  title: 'App preferences',
                  icon: Icons.tune_rounded,
                  children: [
                    _buildToggle(
                      title: 'Dark mode',
                      subtitle: 'Use the dark app theme',
                      value: context.select<ThemeProvider, bool>(
                        (p) => p.isDarkMode,
                      ),
                      onChanged: (v) =>
                          context.read<ThemeProvider>().setDarkMode(v),
                    ),
                    _buildToggle(
                      title: 'Outdoor mode (High Contrast)',
                      subtitle: 'Pure white background and pitch-black text for direct sunlight',
                      value: context.select<ThemeProvider, bool>(
                        (p) => p.isOutdoorMode,
                      ),
                      onChanged: (v) =>
                          context.read<ThemeProvider>().setOutdoorMode(v),
                    ),
                    const Divider(height: 24),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Language / Wika / Pinulongan',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Choose your preferred language across the app',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppUi.textSecondaryOf(context),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Consumer<AppLanguageProvider>(
                          builder: (context, langProvider, _) {
                            return Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: AppLanguage.values.map((lang) {
                                final isSelected = langProvider.language == lang;
                                return ChoiceChip(
                                  label: Text('${lang.label} (${lang.subtitle})'),
                                  selected: isSelected,
                                  onSelected: (_) => langProvider.setLanguage(lang),
                                  selectedColor: AppUi.bluePrimary.withValues(alpha: 0.15),
                                  labelStyle: TextStyle(
                                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                    color: isSelected ? AppUi.brandOf(context) : AppUi.textPrimaryOf(context),
                                  ),
                                );
                              }).toList(),
                            );
                          },
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                AppFormSubmitButton(
                  text: 'Save Changes',
                  icon: Icons.save_outlined,
                  isLoading: _isSaving,
                  onPressed: _save,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: AppUi.cardDecorationOf(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppUi.brandOf(context)),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }

  Widget _buildToggle({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 12, color: AppUi.textMutedOf(context)),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            activeThumbColor: AppUi.bluePrimary,
            activeTrackColor: AppUi.bluePrimary.withValues(alpha: 0.3),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
