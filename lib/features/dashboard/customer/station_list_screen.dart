import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/services.dart';

import '../../../core/widgets/skeleton.dart';

import '../../../core/constants.dart';
import '../../../core/water_types.dart';
import '../../../core/widgets/brand/hero_header.dart';
import '../../../core/widgets/brand/axo_states.dart';
import '../../../core/widgets/auth_dialogs.dart';
import '../../../core/widgets/refill_status_widgets.dart';
import '../../../core/routing/app_navigation.dart';
import '../../../core/services/station_data_cache.dart';
import '../../../core/widgets/map_tiles.dart';
import 'package:provider/provider.dart';
import '../../../core/providers/user_provider.dart';
import '../../../core/utils/station_orderability.dart';
import '../../../core/utils/station_price_helpers.dart';
import '../../../core/widgets/app_cached_image.dart';

class StationListScreen extends StatefulWidget {
  const StationListScreen({super.key, this.initialFilter});

  /// e.g. `'Favorites'` to open saved stations.
  final String? initialFilter;

  @override
  State<StationListScreen> createState() => _StationListScreenState();
}

class _StationListScreenState extends State<StationListScreen> {
  final supabase = Supabase.instance.client;
  late final Stream<List<Map<String, dynamic>>> _stationsStream;
  RealtimeChannel? _pricingChannel;
  RealtimeChannel? _favoritesChannel;
  bool _isLoading = true;
  String? _userTown;
  String _searchQuery = '';
  String _selectedFilter = 'All';
  String? _preferredWaterType;
  Position? _currentPosition;
  String? _locationUnavailableReason;
  bool _isMapView = false;
  Set<String> _favoriteStationIds = {};
  int? _highlightedMapStationIndex;

  double _filterMaxPrice = 100.0;
  double _filterMinRating = 0.0;
  bool _filterOpenOnly = false;
  Map<String, double> _ownerPrices = {};
  Map<String, double> _productPrices = {};
  int _pricingLoadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _stationsStream = supabase
        .from('profiles')
        .stream(primaryKey: ['id'])
        .eq('role', 'owner')
        .handleError((error, stackTrace) {
          debugPrint('Station list stream error: $error');
          debugPrint('Station list stream stack: $stackTrace');
          return <Map<String, dynamic>>[];
        });
    if (widget.initialFilter != null && widget.initialFilter!.isNotEmpty) {
      _selectedFilter = widget.initialFilter!;
    }
    _loadUserPreferences();
    _loadStationPricing();
    _subscribeToStationPricing();
    _subscribeToFavorites();
    _determinePosition();
    _fetchFavorites();
  }

  void _subscribeToStationPricing() {
    _pricingChannel = supabase
        .channel('station_pricing_updates')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'products',
          callback: (_) => _loadStationPricing(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'owner_settings',
          callback: (_) => _loadStationPricing(),
        )
        .subscribe();
  }

  void _subscribeToFavorites() {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    _favoritesChannel = supabase
        .channel('station-list:favorites:$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'favorites',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (_) => _fetchFavorites(),
        )
        .subscribe();
  }

  @override
  void dispose() {
    final channel = _pricingChannel;
    if (channel != null) {
      supabase.removeChannel(channel);
    }
    final favoritesChannel = _favoritesChannel;
    if (favoritesChannel != null) {
      supabase.removeChannel(favoritesChannel);
    }
    super.dispose();
  }

  Future<void> _loadStationPricing() async {
    final generation = ++_pricingLoadGeneration;
    try {
      final settingsFuture = supabase
          .from('owner_settings')
          .select('owner_id, price_per_gallon');
      final productsFuture = supabase
          .from('products')
          .select('owner_id, price, is_available')
          .eq('is_available', true);

      final results = await Future.wait([settingsFuture, productsFuture]);
      if (mounted && generation == _pricingLoadGeneration) {
        setState(() {
          _ownerPrices = StationPriceHelpers.mapFromSettingsRows(results[0]);
          _productPrices = StationPriceHelpers.mapFromProductRows(results[1]);
        });
      }
    } catch (e) {
      if (generation == _pricingLoadGeneration) {
        debugPrint('Station pricing fetch error: $e');
      }
    }
  }

  double _priceFor(dynamic station) {
    return StationPriceHelpers.priceForStation(
      Map<String, dynamic>.from(station),
      ownerPrices: _ownerPrices,
      productPrices: _productPrices,
    );
  }

  Map<String, dynamic> _stationForDisplay(dynamic station) {
    return StationPriceHelpers.withResolvedPrice(
      Map<String, dynamic>.from(station),
      ownerPrices: _ownerPrices,
      productPrices: _productPrices,
    );
  }

  bool _isOrderable(dynamic station) {
    return StationOrderability.isOrderable(
      Map<String, dynamic>.from(station),
      ownerSettingsPrices: _ownerPrices,
      productPrices: _productPrices,
    );
  }

  Future<void> _fetchFavorites() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;
    try {
      final data = await supabase
          .from('favorites')
          .select('station_id')
          .eq('user_id', userId);
      if (mounted) {
        setState(() {
          _favoriteStationIds = (data as List)
              .map((f) => f['station_id'].toString())
              .toSet();
        });
      }
    } catch (e) {
      debugPrint('Error fetching favorites: $e');
    }
  }

  Future<void> _toggleFav(String stationId) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      AuthDialogs.showSignInRequired(context);
      return;
    }

    HapticFeedback.mediumImpact();
    final isFav = _favoriteStationIds.contains(stationId);

    setState(() {
      if (isFav) {
        _favoriteStationIds.remove(stationId);
      } else {
        _favoriteStationIds.add(stationId);
      }
    });

    try {
      if (!isFav) {
        await supabase.from('favorites').insert({
          'user_id': userId,
          'station_id': stationId,
        });
      } else {
        await supabase
            .from('favorites')
            .delete()
            .eq('user_id', userId)
            .eq('station_id', stationId);
      }
    } catch (e) {
      // Revert if error
      setState(() {
        if (isFav) {
          _favoriteStationIds.add(stationId);
        } else {
          _favoriteStationIds.remove(stationId);
        }
      });
      debugPrint('Error toggling favorite: $e');
    }
  }

  Future<void> _determinePosition() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) {
        setState(() {
          _locationUnavailableReason =
              'Turn on location services to sort by nearest station.';
        });
      }
      return;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (mounted) {
          setState(() {
            _locationUnavailableReason =
                'Allow location access to sort stations by distance.';
          });
        }
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      if (mounted) {
        setState(() {
          _locationUnavailableReason =
              'Location access is blocked. Enable it in settings to sort by distance.';
        });
      }
      return;
    }

    final pos = await Geolocator.getCurrentPosition();
    if (mounted) {
      setState(() {
        _currentPosition = pos;
        _locationUnavailableReason = null;
      });
    }
  }

  Future<void> _loadUserPreferences() async {
    final cachedUser = mounted ? context.read<UserProvider>().user : null;
    if (cachedUser != null) {
      if (mounted) {
        setState(() {
          _userTown = cachedUser.town;
          _preferredWaterType = cachedUser.preferredWaterType;
          _isLoading = false;
        });
      }
    }
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    try {
      final rows = await Future.wait<Map<String, dynamic>?>([
        supabase.from('profiles').select('town').eq('id', userId).maybeSingle(),
        supabase.from('profiles').select('preferred_water_type').eq('id', userId).maybeSingle(),
      ]);
      final townRow = rows[0];
      final prefRow = rows[1];
      if (mounted) {
        setState(() {
          _userTown = townRow?['town'] as String? ?? _userTown;
          _preferredWaterType = prefRow?['preferred_water_type']?.toString() ?? _preferredWaterType;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Profile preferences fetch error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _openStationDetails(dynamic station) {
    context.openStationDetails(_stationForDisplay(station));
  }

  List<dynamic> _scopeByTown(List<dynamic> source) {
    if (_userTown == null || _userTown!.isEmpty) return source;
    final townKey = _userTown!.toLowerCase();
    return source
        .where((s) => s['town']?.toString().toLowerCase() == townKey)
        .toList();
  }

  List<dynamic> _filterStations(List<dynamic> source) {
    final query = _searchQuery.trim().toLowerCase();

    var filtered = source.where((s) {
      final stationName = (s['station_name'] ?? '').toString().toLowerCase();
      final barangay = (s['barangay'] ?? '').toString().toLowerCase();
      final town = (s['town'] ?? '').toString().toLowerCase();
      final isOpen = (s['is_open'] as bool?) ?? true;
      final avgRating = (s['average_rating'] as num?)?.toDouble() ?? 0.0;
      final price = _priceFor(s);

      if (!_isOrderable(s)) return false;

      final matchesSearch =
          query.isEmpty ||
          stationName.contains(query) ||
          barangay.contains(query) ||
          town.contains(query);

      if (price > _filterMaxPrice) return false;
      if (avgRating < _filterMinRating) return false;
      if (_filterOpenOnly && !isOpen) return false;

      if (_selectedFilter == 'Favorites') {
        final id = s['id']?.toString() ?? '';
        if (!_favoriteStationIds.contains(id)) return false;
      }

      final matchesFilter =
          _selectedFilter == 'All' ||
          _selectedFilter == 'Favorites' ||
          (_selectedFilter == 'Open Now' && isOpen) ||
          (_selectedFilter == 'Top Rated' && avgRating >= 4) ||
          (_selectedFilter == 'Nearest');

      return matchesSearch && matchesFilter;
    }).toList();

    if (_selectedFilter == 'Nearest' && _currentPosition != null) {
      filtered.sort((a, b) {
        final latA =
            (a['latitude'] as num?)?.toDouble() ??
            (a['lat'] as num?)?.toDouble() ??
            0;
        final lngA =
            (a['longitude'] as num?)?.toDouble() ??
            (a['lng'] as num?)?.toDouble() ??
            0;
        final latB =
            (b['latitude'] as num?)?.toDouble() ??
            (b['lat'] as num?)?.toDouble() ??
            0;
        final lngB =
            (b['longitude'] as num?)?.toDouble() ??
            (b['lng'] as num?)?.toDouble() ??
            0;
        final distA = latA == 0
            ? double.infinity
            : Geolocator.distanceBetween(
                _currentPosition!.latitude,
                _currentPosition!.longitude,
                latA,
                lngA,
              );
        final distB = latB == 0
            ? double.infinity
            : Geolocator.distanceBetween(
                _currentPosition!.latitude,
                _currentPosition!.longitude,
                latB,
                lngB,
              );
        return distA.compareTo(distB);
      });
    }

    return filtered;
  }

  void _resetFilters() {
    setState(() {
      _searchQuery = '';
      _selectedFilter = 'All';
      _filterMaxPrice = 100.0;
      _filterMinRating = 0.0;
      _filterOpenOnly = false;
    });
  }

  void _showAdvancedFilters() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppUi.surfaceOf(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppUi.radius)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setBottomState) {
            return SafeArea(
              child: SingleChildScrollView(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom,
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Station filters',
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          TextButton(
                            onPressed: () {
                              setBottomState(() {
                                _filterMaxPrice = 100.0;
                                _filterMinRating = 0.0;
                                _filterOpenOnly = false;
                              });
                            },
                            child: const Text('Reset'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Max refill price',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                          Text(
                            '₱${_filterMaxPrice.toInt()}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: AppUi.bluePrimary,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          activeTrackColor: AppUi.bluePrimary,
                          inactiveTrackColor: AppUi.blueBorder,
                          thumbColor: AppUi.bluePrimary,
                        ),
                        child: Slider(
                          value: _filterMaxPrice,
                          min: 10.0,
                          max: 100.0,
                          divisions: 18,
                          onChanged: (val) =>
                              setBottomState(() => _filterMaxPrice = val),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Minimum Rating',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [0.0, 3.0, 4.0, 4.5].map((rating) {
                          final isSelected = _filterMinRating == rating;
                          return Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4.0,
                              ),
                              child: InkWell(
                                onTap: () => setBottomState(
                                  () => _filterMinRating = rating,
                                ),
                                borderRadius: BorderRadius.circular(12),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? AppUi.bluePrimary
                                        : AppUi.surfaceOf(context),
                                    border: Border.all(
                                      color: isSelected
                                          ? AppUi.bluePrimary
                                          : AppUi.borderOf(context),
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    rating == 0.0 ? 'Any' : '$rating+ stars',
                                    style: TextStyle(
                                      color: isSelected
                                          ? Colors.white
                                          : AppUi.textPrimaryOf(context),
                                      fontWeight: isSelected
                                          ? FontWeight.w800
                                          : FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 24),
                      Material(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                        shape: RoundedRectangleBorder(
                          borderRadius: AppUi.cardRadius,
                          side: BorderSide(color: AppUi.borderOf(context)),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Material(
                            color: Colors.transparent,
                            child: SwitchListTile(
                              value: _filterOpenOnly,
                              onChanged: (val) =>
                                  setBottomState(() => _filterOpenOnly = val),
                              title: Text(
                                'Show Open Stations Only',
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              thumbColor:
                                  WidgetStateProperty.resolveWith((states) {
                                if (states.contains(WidgetState.selected)) {
                                  return AppUi.bluePrimary;
                                }
                                return null;
                              }),
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: ElevatedButton(
                          onPressed: () {
                            setState(() {});
                            Navigator.pop(context);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppUi.bluePrimary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: AppUi.cardRadius,
                            ),
                            elevation: 0,
                          ),
                          child: Text(
                            'Apply Advanced Filters',
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  List<Map<String, dynamic>> _mappableFrom(List<dynamic> stations) {
    return stations
        .where((s) {
          final lat =
              (s['latitude'] as num?)?.toDouble() ??
              (s['lat'] as num?)?.toDouble();
          final lng =
              (s['longitude'] as num?)?.toDouble() ??
              (s['lng'] as num?)?.toDouble();
          return lat != null && lng != null;
        })
        .map((s) {
          final base = Map<String, dynamic>.from(s);
          // Fallback normalization
          if (base['latitude'] == null && base['lat'] != null) {
            base['latitude'] = base['lat'];
          }
          if (base['longitude'] == null && base['lng'] != null) {
            base['longitude'] = base['lng'];
          }
          return base;
        })
        .toList();
  }

  Widget _buildStationListTile(dynamic s) {
    final stationName = s['station_name']?.toString().trim().isNotEmpty == true
        ? s['station_name'].toString()
        : s['full_name']?.toString() ?? 'Water Station';
    final barangay = s['barangay']?.toString() ?? '';
    final town = s['town']?.toString() ?? '';
    final location = [
      barangay,
      town,
    ].where((part) => part.isNotEmpty).join(', ');
    final isOpen = (s['is_open'] as bool?) ?? true;
    final availability =
        s['station_availability']?.toString() ?? (isOpen ? 'open' : 'closed');
    final price = _priceFor(s);
    final avgRating = (s['average_rating'] as num?)?.toDouble() ?? 0.0;
    final reviewCount = (s['review_count'] as num?)?.toInt() ?? 0;
    final lat = (s['latitude'] as num?)?.toDouble();
    final lng = (s['longitude'] as num?)?.toDouble();
    final waterType = s['primary_water_type']?.toString();
    final stationId = s['id']?.toString() ?? '';
    final isFavorite = _favoriteStationIds.contains(stationId);
    var distanceStr = '';
    if (_currentPosition != null && lat != null && lng != null) {
      final meters = Geolocator.distanceBetween(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
        lat,
        lng,
      );
      distanceStr = '${(meters / 1000).toStringAsFixed(1)} km';
    }

    return Material(
      color: AppUi.surfaceOf(context),
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: () => _openStationDetails(s),
        borderRadius: BorderRadius.circular(22),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: AppUi.borderOf(context)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 168,
                width: double.infinity,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _stationCover(s),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0x35000000), Colors.transparent],
                          stops: [0, 0.45],
                        ),
                      ),
                    ),
                    Positioned(
                      top: 12,
                      left: 12,
                      child: AvailabilityBadge(availability: availability),
                    ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Material(
                        color: AppUi.surfaceOf(context).withValues(alpha: 0.94),
                        shape: const CircleBorder(),
                        child: IconButton(
                          tooltip: isFavorite
                              ? 'Remove from favorites'
                              : 'Add to favorites',
                          visualDensity: VisualDensity.compact,
                          onPressed: stationId.isEmpty
                              ? null
                              : () => _toggleFav(stationId),
                          icon: Icon(
                            isFavorite
                                ? Icons.favorite_rounded
                                : Icons.favorite_border_rounded,
                            color: isFavorite
                                ? Colors.redAccent
                                : AppUi.textMuted,
                            size: 21,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 15),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            stationName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 17,
                              letterSpacing: -0.2,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 11,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: AppUi.blueSoft,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                price > 0
                                    ? '₱${price.toStringAsFixed(0)}'
                                    : '—',
                                style: const TextStyle(
                                  color: AppUi.bluePrimary,
                                  fontSize: 20,
                                  height: 1,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 3),
                              const Text(
                                'per gallon',
                                style: TextStyle(
                                  color: AppUi.textSecondary,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 7),
                    Row(
                      children: [
                        const Icon(
                          Icons.location_on_outlined,
                          size: 15,
                          color: AppUi.textMuted,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            location.isEmpty
                                ? 'Location not provided'
                                : location,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppUi.captionText.copyWith(
                              color: AppUi.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 14,
                      runSpacing: 8,
                      children: [
                        _stationInfo(
                          Icons.star_rounded,
                          reviewCount > 0
                              ? '${avgRating.toStringAsFixed(1)} · $reviewCount reviews'
                              : 'New station',
                          iconColor: const Color(0xFFF59E0B),
                        ),
                        if (distanceStr.isNotEmpty)
                          _stationInfo(Icons.near_me_outlined, distanceStr),
                        if (waterType != null && waterType.trim().isNotEmpty)
                          _stationInfo(
                            Icons.water_drop_outlined,
                            WaterTypes.byName(waterType).name,
                          ),
                      ],
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

  Widget _stationInfo(
    IconData icon,
    String label, {
    Color iconColor = AppUi.textSecondary,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: iconColor),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(
            color: AppUi.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _stationCover(dynamic station) {
    final photoUrl = station['station_photo_url']?.toString();
    return AppCachedImage(
      imageUrl: photoUrl,
      width: double.infinity,
      height: double.infinity,
      fit: BoxFit.cover,
      memCacheWidth: 600,
      memCacheHeight: 400,
      fallbackIcon: Icons.water_drop_rounded,
    );
  }

  Widget _buildMapSheetTile(dynamic s, int index) {
    final stationName = s['station_name'] ?? 'Water Station';
    final barangay = s['barangay'] ?? '';
    final town = s['town'] ?? '';
    final isOpen = (s['is_open'] as bool?) ?? true;
    final price = _priceFor(s);
    final avgRating = (s['average_rating'] as num?)?.toDouble() ?? 0.0;
    final lat = (s['latitude'] as num?)?.toDouble();
    final lng = (s['longitude'] as num?)?.toDouble();
    var distanceStr = '';
    if (_currentPosition != null && lat != null && lng != null) {
      final meters = Geolocator.distanceBetween(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
        lat,
        lng,
      );
      distanceStr = '${(meters / 1000).toStringAsFixed(1)} km';
    }
    final highlighted = _highlightedMapStationIndex == index;

    return Material(
      color: highlighted ? AppUi.blueSoft : AppUi.surfaceOf(context),
      borderRadius: AppUi.cardRadius,
      child: InkWell(
        onTap: () => _openStationDetails(s),
        borderRadius: AppUi.cardRadius,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: AppUi.cardRadius,
            border: Border.all(
              color: highlighted ? AppUi.bluePrimary : AppUi.borderOf(context),
              width: highlighted ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppUi.bluePrimary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.water_drop_rounded,
                  color: AppUi.bluePrimary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      stationName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        barangay,
                        town,
                      ].where((e) => e.toString().isNotEmpty).join(', '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppUi.captionText,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          '₱${price.toStringAsFixed(0)}/gal',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: AppUi.bluePrimary,
                            fontSize: 12,
                          ),
                        ),
                        if (distanceStr.isNotEmpty) ...[
                          Text(' · ', style: AppUi.captionText),
                          Text(distanceStr, style: AppUi.captionText),
                        ],
                        if (avgRating > 0) ...[
                          const Icon(
                            Icons.star_rounded,
                            size: 12,
                            color: Colors.amber,
                          ),
                          Text(
                            avgRating.toStringAsFixed(1),
                            style: AppUi.captionText,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  AvailabilityBadge(availability: isOpen ? 'open' : 'closed'),
                  const SizedBox(height: 8),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: AppUi.textMuted,
                    size: 20,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _stationsStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            backgroundColor: AppUi.pageBgOf(context),
            body: Center(
              child: AxoEmptyState(
                pose: AxoPose.thinking,
                title: 'Could not load stations',
                message: snapshot.error.toString(),
                actionLabel: 'Retry',
                onAction: () => setState(() {}),
                compact: true,
              ),
            ),
          );
        }

        final ownerRows = snapshot.data ?? [];
        final scoped = _scopeByTown(ownerRows);
        final stations = _filterStations(scoped);
        if (stations.isNotEmpty) {
          StationDataCache.instance.prefetch(
            stations.map((s) => s['id']?.toString() ?? '').toList(),
          );
        }
        final mappableStations = _mappableFrom(stations);

        final town = _userTown?.trim();
        final titleTown = town == null || town.isEmpty ||
                town.toLowerCase() == 'cantilan & madrid'
            ? 'your municipality'
            : town;
        final prefLabel = _preferredWaterType != null
            ? WaterTypes.byName(_preferredWaterType).shortName
            : null;

        Widget buildMapView() {
          if (mappableStations.isEmpty) {
            return AxoEmptyState(
              pose: AxoPose.thinking,
              compact: true,
              title: 'No map pins yet',
              message:
                  'Stations in this area have not set their location. Try list view instead.',
              actionLabel: 'Reset filters',
              onAction: _resetFilters,
            );
          }

          final center = _currentPosition != null
              ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
              : LatLng(
                  (mappableStations.first['latitude'] as num).toDouble(),
                  (mappableStations.first['longitude'] as num).toDouble(),
                );

          return Stack(
            children: [
              FlutterMap(
                options: MapOptions(
                  initialCenter: center,
                  initialZoom: 13.0,
                  onTap: (event, point) =>
                      setState(() => _highlightedMapStationIndex = null),
                ),
                children: [
                  AppMapTiles.layer(context: context),
                  if (_currentPosition != null)
                    MarkerLayer(
                      markers: [
                        Marker(
                          width: 24,
                          height: 24,
                          point: LatLng(
                            _currentPosition!.latitude,
                            _currentPosition!.longitude,
                          ),
                          child: Container(
                            decoration: BoxDecoration(
                              color: AppUi.bluePrimary,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 3),
                            ),
                          ),
                        ),
                      ],
                    ),
                  MarkerLayer(
                    markers: mappableStations.asMap().entries.map((entry) {
                      final index = entry.key;
                      final s = entry.value;
                      final selected = _highlightedMapStationIndex == index;
                      return Marker(
                        width: selected ? 56 : 50,
                        height: selected ? 56 : 50,
                        point: LatLng(
                          (s['latitude'] as num).toDouble(),
                          (s['longitude'] as num).toDouble(),
                        ),
                        child: GestureDetector(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() => _highlightedMapStationIndex = index);
                          },
                          child: Icon(
                            Icons.location_on_rounded,
                            color: selected
                                ? AppUi.accentGreen
                                : AppUi.bluePrimary,
                            size: selected ? 48 : 44,
                            shadows: const [
                              Shadow(
                                color: Colors.black54,
                                blurRadius: 8,
                                offset: Offset(0, 3),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
              DraggableScrollableSheet(
                initialChildSize: 0.32,
                minChildSize: 0.16,
                maxChildSize: 0.82,
                snap: true,
                snapSizes: const [0.16, 0.32, 0.82],
                builder: (context, scrollController) {
                  return Container(
                    decoration: BoxDecoration(
                      color: AppUi.surfaceOf(context),
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(AppUi.radiusSheet),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.12),
                          blurRadius: 24,
                          offset: const Offset(0, -6),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Container(
                          margin: const EdgeInsets.only(top: 10, bottom: 6),
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: AppUi.borderOf(context),
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                          child: Row(
                            children: [
                              Text(
                                '${mappableStations.length} stations nearby',
                                style: AppUi.sectionTitle,
                              ),
                              const Spacer(),
                              Text(
                                'Swipe up for list',
                                style: AppUi.captionText.copyWith(
                                  color: AppUi.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: ListView.separated(
                            controller: scrollController,
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                            itemCount: mappableStations.length,
                            separatorBuilder: (context, index) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              return _buildMapSheetTile(
                                mappableStations[index],
                                index,
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          );
        }

        return Scaffold(
          backgroundColor: AppUi.pageBgOf(context),
          body: Column(
            children: [
              StationDiscoverHeader(
                title: 'Water stations',
                subtitle: prefLabel != null
                    ? '$prefLabel refills in $titleTown'
                    : 'Refill stations in $titleTown',
                actions: [
                  SegmentedButton<bool>(
                    showSelectedIcon: false,
                    style: ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      padding: const WidgetStatePropertyAll(
                        EdgeInsets.symmetric(horizontal: 8),
                      ),
                      textStyle: const WidgetStatePropertyAll(
                        TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                      ),
                      foregroundColor: WidgetStateProperty.resolveWith(
                        (states) => states.contains(WidgetState.selected)
                            ? AppUi.bluePrimary
                            : Colors.white,
                      ),
                      backgroundColor: WidgetStateProperty.resolveWith(
                        (states) => states.contains(WidgetState.selected)
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.14),
                      ),
                      side: WidgetStatePropertyAll(
                        BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                      ),
                    ),
                    segments: const [
                      ButtonSegment<bool>(
                        value: false,
                        icon: Icon(Icons.view_list_rounded, size: 18),
                        label: Text('List'),
                      ),
                      ButtonSegment<bool>(
                        value: true,
                        icon: Icon(Icons.map_outlined, size: 18),
                        label: Text('Map'),
                      ),
                    ],
                    selected: {_isMapView},
                    onSelectionChanged: (selection) {
                      setState(() => _isMapView = selection.first);
                    },
                  ),
                ],
              ),
              if (!_isMapView)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Material(
                              color: AppUi.surfaceOf(context),
                              borderRadius: AppUi.pillRadius,
                              child: SizedBox(
                                height: 48,
                                child: TextField(
                                  onChanged: (value) =>
                                      setState(() => _searchQuery = value),
                                  textInputAction: TextInputAction.search,
                                  decoration: InputDecoration(
                                    hintText: 'Search station or barangay',
                                    prefixIcon: const Icon(
                                      Icons.search_rounded,
                                    ),
                                    border: InputBorder.none,
                                    filled: false,
                                    contentPadding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            height: 48,
                            width: 132,
                            padding: const EdgeInsets.symmetric(horizontal: 9),
                            decoration: BoxDecoration(
                              color: AppUi.surfaceOf(context),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: AppUi.borderOf(context),
                              ),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                isExpanded: true,
                                value:
                                    const {
                                      'All',
                                      'Open Now',
                                      'Favorites',
                                      'Top Rated',
                                      'Nearest',
                                    }.contains(_selectedFilter)
                                    ? _selectedFilter
                                    : 'All',
                                borderRadius: BorderRadius.circular(14),
                                icon: const Icon(
                                  Icons.expand_more_rounded,
                                  size: 18,
                                ),
                                style: TextStyle(
                                  color: AppUi.textPrimaryOf(context),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                                items: const [
                                  DropdownMenuItem(
                                    value: 'All',
                                    child: Text(
                                      'All stations',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  DropdownMenuItem(
                                    value: 'Open Now',
                                    child: Text(
                                      'Open now',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  DropdownMenuItem(
                                    value: 'Favorites',
                                    child: Text(
                                      'Favorites',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  DropdownMenuItem(
                                    value: 'Top Rated',
                                    child: Text(
                                      'Top rated',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  DropdownMenuItem(
                                    value: 'Nearest',
                                    child: Text(
                                      'Nearest',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                                onChanged: (value) {
                                  if (value == null) return;
                                  if (value == 'Nearest' &&
                                      _currentPosition == null) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          _locationUnavailableReason ??
                                              'Location is not ready yet. Try again in a moment.',
                                        ),
                                      ),
                                    );
                                    _determinePosition();
                                    return;
                                  }
                                  setState(() => _selectedFilter = value);
                                },
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Material(
                            color: AppUi.surfaceOf(context),
                            borderRadius: BorderRadius.circular(14),
                            child: InkWell(
                              onTap: _showAdvancedFilters,
                              borderRadius: BorderRadius.circular(14),
                              child: Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: AppUi.borderOf(context),
                                  ),
                                ),
                                child: const Icon(
                                  Icons.tune_rounded,
                                  color: AppUi.bluePrimary,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: _isLoading || !snapshot.hasData
                    ? SkeletonList(
                        itemCount: 4,
                        itemDelegate: (context, index) => const Padding(
                          padding: EdgeInsets.all(16.0),
                          child: CardSkeleton(),
                        ),
                      )
                    : _isMapView
                    ? buildMapView()
                    : CustomScrollView(
                        slivers: [
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.transparent,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          '${stations.length} station${stations.length == 1 ? '' : 's'}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                            color: AppUi.textSecondaryOf(
                                              context,
                                            ),
                                          ),
                                        ),
                                        if (prefLabel != null) ...[
                                          Text(
                                            ' · ',
                                            style: TextStyle(
                                              color: AppUi.textMuted.withValues(
                                                alpha: 0.8,
                                              ),
                                            ),
                                          ),
                                          Text(
                                            prefLabel,
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: AppUi.bluePrimary,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ],
                                        const Spacer(),
                                        if (_searchQuery.isNotEmpty)
                                          Text(
                                            '"$_searchQuery"',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: AppUi.bluePrimary,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          stations.isEmpty
                              ? SliverFillRemaining(
                                  child: AxoEmptyState(
                                    pose: AxoPose.empty,
                                    title: 'No matching stations',
                                    message: prefLabel != null
                                        ? 'No $prefLabel stations in $titleTown right now. Try another filter or update your water preference in Account.'
                                        : _selectedFilter == 'Favorites'
                                        ? 'Tap the heart on a station to save it here for quick reorder.'
                                        : 'Try another search, reset filters, or refresh your location.',
                                    actionLabel: 'Reset filters',
                                    onAction: _resetFilters,
                                    compact: true,
                                  ),
                                )
                              : SliverPadding(
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    0,
                                    16,
                                    96,
                                  ),
                                  sliver: SliverList.separated(
                                    itemCount: stations.length,
                                    separatorBuilder: (context, index) =>
                                        const SizedBox(height: 10),
                                    itemBuilder: (context, index) =>
                                        _buildStationListTile(stations[index]),
                                  ),
                                ),
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}
