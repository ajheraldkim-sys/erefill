import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/constants.dart';
import '../../../core/water_types.dart';
import '../../../core/providers/theme_provider.dart';
import '../../../core/providers/user_provider.dart';
import '../../../core/widgets/account/account_ui.dart';
import '../../../core/widgets/brand/hero_header.dart';
import '../../../core/widgets/brand/axo_states.dart';
import '../../../core/models/user_model.dart';
import '../../../core/utils/profile_query_helpers.dart';
import 'package:erefill/core/routing/app_navigation.dart';
import '../../../core/widgets/app_form_fields.dart';
import '../../loyalty/widgets/loyalty_rewards_sheet.dart';

class CustomerProfileScreen extends StatefulWidget {
  const CustomerProfileScreen({super.key});

  @override
  State<CustomerProfileScreen> createState() => _CustomerProfileScreenState();
}

class _CustomerProfileScreenState extends State<CustomerProfileScreen> {
  final supabase = Supabase.instance.client;
  bool _isLoading = true;
  String? _loadError;
  LatLng _pickedLocation = const LatLng(9.3333, 125.9833);
  bool _notificationsEnabled = true;

  String _fullName = '';
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _miController = TextEditingController();
  final _suffixController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _landmarkController = TextEditingController();
  final _zipCodeController = TextEditingController();

  bool _isEditingProfile = false;
  bool _isSavingProfile = false;

  final Map<String, List<String>> _municipalityData =
      AppConstants.municipalityData;

  String? _selectedTown;
  String? _selectedBarangay;
  String? _selectedPurok;
  String? _selectedSuffix;
  String _preferredWaterType = WaterTypes.purified.name;

  final List<String> _suffixOptions = [
    'None',
    'Jr.',
    'Sr.',
    'II',
    'III',
    'IV',
    'V',
  ];

  @override
  void initState() {
    super.initState();
    _loadProfileData();
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _miController.dispose();
    _suffixController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _landmarkController.dispose();
    _zipCodeController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final user = Provider.of<UserProvider>(context).user;
    if (user != null && !_isEditingProfile) {
      _updateFieldsFromUser(user);
      _isLoading = false;
    }
  }

  void _updateFieldsFromUser(UserModel user) {
    _firstNameController.text =
        user.firstName ?? user.fullName?.split(' ').first ?? '';
    _lastNameController.text =
        user.lastName ??
        ((user.fullName?.split(' ').length ?? 0) > 1
            ? user.fullName?.split(' ').last
            : '') ??
        '';
    _miController.text = _formatMiddleInitial(user.mi);
    _selectedSuffix = _normalizeSuffix(user.suffix);
    _suffixController.text = _selectedSuffix == 'None' ? '' : _selectedSuffix!;
    _phoneController.text = user.phone ?? '';

    if (user.latitude != null && user.longitude != null) {
      _pickedLocation = LatLng(user.latitude!, user.longitude!);
    }

    String? rawTown = user.town;
    _selectedTown =
        AppConstants.municipalityData.keys
            .firstWhere(
              (k) => k.toLowerCase() == rawTown?.toLowerCase(),
              orElse: () => '',
            )
            .isEmpty
        ? null
        : AppConstants.municipalityData.keys.firstWhere(
            (k) => k.toLowerCase() == rawTown?.toLowerCase(),
          );

    String? rawBrgy = user.barangay;
    if (_selectedTown != null) {
      _selectedBarangay =
          AppConstants.municipalityData[_selectedTown]!
              .firstWhere(
                (b) => b.toLowerCase() == rawBrgy?.toLowerCase(),
                orElse: () => '',
              )
              .isEmpty
          ? null
          : AppConstants.municipalityData[_selectedTown]!.firstWhere(
              (b) => b.toLowerCase() == rawBrgy?.toLowerCase(),
            );
    }

    _selectedPurok = _normalizePurok(
      _selectedTown,
      _selectedBarangay,
      user.purok,
    );
    _zipCodeController.text =
        user.zipCode ?? AppConstants.municipalityZipCodes[_selectedTown] ?? '';
    _addressController.text = user.completeAddress ?? '';
    _landmarkController.text = user.landmark ?? '';
    _preferredWaterType = user.preferredWaterType ?? WaterTypes.purified.name;
  }

  Future<void> _loadProfileData() async {
    final hasExistingData = _firstNameController.text.isNotEmpty || _phoneController.text.isNotEmpty;
    setState(() {
      _loadError = null;
      if (!hasExistingData) {
        _isLoading = true;
      }
    });
    try {
      final user = supabase.auth.currentUser;
      if (user == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final profileData = await ProfileQueryHelpers.fetchProfile(
        supabase,
        user.id,
      );

      if (mounted) {
        setState(() {
          _fullName = profileData['full_name'] ?? '';
          _firstNameController.text = profileData['first_name'] ?? '';
          _lastNameController.text = profileData['last_name'] ?? '';
          _miController.text = _formatMiddleInitial(profileData['mi']);
          _selectedSuffix = _normalizeSuffix(profileData['suffix']);
          _suffixController.text = _selectedSuffix == 'None'
              ? ''
              : _selectedSuffix!;
          _phoneController.text = profileData['phone'] ?? '';

          final rawTown = profileData['town']?.toString();
          _selectedTown = _municipalityData.keys.firstWhere(
            (k) => k.toLowerCase() == rawTown?.toLowerCase(),
            orElse: () => rawTown ?? '',
          );
          if (!_municipalityData.containsKey(_selectedTown)) {
            _selectedTown = null;
          }

          final rawBrgy = profileData['barangay']?.toString();
          if (_selectedTown != null) {
            _selectedBarangay = _municipalityData[_selectedTown]!.firstWhere(
              (b) => b.toLowerCase() == rawBrgy?.toLowerCase(),
              orElse: () => rawBrgy ?? '',
            );
            if (!_municipalityData[_selectedTown]!.contains(
              _selectedBarangay,
            )) {
              _selectedBarangay = null;
            }
          }

          _selectedPurok = _normalizePurok(
            _selectedTown,
            _selectedBarangay,
            profileData['purok']?.toString(),
          );
          _zipCodeController.text =
              profileData['zip_code']?.toString() ??
              AppConstants.municipalityZipCodes[_selectedTown] ??
              '';
          _addressController.text = profileData['complete_address'] ?? '';
          _landmarkController.text = profileData['landmark'] ?? '';
          _preferredWaterType =
              profileData['preferred_water_type']?.toString() ??
              WaterTypes.purified.name;
          if (profileData['latitude'] != null &&
              profileData['longitude'] != null) {
            _pickedLocation = LatLng(
              (profileData['latitude'] as num).toDouble(),
              (profileData['longitude'] as num).toDouble(),
            );
          }
          _isLoading = false;
          _loadError = null;
        });
      }
    } catch (e) {
      debugPrint('Profile load error: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadError = 'Could not load your profile. Pull to retry.';
        });
      }
    }
  }

  String? _normalizeSuffix(String? value) {
    if (value == null || value.trim().isEmpty) return 'None';
    final trimmed = value.trim();
    return _suffixOptions.contains(trimmed) ? trimmed : 'None';
  }

  String _formatMiddleInitial(String? value) {
    if (value == null || value.trim().isEmpty) return '';
    final letter = value.trim().replaceAll('.', '').toUpperCase();
    if (letter.isEmpty) return '';
    return '$letter.';
  }

  void _onMiddleInitialChanged(String value) {
    final letter = value.replaceAll('.', '').toUpperCase();
    if (letter.isEmpty) {
      _miController.value = const TextEditingValue(text: '');
      return;
    }
    _miController.value = TextEditingValue(
      text: '${letter[0]}.',
      selection: const TextSelection.collapsed(offset: 2),
    );
  }

  String? _normalizePurok(String? town, String? barangay, String? purok) {
    if (town == null || barangay == null || purok == null) return null;
    final options = AppConstants.purokData[town]?[barangay];
    if (options == null) return purok;
    for (final option in options) {
      if (option.toLowerCase() == purok.toLowerCase()) return option;
    }
    return options.contains(purok) ? purok : null;
  }

  String get _selectedZipCode =>
      AppConstants.municipalityZipCodes[_selectedTown] ?? '';

  String get _composedFullName {
    final parts = <String>[
      _firstNameController.text.trim(),
      _miController.text.trim(),
      _lastNameController.text.trim(),
      if (_selectedSuffix != null && _selectedSuffix != 'None')
        _selectedSuffix!,
    ].where((p) => p.isNotEmpty);
    return parts.join(' ').replaceAll(RegExp(r'\s+'), ' ');
  }

  String get _composedAddress {
    final parts = <String>[
      ?_selectedPurok,
      if (_addressController.text.trim().isNotEmpty)
        _addressController.text.trim(),
      ?_selectedBarangay,
      ?_selectedTown,
      if (_selectedZipCode.isNotEmpty) _selectedZipCode,
    ];
    return parts.where((p) => p.isNotEmpty).join(', ');
  }

  bool get _profileIsComplete {
    return _firstNameController.text.trim().isNotEmpty &&
        _lastNameController.text.trim().isNotEmpty &&
        _phoneController.text.trim().isNotEmpty &&
        _selectedTown != null &&
        _selectedBarangay != null &&
        _composedAddress.isNotEmpty;
  }

  String get _profileCompletionMessage {
    if (_firstNameController.text.trim().isEmpty ||
        _lastNameController.text.trim().isEmpty ||
        _phoneController.text.trim().isEmpty) {
      return 'Add your name and phone so stations can confirm orders.';
    }
    if (_composedAddress.isEmpty) {
      return 'Add your delivery address and map pin before checkout.';
    }
    return 'Complete your profile for faster checkout.';
  }

  void _openEditProfileSheet() {
    setState(() => _isEditingProfile = true);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          Future<void> handleSave() async {
            final saved = await _savePersonalInfo();
            if (saved && sheetContext.mounted) {
              Navigator.pop(sheetContext);
            } else {
              setSheetState(() {});
            }
          }

          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
            ),
            child: Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(sheetContext).size.height * 0.92,
              ),
              decoration: BoxDecoration(
                color: AppUi.surfaceOf(context),
                borderRadius: AppUi.radiusSheetTop,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 10),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppUi.dividerOf(context),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'About you',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppUi.textPrimaryOf(context),
                        ),
                      ),
                    ),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                      child: _buildAboutYouForm(
                        onChanged: () => setSheetState(() {}),
                        onSave: handleSave,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ).whenComplete(() {
      if (mounted) setState(() => _isEditingProfile = false);
    });
  }

  Future<List<Map<String, dynamic>>> _fetchSavedAddresses() async {
    final customerId = supabase.auth.currentUser?.id;
    if (customerId == null) return const [];

    try {
      final rows = await supabase
          .from('customer_addresses')
          .select()
          .eq('customer_id', customerId)
          .order('is_default', ascending: false)
          .order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(rows);
    } catch (e) {
      debugPrint('Error loading saved addresses list: $e');
      return const [];
    }
  }

  Future<void> _syncSavedAddressToProfile(Map<String, dynamic> addr) async {
    final customerId = supabase.auth.currentUser?.id;
    if (customerId == null) return;

    try {
      final town = addr['town']?.toString();
      final zip = town != null ? AppConstants.municipalityZipCodes[town] : null;
      final payload = <String, dynamic>{
        'complete_address': addr['complete_address'],
        'town': town,
        'barangay': addr['barangay'],
        'landmark': addr['landmark'],
        'latitude': (addr['latitude'] as num?)?.toDouble() ?? 0.0,
        'longitude': (addr['longitude'] as num?)?.toDouble() ?? 0.0,
      };
      if (zip != null) {
        payload['zip_code'] = zip;
      }
      await supabase.from('profiles').update(payload).eq('id', customerId);
    } catch (e) {
      debugPrint('Error syncing saved address to profile: $e');
    }
  }

  Future<void> _showAddressEditorSheet({Map<String, dynamic>? initial}) async {
    final isEditing = initial != null;
    final labelController = TextEditingController(
      text: initial?['label']?.toString() ?? 'Home',
    );
    final addressController = TextEditingController(
      text: initial?['complete_address']?.toString() ?? '',
    );
    final landmarkController = TextEditingController(
      text: initial?['landmark']?.toString() ?? '',
    );

    final municipalityData = AppConstants.municipalityData;
    String? selectedTown = initial?['town']?.toString() ?? _selectedTown;
    if (selectedTown == null || !municipalityData.containsKey(selectedTown)) {
      selectedTown = municipalityData.keys.first;
    }

    String? selectedBarangay =
        initial?['barangay']?.toString() ?? _selectedBarangay;
    final barangays = municipalityData[selectedTown] ?? [];
    if (selectedBarangay != null && !barangays.contains(selectedBarangay)) {
      selectedBarangay = barangays.isNotEmpty ? barangays.first : null;
    } else if (selectedBarangay == null && barangays.isNotEmpty) {
      selectedBarangay = barangays.first;
    }

    bool isDefault = initial?['is_default'] == true;
    bool isSaving = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          Future<void> handleSave() async {
            final label = labelController.text.trim();
            final completeAddress = addressController.text.trim();
            final landmark = landmarkController.text.trim();

            if (label.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Please enter an address label.')),
              );
              return;
            }
            if (selectedTown == null || selectedBarangay == null) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Please select municipality and barangay.'),
                ),
              );
              return;
            }
            if (completeAddress.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Please enter your house/street address.'),
                ),
              );
              return;
            }

            final customerId = supabase.auth.currentUser?.id;
            if (customerId == null) return;

            setSheetState(() => isSaving = true);
            try {
              final payload = {
                'label': label,
                'complete_address': completeAddress,
                'barangay': selectedBarangay,
                'town': selectedTown,
                'landmark': landmark,
                'latitude': _pickedLocation.latitude,
                'longitude': _pickedLocation.longitude,
                'is_default': isDefault,
                'updated_at': DateTime.now().toIso8601String(),
              };

              if (isEditing) {
                await supabase
                    .from('customer_addresses')
                    .update(payload)
                    .eq('id', initial['id']);
                if (isDefault) {
                  await _syncSavedAddressToProfile(payload);
                }
              } else {
                await supabase.from('customer_addresses').insert({
                  'customer_id': customerId,
                  ...payload,
                  'created_at': DateTime.now().toIso8601String(),
                });
                if (isDefault) {
                  await _syncSavedAddressToProfile(payload);
                }
              }

              if (sheetContext.mounted) Navigator.pop(sheetContext);
              await _loadProfileData();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      isEditing
                          ? 'Address updated successfully.'
                          : 'Address added successfully.',
                    ),
                  ),
                );
              }
            } catch (e) {
              debugPrint('Error saving address: $e');
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Could not save address: $e')),
                );
              }
            } finally {
              if (sheetContext.mounted) {
                setSheetState(() => isSaving = false);
              }
            }
          }

          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
            ),
            child: Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(sheetContext).size.height * 0.9,
              ),
              decoration: BoxDecoration(
                color: AppUi.surfaceOf(context),
                borderRadius: AppUi.radiusSheetTop,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 10),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppUi.dividerOf(context),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          isEditing ? 'Edit address' : 'Add delivery address',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: AppUi.textPrimaryOf(context),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, size: 20),
                          onPressed: () => Navigator.pop(sheetContext),
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const AppFormSectionHeader(
                            title: 'ADDRESS DETAILS',
                            subtitle: 'Provide precise address for deliveries',
                          ),
                          AppUi.vGapMd,
                          AppFormField(
                            controller: labelController,
                            label: 'Address Label (e.g. Home, Office)',
                            prefixIcon: Icons.bookmark_outline_rounded,
                            compact: true,
                          ),
                          AppUi.vGapMd,
                          AppDropdownField<String>(
                            value: selectedTown,
                            label: 'Municipality',
                            prefixIcon: Icons.location_city_outlined,
                            compact: true,
                            items: municipalityData.keys
                                .map(
                                  (town) => DropdownMenuItem(
                                    value: town,
                                    child: Text(town),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) {
                              if (value == null) return;
                              setSheetState(() {
                                selectedTown = value;
                                final nextBarangays =
                                    municipalityData[value] ?? [];
                                selectedBarangay =
                                    nextBarangays.contains(selectedBarangay)
                                    ? selectedBarangay
                                    : (nextBarangays.isNotEmpty
                                          ? nextBarangays.first
                                          : null);
                              });
                            },
                          ),
                          AppUi.vGapMd,
                          AppDropdownField<String>(
                            value: selectedBarangay,
                            label: 'Barangay',
                            prefixIcon: Icons.holiday_village_outlined,
                            compact: true,
                            items: (municipalityData[selectedTown] ?? [])
                                .map(
                                  (barangay) => DropdownMenuItem(
                                    value: barangay,
                                    child: Text(barangay),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) =>
                                setSheetState(() => selectedBarangay = value),
                          ),
                          AppUi.vGapMd,
                          AppFormField(
                            controller: addressController,
                            maxLines: 2,
                            label: 'House number / street / block',
                            prefixIcon: Icons.location_on_outlined,
                            compact: true,
                          ),
                          AppUi.vGapMd,
                          AppFormField(
                            controller: landmarkController,
                            label: 'Landmark (Optional)',
                            prefixIcon: Icons.flag_outlined,
                            compact: true,
                          ),
                          AppUi.vGapMd,
                          Container(
                            decoration: AppUi.cardDecorationOf(context),
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Set as default delivery address',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: AppUi.textPrimaryOf(context),
                                    ),
                                  ),
                                ),
                                Switch(
                                  value: isDefault,
                                  onChanged: (value) =>
                                      setSheetState(() => isDefault = value),
                                ),
                              ],
                            ),
                          ),
                          AppUi.vGapLg,
                          AppFormSubmitButton(
                            text: isEditing ? 'Save Changes' : 'Add Address',
                            icon: Icons.check_circle_rounded,
                            isLoading: isSaving,
                            onPressed: handleSave,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _showSavedAddressesSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => FutureBuilder<List<Map<String, dynamic>>>(
        future: _fetchSavedAddresses(),
        builder: (context, snapshot) {
          final addresses = snapshot.data ?? const [];
          return Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(sheetContext).size.height * 0.86,
            ),
            decoration: BoxDecoration(
              color: AppUi.surfaceOf(context),
              borderRadius: AppUi.radiusSheetTop,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppUi.dividerOf(context),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Saved addresses',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppUi.textPrimaryOf(context),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, size: 20),
                        onPressed: () => Navigator.pop(sheetContext),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Flexible(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    children: [
                      if (addresses.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: AppUi.cardDecorationOf(context),
                          child: Text(
                            'No saved addresses yet. Add your first delivery location to make checkout faster.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: AppUi.textSecondaryOf(context),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        )
                      else
                        ...addresses.map((addr) {
                          final label = addr['label']?.toString() ?? 'Address';
                          final fullAddress =
                              [
                                    addr['complete_address']?.toString(),
                                    addr['barangay']?.toString(),
                                    addr['town']?.toString(),
                                  ]
                                  .where((v) => (v ?? '').trim().isNotEmpty)
                                  .join(', ');
                          final isDefault = addr['is_default'] == true;
                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(14),
                            decoration: AppUi.cardDecorationOf(context),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        label,
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w800,
                                          color: AppUi.textPrimaryOf(context),
                                        ),
                                      ),
                                    ),
                                    if (isDefault)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: AppUi.bluePrimary.withValues(
                                            alpha: 0.12,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            999,
                                          ),
                                        ),
                                        child: const Text(
                                          'Default',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  fullAddress,
                                  style: TextStyle(
                                    color: AppUi.textSecondaryOf(context),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if ((addr['landmark']?.toString() ?? '')
                                    .trim()
                                    .isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Text(
                                      'Landmark: ${addr['landmark']}',
                                      style: TextStyle(
                                        color: AppUi.textSecondaryOf(context),
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                const SizedBox(height: 12),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    if (!isDefault)
                                      TextButton.icon(
                                        onPressed: () async {
                                          final customerId =
                                              supabase.auth.currentUser?.id;
                                          if (customerId == null) return;
                                          final messenger =
                                              ScaffoldMessenger.maybeOf(
                                                context,
                                              );

                                          await supabase
                                              .from('customer_addresses')
                                              .update({'is_default': false})
                                              .eq('customer_id', customerId);
                                          await supabase
                                              .from('customer_addresses')
                                              .update({'is_default': true})
                                              .eq('id', addr['id']);
                                          await _syncSavedAddressToProfile(
                                            Map<String, dynamic>.from(addr),
                                          );
                                          if (sheetContext.mounted) {
                                            Navigator.pop(sheetContext);
                                          }
                                          await _loadProfileData();
                                          if (mounted && messenger != null) {
                                            messenger.showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  'Set "$label" as your default delivery address.',
                                                ),
                                              ),
                                            );
                                          }
                                        },
                                        icon: const Icon(
                                          Icons.check_circle_outline_rounded,
                                          size: 18,
                                        ),
                                        label: const Text('Set default'),
                                      ),
                                    TextButton.icon(
                                      onPressed: () async {
                                        Navigator.pop(sheetContext);
                                        await _showAddressEditorSheet(
                                          initial: addr,
                                        );
                                      },
                                      icon: const Icon(
                                        Icons.edit_outlined,
                                        size: 18,
                                      ),
                                      label: const Text('Edit'),
                                    ),
                                    TextButton.icon(
                                      onPressed: () async {
                                        final dialogContext = context;
                                        final messenger =
                                            ScaffoldMessenger.maybeOf(
                                              sheetContext,
                                            );
                                        final confirmed = await showDialog<bool>(
                                          context: dialogContext,
                                          builder: (ctx) => AlertDialog(
                                            title: const Text(
                                              'Delete address?',
                                            ),
                                            content: Text(
                                              'Remove "$label" from your saved addresses?',
                                            ),
                                            actions: [
                                              TextButton(
                                                onPressed: () =>
                                                    Navigator.pop(ctx, false),
                                                child: const Text('Cancel'),
                                              ),
                                              FilledButton(
                                                onPressed: () =>
                                                    Navigator.pop(ctx, true),
                                                child: const Text('Delete'),
                                              ),
                                            ],
                                          ),
                                        );
                                        if (confirmed == true) {
                                          await supabase
                                              .from('customer_addresses')
                                              .delete()
                                              .eq('id', addr['id']);
                                          if (sheetContext.mounted) {
                                            Navigator.pop(sheetContext);
                                          }
                                          await _loadProfileData();
                                          if (mounted && messenger != null) {
                                            messenger.showSnackBar(
                                              const SnackBar(
                                                content: Text(
                                                  'Address deleted.',
                                                ),
                                              ),
                                            );
                                          }
                                        }
                                      },
                                      icon: const Icon(
                                        Icons.delete_outline_rounded,
                                        size: 18,
                                      ),
                                      label: const Text('Delete'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        }),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () async {
                            Navigator.pop(sheetContext);
                            await _showAddressEditorSheet();
                          },
                          icon: const Icon(Icons.add_rounded),
                          label: const Text('Add new address'),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppUi.bluePrimary,
                            shape: RoundedRectangleBorder(
                              borderRadius: AppUi.pillRadius,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _openSavedAddresses() async {
    await _showSavedAddressesSheet();
    if (mounted) _loadProfileData();
  }

  Widget _buildAboutYouForm({
    required VoidCallback onChanged,
    required Future<void> Function() onSave,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AppFormSectionHeader(
          title: 'PERSONAL DETAILS',
          subtitle: 'Update your name and primary contact number',
        ),
        AppUi.vGapLg,
        AppFormField(
          controller: _firstNameController,
          label: 'First Name',
          prefixIcon: Icons.person_outline_rounded,
          textCapitalization: TextCapitalization.words,
          compact: true,
        ),
        AppUi.vGapMd,
        Row(
          children: [
            Expanded(
              flex: 1,
              child: AppFormField(
                controller: _miController,
                label: 'M.I.',
                prefixIcon: Icons.text_fields_rounded,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z.]')),
                  LengthLimitingTextInputFormatter(2),
                ],
                textCapitalization: TextCapitalization.characters,
                onChanged: _onMiddleInitialChanged,
                compact: true,
              ),
            ),
            AppUi.hGapMd,
            Expanded(
              flex: 1,
              child: AppDropdownField<String>(
                label: 'Suffix',
                value: _selectedSuffix,
                prefixIcon: Icons.star_border_rounded,
                compact: true,
                items: _suffixOptions
                    .map(
                      (item) =>
                          DropdownMenuItem(value: item, child: Text(item)),
                    )
                    .toList(),
                onChanged: (val) {
                  setState(() {
                    _selectedSuffix = _normalizeSuffix(val);
                    _suffixController.text = _selectedSuffix == 'None'
                        ? ''
                        : _selectedSuffix!;
                  });
                  onChanged();
                },
              ),
            ),
          ],
        ),
        AppUi.vGapMd,
        AppFormField(
          controller: _lastNameController,
          label: 'Last Name',
          prefixIcon: Icons.person_outline_rounded,
          textCapitalization: TextCapitalization.words,
          compact: true,
        ),
        AppUi.vGapMd,
        AppFormField(
          controller: _phoneController,
          label: 'Phone Number',
          prefixIcon: Icons.phone_android_rounded,
          keyboardType: TextInputType.phone,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          compact: true,
        ),
        AppUi.vGapLg,
        AppFormSubmitButton(
          text: 'Save Changes',
          icon: Icons.check_circle_rounded,
          isLoading: _isSavingProfile,
          onPressed: _isSavingProfile ? null : onSave,
        ),
      ],
    );
  }

  String _normalizePhone(String raw) {
    var phone = raw.replaceAll(RegExp(r'\s+'), '');
    if (phone.startsWith('+639') && phone.length == 13) {
      phone = '0${phone.substring(3)}';
    }
    if (phone.startsWith('639') && phone.length == 12) {
      phone = '0${phone.substring(2)}';
    }
    return phone;
  }

  String? _validatePersonalInfo() {
    final fname = _firstNameController.text.trim();
    final lname = _lastNameController.text.trim();
    final mi = _formatMiddleInitial(_miController.text);
    final phone = _normalizePhone(_phoneController.text);

    if (fname.isEmpty) return 'First name is required.';
    if (lname.isEmpty) return 'Last name is required.';
    if (mi.isNotEmpty && !RegExp(r'^[A-Z]\.$').hasMatch(mi)) {
      return 'Middle initial must be one letter followed by a dot.';
    }
    if (!RegExp(r'^09\d{9}$').hasMatch(phone)) {
      return 'Please enter a valid 11-digit mobile number (e.g. 09123456789).';
    }
    return null;
  }

  Future<bool> _savePersonalInfo() async {
    final user = supabase.auth.currentUser;
    if (user == null) return false;
    if (_isSavingProfile) return false;

    setState(() => _isSavingProfile = true);
    try {
      final validationMessage = _validatePersonalInfo();
      if (validationMessage != null) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(validationMessage)));
        }
        return false;
      }

      final mi = _formatMiddleInitial(_miController.text);
      final suffix = _selectedSuffix == 'None' ? null : _selectedSuffix;
      final phone = _normalizePhone(_phoneController.text);

      _miController.text = mi;
      _phoneController.text = phone;
      _suffixController.text = suffix ?? '';

      final payload = {
        'id': user.id,
        'email': user.email,
        'role': 'customer',
        'full_name': _composedFullName,
        'first_name': _firstNameController.text.trim(),
        'last_name': _lastNameController.text.trim(),
        'mi': mi.isEmpty ? null : mi,
        'suffix': suffix,
        'phone': phone,
        'town': _selectedTown,
        'barangay': _selectedBarangay,
        'purok': _selectedPurok,
        'zip_code': _selectedZipCode,
        'complete_address': _composedAddress,
        'landmark': _landmarkController.text.trim(),
        'preferred_water_type': _preferredWaterType,
        'latitude': _pickedLocation.latitude,
        'longitude': _pickedLocation.longitude,
        'lat': _pickedLocation.latitude,
        'lng': _pickedLocation.longitude,
      };

      await ProfileQueryHelpers.updateProfile(supabase, payload);

      setState(() => _fullName = _composedFullName);

      if (!mounted) return true;
      await context.read<UserProvider>().refreshProfile();
      if (!mounted) return true;
      await _loadProfileData();
      if (!mounted) return true;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated successfully.')),
      );
      return true;
    } catch (e) {
      debugPrint(e.toString());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Could not save profile. ${e.toString().replaceFirst('Exception: ', '')}',
            ),
          ),
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => _isSavingProfile = false);
    }
  }

  void _showWaterPreferenceSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: AppUi.surfaceOf(ctx),
          borderRadius: AppUi.radiusSheetTop,
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppUi.dividerOf(ctx),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Preferred water type',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: AppUi.textPrimaryOf(ctx),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Your default refill selection when ordering',
              style: TextStyle(fontSize: 13, color: AppUi.textSecondaryOf(ctx)),
            ),
            const SizedBox(height: 16),
            ...WaterTypes.all.map((type) {
              final isSelected =
                  _preferredWaterType.toLowerCase() == type.name.toLowerCase();
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppUi.bluePrimary.withValues(alpha: 0.08)
                      : AppUi.surfaceOf(ctx),
                  borderRadius: AppUi.cardRadius,
                  border: Border.all(
                    color: isSelected ? AppUi.bluePrimary : AppUi.borderOf(ctx),
                    width: isSelected ? 1.5 : 1,
                  ),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: ListTile(
                    leading: Icon(
                      Icons.water_drop_rounded,
                      color: isSelected
                          ? AppUi.bluePrimary
                          : AppUi.textSecondaryOf(ctx),
                    ),
                    title: Text(
                      type.name,
                      style: TextStyle(
                        fontWeight: isSelected
                            ? FontWeight.w800
                            : FontWeight.w600,
                        color: isSelected
                            ? AppUi.bluePrimary
                            : AppUi.textPrimaryOf(ctx),
                      ),
                    ),
                    subtitle: Text(
                      type.description,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppUi.textSecondaryOf(ctx),
                      ),
                    ),
                    trailing: isSelected
                        ? const Icon(
                            Icons.check_circle_rounded,
                            color: AppUi.bluePrimary,
                          )
                        : null,
                    onTap: () async {
                      Navigator.pop(ctx);
                      setState(() => _preferredWaterType = type.name);
                      final user = supabase.auth.currentUser;
                      if (user != null) {
                        try {
                          await supabase
                              .from('profiles')
                              .update({'preferred_water_type': type.name})
                              .eq('id', user.id);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Preferred water set to ${type.name}',
                                ),
                              ),
                            );
                          }
                        } catch (e) {
                          debugPrint('Error updating water preference: $e');
                        }
                      }
                    },
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  void _showHelpSupportSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: AppUi.surfaceOf(ctx),
          borderRadius: AppUi.radiusSheetTop,
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppUi.dividerOf(ctx),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppUi.bluePrimary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.support_agent_rounded,
                    color: AppUi.bluePrimary,
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Help & Customer Support',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: AppUi.textPrimaryOf(ctx),
                      ),
                    ),
                    Text(
                      'Cantilan & Madrid refill customer care',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppUi.textSecondaryOf(ctx),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              'CONTACT INFORMATION',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
                color: AppUi.textSecondaryOf(ctx),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: AppUi.cardDecorationOf(ctx),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.phone_in_talk_rounded,
                        size: 20,
                        color: AppUi.bluePrimary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Customer Hotline',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppUi.textSecondaryOf(ctx),
                              ),
                            ),
                            Text(
                              '+63 912 345 6789',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: AppUi.textPrimaryOf(ctx),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '7 AM - 6 PM',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppUi.textSecondaryOf(ctx),
                        ),
                      ),
                    ],
                  ),
                  Divider(height: 20, color: AppUi.dividerOf(ctx)),
                  Row(
                    children: [
                      const Icon(
                        Icons.email_outlined,
                        size: 20,
                        color: AppUi.bluePrimary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Support Email',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppUi.textSecondaryOf(ctx),
                              ),
                            ),
                            Text(
                              'support@erefill.com',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: AppUi.textPrimaryOf(ctx),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'QUICK FAQS',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
                color: AppUi.textSecondaryOf(ctx),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: AppUi.cardDecorationOf(ctx),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '• Gallon container exchange',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: AppUi.textPrimaryOf(ctx),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Have your clean empty gallon ready at handover. The rider will swap it with the newly refilled bottle.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppUi.textSecondaryOf(ctx),
                    ),
                  ),
                  Divider(height: 16, color: AppUi.dividerOf(ctx)),
                  Text(
                    '• Payment methods',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: AppUi.textPrimaryOf(ctx),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Cash on Delivery (COD), GCash, Maya, and Cards are supported right at checkout.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppUi.textSecondaryOf(ctx),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: Text(
                'eRefill v1.0.0 • Cantilan & Madrid Service',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppUi.textMuted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showLogoutConfirmation(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: AppUi.cardRadius),
        title: const Text('Sign out?'),
        content: const Text('You can sign back in anytime.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              await supabase.auth.signOut();
              if (!context.mounted) return;
              context.resetToAuth();
            },
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
  }

  void _showDeleteAccountDialog(BuildContext context) {
    final deleteController = TextEditingController();
    bool isDeleting = false;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Container(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          decoration: BoxDecoration(
            color: AppUi.surfaceOf(context),
            borderRadius: AppUi.radiusSheetTop,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppUi.dividerOf(context),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      color: Color(0xFFEF4444),
                      size: 48,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Delete account',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: AppUi.textPrimaryOf(context),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'This permanently removes your profile, orders, and favorites.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppUi.textSecondary,
                        fontWeight: FontWeight.w600,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: deleteController,
                      textAlign: TextAlign.center,
                      decoration: AppUi.fieldDecorationOf(
                        context,
                        'Type DELETE',
                      ),
                      onChanged: (_) => setSheetState(() {}),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: FilledButton(
                        onPressed:
                            isDeleting ||
                                deleteController.text.toUpperCase() != 'DELETE'
                            ? null
                            : () async {
                                setSheetState(() => isDeleting = true);
                                try {
                                  await supabase.rpc('delete_user_account');
                                  await supabase.auth.signOut();
                                  if (context.mounted) {
                                    context.resetToAuth();
                                  }
                                } catch (e) {
                                  if (!context.mounted) return;
                                  setSheetState(() => isDeleting = false);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Deletion failed: $e'),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                }
                              },
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFEF4444),
                        ),
                        child: isDeleting
                            ? const CircularProgressIndicator(
                                color: Colors.white,
                              )
                            : const Text(
                                'Delete everything',
                                style: TextStyle(fontWeight: FontWeight.w800),
                              ),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppUi.pageBgOf(context),
      body: _isLoading
          ? const AxoLoader(message: 'Loading your account...')
          : _loadError != null
          ? Center(
              child: AxoEmptyState(
                pose: AxoPose.thinking,
                title: 'Profile unavailable',
                message: _loadError!,
                actionLabel: 'Retry',
                onAction: _loadProfileData,
                compact: true,
              ),
            )
          : Column(
              children: [
                const TabScreenHeroHeader(
                  title: 'Account',
                  subtitle: 'Profile, delivery, and preferences',
                ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _loadProfileData,
                    child: CustomScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      slivers: [
                        SliverPadding(
                          padding:
                              AppUi.pagePadding.copyWith(top: 12, bottom: 96),
                          sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        AccountIdentityBlock(
                          name: _fullName,
                          email: supabase.auth.currentUser?.email ?? '',
                        ),
                        if (!_profileIsComplete)
                          AccountCompletenessHint(
                            message: _profileCompletionMessage,
                            onTap:
                                (_firstNameController.text.trim().isEmpty ||
                                    _lastNameController.text.trim().isEmpty ||
                                    _phoneController.text.trim().isEmpty)
                                ? _openEditProfileSheet
                                : _openSavedAddresses,
                          ),
                        const AccountSectionLabel('Profile'),
                        AccountGroup(
                          children: [
                            AccountNavTile(
                              icon: Icons.person_outline_rounded,
                              title: 'Personal information',
                              subtitle: _phoneController.text.trim().isEmpty
                                  ? 'Name, phone number, and username'
                                  : 'Phone: ${_phoneController.text.trim()} · Tap to edit',
                              onTap: _openEditProfileSheet,
                            ),
                          ],
                        ),
                        const AccountSectionLabel('Delivery'),
                        AccountGroup(
                          children: [
                            AccountNavTile(
                              icon: Icons.location_on_outlined,
                              title: 'Saved addresses',
                              subtitle: _composedAddress.isEmpty
                                  ? 'Manage or add delivery addresses'
                                  : _composedAddress,
                              onTap: _openSavedAddresses,
                            ),
                          ],
                        ),
                        const AccountSectionLabel('Rewards & Referrals'),
                        AccountGroup(
                          children: [
                            AccountNavTile(
                              icon: Icons.card_giftcard_rounded,
                              title: 'Loyalty Rewards & Referral Program',
                              subtitle:
                                  'Earn points, claim discount vouchers, and invite friends',
                              onTap: () {
                                final uid = supabase.auth.currentUser?.id;
                                if (uid != null) {
                                  LoyaltyRewardsSheet.show(context, uid);
                                }
                              },
                            ),
                          ],
                        ),
                        const AccountSectionLabel('Preferences'),
                        AccountGroup(
                          children: [
                            AccountNavTile(
                              icon: Icons.water_drop_outlined,
                              title: 'Water preference',
                              subtitle: WaterTypes.byName(
                                _preferredWaterType,
                              ).name,
                              onTap: _showWaterPreferenceSheet,
                            ),
                            AccountToggleTile(
                              icon: Icons.notifications_active_outlined,
                              title: 'Order notifications',
                              value: _notificationsEnabled,
                              onChanged: (v) =>
                                  setState(() => _notificationsEnabled = v),
                            ),
                            AccountToggleTile(
                              icon: Icons.dark_mode_outlined,
                              title: 'Dark mode',
                              value: context.select<ThemeProvider, bool>(
                                (t) => t.isDarkMode,
                              ),
                              onChanged: (v) =>
                                  context.read<ThemeProvider>().setDarkMode(v),
                            ),
                          ],
                        ),
                        const AccountSectionLabel('Support'),
                        AccountGroup(
                          children: [
                            AccountNavTile(
                              icon: Icons.support_agent_rounded,
                              title: 'Help & customer support',
                              subtitle: 'Hotline, FAQs, and app info',
                              onTap: _showHelpSupportSheet,
                            ),
                          ],
                        ),
                        const AccountSectionLabel('Account'),
                        AccountGroup(
                          children: [
                            AccountNavTile(
                              icon: Icons.logout_rounded,
                              iconColor: const Color(0xFFEF4444),
                              title: 'Sign out',
                              titleColor: const Color(0xFFEF4444),
                              subtitle:
                                  'Log out of your account on this device',
                              onTap: () => _showLogoutConfirmation(context),
                            ),
                            AccountNavTile(
                              icon: Icons.delete_outline_rounded,
                              iconColor: const Color(0xFFDC2626),
                              title: 'Delete account',
                              titleColor: const Color(0xFFDC2626),
                              subtitle:
                                  'Permanently remove your account and data',
                              onTap: () => _showDeleteAccountDialog(context),
                            ),
                          ],
                        ),
                      ]),
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
