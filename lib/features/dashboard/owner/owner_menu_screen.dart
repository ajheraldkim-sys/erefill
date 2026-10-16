import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:erefill/core/constants.dart';
import 'package:erefill/core/widgets/brand/hero_header.dart';
import 'package:erefill/core/providers/theme_provider.dart';
import 'package:erefill/core/utils/friendly_errors.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;
import 'package:erefill/core/routing/app_navigation.dart';
import 'package:erefill/core/widgets/map_tiles.dart';
import 'package:erefill/core/widgets/account/account_ui.dart';
import 'package:erefill/core/widgets/app_form_fields.dart';
import 'package:erefill/core/providers/user_provider.dart';
import 'package:erefill/core/utils/safe_supabase.dart';
import 'package:erefill/core/utils/profile_query_helpers.dart';
import 'package:erefill/features/settings/payment_account_models.dart';
import 'package:erefill/features/settings/payment_settings_service.dart';
import 'package:erefill/features/settings/owner/owner_settings_service.dart';
import 'package:erefill/features/settings/account_security_screen.dart';
import 'package:erefill/core/services/local_data_cache.dart';
import 'package:go_router/go_router.dart';
import 'package:erefill/core/routing/app_routes.dart';
import 'service_catalog_screen.dart';

class OwnerMenuScreen extends StatefulWidget {
  const OwnerMenuScreen({super.key});

  @override
  State<OwnerMenuScreen> createState() => _OwnerMenuScreenState();
}

class _OwnerMenuScreenState extends State<OwnerMenuScreen> {
  final supabase = Supabase.instance.client;
  final _ownerSettingsService = OwnerSettingsService();
  bool _isLoading = true;
  StreamSubscription? _profileSub;
  StreamSubscription? _settingsSub;

  // Profile data
  String _avatarUrl = '';
  String _coverPhotoUrl = '';

  // Settings & Configurations
  bool _isEditingProfile = false;
  bool _isSavingStation = false;
  bool _isSavingOwner = false;
  bool _isSavingPricing = false;
  bool _isSavingPayments = false;
  String _contactEmail = '';
  bool _isUploadingImage = false;
  bool _isUploadingCover = false;
  final _mapController = MapController();
  LatLng _pickedLocation = const LatLng(9.3333, 125.9833);
  // Controllers for editable fields
  final _businessNameController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _miController = TextEditingController();
  final _suffixController = TextEditingController();
  final _phoneController = TextEditingController();
  final _townController = TextEditingController();
  final _barangayController = TextEditingController();

  // Pricing & Delivery Controllers
  final _priceController = TextEditingController();
  final _deliveryFeeController = TextEditingController();
  final _commissionController = TextEditingController();
  final _radiusController = TextEditingController();

  // Payment methods
  List<String> _enabledPaymentMethods = ['cod', 'gcash', 'maya', 'card'];

  final Map<String, List<String>> _municipalityData =
      AppConstants.municipalityData;

  String? _selectedTown;
  String? _selectedBarangay;
  String? _selectedSuffix;
  final List<String> _suffixOptions = [
    '',
    'Jr.',
    'Sr.',
    'II',
    'III',
    'IV',
    'V',
  ];

  bool _notificationsEnabled = true;

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : null,
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    final user = supabase.auth.currentUser;
    if (user != null) {
      final cachedSettings = LocalDataCache.instance.getMemory<Map<String, dynamic>>('owner_settings_${user.id}');
      if (cachedSettings != null) {
        _updateSettingsFromData(cachedSettings);
        _isLoading = false;
      }
      final cachedProfile = LocalDataCache.instance.getMemory<Map<String, dynamic>>('user_profile_${user.id}');
      if (cachedProfile != null) {
        _updateProfileFromData(cachedProfile);
        _isLoading = false;
      }
    }
    _loadAllData();
    _setupRealtimeListener();
  }

  @override
  void dispose() {
    _profileSub?.cancel();
    _settingsSub?.cancel();
    _businessNameController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _miController.dispose();
    _suffixController.dispose();
    _phoneController.dispose();
    _townController.dispose();
    _barangayController.dispose();
    _priceController.dispose();
    _deliveryFeeController.dispose();
    _commissionController.dispose();
    _radiusController.dispose();
    super.dispose();
  }

  void _setupRealtimeListener() {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    _profileSub = SafeSupabase.listen(
      supabase.from('profiles').stream(primaryKey: ['id']).eq('id', user.id),
      (data) {
        if (data.isNotEmpty && mounted) {
          _updateProfileFromData(data.first);
        }
      },
      onError: (error, stackTrace) {
        debugPrint('Owner menu profile stream error: $error');
        debugPrint('Owner menu profile stream stack: $stackTrace');
      },
    );

    _settingsSub = SafeSupabase.listen(
      supabase
          .from('owner_settings')
          .stream(primaryKey: ['id'])
          .eq('owner_id', user.id),
      (data) {
        if (data.isNotEmpty && mounted) {
          _updateSettingsFromData(data.first);
        }
      },
      onError: (error, stackTrace) {
        debugPrint('Owner menu settings stream error: $error');
      },
    );
  }

  void _updateSettingsFromData(Map<String, dynamic> settings) {
    if (!mounted) return;
    setState(() {
      if (settings['price_per_gallon'] != null) {
        _priceController.text =
            (settings['price_per_gallon'] as num).toStringAsFixed(2);
      }
      if (settings['base_delivery_fee'] != null) {
        _deliveryFeeController.text =
            (settings['base_delivery_fee'] as num).toStringAsFixed(2);
      }
      if (settings['service_radius_km'] != null) {
        _radiusController.text =
            (settings['service_radius_km'] as num).toString();
      }
      final configuredMethods = settings['enabled_payment_methods'];
      if (configuredMethods is List) {
        final parsed = configuredMethods
            .whereType<String>()
            .where((m) => ['cod', 'gcash', 'maya', 'card'].contains(m))
            .toSet()
            .toList();
        if (parsed.isNotEmpty) {
          _enabledPaymentMethods = parsed;
        }
      }
    });
  }

  void _updateProfileFromData(Map<String, dynamic> profile) {
    if (!mounted) return;
    setState(() {
      _avatarUrl = profile['avatar_url'] ?? '';
      _coverPhotoUrl = profile['station_photo_url'] ?? '';
      _businessNameController.text = profile['station_name'] ?? '';
      _firstNameController.text = profile['first_name'] ?? '';
      _lastNameController.text = profile['last_name'] ?? '';
      _miController.text = profile['mi'] ?? '';
      _suffixController.text = profile['suffix'] ?? '';
      _selectedSuffix = _suffixOptions.contains(profile['suffix'])
          ? profile['suffix']
          : null;
      _phoneController.text = profile['phone'] ?? '';
      _contactEmail = profile['email'] ?? '';

      final rawTown = profile['town']?.toString();
      _selectedTown = null;
      for (final town in _municipalityData.keys) {
        if (town.toLowerCase() == rawTown?.toLowerCase()) {
          _selectedTown = town;
          break;
        }
      }

      final rawBarangay = profile['barangay']?.toString();
      if (_selectedTown != null) {
        _selectedBarangay = null;
        for (final barangay in _municipalityData[_selectedTown]!) {
          if (barangay.toLowerCase() == rawBarangay?.toLowerCase()) {
            _selectedBarangay = barangay;
            break;
          }
        }
      } else {
        _selectedBarangay = null;
      }
      _townController.text = _selectedTown ?? '';
      _barangayController.text = _selectedBarangay ?? '';

      if (profile['commission_rate'] != null) {
        _commissionController.text =
            (profile['commission_rate'] as num).toStringAsFixed(2);
      }
      if (profile['price_per_gallon'] != null && _priceController.text.isEmpty) {
        _priceController.text =
            (profile['price_per_gallon'] as num).toStringAsFixed(2);
      }

      final lat = (profile['latitude'] ?? profile['lat']) as num?;
      final lng = (profile['longitude'] ?? profile['lng']) as num?;
      if (lat != null && lng != null) {
        _pickedLocation = LatLng(lat.toDouble(), lng.toDouble());
      }
    });
  }

  Future<void> _locateMe() async {
    try {
      final position = await Geolocator.getCurrentPosition();
      if (!mounted) return;
      final newLoc = LatLng(position.latitude, position.longitude);
      setState(() => _pickedLocation = newLoc);
      _mapController.move(newLoc, 16);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not determine location')),
        );
      }
    }
  }

  Future<void> _loadAllData() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final profileFuture = supabase
          .from('profiles')
          .select(
            'avatar_url, station_photo_url, station_name, phone, email, full_name, first_name, last_name, mi, suffix, town, barangay, latitude, longitude, lat, lng, primary_water_type, commission_rate, price_per_gallon',
          )
          .eq('id', user.id)
          .maybeSingle();

      final settingsFuture = _ownerSettingsService.getSettings(user.id);

      final profile = await profileFuture;
      final settings = await settingsFuture;

      if (!mounted) return;

      setState(() {
        if (profile != null) {
          _avatarUrl = profile['avatar_url'] ?? '';
          _coverPhotoUrl = profile['station_photo_url'] ?? '';
          _businessNameController.text = profile['station_name'] ?? '';
          _firstNameController.text =
              profile['first_name'] ??
              profile['full_name']?.split(' ').first ??
              '';
          _lastNameController.text =
              profile['last_name'] ??
              (profile['full_name']?.split(' ').length > 1
                  ? profile['full_name']?.split(' ').last
                  : '') ??
              '';
          _miController.text = profile['mi'] ?? '';
          _suffixController.text = profile['suffix'] ?? '';
          _selectedSuffix = _suffixOptions.contains(profile['suffix'])
              ? profile['suffix']
              : null;
          _phoneController.text = profile['phone'] ?? '';
          _contactEmail = profile['email'] ?? user.email ?? '';

          final lat = (profile['latitude'] ?? profile['lat']) as num?;
          final lng = (profile['longitude'] ?? profile['lng']) as num?;
          if (lat != null && lng != null) {
            _pickedLocation = LatLng(lat.toDouble(), lng.toDouble());
          }

          // Normalize Town
          String? rawTown = profile['town']?.toString();
          _selectedTown = _municipalityData.keys.firstWhere(
            (k) => k.toLowerCase() == rawTown?.toLowerCase(),
            orElse: () => rawTown ?? '',
          );
          if (!_municipalityData.containsKey(_selectedTown)) {
            _selectedTown = null;
          }

          // Normalize Barangay
          String? rawBrgy = profile['barangay']?.toString();
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

          _townController.text = _selectedTown ?? '';
          _barangayController.text = _selectedBarangay ?? '';

          if (profile['commission_rate'] != null) {
            _commissionController.text =
                (profile['commission_rate'] as num).toStringAsFixed(2);
          } else {
            _commissionController.text = '5.00';
          }
        } else {
          _commissionController.text = '5.00';
        }

        if (settings != null) {
          _priceController.text =
              (settings['price_per_gallon'] as num?)?.toStringAsFixed(2) ??
              (profile?['price_per_gallon'] as num?)?.toStringAsFixed(2) ??
              '15.00';
          _deliveryFeeController.text =
              (settings['base_delivery_fee'] as num?)?.toStringAsFixed(2) ??
              '25.00';
          _radiusController.text =
              (settings['service_radius_km'] as num?)?.toString() ?? '5';

          final configuredMethods = settings['enabled_payment_methods'];
          if (configuredMethods is List) {
            _enabledPaymentMethods = configuredMethods
                .whereType<String>()
                .where((m) => ['cod', 'gcash', 'maya', 'card'].contains(m))
                .toSet()
                .toList();
            if (_enabledPaymentMethods.isEmpty) {
              _enabledPaymentMethods = ['cod', 'gcash', 'maya', 'card'];
            }
          }
        } else {
          _priceController.text =
              (profile?['price_per_gallon'] as num?)?.toStringAsFixed(2) ??
              '15.00';
          _deliveryFeeController.text = '25.00';
          _radiusController.text = '5';
          _enabledPaymentMethods = ['cod', 'gcash', 'maya', 'card'];
        }

        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading account data: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  double get _currentPricePerGallon =>
      double.tryParse(_priceController.text.trim()) ?? 15.0;
  double get _currentBaseFee =>
      double.tryParse(_deliveryFeeController.text.trim()) ?? 25.0;
  int get _currentRadiusKm =>
      int.tryParse(_radiusController.text.trim()) ?? 5;

  String get _pricingSummary =>
      '₱${_currentPricePerGallon.toStringAsFixed(2)}/gal · ₱${_currentBaseFee.toStringAsFixed(2)} delivery · ${_currentRadiusKm}km';

  String get _paymentMethodsSummary {
    if (_enabledPaymentMethods.isEmpty) return 'None enabled';
    return _enabledPaymentMethods
        .map((m) => m == 'cod' ? 'COD' : m == 'card' ? 'Card' : m.toUpperCase())
        .join(', ');
  }

  String get _ownerFullName {
    final parts = [
      _firstNameController.text.trim(),
      _miController.text.trim(),
      _lastNameController.text.trim(),
      if (_selectedSuffix != null &&
          _selectedSuffix!.isNotEmpty &&
          _selectedSuffix != 'None')
        _selectedSuffix!,
    ].where((p) => p.isNotEmpty);
    return parts.join(' ').replaceAll(RegExp(r'\s+'), ' ');
  }

  String get _stationLocationSummary {
    return [
      _selectedBarangay,
      _selectedTown,
    ].where((part) => (part ?? '').trim().isNotEmpty).join(', ');
  }

  bool get _profileIsComplete {
    return _businessNameController.text.trim().isNotEmpty &&
        _firstNameController.text.trim().isNotEmpty &&
        _lastNameController.text.trim().isNotEmpty &&
        _phoneController.text.trim().isNotEmpty &&
        _selectedTown != null &&
        _selectedBarangay != null;
  }

  String get _profileCompletionMessage {
    if (_businessNameController.text.trim().isEmpty ||
        _stationLocationSummary.isEmpty) {
      return 'Add your station name, address, and map pin.';
    }
    if (_firstNameController.text.trim().isEmpty ||
        _lastNameController.text.trim().isEmpty) {
      return 'Complete owner details for station verification.';
    }
    return 'Complete your station profile for smoother operations.';
  }

  Future<bool> _saveStationDetails() async {
    if (!mounted) return false;
    final user = supabase.auth.currentUser;
    if (user == null) return false;

    final stationName = _businessNameController.text.trim();
    final phone = _phoneController.text.trim();
    final validationMessage =
        AppValidators.requiredText(stationName, 'Station name') ??
        AppValidators.phone(phone) ??
        (_selectedTown == null ? 'Please select the station town.' : null) ??
        (_selectedBarangay == null
            ? 'Please select the station barangay.'
            : null);

    if (validationMessage != null) {
      _showMessage(validationMessage, isError: true);
      return false;
    }

    if (!mounted) return false;
    setState(() => _isSavingStation = true);
    try {
      final completeAddr = '$_selectedBarangay, $_selectedTown';
      await ProfileQueryHelpers.updateProfile(supabase, {
        'station_name': stationName,
        'phone': phone,
        'town': _selectedTown,
        'barangay': _selectedBarangay,
        'complete_address': completeAddr,
        'latitude': _pickedLocation.latitude,
        'longitude': _pickedLocation.longitude,
        'lat': _pickedLocation.latitude,
        'lng': _pickedLocation.longitude,
      }, userId: user.id);

      if (!mounted) return false;
      final up = context.read<UserProvider>();
      await up.refreshProfile();
      if (mounted) {
        _showMessage('Station details updated successfully.');
      }
      return true;
    } catch (e) {
      debugPrint(e.toString());
      if (mounted) {
        _showMessage(
          FriendlyErrors.message(
            e,
            fallback: 'Could not update station details. Please try again.',
          ),
          isError: true,
        );
      }
      return false;
    } finally {
      if (mounted) {
        setState(() => _isSavingStation = false);
      }
    }
  }

  void _openStationDetailsSheet() {
    setState(() => _isEditingProfile = true);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setModalState) => Padding(
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
                const SizedBox(height: 12),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppUi.borderOf(context),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Station details',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: AppUi.textPrimaryOf(context),
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () {
                          if (sheetContext.mounted && Navigator.canPop(sheetContext)) {
                            Navigator.pop(sheetContext);
                          }
                        },
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    child: _buildStationDetailsForm(sheetContext, setModalState),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ).whenComplete(() {
      if (mounted) setState(() => _isEditingProfile = false);
    });
  }

  Widget _buildStationDetailsForm(
    BuildContext sheetContext,
    void Function(void Function()) setModalState,
  ) {
    final barangayList =
        _selectedTown != null && _municipalityData.containsKey(_selectedTown)
            ? _municipalityData[_selectedTown]!
            : <String>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AppFormSectionHeader(
          title: 'STATION IDENTITY',
          subtitle: 'Your public station brand name and contact number',
        ),
        AppUi.vGapMd,
        AppFormField(
          label: 'Station Name',
          controller: _businessNameController,
          prefixIcon: Icons.storefront_outlined,
          compact: true,
          textCapitalization: TextCapitalization.words,
        ),
        AppUi.vGapMd,
        AppFormField(
          label: 'Contact Phone Number',
          controller: _phoneController,
          prefixIcon: Icons.phone_android_rounded,
          keyboardType: TextInputType.phone,
          compact: true,
        ),
        AppUi.vGapLg,
        const AppFormSectionHeader(
          title: 'STATION LOCATION',
          subtitle: 'Municipality and barangay address',
        ),
        AppUi.vGapMd,
        AppDropdownField<String>.fromStrings(
          label: 'Station Town',
          value: _selectedTown,
          prefixIcon: Icons.location_city_outlined,
          items: _municipalityData.keys.toList(),
          compact: true,
          onChanged: (val) {
            setModalState(() {
              _selectedTown = val;
              _selectedBarangay = null;
            });
          },
        ),
        AppUi.vGapMd,
        AppDropdownField<String>.fromStrings(
          label: 'Station Barangay',
          value: _selectedBarangay,
          prefixIcon: Icons.home_work_outlined,
          items: barangayList,
          compact: true,
          onChanged: (val) => setModalState(() => _selectedBarangay = val),
        ),
        AppUi.vGapLg,
        const AppFormSectionHeader(
          title: 'PRECISE STATION PIN',
          subtitle: 'Pinpoint exact customer map and routing coordinates',
        ),
        AppUi.vGapMd,
        Container(
          height: 200,
          decoration: BoxDecoration(
            borderRadius: AppUi.cardRadius,
            border: Border.all(color: AppUi.borderOf(context)),
          ),
          child: Stack(
            children: [
              ClipRRect(
                borderRadius: AppUi.cardRadius,
                child: FlutterMap(
                  key: ValueKey(_isEditingProfile),
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _pickedLocation,
                    initialZoom: 15,
                    onPositionChanged: (camera, hasGesture) {
                      if (hasGesture) {
                        setModalState(() => _pickedLocation = camera.center);
                      }
                    },
                  ),
                  children: [AppMapTiles.layer(context: context)],
                ),
              ),
              const Center(
                child: Padding(
                  padding: EdgeInsets.only(bottom: 35),
                  child: Icon(
                    Icons.location_on_rounded,
                    color: AppUi.bluePrimary,
                    size: 44,
                    shadows: [
                      Shadow(
                        color: Colors.black54,
                        blurRadius: 8,
                        offset: Offset(0, 3),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                right: 12,
                bottom: 12,
                child: FloatingActionButton.small(
                  onPressed: () async {
                    await _locateMe();
                    setModalState(() {});
                  },
                  backgroundColor: AppUi.surfaceOf(context),
                  foregroundColor: AppUi.bluePrimary,
                  child: const Icon(Icons.my_location_rounded),
                ),
              ),
            ],
          ),
        ),
        AppUi.vGapLg,
        AppFormSubmitButton(
          text: 'Save Station Details',
          icon: Icons.save_outlined,
          isLoading: _isSavingStation,
          onPressed: () async {
            final saved = await _saveStationDetails();
            if (saved && sheetContext.mounted && Navigator.canPop(sheetContext)) {
              Navigator.pop(sheetContext);
            }
          },
        ),
      ],
    );
  }

  Future<bool> _saveOwnerDetails() async {
    if (!mounted) return false;
    final user = supabase.auth.currentUser;
    if (user == null) return false;

    final fname = _firstNameController.text.trim();
    final lname = _lastNameController.text.trim();
    final mi = _miController.text.trim();
    final suffix = (_selectedSuffix == 'None' || _selectedSuffix == null)
        ? ''
        : _selectedSuffix!;

    final validationMessage =
        AppValidators.name(fname, 'First name') ??
        AppValidators.name(lname, 'Last name') ??
        AppValidators.optionalInitial(mi);

    if (validationMessage != null) {
      _showMessage(validationMessage, isError: true);
      return false;
    }

    if (!mounted) return false;
    setState(() => _isSavingOwner = true);
    try {
      final fullName = "$fname $mi $lname $suffix".replaceAll(
        RegExp(r'\s+'),
        ' ',
      ).trim();

      await ProfileQueryHelpers.updateProfile(supabase, {
        'full_name': fullName,
        'first_name': fname,
        'last_name': lname,
        'mi': mi,
        'suffix': suffix.isEmpty ? null : suffix,
      }, userId: user.id);

      if (!mounted) return false;
      final up = context.read<UserProvider>();
      await up.refreshProfile();
      if (mounted) {
        _showMessage('Owner details updated successfully.');
      }
      return true;
    } catch (e) {
      debugPrint(e.toString());
      if (mounted) {
        _showMessage(
          FriendlyErrors.message(
            e,
            fallback: 'Could not update owner details. Please try again.',
          ),
          isError: true,
        );
      }
      return false;
    } finally {
      if (mounted) {
        setState(() => _isSavingOwner = false);
      }
    }
  }

  void _openOwnerDetailsSheet() {
    setState(() => _isEditingProfile = true);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setModalState) => Padding(
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
                const SizedBox(height: 12),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppUi.borderOf(context),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'About owner',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: AppUi.textPrimaryOf(context),
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () {
                          if (sheetContext.mounted && Navigator.canPop(sheetContext)) {
                            Navigator.pop(sheetContext);
                          }
                        },
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    child: _buildOwnerDetailsForm(sheetContext, setModalState),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ).whenComplete(() {
      if (mounted) setState(() => _isEditingProfile = false);
    });
  }

  Widget _buildOwnerDetailsForm(
    BuildContext sheetContext,
    void Function(void Function()) setModalState,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AppFormSectionHeader(
          title: 'OWNER REPRESENTATIVE',
          subtitle: 'Registered station owner details',
        ),
        AppUi.vGapMd,
        AppFormField(
          label: 'First Name',
          controller: _firstNameController,
          prefixIcon: Icons.person_outline_rounded,
          compact: true,
          textCapitalization: TextCapitalization.words,
        ),
        AppUi.vGapMd,
        AppFormField(
          label: 'Last Name',
          controller: _lastNameController,
          prefixIcon: Icons.badge_outlined,
          compact: true,
          textCapitalization: TextCapitalization.words,
        ),
        AppUi.vGapMd,
        AppFormField(
          label: 'Middle Initial (Optional)',
          controller: _miController,
          prefixIcon: Icons.text_fields_rounded,
          compact: true,
          textCapitalization: TextCapitalization.characters,
        ),
        AppUi.vGapMd,
        AppDropdownField<String>.fromStrings(
          label: 'Suffix (Optional)',
          value: (_selectedSuffix == null || _selectedSuffix!.isEmpty)
              ? 'None'
              : _selectedSuffix,
          prefixIcon: Icons.star_border_rounded,
          items: const ['None', 'Jr.', 'Sr.', 'II', 'III', 'IV', 'V'],
          compact: true,
          onChanged: (val) => setModalState(() {
            _selectedSuffix = (val == 'None' || val == null) ? null : val;
          }),
        ),
        if (_contactEmail.isNotEmpty) ...[
          AppUi.vGapLg,
          const AppFormSectionHeader(
            title: 'ACCOUNT CREDENTIALS',
            subtitle:
                'Registered email address associated with this owner account',
          ),
          AppUi.vGapMd,
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: AppUi.chipBgOf(context),
              borderRadius: AppUi.cardRadius,
              border: Border.all(color: AppUi.borderOf(context)),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.email_outlined,
                  size: 20,
                  color: AppUi.textSecondaryOf(context),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Email address',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppUi.textSecondaryOf(context),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _contactEmail,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppUi.textPrimaryOf(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
        AppUi.vGapLg,
        AppFormSubmitButton(
          text: 'Save Owner Details',
          icon: Icons.save_outlined,
          isLoading: _isSavingOwner,
          onPressed: () async {
            final saved = await _saveOwnerDetails();
            if (saved && sheetContext.mounted && Navigator.canPop(sheetContext)) {
              Navigator.pop(sheetContext);
            }
          },
        ),
      ],
    );
  }

  Future<bool> _savePricingAndDelivery() async {
    if (!mounted) return false;
    final user = supabase.auth.currentUser;
    if (user == null) return false;

    final price = double.tryParse(_priceController.text.trim());
    final fee = double.tryParse(_deliveryFeeController.text.trim());
    final commission =
        double.tryParse(_commissionController.text.trim()) ?? 0.0;
    final radius = int.tryParse(_radiusController.text.trim());

    if (price == null || price < 0) {
      _showMessage('Please enter a valid price per gallon.', isError: true);
      return false;
    }
    if (fee == null || fee < 0) {
      _showMessage('Please enter a valid delivery fee.', isError: true);
      return false;
    }
    if (radius == null || radius <= 0) {
      _showMessage('Service radius must be greater than 0 km.', isError: true);
      return false;
    }

    setState(() => _isSavingPricing = true);
    try {
      await _ownerSettingsService.updateSettings(user.id, {
        'price_per_gallon': price,
        'base_delivery_fee': fee,
        'service_radius_km': radius,
      });

      await ProfileQueryHelpers.updateProfile(supabase, {
        'price_per_gallon': price,
        'commission_rate': commission,
      }, userId: user.id);

      try {
        await supabase.rpc(
          'sync_owner_default_product',
          params: {'p_owner_id': user.id},
        );
      } catch (syncErr) {
        debugPrint('Product sync RPC error: $syncErr');
      }

      if (!mounted) return false;
      final up = context.read<UserProvider>();
      await up.refreshProfile();
      if (mounted) {
        _showMessage('Pricing & delivery settings saved successfully.');
      }
      return true;
    } catch (e) {
      debugPrint('Error saving pricing: $e');
      if (mounted) {
        _showMessage(
          FriendlyErrors.message(
            e,
            fallback: 'Could not save pricing settings. Please try again.',
          ),
          isError: true,
        );
      }
      return false;
    } finally {
      if (mounted) {
        setState(() => _isSavingPricing = false);
      }
    }
  }

  void _openPricingDeliverySheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setModalState) => Padding(
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
                const SizedBox(height: 12),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppUi.borderOf(context),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Pricing & delivery rules',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: AppUi.textPrimaryOf(context),
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () {
                          if (sheetContext.mounted && Navigator.canPop(sheetContext)) {
                            Navigator.pop(sheetContext);
                          }
                        },
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    child: _buildPricingDeliveryForm(
                      sheetContext,
                      setModalState,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPricingDeliveryForm(
    BuildContext sheetContext,
    void Function(void Function()) setModalState,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AppFormSectionHeader(
          title: 'REFILL PRICING & BASE FEE',
          subtitle: 'Configure order pricing and standard delivery charges',
        ),
        AppUi.vGapMd,
        AppFormField(
          label: 'Price per Gallon (₱)',
          controller: _priceController,
          prefixIcon: Icons.payments_outlined,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          compact: true,
        ),
        AppUi.vGapMd,
        AppFormField(
          label: 'Base Delivery Fee (₱)',
          controller: _deliveryFeeController,
          prefixIcon: Icons.local_shipping_outlined,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          compact: true,
        ),
        AppUi.vGapLg,
        const AppFormSectionHeader(
          title: 'LOGISTICS & COMMISSIONS',
          subtitle:
              'Set rider payout per gallon and maximum delivery service radius',
        ),
        AppUi.vGapMd,
        AppFormField(
          label: 'Rider Commission per Gallon (₱)',
          controller: _commissionController,
          prefixIcon: Icons.two_wheeler_outlined,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          compact: true,
        ),
        AppUi.vGapMd,
        AppFormField(
          label: 'Service Radius (km)',
          controller: _radiusController,
          prefixIcon: Icons.radar_outlined,
          keyboardType: TextInputType.number,
          compact: true,
        ),
        AppUi.vGapLg,
        AppFormSubmitButton(
          text: 'Save Pricing & Delivery',
          icon: Icons.save_outlined,
          isLoading: _isSavingPricing,
          onPressed: () async {
            final saved = await _savePricingAndDelivery();
            if (saved && sheetContext.mounted && Navigator.canPop(sheetContext)) {
              Navigator.pop(sheetContext);
            }
          },
        ),
      ],
    );
  }

  Future<bool> _savePaymentMethods() async {
    if (!mounted) return false;
    final user = supabase.auth.currentUser;
    if (user == null) return false;

    if (_enabledPaymentMethods.isEmpty) {
      _showMessage(
        'Please enable at least one payment method.',
        isError: true,
      );
      return false;
    }

    setState(() => _isSavingPayments = true);
    try {
      await _ownerSettingsService.updateSettings(user.id, {
        'enabled_payment_methods': _enabledPaymentMethods,
      });

      if (!mounted) return false;
      final up = context.read<UserProvider>();
      await up.refreshProfile();
      if (mounted) {
        _showMessage('Payment methods updated successfully.');
      }
      return true;
    } catch (e) {
      debugPrint('Error saving payment methods: $e');
      if (mounted) {
        _showMessage(
          FriendlyErrors.message(
            e,
            fallback: 'Could not update payment methods. Please try again.',
          ),
          isError: true,
        );
      }
      return false;
    } finally {
      if (mounted) {
        setState(() => _isSavingPayments = false);
      }
    }
  }

  void _openPaymentMethodsSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setModalState) => Padding(
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
                const SizedBox(height: 12),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppUi.borderOf(context),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Accepted payment methods',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: AppUi.textPrimaryOf(context),
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () {
                          if (sheetContext.mounted && Navigator.canPop(sheetContext)) {
                            Navigator.pop(sheetContext);
                          }
                        },
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    child: _buildPaymentMethodsForm(
                      sheetContext,
                      setModalState,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPaymentMethodsForm(
    BuildContext sheetContext,
    void Function(void Function()) setModalState,
  ) {
    const paymentOptions = <(String, String, IconData, String)>[
      (
        'cod',
        'Cash on Delivery (COD)',
        Icons.payments_outlined,
        'Customer pays with cash upon delivery arrival',
      ),
      (
        'gcash',
        'GCash',
        Icons.phone_android_rounded,
        'Digital e-wallet payments via QR or phone number',
      ),
      (
        'maya',
        'Maya',
        Icons.credit_card_outlined,
        'Digital Maya wallet payments',
      ),
      (
        'card',
        'Credit / Debit Card',
        Icons.credit_card_rounded,
        'Online card payments powered by payment gateway',
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AppFormSectionHeader(
          title: 'ACCEPTED PAYMENT CHANNELS',
          subtitle:
              'Select which payment options customers can choose during checkout',
        ),
        AppUi.vGapMd,
        ...paymentOptions.map((opt) {
          final isEnabled = _enabledPaymentMethods.contains(opt.$1);
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Material(
              color: isEnabled
                  ? AppUi.bluePrimary.withValues(alpha: 0.05)
                  : AppUi.chipBgOf(sheetContext),
              shape: RoundedRectangleBorder(
                borderRadius: AppUi.cardRadius,
                side: BorderSide(
                  color: isEnabled
                      ? AppUi.bluePrimary.withValues(alpha: 0.3)
                      : AppUi.borderOf(sheetContext),
                ),
              ),
              child: Material(
                color: Colors.transparent,
                child: SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  secondary: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isEnabled
                          ? AppUi.bluePrimary.withValues(alpha: 0.15)
                          : AppUi.borderOf(sheetContext).withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      opt.$3,
                      color: isEnabled
                          ? AppUi.bluePrimary
                          : AppUi.textSecondaryOf(sheetContext),
                      size: 20,
                    ),
                  ),
                  title: Text(
                    opt.$2,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: AppUi.textPrimaryOf(sheetContext),
                    ),
                  ),
                  subtitle: Text(
                    opt.$4,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppUi.textSecondaryOf(sheetContext),
                    ),
                  ),
                  value: isEnabled,
                  activeThumbColor: AppUi.bluePrimary,
                  onChanged: (val) {
                    setModalState(() {
                      setState(() {
                        if (val) {
                          if (!_enabledPaymentMethods.contains(opt.$1)) {
                            _enabledPaymentMethods.add(opt.$1);
                          }
                        } else {
                          if (_enabledPaymentMethods.length > 1) {
                            _enabledPaymentMethods.remove(opt.$1);
                          } else {
                            _showMessage(
                              'At least one payment method must remain enabled.',
                              isError: true,
                            );
                          }
                        }
                      });
                    });
                  },
                ),
              ),
          ),
        );
        }),
        AppUi.vGapLg,
        AppFormSubmitButton(
          text: 'Save Payment Methods',
          icon: Icons.save_outlined,
          isLoading: _isSavingPayments,
          onPressed: () async {
            final saved = await _savePaymentMethods();
            if (saved && sheetContext.mounted && Navigator.canPop(sheetContext)) {
              Navigator.pop(sheetContext);
            }
          },
        ),
      ],
    );
  }

  void _openWaterProductsCatalogPopup() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ClipRRect(
        borderRadius: AppUi.radiusSheetTop,
        child: SizedBox(
          height: MediaQuery.of(ctx).size.height * 0.92,
          child: const ServiceCatalogScreen(isPopup: true),
        ),
      ),
    );
  }

  void _showPayoutAccountSheet() {
    final paymentService = PaymentSettingsService();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          return Container(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
              top: 16,
              left: 20,
              right: 20,
            ),
            decoration: BoxDecoration(
              color: AppUi.surfaceOf(ctx),
              borderRadius: AppUi.radiusSheetTop,
            ),
            child: FutureBuilder<List<PaymentAccount>>(
              future: paymentService.list(
                PaymentAccountScope.ownerPayoutAccounts,
              ),
              builder: (ctx, snapshot) {
                final accounts = snapshot.data ?? [];
                final isLoading =
                    snapshot.connectionState == ConnectionState.waiting;

                return Column(
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
                            Icons.account_balance_wallet_rounded,
                            color: AppUi.bluePrimary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Payout Destination',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                  color: AppUi.textPrimaryOf(ctx),
                                ),
                              ),
                              Text(
                                'Where customer GCash & Maya payments arrive',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppUi.textSecondaryOf(ctx),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    if (isLoading)
                      const Padding(
                        padding: EdgeInsets.all(32),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (accounts.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: AppUi.cardDecorationOf(ctx),
                        child: Column(
                          children: [
                            Icon(
                              Icons.payments_outlined,
                              size: 40,
                              color: AppUi.textSecondaryOf(ctx),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'No payout account added yet',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: AppUi.textPrimaryOf(ctx),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Add your GCash or Maya mobile number so customers can pay digitally.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 12,
                                color: AppUi.textSecondaryOf(ctx),
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      ...accounts.map((acc) {
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: AppUi.cardDecorationOf(ctx),
                          child: Material(
                            color: Colors.transparent,
                            child: ListTile(
                            leading: Icon(
                              acc.type == 'gcash'
                                  ? Icons.phone_android_rounded
                                  : Icons.account_balance_rounded,
                              color: AppUi.bluePrimary,
                            ),
                            title: Text(
                              acc.label,
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: AppUi.textPrimaryOf(ctx),
                              ),
                            ),
                            subtitle: Text(
                              '${acc.type.toUpperCase()} · ${acc.maskedValue}',
                              style: TextStyle(
                                color: AppUi.textSecondaryOf(ctx),
                                fontSize: 12,
                              ),
                            ),
                            trailing: acc.isDefault
                                ? Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppUi.bluePrimary.withValues(
                                        alpha: 0.1,
                                      ),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: const Text(
                                      'PRIMARY',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w900,
                                        color: AppUi.bluePrimary,
                                      ),
                                    ),
                                  )
                                : null,
                            ),
                          ),
                        );
                      }),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: FilledButton.icon(
                        icon: const Icon(Icons.add_rounded, size: 20),
                        label: const Text(
                          'Add Payout Account',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppUi.bluePrimary,
                          shape: RoundedRectangleBorder(
                            borderRadius: AppUi.pillRadius,
                          ),
                        ),
                        onPressed: () => _showAddPayoutDialog(
                          ctx,
                          paymentService,
                          () => setSheetState(() {}),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          );
        },
      ),
    );
  }

  void _showAddPayoutDialog(
    BuildContext sheetContext,
    PaymentSettingsService service,
    VoidCallback onSaved,
  ) {
    final nameCtrl = TextEditingController(
      text: _businessNameController.text.trim(),
    );
    final refCtrl = TextEditingController(text: _phoneController.text.trim());
    String selectedType = 'gcash';

    showDialog<void>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: AppUi.cardRadius),
          backgroundColor: AppUi.surfaceOf(dialogCtx),
          title: Text(
            'Add Payout Account',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: AppUi.textPrimaryOf(dialogCtx),
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Account Provider',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppUi.textSecondaryOf(dialogCtx),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: ChoiceChip(
                        label: const Text('GCash'),
                        selected: selectedType == 'gcash',
                        onSelected: (s) =>
                            setDialogState(() => selectedType = 'gcash'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ChoiceChip(
                        label: const Text('Maya'),
                        selected: selectedType == 'maya',
                        onSelected: (s) =>
                            setDialogState(() => selectedType = 'maya'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: nameCtrl,
                  decoration: AppUi.fieldDecorationOf(
                    dialogCtx,
                    'Account Name',
                  ),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppUi.textPrimaryOf(dialogCtx),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: refCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: AppUi.fieldDecorationOf(
                    dialogCtx,
                    'Mobile Number (09xx)',
                  ),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppUi.textPrimaryOf(dialogCtx),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                if (dialogCtx.mounted && Navigator.canPop(dialogCtx)) {
                  Navigator.pop(dialogCtx);
                }
              },
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final name = nameCtrl.text.trim();
                final ref = refCtrl.text.trim();
                if (name.isEmpty || ref.isEmpty) {
                  _showMessage(
                    'Please enter account name and number',
                    isError: true,
                  );
                  return;
                }
                if (dialogCtx.mounted && Navigator.canPop(dialogCtx)) {
                  Navigator.pop(dialogCtx);
                }
                try {
                  await service.create(
                    scope: PaymentAccountScope.ownerPayoutAccounts,
                    type: selectedType,
                    accountName: name,
                    accountRef: ref,
                    providerName: selectedType.toUpperCase(),
                  );
                  onSaved();
                  _showMessage('Payout destination added successfully');
                } catch (e) {
                  _showMessage(
                    FriendlyErrors.message(
                      e,
                      fallback: 'Could not save payout account. Please try again.',
                    ),
                    isError: true,
                  );
                }
              },
              style: FilledButton.styleFrom(backgroundColor: AppUi.bluePrimary),
              child: const Text('Save Account'),
            ),
          ],
        ),
      ),
    );
  }

  void _logout() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: AppUi.cardRadius),
        title: const Text('Sign out?'),
        content: const Text('You can sign back in anytime.'),
        actions: [
          TextButton(
            onPressed: () {
              if (context.mounted && Navigator.canPop(context)) {
                Navigator.pop(context);
              }
            },
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              if (context.mounted && Navigator.canPop(context)) {
                Navigator.pop(context);
              }
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

  Future<void> _pickAndUploadImage() async {
    final user = supabase.auth.currentUser;
    if (user == null || !mounted) return;
    try {
      setState(() => _isUploadingImage = true);
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 600,
        maxHeight: 600,
        imageQuality: 85,
      );
      if (image == null) return;

      final fileBytes = await image.readAsBytes();
      final fileName = 'avatar_${user.id}${path.extension(image.name)}';
      await supabase.storage
          .from('avatars')
          .uploadBinary(
            fileName,
            fileBytes,
            fileOptions: const FileOptions(upsert: true),
          );
      final publicUrl = supabase.storage.from('avatars').getPublicUrl(fileName);
      await supabase
          .from('profiles')
          .update({'avatar_url': publicUrl})
          .eq('id', user.id);
      if (mounted) {
        setState(
          () => _avatarUrl =
              '$publicUrl?t=${DateTime.now().millisecondsSinceEpoch}',
        );
      }
    } finally {
      if (mounted) setState(() => _isUploadingImage = false);
    }
  }

  Future<void> _pickAndUploadCoverPhoto() async {
    final user = supabase.auth.currentUser;
    if (user == null || !mounted) return;
    try {
      setState(() => _isUploadingCover = true);
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1200,
        maxHeight: 600,
        imageQuality: 85,
      );
      if (image == null) return;

      final fileBytes = await image.readAsBytes();
      final fileName = 'cover_${user.id}${path.extension(image.name)}';
      await supabase.storage
          .from('avatars')
          .uploadBinary(
            fileName,
            fileBytes,
            fileOptions: const FileOptions(upsert: true),
          );
      final publicUrl = supabase.storage.from('avatars').getPublicUrl(fileName);
      await supabase
          .from('profiles')
          .update({'station_photo_url': publicUrl})
          .eq('id', user.id);
      if (mounted) {
        setState(() {
          _coverPhotoUrl =
              '$publicUrl?t=${DateTime.now().millisecondsSinceEpoch}';
        });
      }
    } finally {
      if (mounted) setState(() => _isUploadingCover = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container();
    }

    return Scaffold(
      backgroundColor: AppUi.pageBgOf(context),
      body: Column(
        children: [
          const TabScreenHeroHeader(
            title: 'Station profile',
            subtitle: 'Account, payouts, settings, and operations',
          ),
          _buildModernHeader(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadAllData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 96),
                child: Padding(
                  padding: AppUi.pagePadding.copyWith(top: 12),
                  child: Column(
                    children: [
                      if (!_profileIsComplete) ...[
                            AccountCompletenessHint(
                              message: _profileCompletionMessage,
                              onTap: (_businessNameController.text.trim().isEmpty || _stationLocationSummary.isEmpty)
                                  ? _openStationDetailsSheet
                                  : _openOwnerDetailsSheet,
                            ),
                          ],
                          const AccountSectionLabel('Station identity'),
                          AccountGroup(
                            children: [
                              AccountNavTile(
                                icon: Icons.storefront_outlined,
                                title: 'Station details',
                                subtitle: _stationLocationSummary.isEmpty
                                    ? 'Add station details and map pin'
                                    : _stationLocationSummary,
                                onTap: _openStationDetailsSheet,
                              ),
                              AccountNavTile(
                                icon: Icons.person_outline_rounded,
                                title: 'About owner',
                                subtitle: _ownerFullName.isEmpty
                                    ? 'Owner name and personal details'
                                    : _ownerFullName,
                                onTap: _openOwnerDetailsSheet,
                              ),
                            ],
                          ),

                          const AccountSectionLabel('Pricing & delivery'),
                          AccountGroup(
                            children: [
                              AccountNavTile(
                                icon: Icons.local_shipping_outlined,
                                title: 'Pricing & delivery rules',
                                subtitle: _pricingSummary,
                                onTap: _openPricingDeliverySheet,
                              ),
                              AccountNavTile(
                                icon: Icons.payments_outlined,
                                title: 'Accepted payment methods',
                                subtitle: _paymentMethodsSummary,
                                onTap: _openPaymentMethodsSheet,
                              ),
                              AccountNavTile(
                                icon: Icons.account_balance_wallet_outlined,
                                title: 'Payout destination',
                                subtitle:
                                    'GCash & Maya destination for payments',
                                onTap: _showPayoutAccountSheet,
                              ),
                            ],
                          ),

                          const AccountSectionLabel('Catalog & operations'),
                          AccountGroup(
                            children: [
                              AccountNavTile(
                                icon: Icons.water_drop_outlined,
                                title: 'Water products & catalog',
                                subtitle:
                                    'Refill sizes, alkalines, and custom prices',
                                onTap: _openWaterProductsCatalogPopup,
                              ),
                              AccountNavTile(
                                icon: Icons.inventory_2_outlined,
                                title: 'Inventory stock',
                                subtitle:
                                    'Filled stock, empty gallons, and returns',
                                onTap: () => context.openOwnerInventory(),
                              ),
                              AccountNavTile(
                                icon: Icons.menu_book_outlined,
                                title: 'Delivery & credit ledger',
                                subtitle:
                                    'Offline refills, customer credits, and sales analytics',
                                onTap: () =>
                                    context.push(AppRoutes.deliveryManagement),
                              ),
                            ],
                          ),

                          const AccountSectionLabel('Preferences'),
                          AccountGroup(
                            children: [
                              AccountToggleTile(
                                icon: Icons.notifications_active_outlined,
                                title: 'Order & dispatch alerts',
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
                                onChanged: (v) => context
                                    .read<ThemeProvider>()
                                    .setDarkMode(v),
                              ),
                            ],
                          ),

                          const AccountSectionLabel('Security & account'),
                          AccountGroup(
                            children: [
                              AccountNavTile(
                                icon: Icons.shield_outlined,
                                title: 'Account security',
                                subtitle:
                                    'Password and account protection controls',
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        const AccountSecurityScreen(
                                          role: 'owner',
                                        ),
                                  ),
                                ),
                              ),
                              AccountNavTile(
                                icon: Icons.logout_rounded,
                                iconColor: const Color(0xFFEF4444),
                                title: 'Sign out',
                                titleColor: const Color(0xFFEF4444),
                                subtitle:
                                    'Log out of your account on this device',
                                onTap: _logout,
                              ),
                              AccountNavTile(
                                icon: Icons.delete_outline_rounded,
                                iconColor: const Color(0xFFDC2626),
                                title: 'Delete account',
                                titleColor: const Color(0xFFDC2626),
                                subtitle:
                                    'Permanently remove your account and data',
                                onTap: () =>
                                    _showDeleteAccountDialog(context),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                        ],
                      ),
                    ),
                  ),
                ),
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
                      'This permanently removes your station profile, catalog, and operations data.',
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
                                  await supabase.auth.signOut(
                                    scope: SignOutScope.local,
                                  );
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

  Widget _buildModernHeader() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppUi.surfaceOf(context),
        border: Border(bottom: BorderSide(color: AppUi.borderOf(context))),
      ),
      child: Column(
        children: [
          // Cover Photo with Stacked Profile photo
          Stack(
            clipBehavior: Clip.none,
            children: [
              // Cover Photo
              Container(
                height: 120,
                width: double.infinity,
                decoration: BoxDecoration(color: AppUi.chipBgOf(context)),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _coverPhotoUrl.isNotEmpty
                        ? Image.network(
                            _coverPhotoUrl,
                            fit: BoxFit.cover,
                            cacheWidth: 1080,
                            filterQuality: FilterQuality.low,
                          )
                        : Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.storefront_outlined,
                                  size: 32,
                                  color: AppUi.textSecondaryOf(
                                    context,
                                  ).withValues(alpha: 0.6),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Station storefront photo',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: AppUi.textSecondaryOf(context),
                                  ),
                                ),
                              ],
                            ),
                          ),
                    // Upload Cover Button
                    Positioned(
                      top: 10,
                      right: 10,
                      child: CircleAvatar(
                        backgroundColor: Colors.black.withValues(alpha: 0.5),
                        radius: 16,
                        child: _isUploadingCover
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : IconButton(
                                icon: const Icon(
                                  Icons.camera_alt_outlined,
                                  color: Colors.white,
                                  size: 16,
                                ),
                                onPressed: _pickAndUploadCoverPhoto,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
              // Profile Photo
              Positioned(
                bottom: -28,
                left: 20,
                child: GestureDetector(
                  onTap: _isUploadingImage ? null : _pickAndUploadImage,
                  child: Stack(
                    children: [
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppUi.surfaceOf(context),
                          border: Border.all(
                            color: AppUi.surfaceOf(context),
                            width: 3,
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(36),
                          child: _avatarUrl.isNotEmpty
                              ? Image.network(
                                  _avatarUrl,
                                  fit: BoxFit.cover,
                                  cacheWidth: 200,
                                  cacheHeight: 200,
                                  filterQuality: FilterQuality.low,
                                )
                              : Container(
                                  color: AppUi.bluePrimary.withValues(
                                    alpha: 0.1,
                                  ),
                                  child: const Icon(
                                    Icons.person,
                                    color: AppUi.bluePrimary,
                                    size: 32,
                                  ),
                                ),
                        ),
                      ),
                      if (_isUploadingImage)
                        const Positioned.fill(
                          child: Center(
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      Positioned(
                        bottom: 2,
                        right: 2,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: AppUi.bluePrimary,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.camera_alt,
                            color: Colors.white,
                            size: 11,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          // Business Name & Email
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _businessNameController.text.isNotEmpty
                        ? _businessNameController.text
                        : 'Water Station',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: AppUi.textPrimaryOf(context),
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Icon(
                        Icons.email_outlined,
                        size: 13,
                        color: AppUi.textSecondaryOf(context),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        _contactEmail.isNotEmpty
                            ? _contactEmail
                            : 'owner@erefill.com',
                        style: TextStyle(
                          color: AppUi.textSecondaryOf(context),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Icon(
                        Icons.badge_outlined,
                        size: 13,
                        color: AppUi.textSecondaryOf(context),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        _firstNameController.text.isNotEmpty
                            ? "${_firstNameController.text} ${_lastNameController.text}"
                            : 'Station Owner',
                        style: TextStyle(
                          color: AppUi.textSecondaryOf(context),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

}
