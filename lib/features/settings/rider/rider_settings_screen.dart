import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants.dart';
import '../../../core/providers/user_provider.dart';
import '../../../core/widgets/app_form_fields.dart';
import '../../../core/widgets/skeleton.dart';
import 'rider_settings_service.dart';

class RiderSettingsScreen extends StatefulWidget {
  const RiderSettingsScreen({super.key});

  @override
  State<RiderSettingsScreen> createState() => _RiderSettingsScreenState();
}

class _RiderSettingsScreenState extends State<RiderSettingsScreen> {
  final _service = RiderSettingsService();
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _vehicleController = TextEditingController();
  final _licenseController = TextEditingController();

  bool _notifyAssignments = true;
  bool _notifyOrderUpdates = true;
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final user = context.read<UserProvider>().user;
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    final preferences = await _service.load(userId);
    final profile = await Supabase.instance.client
        .from('profiles')
        .select('first_name, last_name, vehicle_type, license_number')
        .eq('id', userId)
        .maybeSingle();

    if (!mounted) return;
    _firstNameController.text =
        profile?['first_name']?.toString() ?? user?.firstName ?? '';
    _lastNameController.text =
        profile?['last_name']?.toString() ?? user?.lastName ?? '';
    _phoneController.text = user?.phone ?? '';
    _vehicleController.text = profile?['vehicle_type']?.toString() ?? '';
    _licenseController.text = profile?['license_number']?.toString() ?? '';
    setState(() {
      _notifyAssignments = preferences['notifyAssignments'] as bool;
      _notifyOrderUpdates = preferences['notifyOrderUpdates'] as bool;
      _isLoading = false;
    });
  }

  Future<void> _saveSettings() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    try {
      final fname = _firstNameController.text.trim();
      final lname = _lastNameController.text.trim();
      final composedName = '$fname $lname'.trim();

      await context.read<UserProvider>().updateProfile({
        'first_name': fname,
        'last_name': lname,
        if (composedName.isNotEmpty) 'full_name': composedName,
        'phone': _phoneController.text.trim(),
        'vehicle_type': _vehicleController.text.trim(),
        'license_number': _licenseController.text.trim(),
      });
      await _service.save(
        userId: Supabase.instance.client.auth.currentUser!.id,
        notifyAssignments: _notifyAssignments,
        notifyOrderUpdates: _notifyOrderUpdates,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Rider settings saved.'),
          backgroundColor: AppUi.successFg,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to save rider settings.'),
          backgroundColor: AppUi.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    _vehicleController.dispose();
    _licenseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppUi.pageBgOf(context),
      appBar: AppBar(
        title: const Text('Rider settings'),
        centerTitle: true,
        backgroundColor: AppUi.pageBgOf(context),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: _isLoading
          ? const SkeletonList(itemCount: 6)
          : SafeArea(
              child: SingleChildScrollView(
                padding: AppUi.pagePadding,
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      _buildSection(
                        title: 'Rider profile',
                        icon: Icons.person_outline_rounded,
                        children: [
                          AppFormField(
                            controller: _firstNameController,
                            label: 'First name',
                            prefixIcon: Icons.person_outline_rounded,
                            compact: true,
                            validator: (v) =>
                                (v == null || v.trim().isEmpty)
                                    ? 'First name is required.'
                                    : null,
                          ),
                          AppUi.vGapMd,
                          AppFormField(
                            controller: _lastNameController,
                            label: 'Last name',
                            prefixIcon: Icons.badge_outlined,
                            compact: true,
                            validator: (v) =>
                                (v == null || v.trim().isEmpty)
                                    ? 'Last name is required.'
                                    : null,
                          ),
                          AppUi.vGapMd,
                          AppFormField(
                            controller: _phoneController,
                            label: 'Phone number',
                            prefixIcon: Icons.phone_outlined,
                            keyboardType: TextInputType.phone,
                            compact: true,
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) {
                                return 'Phone number is required.';
                              }
                              if (v.replaceAll(RegExp(r'[^0-9+]'), '').length <
                                  8) {
                                return 'Enter a valid phone number.';
                              }
                              return null;
                            },
                          ),
                          AppUi.vGapMd,
                          AppFormField(
                            controller: _vehicleController,
                            label: 'Vehicle type',
                            prefixIcon: Icons.delivery_dining_rounded,
                            compact: true,
                          ),
                          AppUi.vGapMd,
                          AppFormField(
                            controller: _licenseController,
                            label: 'License number',
                            prefixIcon: Icons.badge_rounded,
                            compact: true,
                            validator: (value) =>
                                value == null || value.trim().isEmpty
                                    ? 'License number is required.'
                                    : null,
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      _buildSection(
                        title: 'Delivery preferences',
                        icon: Icons.delivery_dining_outlined,
                        children: [
                          const Text(
                            'Delivery assignment and navigation controls are managed from the active dispatch screen.',
                            style: TextStyle(
                              color: AppUi.textMuted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      _buildSection(
                        title: 'Notifications',
                        icon: Icons.notifications_outlined,
                        children: [
                          Material(
                            color: Colors.transparent,
                            child: SwitchListTile.adaptive(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('New assignments'),
                              subtitle: const Text(
                                'Alert me when a delivery is assigned.',
                              ),
                              value: _notifyAssignments,
                              onChanged: (value) =>
                                  setState(() => _notifyAssignments = value),
                            ),
                          ),
                          Material(
                            color: Colors.transparent,
                            child: SwitchListTile.adaptive(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Order updates'),
                              subtitle: const Text(
                                'Alert me about changes to active deliveries.',
                              ),
                              value: _notifyOrderUpdates,
                              onChanged: (value) =>
                                  setState(() => _notifyOrderUpdates = value),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      AppFormSubmitButton(
                        text: 'Save Changes',
                        icon: Icons.save_outlined,
                        isLoading: _isSaving,
                        onPressed: _saveSettings,
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
    return Material(
      color: AppUi.surfaceOf(context),
      shape: RoundedRectangleBorder(
        borderRadius: AppUi.cardRadius,
        side: BorderSide(color: AppUi.borderOf(context)),
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: AppUi.bluePrimary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ...children,
          ],
        ),
      ),
    );
  }
}
