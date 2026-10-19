import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/providers/user_provider.dart';
import '../../core/services/local_data_cache.dart';
import '../../core/widgets/erefill_header.dart';
import '../../core/widgets/map_tiles.dart';
import '../../core/widgets/skeleton.dart';
import '../../core/widgets/app_form_fields.dart';
import '../../core/utils/profile_query_helpers.dart';

import 'package:erefill/core/utils/friendly_errors.dart';
/// Launch context for saved-addresses route (`extra` map).
class SavedAddressLaunchContext {
  final String address;
  final String landmark;
  final String? town;
  final String? barangay;
  final double latitude;
  final double longitude;

  const SavedAddressLaunchContext({
    required this.address,
    required this.landmark,
    required this.town,
    required this.barangay,
    required this.latitude,
    required this.longitude,
  });

  Map<String, dynamic> toMap() => {
        'address': address,
        'landmark': landmark,
        'town': town,
        'barangay': barangay,
        'latitude': latitude,
        'longitude': longitude,
      };

  factory SavedAddressLaunchContext.fromMap(Map<String, dynamic> map) {
    return SavedAddressLaunchContext(
      address: map['address']?.toString() ?? '',
      landmark: map['landmark']?.toString() ?? '',
      town: map['town']?.toString(),
      barangay: map['barangay']?.toString(),
      latitude: (map['latitude'] as num?)?.toDouble() ?? 0,
      longitude: (map['longitude'] as num?)?.toDouble() ?? 0,
    );
  }
}

class SavedAddressesScreen extends StatefulWidget {
  final SavedAddressLaunchContext launch;

  const SavedAddressesScreen({super.key, required this.launch});

  @override
  State<SavedAddressesScreen> createState() => _SavedAddressesScreenState();
}

class _SavedAddressesScreenState extends State<SavedAddressesScreen> {
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _addresses = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAddresses();
  }

  Future<void> _loadAddresses() async {
    final customerId = supabase.auth.currentUser?.id;
    if (customerId == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final rows = await supabase
          .from('customer_addresses')
          .select()
          .eq('customer_id', customerId)
          .order('is_default', ascending: false)
          .order('created_at', ascending: false);

      var list = List<Map<String, dynamic>>.from(rows);

      // Auto-migrate launch/profile address if customer has no saved addresses yet
      if (list.isEmpty) {
        String address = widget.launch.address.trim();
        String? town = widget.launch.town;
        String? barangay = widget.launch.barangay;
        String landmark = widget.launch.landmark.trim();
        double lat = widget.launch.latitude;
        double lng = widget.launch.longitude;

        if (address.isEmpty) {
          try {
            final prof = await supabase
                .from('profiles')
                .select(
                  'complete_address, town, barangay, landmark, latitude, longitude',
                )
                .eq('id', customerId)
                .maybeSingle();
            if (prof != null) {
              address = (prof['complete_address']?.toString() ?? '').trim();
              town = prof['town']?.toString();
              barangay = prof['barangay']?.toString();
              landmark = (prof['landmark']?.toString() ?? '').trim();
              lat = (prof['latitude'] as num?)?.toDouble() ?? 0.0;
              lng = (prof['longitude'] as num?)?.toDouble() ?? 0.0;
            }
          } catch (e) {
            debugPrint('Error fetching fallback profile address: $e');
          }
        }

        if (address.isNotEmpty) {
          try {
            await ProfileQueryHelpers.ensureProfileExists(supabase, userId: customerId);

            final payload = <String, dynamic>{
              'customer_id': customerId,
              'label': 'Home',
              'complete_address': address,
              'barangay': barangay,
              'town': town,
              'landmark': landmark,
              'latitude': lat != 0 ? lat : 9.3333,
              'longitude': lng != 0 ? lng : 125.9833,
              'map_pin_town': town,
              'is_default': true,
            };

            Map<String, dynamic>? inserted;
            try {
              inserted = await supabase
                  .from('customer_addresses')
                  .insert(payload)
                  .select()
                  .maybeSingle();
            } catch (e) {
              if (e.toString().contains('map_pin_town')) {
                payload.remove('map_pin_town');
                inserted = await supabase
                    .from('customer_addresses')
                    .insert(payload)
                    .select()
                    .maybeSingle();
              } else {
                rethrow;
              }
            }

            if (inserted != null) {
              list = [Map<String, dynamic>.from(inserted)];
            }
          } catch (e) {
            debugPrint('Error auto-migrating profile address: $e');
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _addresses = list;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading saved addresses: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _syncToProfile(Map<String, dynamic> addr) async {
    final customerId = supabase.auth.currentUser?.id;
    if (customerId == null) return;
    try {
      final town = addr['town']?.toString();
      final zip =
          town != null ? AppConstants.municipalityZipCodes[town] : null;
      final payload = <String, dynamic>{
        'complete_address': addr['complete_address'],
        'town': town,
        'barangay': addr['barangay'],
        'landmark': addr['landmark'],
        // A saved address does not include a purok. Retaining the prior
        // municipality's purok produces an internally inconsistent profile.
        'purok': null,
        'zip_code': zip,
        'latitude': (addr['latitude'] as num?)?.toDouble() ?? 0.0,
        'longitude': (addr['longitude'] as num?)?.toDouble() ?? 0.0,
      };
      await supabase.from('profiles').update(payload).eq('id', customerId);
      // Invalidate customer home and station caches so screens update immediately
      await LocalDataCache.instance.invalidatePattern('customer_home_');
      await LocalDataCache.instance.invalidate('cached_owner_stations');
      if (mounted) {
        // Do not wait for a Realtime event before the retained home and
        // station-list tabs learn about the municipality change.
        await context.read<UserProvider>().refreshProfile();
      }
    } catch (e) {
      debugPrint('Error syncing default address to profile: $e');
      rethrow;
    }
  }

  Future<void> _clearProfileAddress() async {
    final customerId = supabase.auth.currentUser?.id;
    if (customerId == null) return;
    try {
      await supabase.from('profiles').update({
        'complete_address': '',
        'town': null,
        'barangay': null,
        'landmark': '',
        'purok': null,
        'zip_code': null,
        'latitude': null,
        'longitude': null,
      }).eq('id', customerId);
      await LocalDataCache.instance.invalidatePattern('customer_home_');
      await LocalDataCache.instance.invalidate('cached_owner_stations');
      if (mounted) {
        await context.read<UserProvider>().refreshProfile();
      }
    } catch (e) {
      debugPrint('Error clearing profile address: $e');
    }
  }

  Future<void> _setDefault(String id) async {
    final customerId = supabase.auth.currentUser?.id;
    if (customerId == null) return;

    final target = _addresses.firstWhere(
      (a) => a['id'].toString() == id,
      orElse: () => {},
    );
    if (target.isEmpty) return;

    final town = target['town']?.toString();
    final pinTown = target['map_pin_town']?.toString();
    final lat = (target['latitude'] as num?)?.toDouble() ?? 0.0;
    final lng = (target['longitude'] as num?)?.toDouble() ?? 0.0;
    final hasValidCoords = (lat != 0 || lng != 0) &&
        lat >= -90 &&
        lat <= 90 &&
        lng >= -180 &&
        lng <= 180;

    // Only force map confirmation if coordinates are completely missing/zero,
    // or if pinTown is explicitly non-null and differs from the address municipality.
    final hasPinMismatch = pinTown != null &&
        pinTown.isNotEmpty &&
        town != null &&
        town.isNotEmpty &&
        pinTown != town;

    if (!hasValidCoords || hasPinMismatch) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Confirm this address on the map before making it your default.',
            ),
          ),
        );
      }
      await _showAddressForm(initial: {...target, 'is_default': true});
      return;
    }

    try {
      // 1. Immediately update UI state for instant visual feedback
      setState(() {
        for (final a in _addresses) {
          a['is_default'] = (a['id'].toString() == id);
        }
      });

      // 2. Clear default flag from all other addresses for this customer
      await supabase
          .from('customer_addresses')
          .update({'is_default': false})
          .eq('customer_id', customerId)
          .neq('id', id);

      // 3. Set the target address as default
      await supabase
          .from('customer_addresses')
          .update({'is_default': true})
          .eq('id', id)
          .eq('customer_id', customerId);

      await _syncToProfile(target);
      await _loadAddresses();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Selected "${target['label'] ?? 'Address'}" as your default delivery address.',
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error setting default address: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update default address: ${FriendlyErrors.message(e)}')),
        );
      }
      await _loadAddresses();
    }
  }

  Future<void> _deleteAddress(Map<String, dynamic> address) async {
    final customerId = supabase.auth.currentUser?.id;
    if (customerId == null) return;

    final id = address['id'].toString();
    final label = address['label']?.toString() ?? 'this address';
    final wasDefault = address['is_default'] == true;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Delete Address?'),
        content: Text('Are you sure you want to remove "$label"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.uiError,
            ),
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await supabase.from('customer_addresses').delete().eq('id', id);

      // If deleted address was default, promote next available address
      if (wasDefault) {
        final remainingRows = await supabase
            .from('customer_addresses')
            .select()
            .eq('customer_id', customerId)
            .order('created_at', ascending: false);
        final remaining = List<Map<String, dynamic>>.from(remainingRows);

        if (remaining.isNotEmpty) {
          final nextDefault = remaining.first;
          await supabase
              .from('customer_addresses')
              .update({'is_default': false})
              .eq('customer_id', customerId);
          await supabase
              .from('customer_addresses')
              .update({'is_default': true})
              .eq('id', nextDefault['id'])
              .eq('customer_id', customerId);
          await _syncToProfile(nextDefault);
        } else {
          await _clearProfileAddress();
        }
      }

      await _loadAddresses();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Address deleted successfully.')),
        );
      }
    } catch (e) {
      debugPrint('Error deleting address: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not delete address: ${FriendlyErrors.message(e)}')),
        );
      }
    }
  }

  Future<void> _showAddressForm({Map<String, dynamic>? initial}) async {
    final isEditing = initial != null;
    final labelController = TextEditingController(
      text: initial?['label']?.toString() ?? 'Home',
    );
    final addressController = TextEditingController(
      text: initial?['complete_address']?.toString() ??
          (isEditing ? '' : widget.launch.address),
    );
    final landmarkController = TextEditingController(
      text: initial?['landmark']?.toString() ??
          (isEditing ? '' : widget.launch.landmark),
    );

    final municipalityData = AppConstants.municipalityData;
    String? selectedTown = initial?['town']?.toString() ??
        widget.launch.town ??
        municipalityData.keys.first;
    if (!municipalityData.containsKey(selectedTown)) {
      selectedTown = municipalityData.keys.first;
    }

    String? selectedBarangay =
        initial?['barangay']?.toString() ?? widget.launch.barangay;
    final barangays = municipalityData[selectedTown] ?? [];
    if (selectedBarangay != null && !barangays.contains(selectedBarangay)) {
      selectedBarangay = barangays.isNotEmpty ? barangays.first : null;
    } else if (selectedBarangay == null && barangays.isNotEmpty) {
      selectedBarangay = barangays.first;
    }

    final initialCenter = AppConstants.municipalityCenters[selectedTown];
    double initLat = (initial?['latitude'] as num?)?.toDouble() ??
        widget.launch.latitude;
    double initLng = (initial?['longitude'] as num?)?.toDouble() ??
        widget.launch.longitude;
    final hasInitialPin =
        initLat >= -90 &&
        initLat <= 90 &&
        initLng >= -180 &&
        initLng <= 180 &&
        (initLat != 0 || initLng != 0);
    if (!hasInitialPin) {
      initLat = initialCenter?.latitude ?? 9.3333;
      initLng = initialCenter?.longitude ?? 125.9833;
    }

    LatLng pickedLocation = LatLng(initLat, initLng);
    final mapController = MapController();
    bool isDefault = initial?['is_default'] == true || _addresses.isEmpty;
    bool isSaving = false;
    bool isLocating = false;
    final pinTown = initial?['map_pin_town']?.toString();
    bool requiresPinConfirmation = !hasInitialPin ||
        (pinTown != null && pinTown.isNotEmpty && pinTown != selectedTown);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setModalState) {
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
            if (requiresPinConfirmation) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Move the map to confirm the exact pin for the new municipality.',
                  ),
                ),
              );
              return;
            }

            final customerId = supabase.auth.currentUser?.id;
            if (customerId == null) return;

            setModalState(() => isSaving = true);

            try {
              final payload = <String, dynamic>{
                'label': label,
                'complete_address': completeAddress,
                'barangay': selectedBarangay,
                'town': selectedTown,
                'landmark': landmark,
                'latitude': pickedLocation.latitude,
                'longitude': pickedLocation.longitude,
                'map_pin_town': selectedTown,
                'is_default': isDefault || _addresses.isEmpty,
              };

              // If setting this address as default, unset others first to avoid duplicate defaults
              if (payload['is_default'] == true) {
                try {
                  await supabase
                      .from('customer_addresses')
                      .update({'is_default': false})
                      .eq('customer_id', customerId);
                } catch (e) {
                  debugPrint('Non-fatal: clearing prior defaults: $e');
                }
              }

              Future<void> executeSave(Map<String, dynamic> data) async {
                if (isEditing) {
                  final editData = {
                    ...data,
                    'updated_at': DateTime.now().toIso8601String(),
                  };
                  await supabase
                      .from('customer_addresses')
                      .update(editData)
                      .eq('id', initial['id'])
                      .eq('customer_id', customerId);
                } else {
                  final insertData = {
                    ...data,
                    'customer_id': customerId,
                  };
                  await supabase.from('customer_addresses').insert(insertData);
                }
              }

              try {
                await ProfileQueryHelpers.ensureProfileExists(supabase, userId: customerId);
                await executeSave(payload);
              } catch (e) {
                // If map_pin_town column is missing on remote Supabase, retry without it
                if (e.toString().contains('map_pin_town')) {
                  payload.remove('map_pin_town');
                  await executeSave(payload);
                } else {
                  rethrow;
                }
              }

              if (payload['is_default'] == true) {
                await _syncToProfile(payload);
              }

              if (sheetContext.mounted) Navigator.pop(sheetContext);
              await _loadAddresses();

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
                final isFkError = e.toString().contains('23503') ||
                    e.toString().contains('customer_addresses_customer_id_fkey') ||
                    e.toString().contains('Key is not present in table "profiles"');
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      isFkError
                          ? 'Account profile record is initializing. Please re-open or try again in a moment.'
                          : FriendlyErrors.message(
                              e,
                              fallback: 'Could not save address. Please try again.',
                            ),
                    ),
                  ),
                );
              }
            } finally {
              if (sheetContext.mounted) {
                setModalState(() => isSaving = false);
              }
            }
          }

          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
            ),
            child: Material(
              color: AppUi.surfaceOf(context),
              borderRadius: AppUi.radiusSheetTop,
              clipBehavior: Clip.antiAlias,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(sheetContext).size.height * 0.92,
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
                            fontWeight: FontWeight.w700,
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
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Label chips & input
                          const AppFormSectionHeader(
                            title: 'ADDRESS LABEL',
                            subtitle: 'Choose a preset or type your custom label',
                          ),
                          AppUi.vGapSm,
                          Wrap(
                            spacing: 8,
                            children: ['Home', 'Work', 'Office', 'Other']
                                .map((preset) {
                              final isSelected =
                                  labelController.text.trim().toLowerCase() ==
                                      preset.toLowerCase();
                              return ChoiceChip(
                                label: Text(preset),
                                selected: isSelected,
                                selectedColor: AppUi.bluePrimary
                                    .withValues(alpha: 0.15),
                                labelStyle: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: isSelected
                                      ? AppUi.brandOf(context)
                                      : AppUi.textPrimaryOf(context),
                                ),
                                onSelected: (_) {
                                  setModalState(() {
                                    labelController.text = preset;
                                  });
                                },
                              );
                            }).toList(),
                          ),
                          AppUi.vGapSm,
                          AppFormField(
                            controller: labelController,
                            label: 'Address Label (e.g. Home)',
                            prefixIcon: Icons.bookmark_outline_rounded,
                            compact: true,
                            onChanged: (_) => setModalState(() {}),
                          ),
                          AppUi.vGapLg,

                          // Municipality & Barangay
                          const AppFormSectionHeader(
                            title: 'LOCATION AREA',
                            subtitle: 'City/town and barangay in Surigao del Sur',
                          ),
                          AppUi.vGapSm,
                          AppDropdownField<String>(
                            key: ValueKey('town-$selectedTown'),
                            value: selectedTown,
                            label: 'Municipality',
                            prefixIcon: Icons.location_city_outlined,
                            compact: true,
                            items: municipalityData.keys.map((town) {
                              return DropdownMenuItem(
                                value: town,
                                child: Text(town),
                              );
                            }).toList(),
                            onChanged: (town) {
                              setModalState(() {
                                selectedTown = town;
                                final bList = municipalityData[town] ?? [];
                                selectedBarangay =
                                    bList.isNotEmpty ? bList.first : null;
                                final center =
                                    AppConstants.municipalityCenters[town];
                                if (center != null) {
                                  pickedLocation = LatLng(
                                    center.latitude,
                                    center.longitude,
                                  );
                                  // Move map to the center of the newly selected municipality
                                  requiresPinConfirmation = false;
                                  mapController.move(pickedLocation, 14);
                                }
                              });
                            },
                          ),
                          AppUi.vGapMd,
                          AppDropdownField<String>(
                            key: ValueKey(
                              'barangay-$selectedTown-$selectedBarangay',
                            ),
                            value: selectedBarangay,
                            label: 'Barangay',
                            prefixIcon: Icons.holiday_village_outlined,
                            compact: true,
                            items: (selectedTown != null
                                    ? municipalityData[selectedTown] ?? []
                                    : <String>[])
                                .map((b) => DropdownMenuItem(
                                      value: b,
                                      child: Text(b),
                                    ))
                                .toList(),
                            onChanged: (b) =>
                                setModalState(() => selectedBarangay = b),
                          ),
                          AppUi.vGapLg,

                          // Street / Complete address
                          const AppFormSectionHeader(
                            title: 'STREET & LANDMARK',
                            subtitle: 'Precise delivery instructions',
                          ),
                          AppUi.vGapSm,
                          AppFormField(
                            controller: addressController,
                            label: 'House no., street name, or purok',
                            prefixIcon: Icons.location_on_outlined,
                            maxLines: 2,
                            compact: true,
                          ),
                          AppUi.vGapMd,
                          AppFormField(
                            controller: landmarkController,
                            label: 'Landmark (e.g. Near church or water station)',
                            prefixIcon: Icons.flag_outlined,
                            compact: true,
                          ),
                          AppUi.vGapLg,

                          // Interactive map pin
                          const AppFormSectionHeader(
                            title: 'MAP PIN LOCATION',
                            subtitle: 'Drag map to pin exact delivery spot',
                          ),
                          AppUi.vGapSm,
                          ClipRRect(
                            borderRadius: AppUi.cardRadius,
                            child: SizedBox(
                              height: 180,
                              child: Stack(
                                children: [
                                  FlutterMap(
                                    mapController: mapController,
                                    options: MapOptions(
                                      initialCenter: pickedLocation,
                                      initialZoom: 15,
                                      onPositionChanged: (camera, hasGesture) {
                                        if (hasGesture) {
                                          setModalState(() {
                                            pickedLocation = camera.center;
                                            requiresPinConfirmation = false;
                                          });
                                        }
                                      },
                                    ),
                                    children: [
                                      AppMapTiles.layer(context: context)
                                    ],
                                  ),
                                  Center(
                                    child: Padding(
                                      padding: EdgeInsets.only(bottom: 28),
                                      child: Icon(
                                        Icons.location_on_rounded,
                                        color: AppUi.brandOf(context),
                                        size: 38,
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
                                    right: 10,
                                    bottom: 10,
                                    child: FloatingActionButton.small(
                                      onPressed: isLocating
                                          ? null
                                          : () async {
                                              setModalState(
                                                  () => isLocating = true);
                                              try {
                                                final pos = await Geolocator
                                                    .getCurrentPosition();
                                                final newLoc = LatLng(
                                                  pos.latitude,
                                                  pos.longitude,
                                                );
                                                setModalState(() {
                                                  pickedLocation = newLoc;
                                                  requiresPinConfirmation =
                                                      false;
                                                });
                                                mapController.move(newLoc, 16);
                                              } catch (e) {
                                                debugPrint('GPS error: $e');
                                                if (mounted) {
                                                  ScaffoldMessenger.of(context)
                                                      .showSnackBar(
                                                    const SnackBar(
                                                      content: Text(
                                                        'Location access is unavailable. Please place the pin manually.',
                                                      ),
                                                    ),
                                                  );
                                                }
                                              } finally {
                                                setModalState(
                                                    () => isLocating = false);
                                              }
                                            },
                                      backgroundColor: AppUi.surfaceOf(context),
                                      foregroundColor: AppUi.brandOf(context),
                                      child: isLocating
                                          ? const SizedBox(
                                              width: 16,
                                              height: 16,
                                              child:
                                                  CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : const Icon(
                                              Icons.my_location_rounded,
                                              size: 18,
                                            ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            requiresPinConfirmation
                                ? 'Municipality changed. Drag the map to confirm the exact delivery pin.'
                                : 'Drag map to position pin for accurate delivery.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              color: AppUi.textSecondaryOf(context),
                            ),
                          ),
                          AppUi.vGapMd,

                          // Default address switch
                          Material(
                            color: Colors.transparent,
                            child: SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text(
                                'Set as default delivery address',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                              subtitle: Text(
                                'Auto-selected for your orders and checkout',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppUi.textSecondaryOf(context),
                                ),
                              ),
                              value: isDefault,
                              activeThumbColor: AppUi.bluePrimary,
                              onChanged: (val) =>
                                  setModalState(() => isDefault = val),
                            ),
                          ),
                          AppUi.vGapLg,

                          // Submit button
                          AppFormSubmitButton(
                            text: isEditing ? 'Update Address' : 'Save Address',
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
          ),
        );
      },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppUi.pageBgOf(context),
      appBar: ERefillHeader(
        title: 'Saved Addresses',
        subtitle: 'Select, edit, or add delivery addresses',
        actions: [
          IconButton(
            onPressed: () => _showAddressForm(),
            icon: Icon(
              Icons.add_location_alt_outlined,
              color: AppUi.brandOf(context),
            ),
            tooltip: 'Add new address',
          ),
        ],
      ),
      body: _isLoading
          ? const SkeletonList(itemCount: 4)
          : _addresses.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.location_off_outlined,
                          size: 56,
                          color: AppUi.textMuted,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No saved addresses yet',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: AppUi.textPrimaryOf(context),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Add your delivery address so stations can deliver refills quickly.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppUi.textSecondaryOf(context),
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 20),
                        FilledButton.icon(
                          onPressed: () => _showAddressForm(),
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: const Text('Add delivery address'),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppUi.bluePrimary,
                            shape: RoundedRectangleBorder(
                              borderRadius: AppUi.pillRadius,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  padding: AppUi.pagePaddingLoose,
                  itemCount: _addresses.length + 1,
                  itemBuilder: (context, index) {
                    if (index == _addresses.length) {
                      return Padding(
                        padding: const EdgeInsets.only(top: 8, bottom: 24),
                        child: OutlinedButton.icon(
                          onPressed: () => _showAddressForm(),
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: const Text(
                            'Add another address',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppUi.brandOf(context),
                            side: BorderSide(
                              color: AppUi.brandOf(context)
                                  .withValues(alpha: 0.35),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: AppUi.pillRadius,
                            ),
                            padding: const EdgeInsets.symmetric(
                              vertical: 14,
                            ),
                          ),
                        ),
                      );
                    }

                    final saved = _addresses[index];
                    final isDefault = saved['is_default'] == true;
                    final label =
                        saved['label']?.toString() ?? 'Address';
                    final completeAddress =
                        saved['complete_address']?.toString() ?? '';
                    final town = saved['town']?.toString();
                    final barangay = saved['barangay']?.toString();
                    final landmark =
                        saved['landmark']?.toString() ?? '';

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: AppUi.cardDecorationOf(
                        context,
                        borderColor:
                            isDefault ? AppUi.bluePrimary : null,
                        elevated: isDefault,
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: AppUi.cardRadius,
                          onTap: () {
                            if (!isDefault) {
                              _setDefault(saved['id'].toString());
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    '"$label" is already your default delivery address.',
                                  ),
                                ),
                              );
                            }
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      isDefault
                                          ? Icons.check_circle_rounded
                                          : Icons
                                              .radio_button_unchecked_rounded,
                                      color: isDefault
                                          ? AppUi.brandOf(context)
                                          : AppUi.textMuted,
                                      size: 22,
                                    ),
                                    const SizedBox(width: 10),
                                    Text(
                                      label,
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                        color: AppUi.textPrimaryOf(context),
                                      ),
                                    ),
                                    if (isDefault) ...[
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: AppUi.bluePrimary
                                              .withValues(alpha: 0.12),
                                          borderRadius:
                                              BorderRadius.circular(AppUi.radiusSm),
                                        ),
                                        child: Text(
                                          'DEFAULT',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            color: AppUi.brandOf(context),
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                      ),
                                    ],
                                    const Spacer(),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.edit_outlined,
                                        size: 20,
                                      ),
                                      color: AppUi.textSecondaryOf(context),
                                      tooltip: 'Edit address',
                                      visualDensity: VisualDensity.compact,
                                      onPressed: () => _showAddressForm(
                                        initial: saved,
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.delete_outline_rounded,
                                        size: 20,
                                      ),
                                      color: AppColors.uiError,
                                      tooltip: 'Delete address',
                                      visualDensity: VisualDensity.compact,
                                      onPressed: () =>
                                          _deleteAddress(saved),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Padding(
                                  padding: const EdgeInsets.only(left: 32),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        completeAddress,
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color:
                                              AppUi.textPrimaryOf(context),
                                          height: 1.3,
                                        ),
                                      ),
                                      if (barangay != null || town != null) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          [barangay, town]
                                              .where((e) =>
                                                  e != null && e.isNotEmpty)
                                              .join(', '),
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: AppUi.textSecondaryOf(
                                                context),
                                          ),
                                        ),
                                      ],
                                      if (landmark.isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            Icon(
                                              Icons.flag_outlined,
                                              size: 13,
                                              color: AppUi.textSecondaryOf(
                                                  context),
                                            ),
                                            const SizedBox(width: 4),
                                            Expanded(
                                              child: Text(
                                                'Landmark: $landmark',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontStyle: FontStyle.italic,
                                                  color: AppUi.textSecondaryOf(
                                                      context),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                      if (!isDefault) ...[
                                        const SizedBox(height: 8),
                                        Text(
                                          'Tap to set as default address',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: AppUi.brandOf(context),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
