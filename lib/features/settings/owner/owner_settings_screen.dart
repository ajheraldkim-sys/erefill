import 'package:erefill/core/utils/money.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants.dart';
import '../../../core/providers/user_provider.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/app_form_fields.dart';
import '../../../core/utils/friendly_errors.dart';
import '../../../core/utils/profile_query_helpers.dart';
import 'owner_settings_service.dart';

class OwnerSettingsScreen extends StatefulWidget {
  const OwnerSettingsScreen({super.key});

  @override
  State<OwnerSettingsScreen> createState() => _OwnerSettingsScreenState();
}

class _OwnerSettingsScreenState extends State<OwnerSettingsScreen> {
  final _service = OwnerSettingsService();
  final _formKey = GlobalKey<FormState>();
  final _stationNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _deliveryFeeController = TextEditingController();
  final _priceController = TextEditingController();
  final _commissionController = TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;
  String? _loadError;
  static const _paymentMethods = <(String, String)>[
    ('cod', 'Cash on Delivery'),
    ('gcash', 'GCash'),
    ('maya', 'Maya'),
    ('card', 'Credit / debit card'),
  ];
  List<String> _enabledPaymentMethods = ['cod', 'gcash', 'maya', 'card'];
  double? _systemDeliveryRate;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final client = Supabase.instance.client;
    final currentAuthUser = client.auth.currentUser;
    final user = context.read<UserProvider>().user;
    final userId = currentAuthUser?.id ?? user?.id;
    if (userId == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final profileFuture = client
          .from('profiles')
          .select('station_name, phone, email, commission_rate, price_per_gallon')
          .eq('id', userId)
          .maybeSingle();
      final settingsFuture = _service.getSettings(userId);

      final results = await Future.wait([profileFuture, settingsFuture]);
      final profile = results[0];
      final settings = results[1];

      try {
        final delivCfg = await client.rpc('get_delivery_fee_config');
        if (delivCfg is Map && delivCfg['rate_per_km'] != null) {
          _systemDeliveryRate = (delivCfg['rate_per_km'] as num).toDouble();
        }
      } catch (_) {}

      if (mounted) {
        _stationNameController.text = profile?['station_name'] ?? '';
        _phoneController.text = profile?['phone'] ?? '';
        _emailController.text =
            profile?['email'] ?? currentAuthUser?.email ?? user?.email ?? '';
        _priceController.text =
            (settings?['price_per_gallon'] as num?)?.toStringAsFixed(2) ??
            (profile?['price_per_gallon'] as num?)?.toStringAsFixed(2) ??
            '15.00';
        _commissionController.text =
            (profile?['commission_rate'] as num?)?.toStringAsFixed(2) ??
            '5.00';
        final configuredMethods = settings?['enabled_payment_methods'];
        if (configuredMethods is List) {
          _enabledPaymentMethods = configuredMethods
              .whereType<String>()
              .where((method) =>
                  _paymentMethods.any((option) => option.$1 == method))
              .toSet()
              .toList();
        }

        setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('Error loading station settings: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadError = 'Could not load station settings.';
        });
      }
    }
  }

  Future<void> _saveSettings() async {
    if (!_formKey.currentState!.validate()) return;
    if (_enabledPaymentMethods.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enable at least one payment method.')),
      );
      return;
    }

    final client = Supabase.instance.client;
    final userId =
        client.auth.currentUser?.id ?? context.read<UserProvider>().user?.id;
    if (userId == null) return;

    setState(() => _isSaving = true);

    try {
      final price = double.tryParse(_priceController.text) ?? 15.0;
      final commission = double.tryParse(_commissionController.text) ?? 0.0;

      await ProfileQueryHelpers.updateProfile(client, {
        'station_name': _stationNameController.text.trim(),
        'phone': _phoneController.text.trim(),
        'price_per_gallon': price,
        'commission_rate': commission,
      }, userId: userId);

      await _service.updateSettings(userId, {
        'price_per_gallon': price,
        'enabled_payment_methods': _enabledPaymentMethods,
      });

      try {
        await client.rpc('sync_owner_default_product', params: {'p_owner_id': userId});
      } catch (e) {
        debugPrint('Product sync failed: $e');
      }

      if (mounted) {
        await context.read<UserProvider>().refreshProfile();
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Station settings saved successfully.'),
          backgroundColor: AppUi.successFg,
        ),
      );
    } catch (e) {
      debugPrint('Error saving station settings: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            FriendlyErrors.message(
              e,
              fallback: 'Unable to save station settings. Please try again.',
            ),
          ),
          backgroundColor: AppUi.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  void dispose() {
    _stationNameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _deliveryFeeController.dispose();
    _priceController.dispose();
    _commissionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppUi.pageBgOf(context),
      appBar: AppBar(
        title: const Text('Station Settings'),
        centerTitle: true,
        backgroundColor: AppUi.pageBgOf(context),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: _isLoading
          ? const SkeletonList(itemCount: 6)
          : _loadError != null
          ? Center(
              child: Padding(
                padding: AppUi.pagePadding,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_loadError!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () {
                        setState(() {
                          _isLoading = true;
                          _loadError = null;
                        });
                        _loadSettings();
                      },
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            )
          : SafeArea(
              child: SingleChildScrollView(
                padding: AppUi.pagePadding,
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: double.infinity,
                        padding: AppUi.cardPadding,
                        decoration: AppUi.cardDecorationOf(context),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const AppFormSectionHeader(
                              title: 'STATION PROFILE',
                              subtitle: 'Your public station brand & contact information',
                            ),
                            AppUi.vGapLg,
                            AppFormField(
                              controller: _stationNameController,
                              label: 'Station Name',
                              prefixIcon: Icons.storefront_outlined,
                              compact: true,
                              validator: (v) =>
                                  (v == null || v.trim().isEmpty)
                                      ? 'Station name is required.'
                                      : null,
                            ),
                            AppUi.vGapMd,
                            AppFormField(
                              controller: _phoneController,
                              label: 'Contact Phone Number',
                              prefixIcon: Icons.phone_outlined,
                              keyboardType: TextInputType.phone,
                              compact: true,
                              validator: (v) =>
                                  (v == null || v.trim().isEmpty)
                                      ? 'Phone number is required.'
                                      : null,
                            ),
                            AppUi.vGapMd,
                            AppFormField(
                              controller: _emailController,
                              label: 'Support Email (Read-only)',
                              prefixIcon: Icons.email_outlined,
                              keyboardType: TextInputType.emailAddress,
                              enabled: false,
                              compact: true,
                              validator: (v) =>
                                  (v == null || v.trim().isEmpty)
                                      ? 'Support email is required.'
                                      : null,
                            ),
                          ],
                        ),
                      ),
                      AppUi.vGapLg,
                      Container(
                        width: double.infinity,
                        padding: AppUi.cardPadding,
                        decoration: AppUi.cardDecorationOf(context),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const AppFormSectionHeader(
                              title: 'PRICING & DELIVERY',
                              subtitle: 'Configure order pricing and rider commissions',
                            ),
                            AppUi.vGapLg,
                            AppFormField(
                              controller: _priceController,
                              label: 'Price per Gallon (₱)',
                              prefixIcon: Icons.payments_outlined,
                              keyboardType: const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                              compact: true,
                              validator: (value) => _validateNumber(
                                value,
                                'Price per gallon',
                              ),
                            ),
                            AppUi.vGapMd,
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppUi.brandSoftOf(context),
                                borderRadius: BorderRadius.circular(AppUi.radiusCard),
                                border: Border.all(
                                  color: AppUi.bluePrimary.withValues(alpha: 0.25),
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    Icons.verified_outlined,
                                    color: AppUi.brandOf(context),
                                    size: 20,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            const Text(
                                              'Delivery Fee Policy',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w700,
                                                fontSize: 13,
                                              ),
                                            ),
                                            Container(
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 6,
                                                vertical: 2,
                                              ),
                                              decoration: BoxDecoration(
                                                color: AppUi.bluePrimary,
                                                borderRadius:
                                                    BorderRadius.circular(AppUi.radiusSm),
                                              ),
                                              child: const Text(
                                                'Centralized',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          _systemDeliveryRate == null ? 'Delivery rates are set centrally by the eRefill admin.' : 'Delivery rate: ${formatPeso(_systemDeliveryRate)}/km, set centrally by the eRefill admin. Station owners cannot change it.',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            height: 1.35,
                                            color: AppUi.textSecondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            AppUi.vGapMd,
                            AppFormField(
                              controller: _commissionController,
                              label: 'Rider Commission per Gallon (₱)',
                              prefixIcon: Icons.two_wheeler_outlined,
                              keyboardType: const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                              compact: true,
                              validator: (value) => _validateNumber(
                                value,
                                'Rider commission',
                              ),
                            ),
                          ],
                        ),
                      ),
                      AppUi.vGapLg,
                      Material(
                        color: AppUi.surfaceOf(context),
                        shape: RoundedRectangleBorder(
                          borderRadius: AppUi.cardRadius,
                          side: BorderSide(color: AppUi.borderOf(context)),
                        ),
                        child: Container(
                          width: double.infinity,
                          padding: AppUi.cardPadding,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                            const AppFormSectionHeader(
                              title: 'PAYMENT METHODS',
                              subtitle:
                                  'Choose which methods customers can use at your station',
                            ),
                            AppUi.vGapMd,
                            ..._paymentMethods.map(
                              (option) => Material(
                                color: Colors.transparent,
                                child: SwitchListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(option.$2),
                                  value: _enabledPaymentMethods.contains(
                                    option.$1,
                                  ),
                                  onChanged: (enabled) {
                                    setState(() {
                                      if (enabled) {
                                        _enabledPaymentMethods = [
                                          ..._enabledPaymentMethods,
                                          option.$1,
                                        ];
                                      } else {
                                        _enabledPaymentMethods.remove(option.$1);
                                      }
                                    });
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    AppUi.vGapXl,
                      AppFormSubmitButton(
                        text: 'Save Station Settings',
                        icon: Icons.check_circle_rounded,
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

  String? _validateNumber(String? value, String label) {
    if (value == null || value.trim().isEmpty) {
      return '$label is required.';
    }
    final parsed = double.tryParse(value.trim());
    return (parsed == null || parsed < 0)
        ? 'Enter a valid value greater than or equal to 0.'
        : null;
  }
}
