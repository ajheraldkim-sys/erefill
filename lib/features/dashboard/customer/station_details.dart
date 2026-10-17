import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants.dart';
import '../../../core/db_tables.dart';
import '../../../core/routing/app_navigation.dart';
import '../../../core/services/external_navigation_service.dart';
import '../../../core/services/station_data_cache.dart';
import '../../../core/utils/friendly_errors.dart';
import '../../../core/providers/user_provider.dart';
import '../../../core/utils/order_product_helpers.dart';
import '../../../core/utils/station_price_helpers.dart';
import '../../../core/water_types.dart';
import '../../../core/widgets/app_cached_image.dart';
import '../../../core/widgets/auth_dialogs.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../models/cart_model.dart';
import '../../chat/models/chat_room.dart';
import '../../chat/services/chat_service.dart';
import '../../subscriptions/models/subscription_model.dart';
import '../../subscriptions/services/subscription_service.dart';

class StationDetailsScreen extends StatefulWidget {
  final Map<String, dynamic> station;
  const StationDetailsScreen({super.key, required this.station});

  @override
  State<StationDetailsScreen> createState() => _StationDetailsScreenState();
}

class _StationDetailsScreenState extends State<StationDetailsScreen> {
  final _supabase = Supabase.instance.client;
  final _quantityController = TextEditingController(text: '1');
  late Map<String, dynamic> _stationData;
  RealtimeChannel? _stationChannel;
  int _waterOptionsLoadGeneration = 0;
  int _quantity = 1;
  double? _pricePerGallon;
  String? _waterType;
  bool _isFav = false;
  bool _isPlacingOrder = false;
  CustomerSubscription? _activeSubscription;

  StreamSubscription<String>? _cacheSub;

  // Real-time refill options configured by this station.
  List<dynamic> _products = [];
  List<int> _ratingCounts = List.filled(5, 0);
  List<dynamic> _reviews = [];
  bool _isLoadingPurified = true;
  Map<String, dynamic>? _selectedProduct;

  static const String _sampleStationImage =
      'https://images.unsplash.com/photo-1564419320461-6870880221ad?auto=format&fit=crop&w=1200&q=60';

  @override
  void initState() {
    super.initState();
    _stationData = Map<String, dynamic>.from(widget.station);
    final ownerId = _stationData['id']?.toString();
    final cached = StationDataCache.instance.get(ownerId);

    if (cached != null) {
      // Instant rendering from real-time in-memory cache (0ms)
      _isLoadingPurified = false;
      _products = cached.products;
      _ratingCounts = cached.ratingCounts;
      _reviews = cached.reviews;
      _pricePerGallon = cached.pricePerGallon;
      _waterType = cached.waterType;
      if (cached.profileData != null) {
        _stationData = {..._stationData, ...cached.profileData!};
      }
      _stationData['price_per_gallon'] = _pricePerGallon;
      if (ownerId != null) _resolveSelectedProduct(ownerId);
    } else {
      // Seed immediately with initial station data so UI renders without delay
      _pricePerGallon = (_stationData['price_per_gallon'] as num?)?.toDouble() ??
          StationPriceHelpers.priceForStation(_stationData);
      _waterType = _stationData['primary_water_type']?.toString();
      if (ownerId != null) _resolveSelectedProduct(ownerId);
      // Immediately allow instant user interaction with display fallback product (0ms)
      _isLoadingPurified = false;
    }

    _checkIsFav();
    _checkActiveSubscription();
    _loadWaterOptions(forceRefresh: cached == null);
    _subscribeToStationUpdates();
  }

  @override
  void dispose() {
    _cacheSub?.cancel();
    final channel = _stationChannel;
    if (channel != null) {
      _supabase.removeChannel(channel);
    }
    _quantityController.dispose();
    super.dispose();
  }

  void _setQuantity(int quantity) {
    if (quantity < 1) return;
    setState(() {
      _quantity = quantity;
      _quantityController.value = TextEditingValue(
        text: quantity.toString(),
        selection: TextSelection.collapsed(offset: quantity.toString().length),
      );
    });
  }

  Future<void> _editQuantity() async {
    final quantity = await showDialog<int>(
      context: context,
      builder: (_) => _QuantityInputDialog(initialQuantity: _quantity),
    );
    if (mounted && quantity != null) _setQuantity(quantity);
  }

  void _subscribeToStationUpdates() {
    final ownerId = _stationData['id']?.toString();
    if (ownerId == null) return;

    // Listen to real-time cache updates for instantaneous UI refresh
    _cacheSub = StationDataCache.instance.onStationUpdated.listen((updatedId) {
      if (updatedId == ownerId && mounted) {
        final fresh = StationDataCache.instance.get(ownerId);
        if (fresh != null) {
          _applyBundle(fresh);
        }
      }
    });

    _stationChannel = _supabase
        .channel('station_details_updates:$ownerId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: DbTables.waterOptions,
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'owner_id',
            value: ownerId,
          ),
          callback: (payload) {
            StationDataCache.instance.applyRealtimeEvent(
              table: DbTables.waterOptions,
              ownerId: ownerId,
              record: payload.newRecord.isNotEmpty ? payload.newRecord : payload.oldRecord,
              eventType: payload.eventType.name.toUpperCase(),
            );
            _loadWaterOptions(forceRefresh: true);
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'owner_settings',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'owner_id',
            value: ownerId,
          ),
          callback: (payload) {
            StationDataCache.instance.applyRealtimeEvent(
              table: 'owner_settings',
              ownerId: ownerId,
              record: payload.newRecord.isNotEmpty ? payload.newRecord : payload.oldRecord,
              eventType: payload.eventType.name.toUpperCase(),
            );
            _loadWaterOptions(forceRefresh: true);
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'profiles',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: ownerId,
          ),
          callback: (payload) {
            StationDataCache.instance.applyRealtimeEvent(
              table: 'profiles',
              ownerId: ownerId,
              record: payload.newRecord.isNotEmpty ? payload.newRecord : payload.oldRecord,
              eventType: payload.eventType.name.toUpperCase(),
            );
            _loadWaterOptions(forceRefresh: true);
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'reviews',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'station_id',
            value: ownerId,
          ),
          callback: (_) => _loadWaterOptions(forceRefresh: true),
        )
        .subscribe();
  }

  Future<void> _checkIsFav() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;
    try {
      final res = await _supabase
          .from('favorites')
          .select('id')
          .eq('user_id', userId)
          .eq('station_id', _stationData['id'])
          .maybeSingle();
      if (mounted) setState(() => _isFav = res != null);
    } catch (e) {
      debugPrint('Fav check error: $e');
    }
  }

  Future<void> _toggleFav() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      AuthDialogs.showSignInRequired(context);
      return;
    }

    HapticFeedback.mediumImpact();
    setState(() => _isFav = !_isFav); // Optimistic UI

    try {
      if (_isFav) {
        await _supabase.from('favorites').insert({
          'user_id': userId,
          'station_id': _stationData['id'],
        });
      } else {
        await _supabase
            .from('favorites')
            .delete()
            .eq('user_id', userId)
            .eq('station_id', _stationData['id']);
      }
    } catch (e) {
      if (mounted) setState(() => _isFav = !_isFav);
      debugPrint('Fav toggle error: $e');
    }
  }

  String? _getCustomerWaterPreference() {
    if (!mounted) return null;
    try {
      return context.read<UserProvider>().user?.preferredWaterType;
    } catch (_) {
      return null;
    }
  }

  void _resolveSelectedProduct(String ownerId) {
    final settingsPrice = _pricePerGallon ?? 0;
    final previouslySelectedId = _selectedProduct?['id']?.toString();
    Map<String, dynamic>? previouslySelectedProduct;
    for (final product in _products) {
      if (product['id']?.toString() == previouslySelectedId) {
        previouslySelectedProduct =
            OrderProductHelpers.withDisplayDefaults(
              Map<String, dynamic>.from(product),
            );
        break;
      }
    }
    final customerPref = _getCustomerWaterPreference();
    final defaultProduct = OrderProductHelpers.defaultFromList(
      _products,
      stationWaterType: _waterType,
      preferredWaterType: customerPref,
    );
    if (previouslySelectedProduct != null) {
      _selectedProduct = previouslySelectedProduct;
    } else if (defaultProduct != null) {
      _selectedProduct = OrderProductHelpers.withDisplayDefaults(
        defaultProduct,
      );
    } else if (settingsPrice > 0) {
      _selectedProduct = OrderProductHelpers.displayFallback(
        ownerId: ownerId,
        price: settingsPrice,
        waterType: _waterType,
      );
    } else {
      _selectedProduct = null;
    }
  }

  void _applyBundle(CachedStationBundle bundle) {
    final ownerId = bundle.ownerId;
    setState(() {
      _isLoadingPurified = false;
      _pricePerGallon = bundle.pricePerGallon;
      _waterType = bundle.waterType;
      _ratingCounts = bundle.ratingCounts;
      _reviews = bundle.reviews;
      _products = bundle.products;
      if (bundle.profileData != null) {
        _stationData = {..._stationData, ...bundle.profileData!};
      }
      _stationData['price_per_gallon'] = _pricePerGallon;
      _resolveSelectedProduct(ownerId);
    });
  }

  Future<void> _loadWaterOptions({bool forceRefresh = false}) async {
    final generation = ++_waterOptionsLoadGeneration;
    final ownerId = _stationData['id']?.toString();
    if (ownerId == null) {
      if (mounted) setState(() => _isLoadingPurified = false);
      return;
    }

    try {
      // Parallelized & cached bundle fetch
      final bundle = await StationDataCache.instance.getOrFetch(
        ownerId,
        forceRefresh: forceRefresh,
      );

      if (mounted && generation == _waterOptionsLoadGeneration) {
        _applyBundle(bundle);
      }
    } catch (e) {
      if (generation == _waterOptionsLoadGeneration) {
        debugPrint('Error loading station data: $e');
        if (mounted) setState(() => _isLoadingPurified = false);
      }
    }
  }

  Future<void> _openInExternalMaps() async {
    final lat = (_stationData['latitude'] as num?)?.toDouble();
    final lng = (_stationData['longitude'] as num?)?.toDouble();
    final name = _stationData['station_name']?.toString() ?? 'Water Station';
    final address = _stationData['complete_address']?.toString() ?? '';

    final success = await ExternalNavigationService.openNavigation(
      latitude: lat,
      longitude: lng,
      title: name,
      addressFallback: address,
    );

    if (!success && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not open maps application.')));
    }
  }

  Future<void> _callStation() async {
    final phone = _stationData['phone']?.toString().trim();
    if (phone == null || phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Station phone number is not listed yet.')),
      );
      return;
    }
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not launch phone dialer.')),
        );
      }
    }
  }

  Future<void> _chatWithStation() async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      AuthDialogs.showSignInRequired(context);
      return;
    }
    final ownerId = _stationData['id']?.toString();
    if (ownerId == null) return;

    final stationName = _stationData['station_name']?.toString() ?? 'Water Station';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final chatService = ChatService();
      final room = await chatService.createSupportChatRoom(
        customerId: user.id,
        ownerId: ownerId,
        stationName: stationName,
      );

      if (mounted) {
        context.openChat(
          roomId: room.id,
          roomTitle: stationName,
          roomType: ChatRoomType.customerSupport,
        );
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              FriendlyErrors.message(
                e,
                fallback: 'Could not start chat with station. Please try again.',
              ),
            ),
          ),
        );
      }
    }
  }

  Future<void> _scheduleAutoRefill() async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      AuthDialogs.showSignInRequired(context);
      return;
    }

    final ownerId = _stationData['id']?.toString();
    if (ownerId == null || ownerId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Station details unavailable.')),
      );
      return;
    }

    final stationName = _stationData['station_name']?.toString() ??
        _stationData['name']?.toString() ??
        'Water Station';

    String selectedWaterType = _selectedProduct?['water_type']?.toString() ??
        _waterType ??
        'Purified';
    double selectedPrice = (_selectedProduct?['price'] as num?)?.toDouble() ??
        _pricePerGallon ??
        30.0;
    int selectedQty = _quantity > 0 ? _quantity : 1;
    String selectedFrequency = 'weekly';
    String selectedTimeSlot = 'morning';

    String defaultAddress = '';
    try {
      final prof = await _supabase
          .from('profiles')
          .select('complete_address')
          .eq('id', user.id)
          .maybeSingle();
      defaultAddress = prof?['complete_address']?.toString() ?? '';
    } catch (_) {}

    if (!mounted) return;

    final addressController = TextEditingController(text: defaultAddress);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final isDark = Theme.of(ctx).brightness == Brightness.dark;
          final estimatedPrice = selectedPrice * selectedQty;

          return Container(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              top: 16,
              left: 20,
              right: 20,
            ),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppUi.bluePrimary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.autorenew_rounded,
                              color: AppUi.bluePrimary,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Schedule Auto-Refill',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: AppUi.textPrimaryOf(ctx),
                                ),
                              ),
                              Text(
                                stationName,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppUi.textSecondaryOf(ctx),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(sheetCtx),
                      ),
                    ],
                  ),
                  const Divider(height: 20),

                  Text(
                    'Water Type',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppUi.textPrimaryOf(ctx),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: ['Purified', 'Alkaline', 'Mineral', 'Distilled'].map((type) {
                      final isSel = selectedWaterType.toLowerCase() == type.toLowerCase();
                      return ChoiceChip(
                        label: Text(type),
                        selected: isSel,
                        selectedColor: AppUi.bluePrimary.withValues(alpha: 0.15),
                        onSelected: (val) {
                          if (val) setSheetState(() => selectedWaterType = type);
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Bottles per Delivery',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppUi.textPrimaryOf(ctx),
                            ),
                          ),
                          Text(
                            '₱${selectedPrice.toStringAsFixed(0)} / bottle',
                            style: TextStyle(fontSize: 11, color: AppUi.textSecondaryOf(ctx)),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          IconButton(
                            onPressed: selectedQty > 1
                                ? () => setSheetState(() => selectedQty--)
                                : null,
                            icon: const Icon(Icons.remove_circle_outline_rounded),
                          ),
                          Text(
                            '$selectedQty',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: AppUi.textPrimaryOf(ctx),
                            ),
                          ),
                          IconButton(
                            onPressed: () => setSheetState(() => selectedQty++),
                            icon: const Icon(Icons.add_circle_outline_rounded),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  Text(
                    'Refill Routine Frequency',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppUi.textPrimaryOf(ctx),
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: selectedFrequency,
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'every_3_days', child: Text('Every 3 Days')),
                      DropdownMenuItem(value: 'twice_weekly', child: Text('Twice a Week (Every 4 Days)')),
                      DropdownMenuItem(value: 'weekly', child: Text('Weekly Refill (Every 7 Days)')),
                      DropdownMenuItem(value: 'bi_weekly', child: Text('Every 2 Weeks (14 Days)')),
                      DropdownMenuItem(value: 'monthly', child: Text('Monthly Refill')),
                    ],
                    onChanged: (v) {
                      if (v != null) setSheetState(() => selectedFrequency = v);
                    },
                  ),
                  const SizedBox(height: 14),

                  Text(
                    'Preferred Delivery Time Slot',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppUi.textPrimaryOf(ctx),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      {'key': 'morning', 'label': 'Morning (8AM - 12PM)'},
                      {'key': 'afternoon', 'label': 'Afternoon (1PM - 5PM)'},
                      {'key': 'evening', 'label': 'Evening (5PM - 8PM)'},
                    ].map((slot) {
                      final isSel = selectedTimeSlot == slot['key'];
                      return ChoiceChip(
                        label: Text(slot['label']!),
                        selected: isSel,
                        selectedColor: AppUi.bluePrimary.withValues(alpha: 0.15),
                        onSelected: (val) {
                          if (val) setSheetState(() => selectedTimeSlot = slot['key']!);
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),

                  Text(
                    'Delivery Address',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppUi.textPrimaryOf(ctx),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: addressController,
                    decoration: InputDecoration(
                      hintText: 'Enter street, purok, or landmark',
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 18),

                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppUi.blueSoft.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Estimated Total / Refill:',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            color: AppUi.textPrimaryOf(ctx),
                          ),
                        ),
                        Text(
                          '₱${estimatedPrice.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                            color: AppUi.bluePrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppUi.bluePrimary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () async {
                        final address = addressController.text.trim();
                        if (address.isEmpty) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(content: Text('Please enter delivery address.')),
                          );
                          return;
                        }

                        Navigator.pop(sheetCtx);

                        try {
                          await SubscriptionService().createSubscription(
                            customerId: user.id,
                            stationId: ownerId,
                            stationName: stationName,
                            stationPhotoUrl: _stationData['avatar_url']?.toString(),
                            quantity: selectedQty,
                            waterType: selectedWaterType,
                            estimatedPrice: estimatedPrice,
                            frequency: selectedFrequency,
                            preferredTimeSlot: selectedTimeSlot,
                            deliveryAddress: address,
                          );

                          if (mounted) {
                            _checkActiveSubscription();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Auto-Refill scheduled with $stationName! View under Orders > Routine.',
                                ),
                                backgroundColor: const Color(0xFF10B981),
                              ),
                            );
                          }
                        } catch (err) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Failed to schedule routine: $err')),
                            );
                          }
                        }
                      },
                      child: const Text(
                        'Confirm & Schedule Routine',
                        style: TextStyle(fontWeight: FontWeight.bold),
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

  Future<void> _checkActiveSubscription() async {
    final user = _supabase.auth.currentUser;
    final ownerId = _stationData['id']?.toString();
    if (user == null || ownerId == null) return;
    try {
      final subs =
          await SubscriptionService().getCustomerSubscriptions(user.id);
      final active = subs
          .where((s) => s.stationId == ownerId && s.isActive)
          .toList();
      if (active.isNotEmpty && mounted) {
        setState(() {
          _activeSubscription = active.first;
        });
      }
    } catch (e) {
      debugPrint('Check active subscription error: $e');
    }
  }

  Map<String, dynamic> get _displayProduct {
    if (_selectedProduct != null) return _selectedProduct!;
    final price =
        _pricePerGallon ??
        StationPriceHelpers.priceForStation(
          Map<String, dynamic>.from(_stationData),
        );
    return OrderProductHelpers.displayFallback(
      ownerId: _stationData['id']?.toString() ?? '',
      price: price,
      waterType: _waterType,
    );
  }

  Future<Map<String, dynamic>?> _resolveOrderProduct() async {
    final ownerId = _stationData['id']?.toString();
    if (ownerId == null) return null;

    return OrderProductHelpers.resolveOrderProduct(
      _supabase,
      ownerId,
      selected: _selectedProduct,
      products: _products,
      waterType: _waterType ?? _stationData['primary_water_type']?.toString(),
      preferredWaterType: _getCustomerWaterPreference(),
      settingsPrice:
          _pricePerGallon ??
          (_stationData['price_per_gallon'] as num?)?.toDouble(),
    );
  }

  Future<bool> _ensureCartForThisStation(CartProvider cart) async {
    final targetStationId = _stationData['id']?.toString();
    if (cart.items.isNotEmpty &&
        cart.stationId != null &&
        cart.stationId != targetStationId) {
      final replace = await showDialog<bool>(
        context: context,
        builder: (dialogCtx) => AlertDialog(
          backgroundColor: AppUi.surfaceOf(dialogCtx),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text(
            'Start new order?',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          content: Text(
            'Your cart already has items from ${cart.stationName ?? "another station"}. Adding from this station will replace them.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppUi.bluePrimary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => Navigator.pop(dialogCtx, true),
              child: const Text('Start New Order'),
            ),
          ],
        ),
      );
      if (replace == true) {
        cart.clearCart();
        cart.setStation(
          targetStationId,
          _stationData['station_name']?.toString() ?? 'Water Station',
        );
        return true;
      }
      return false;
    }

    if (cart.stationId == null || cart.stationId != targetStationId) {
      cart.setStation(
        targetStationId,
        _stationData['station_name']?.toString() ?? 'Water Station',
      );
    }
    return true;
  }

  Future<void> _addItemToCart(Map<String, dynamic> product, {int qty = 1}) async {
    final cart = context.read<CartProvider>();
    final allowed = await _ensureCartForThisStation(cart);
    if (!allowed) return;

    final id = product['id']?.toString() ?? '';
    final name = product['name']?.toString() ?? 'Water Product';
    final price = (product['price'] as num?)?.toDouble() ?? 0.0;

    final currentQty = cart.items[id]?.quantity ?? 0;
    if (currentQty == 0) {
      cart.addItem(id, name, price);
      if (qty > 1) {
        cart.updateQuantity(id, qty);
      }
    } else {
      cart.updateQuantity(id, currentQty + qty);
    }
    HapticFeedback.selectionClick();
  }

  void _removeItemFromCart(String productId) {
    final cart = context.read<CartProvider>();
    final currentQty = cart.items[productId]?.quantity ?? 0;
    if (currentQty <= 1) {
      cart.removeItem(productId);
    } else {
      cart.updateQuantity(productId, currentQty - 1);
    }
    HapticFeedback.selectionClick();
  }

  bool _isContainerOrAccessory(Map<String, dynamic> product) {
    final cat = (product['category'] ?? '').toString().toLowerCase();
    final name = (product['name'] ?? '').toString().toLowerCase();
    return cat.contains('container') ||
        cat.contains('accessory') ||
        cat.contains('accessories') ||
        name.contains('container') ||
        name.contains('cap') ||
        name.contains('bottle') ||
        name.contains('dispenser');
  }

  Future<void> _handleOrderNow({
    required bool canOrder,
    required String normalizedAvailability,
  }) async {
    if (_isPlacingOrder || _isLoadingPurified) return;

    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      AuthDialogs.showSignInRequired(context);
      return;
    }

    final scaffoldMessenger = ScaffoldMessenger.maybeOf(context);

    if (!canOrder) {
      scaffoldMessenger?.showSnackBar(
        SnackBar(
          content: Text(
            normalizedAvailability == 'busy'
                ? 'Station is busy and not accepting new orders.'
                : normalizedAvailability == 'maintenance'
                    ? 'Station is under maintenance right now.'
                    : 'Station is currently closed.',
          ),
        ),
      );
      return;
    }

    setState(() => _isPlacingOrder = true);
    try {
      final product = await _resolveOrderProduct();
      if (!mounted || !context.mounted) return;
      if (!OrderProductHelpers.isRealProduct(product)) {
        scaffoldMessenger?.showSnackBar(
          const SnackBar(
            content: Text(
              'Ordering is unavailable for this station right now. Please choose another station.',
            ),
          ),
        );
        return;
      }

      final orderProduct = product!;
      final cart = context.read<CartProvider>();
      final allowed = await _ensureCartForThisStation(cart);
      if (!allowed) {
        setState(() => _isPlacingOrder = false);
        return;
      }

      HapticFeedback.mediumImpact();
      final itemId = orderProduct['id'].toString();
      final itemName = orderProduct['name']?.toString() ?? 'Water Refill';
      final itemPrice = (orderProduct['price'] as num?)?.toDouble() ??
          (_stationData['price_per_gallon'] as num?)?.toDouble() ??
          25.0;

      final existingQty = cart.items[itemId]?.quantity ?? 0;
      if (existingQty == 0) {
        cart.addItem(itemId, itemName, itemPrice);
        cart.updateQuantity(itemId, _quantity);
      } else {
        cart.updateQuantity(itemId, _quantity);
      }

      if (!mounted || !context.mounted) return;
      context.openCart(_stationData);
    } catch (e) {
      debugPrint('Order start error: $e');
      if (!mounted) return;
      scaffoldMessenger?.showSnackBar(
        const SnackBar(
          content: Text(
            'Could not start your order. The station may still be setting up pricing.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isPlacingOrder = false);
    }
  }

  // ─── UI COMPONENTS ─────────────────────────────────────────────────────────

  Widget _buildStationHeader(
    BuildContext context,
    String stationName,
    bool isVerified,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Text(
            stationName,
            style: TextStyle(
              color: AppUi.textPrimaryOf(context),
              fontSize: 21,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.4,
              height: 1.2,
            ),
          ),
        ),
        if (isVerified) ...[
          const SizedBox(width: 8),
          const Icon(
            Icons.verified_rounded,
            color: AppUi.bluePrimary,
            size: 20,
          ),
        ],
      ],
    );
  }

  Widget _buildStationMetaRow(
    BuildContext context,
    bool isOpen,
    String rawTown,
    double rating,
    int reviewCount,
  ) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: [
          // Open / Closed Status Indicator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
            decoration: BoxDecoration(
              color: isOpen
                  ? const Color(0xFF10B981).withValues(alpha: 0.12)
                  : const Color(0xFFEF4444).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: isOpen
                        ? const Color(0xFF10B981)
                        : const Color(0xFFEF4444),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  isOpen ? 'Open Now' : 'Closed',
                  style: TextStyle(
                    color: isOpen
                        ? const Color(0xFF047857)
                        : const Color(0xFFB91C1C),
                    fontWeight: FontWeight.w700,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),

          // Rating or New indicator
          if (rating > 0) ...[
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.star_rounded,
                  size: 15,
                  color: Color(0xFFD97706),
                ),
                const SizedBox(width: 3),
                Text(
                  rating.toStringAsFixed(1),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppUi.textPrimaryOf(context),
                  ),
                ),
                if (reviewCount > 0)
                  Text(
                    ' ($reviewCount)',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppUi.textSecondaryOf(context),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 8),
            Text('·', style: TextStyle(color: AppUi.textSecondaryOf(context))),
            const SizedBox(width: 8),
          ] else ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                'New Station',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFB45309),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text('·', style: TextStyle(color: AppUi.textSecondaryOf(context))),
            const SizedBox(width: 8),
          ],

          // Municipality / Town
          if (rawTown.isNotEmpty) ...[
            Text(
              rawTown,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppUi.textSecondaryOf(context),
              ),
            ),
            const SizedBox(width: 8),
            Text('·', style: TextStyle(color: AppUi.textSecondaryOf(context))),
            const SizedBox(width: 8),
          ],

          // Delivery Fee
          const Text(
            'Distance-based delivery',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppUi.bluePrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddressRow(BuildContext context, String completeAddress) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(
            Icons.place_outlined,
            size: 16,
            color: AppUi.bluePrimary,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            completeAddress,
            style: TextStyle(
              color: AppUi.textSecondaryOf(context),
              fontSize: 13,
              height: 1.35,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildQuickActions(BuildContext context) {
    return Row(
      children: [
        _buildQuickActionBtn(
          icon: Icons.phone_outlined,
          label: 'Call',
          onTap: _callStation,
        ),
        const SizedBox(width: 8),
        _buildQuickActionBtn(
          icon: Icons.chat_bubble_outline_rounded,
          label: 'Chat',
          onTap: _chatWithStation,
        ),
        const SizedBox(width: 8),
        _buildQuickActionBtn(
          icon: Icons.autorenew_rounded,
          label: 'Routine',
          onTap: _scheduleAutoRefill,
        ),
        const SizedBox(width: 8),
        _buildQuickActionBtn(
          icon: Icons.directions_outlined,
          label: 'Directions',
          onTap: _openInExternalMaps,
        ),
      ],
    );
  }

  Widget _buildQuickActionBtn({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            HapticFeedback.lightImpact();
            onTap();
          },
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: AppUi.surfaceOf(context),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppUi.borderOf(context)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: const BoxDecoration(
                    color: AppUi.blueSoft,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Icon(icon, size: 18, color: AppUi.bluePrimary),
                ),
                const SizedBox(height: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppUi.textPrimaryOf(context),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBenefitsSection(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppUi.surfaceOf(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppUi.borderOf(context)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              children: [
                _buildBenefitRow(Icons.shield_outlined, 'UV Sterilized'),
                const SizedBox(height: 8),
                _buildBenefitRow(Icons.clean_hands_outlined, 'Free Sanitization'),
              ],
            ),
          ),
          Container(
            width: 1,
            height: 44,
            color: AppUi.dividerOf(context).withValues(alpha: 0.6),
            margin: const EdgeInsets.symmetric(horizontal: 10),
          ),
          Expanded(
            child: Column(
              children: [
                _buildBenefitRow(Icons.water_drop_outlined, 'Purity Tested'),
                const SizedBox(height: 8),
                _buildBenefitRow(Icons.speed_rounded, '~15m Fast Prep'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBenefitRow(IconData icon, String label) {
    return Row(
      children: [
        Icon(icon, size: 15, color: AppUi.bluePrimary),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: AppUi.textSecondaryOf(context),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildAutoRefillCard(BuildContext context) {
    final hasActive = _activeSubscription != null;
    final stationName = _stationData['station_name']?.toString() ?? 'this station';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppUi.blueSoft.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppUi.blueBorder.withValues(alpha: 0.7),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppUi.bluePrimary,
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Icon(
              hasActive ? Icons.event_repeat_rounded : Icons.autorenew_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasActive ? 'Active Routine' : 'Automated Refill Routine',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: AppUi.textPrimaryOf(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  hasActive
                      ? '${_activeSubscription!.frequency.replaceAll('_', ' ')} · ${_activeSubscription!.quantity} bottles'
                      : 'Recurring water deliveries scheduled with $stationName.',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: AppUi.textSecondaryOf(context),
                    height: 1.25,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: hasActive
                ? () => context.openOrderList()
                : _scheduleAutoRefill,
            style: FilledButton.styleFrom(
              backgroundColor: AppUi.bluePrimary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Text(
              hasActive ? 'Manage' : 'Set Up',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreferenceNotice() {
    final customerPref = _getCustomerWaterPreference();
    if (customerPref == null || customerPref.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    final prefInfo = WaterTypes.byName(customerPref);

    // Check if any product offered by the station matches customer's preferred water type
    bool hasMatchingProduct = false;
    if (_products.isNotEmpty) {
      for (final p in _products) {
        final cat = p['category']?.toString() ?? p['name']?.toString() ?? '';
        if (WaterTypes.byName(cat).shortName.toLowerCase() ==
            prefInfo.shortName.toLowerCase()) {
          hasMatchingProduct = true;
          break;
        }
      }
    } else if (_waterType != null) {
      if (WaterTypes.byName(_waterType).shortName.toLowerCase() ==
          prefInfo.shortName.toLowerCase()) {
        hasMatchingProduct = true;
      }
    }

    if (hasMatchingProduct) {
      return const SizedBox.shrink();
    }

    final stationTypeName = _waterType != null
        ? WaterTypes.byName(_waterType).name
        : 'Purified Water';

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF0D9488).withValues(alpha: 0.12)
            : const Color(0xFFF0FDFA),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark
              ? const Color(0xFF0D9488).withValues(alpha: 0.35)
              : const Color(0xFF99F6E4),
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1.5),
            child: Icon(
              Icons.info_outline_rounded,
              size: 16,
              color: isDark ? const Color(0xFF2DD4BF) : const Color(0xFF0D9488),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Your water preference is ${prefInfo.name}. This station currently provides $stationTypeName refills.',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppUi.textPrimaryOf(context),
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRefillProductsSection(BuildContext context) {
    final refillProducts = _products
        .where((p) => !_isContainerOrAccessory(Map<String, dynamic>.from(p)))
        .toList();
    final accessoryProducts = _products
        .where((p) => _isContainerOrAccessory(Map<String, dynamic>.from(p)))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Available Water Refills',
              style: TextStyle(
                fontSize: 16.5,
                fontWeight: FontWeight.w900,
                color: AppUi.textPrimaryOf(context),
                letterSpacing: -0.3,
              ),
            ),
            if (refillProducts.length > 1)
              Text(
                '${refillProducts.length} options',
                style: TextStyle(
                  fontSize: 12,
                  color: AppUi.textSecondaryOf(context),
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        _buildPreferenceNotice(),
        if (_isLoadingPurified && _products.isEmpty)
          Column(
            children: List.generate(
              2,
              (index) => const Padding(
                padding: EdgeInsets.only(bottom: 10),
                child: Skeleton(height: 72, borderRadius: 16),
              ),
            ),
          )
        else if (refillProducts.isNotEmpty)
          ...refillProducts.map((p) {
            final pMap = OrderProductHelpers.withDisplayDefaults(
              Map<String, dynamic>.from(p),
            );
            final isSelected =
                _selectedProduct?['id']?.toString() == pMap['id']?.toString();
            return _buildProductCard(
              pMap,
              isSelected: isSelected,
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _selectedProduct = pMap);
              },
            );
          })
        else
          _buildProductCard(
            _displayProduct,
            isSelected: true,
            onTap: () {},
          ),

        if (accessoryProducts.isNotEmpty) ...[
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Containers & Accessories',
                style: TextStyle(
                  fontSize: 16.5,
                  fontWeight: FontWeight.w900,
                  color: AppUi.textPrimaryOf(context),
                  letterSpacing: -0.3,
                ),
              ),
              Text(
                '${accessoryProducts.length} items',
                style: TextStyle(
                  fontSize: 12,
                  color: AppUi.textSecondaryOf(context),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Containers, caps, and replacement accessories',
            style: TextStyle(
              fontSize: 12,
              color: AppUi.textSecondaryOf(context),
            ),
          ),
          const SizedBox(height: 12),
          ...accessoryProducts.map((p) {
            final pMap = OrderProductHelpers.withDisplayDefaults(
              Map<String, dynamic>.from(p),
            );
            final isSelected =
                _selectedProduct?['id']?.toString() == pMap['id']?.toString();
            return _buildProductCard(
              pMap,
              isSelected: isSelected,
              isAccessory: true,
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _selectedProduct = pMap);
              },
            );
          }),
        ],
      ],
    );
  }

  Widget _buildProductCard(
    Map<String, dynamic> product, {
    required bool isSelected,
    required VoidCallback onTap,
    bool isAccessory = false,
  }) {
    final category = product['category']?.toString() ?? product['name']?.toString() ?? '';
    final waterType = WaterTypes.byName(category);
    final price = (product['price'] as num?)?.toDouble();
    final containerSize = product['container_size']?.toString() ?? (isAccessory ? 'Piece' : '5-Gallon');
    final prepMinutes = (product['preparation_minutes'] as num?)?.toInt() ?? 15;
    final isAvailable = product['is_available'] != false;
    final customerPref = _getCustomerWaterPreference();
    final isCustomerPreferred = !isAccessory &&
        customerPref != null &&
        customerPref.trim().isNotEmpty &&
        WaterTypes.byName(customerPref).shortName.toLowerCase() ==
            waterType.shortName.toLowerCase();

    final cart = context.watch<CartProvider>();
    final targetStationId = _stationData['id']?.toString();
    final pId = product['id']?.toString() ?? '';
    final isThisStation = cart.stationId == targetStationId;
    final inCartQty = isThisStation ? (cart.items[pId]?.quantity ?? 0) : 0;

    Color badgeBg;
    Color iconColor;
    IconData cardIcon;
    if (isAccessory) {
      badgeBg = const Color(0xFFFFFBEB);
      iconColor = const Color(0xFFD97706);
      cardIcon = Icons.inventory_2_outlined;
    } else if (category.toLowerCase().contains('alkaline')) {
      badgeBg = const Color(0xFFF3E8FF);
      iconColor = const Color(0xFF8B5CF6);
      cardIcon = Icons.water_drop_rounded;
    } else if (category.toLowerCase().contains('mineral')) {
      badgeBg = const Color(0xFFE6FFFA);
      iconColor = const Color(0xFF0D9488);
      cardIcon = Icons.water_drop_rounded;
    } else {
      badgeBg = AppUi.blueSoft;
      iconColor = AppUi.bluePrimary;
      cardIcon = Icons.water_drop_rounded;
    }

    return Opacity(
      opacity: isAvailable ? 1.0 : 0.5,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: isAvailable ? onTap : null,
            borderRadius: BorderRadius.circular(16),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppUi.bluePrimary.withValues(alpha: 0.04)
                    : AppUi.surfaceOf(context),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isSelected ? AppUi.bluePrimary : AppUi.borderOf(context),
                  width: isSelected ? 1.4 : 1.0,
                ),
                boxShadow: [
                  BoxShadow(
                    color: isSelected
                        ? AppUi.bluePrimary.withValues(alpha: 0.08)
                        : Colors.black.withValues(alpha: 0.02),
                    blurRadius: isSelected ? 8 : 2,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  // Product icon container
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: badgeBg,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      cardIcon,
                      color: iconColor,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Name, container, prep
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                product['name']?.toString() ?? waterType.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14.5,
                                  color: isSelected
                                      ? AppUi.bluePrimary
                                      : AppUi.textPrimaryOf(context),
                                ),
                              ),
                            ),
                            if (isCustomerPreferred) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 1.5,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0D9488).withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: const Color(0xFF0D9488).withValues(alpha: 0.3),
                                    width: 0.8,
                                  ),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.star_rounded,
                                      size: 11,
                                      color: Color(0xFF0D9488),
                                    ),
                                    SizedBox(width: 2.5),
                                    Text(
                                      'Your pick',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF0D9488),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            if (isSelected) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.all(2),
                                decoration: const BoxDecoration(
                                  color: AppUi.bluePrimary,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.check,
                                  size: 10,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1.5,
                              ),
                              decoration: BoxDecoration(
                                color: AppUi.surfaceRaisedOf(context),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                containerSize,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: AppUi.textSecondaryOf(context),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                isAccessory
                                    ? ((product['description']?.toString().isNotEmpty ?? false)
                                        ? product['description'].toString()
                                        : 'Standard item')
                                    : '• ~$prepMinutes min prep',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: AppUi.textSecondaryOf(context),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(width: 10),

                  // Price display & In-line Cart Controls
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (price != null) ...[
                        Text(
                          '₱${price.toStringAsFixed(0)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                            color: AppUi.bluePrimary,
                            letterSpacing: -0.4,
                          ),
                        ),
                        Text(
                          isAccessory ? '/ piece' : '/ refill',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                            color: AppUi.textSecondaryOf(context),
                          ),
                        ),
                        const SizedBox(height: 6),
                      ],
                      if (inCartQty > 0)
                        Container(
                          height: 30,
                          decoration: BoxDecoration(
                            color: AppUi.blueSoft,
                            borderRadius: BorderRadius.circular(15),
                            border: Border.all(
                              color: AppUi.bluePrimary.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              InkWell(
                                onTap: () => _removeItemFromCart(pId),
                                borderRadius: const BorderRadius.horizontal(left: Radius.circular(15)),
                                child: const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                                  child: Icon(Icons.remove_rounded, size: 14, color: AppUi.bluePrimary),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 3),
                                child: Text(
                                  '$inCartQty',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: AppUi.bluePrimary,
                                  ),
                                ),
                              ),
                              InkWell(
                                onTap: () => _addItemToCart(product, qty: 1),
                                borderRadius: const BorderRadius.horizontal(right: Radius.circular(15)),
                                child: const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                                  child: Icon(Icons.add_rounded, size: 14, color: AppUi.bluePrimary),
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        InkWell(
                          onTap: isAvailable ? () => _addItemToCart(product, qty: 1) : null,
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                            decoration: BoxDecoration(
                              color: isAvailable
                                  ? AppUi.bluePrimary.withValues(alpha: 0.1)
                                  : AppUi.borderOf(context),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.add_shopping_cart_rounded,
                                  size: 13,
                                  color: isAvailable ? AppUi.bluePrimary : AppUi.textSecondaryOf(context),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Add',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: isAvailable ? AppUi.bluePrimary : AppUi.textSecondaryOf(context),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReviewsSection(
    BuildContext context,
    double rating,
    int reviewCount,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Customer Ratings & Reviews',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: AppUi.textPrimaryOf(context),
                letterSpacing: -0.3,
              ),
            ),
            if (reviewCount > 0)
              Text(
                '$reviewCount verified',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppUi.textSecondaryOf(context),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        _buildRatingSummary(
          rating: rating,
          reviewCount: reviewCount,
        ),
        if (_reviews.isNotEmpty) ...[
          const SizedBox(height: 14),
          _buildCustomerReviewsList(context),
        ],
      ],
    );
  }

  Widget _buildCustomerReviewsList(BuildContext context) {
    final displayedReviews = _reviews.take(5).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...displayedReviews.map((review) => _buildReviewCard(context, review)),
      ],
    );
  }

  Widget _buildReviewCard(BuildContext context, dynamic review) {
    final rMap = review is Map ? review : <String, dynamic>{};
    final rating = (rMap['rating'] as num?)?.toInt() ?? 5;
    final comment = rMap['comment']?.toString().trim();
    final createdAtRaw = rMap['created_at']?.toString();
    final profile = rMap['profiles'] is Map ? rMap['profiles'] as Map : null;
    final customerName = profile?['full_name']?.toString().trim().isNotEmpty == true
        ? profile!['full_name'].toString().trim()
        : 'Verified Customer';
    final avatarUrl = profile?['avatar_url']?.toString();

    String formattedDate = '';
    if (createdAtRaw != null && createdAtRaw.isNotEmpty) {
      final dt = DateTime.tryParse(createdAtRaw)?.toLocal();
      if (dt != null) {
        final diff = DateTime.now().difference(dt);
        if (diff.inDays == 0) {
          formattedDate = 'Today';
        } else if (diff.inDays == 1) {
          formattedDate = 'Yesterday';
        } else if (diff.inDays < 30) {
          formattedDate = '${diff.inDays}d ago';
        } else {
          formattedDate = '${dt.month}/${dt.day}/${dt.year}';
        }
      }
    }

    final initial = customerName.isNotEmpty ? customerName[0].toUpperCase() : 'C';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppUi.surfaceOf(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppUi.borderOf(context).withValues(alpha: 0.8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: const BoxDecoration(
                  color: AppUi.blueSoft,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                clipBehavior: Clip.antiAlias,
                child: (avatarUrl != null && avatarUrl.isNotEmpty)
                    ? AppCachedImage(
                        imageUrl: avatarUrl,
                        width: 32,
                        height: 32,
                        fit: BoxFit.cover,
                        fallbackIcon: Icons.person_rounded,
                      )
                    : Text(
                        initial,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: AppUi.bluePrimary,
                        ),
                      ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      customerName,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppUi.textPrimaryOf(context),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Row(
                          children: List.generate(5, (starIdx) {
                            return Icon(
                              starIdx < rating
                                  ? Icons.star_rounded
                                  : Icons.star_outline_rounded,
                              size: 13,
                              color: const Color(0xFFFFC107),
                            );
                          }),
                        ),
                        if (formattedDate.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Text(
                            '· $formattedDate',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppUi.textSecondaryOf(context),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFECFDF5),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.check_circle_rounded,
                      size: 11,
                      color: Color(0xFF059669),
                    ),
                    SizedBox(width: 3),
                    Text(
                      'Verified',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF059669),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (comment != null && comment.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              comment,
              style: TextStyle(
                fontSize: 13,
                color: AppUi.textPrimaryOf(context),
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRatingSummary({
    required double rating,
    required int reviewCount,
  }) {
    // If station has no reviews, show an honest, subtle empty review state
    if (reviewCount <= 0 || rating <= 0) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        decoration: BoxDecoration(
          color: AppUi.surfaceOf(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppUi.borderOf(context)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                color: Color(0xFFFEF3C7),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.star_outline_rounded,
                color: Color(0xFFD97706),
                size: 24,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'No reviews yet',
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w800,
                color: AppUi.textPrimaryOf(context),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Be the first to review this station after your water delivery.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: AppUi.textSecondaryOf(context),
              ),
            ),
          ],
        ),
      );
    }

    // When real reviews exist:
    final hasDistribution = _ratingCounts.any((c) => c > 0);
    final maxRatingCount = hasDistribution
        ? _ratingCounts.reduce((a, b) => a > b ? a : b)
        : 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppUi.surfaceOf(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppUi.borderOf(context)),
      ),
      child: Row(
        children: [
          // Left: Score & Stars
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    rating.toStringAsFixed(1),
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -1,
                      height: 1,
                      color: AppUi.textPrimaryOf(context),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '/ 5.0',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppUi.textSecondaryOf(context),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: List.generate(5, (index) {
                  final remaining = rating - index;
                  final icon = remaining >= 1
                      ? Icons.star_rounded
                      : remaining >= 0.25
                          ? Icons.star_half_rounded
                          : Icons.star_outline_rounded;
                  return Icon(icon, color: const Color(0xFFFFC107), size: 16);
                }),
              ),
              const SizedBox(height: 6),
              Text(
                '$reviewCount verified review${reviewCount == 1 ? '' : 's'}',
                style: TextStyle(
                  color: AppUi.textSecondaryOf(context),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          if (hasDistribution && maxRatingCount > 0) ...[
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                children: [
                  for (var stars = 5; stars >= 1; stars--)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          Text(
                            '$stars',
                            style: TextStyle(
                              color: AppUi.textSecondaryOf(context),
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(99),
                              child: LinearProgressIndicator(
                                value: _ratingCounts[stars - 1] / maxRatingCount,
                                minHeight: 5,
                                backgroundColor: AppUi.borderOf(context),
                                color: const Color(0xFFFFC107),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ─── MAIN BUILD ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final station = _stationData;
    final stationName = station['station_name']?.toString() ?? 'Water Station';
    final rawComplete = station['complete_address']?.toString().trim() ?? '';
    final rawBarangay = station['barangay']?.toString().trim() ?? '';
    final rawTown = station['town']?.toString().trim() ?? '';

    String completeAddress;
    if (rawComplete.isNotEmpty) {
      completeAddress = rawComplete;
      if (rawTown.isNotEmpty &&
          !completeAddress.toLowerCase().contains(rawTown.toLowerCase())) {
        completeAddress = '$completeAddress, $rawTown';
      }
    } else {
      final parts = [rawBarangay, rawTown].where((s) => s.isNotEmpty).toList();
      completeAddress =
          parts.isNotEmpty ? parts.join(', ') : 'Location not specified';
    }

    final reviewCount = _reviews.isNotEmpty
        ? _reviews.length
        : ((station['review_count'] as num?)?.toInt() ?? 0);
    final rating = _reviews.isNotEmpty
        ? (_reviews.fold<double>(
                0.0,
                (acc, r) =>
                    acc +
                    ((r is Map ? r['rating'] : null) as num? ?? 0.0).toDouble(),
              ) /
            _reviews.length)
        : ((station['average_rating'] as num?)?.toDouble() ?? 0.0);
    final isVerified =
        station['is_verified'] == true || station['verified'] == true;
    final photoUrl = station['station_photo_url'] as String?;
    final photo =
        (photoUrl == null || photoUrl.isEmpty) ? _sampleStationImage : photoUrl;

    final isOpen = (station['is_open'] as bool?) ?? true;
    final availability =
        station['station_availability']?.toString() ??
        (isOpen ? 'open' : 'closed');
    final normalizedAvailability = availability.toLowerCase();
    final canOrder =
        isOpen &&
        !{'busy', 'maintenance', 'closed'}.contains(normalizedAvailability);

    final selectedProduct = _selectedProduct ?? _displayProduct;
    final unitPrice = (selectedProduct['price'] as num?)?.toDouble() ??
        _pricePerGallon ??
        25.0;
    final subtotal = unitPrice * _quantity;

    return Scaffold(
      backgroundColor: AppUi.pageBgOf(context),
      body: CustomScrollView(
        physics: const ClampingScrollPhysics(),
        slivers: [
          // ── Collapsible Hero AppBar ──────────────────────────────────────
          SliverAppBar(
            expandedHeight: 220,
            pinned: true,
            stretch: false,
            backgroundColor: AppUi.surfaceOf(context),
            elevation: 0,
            leading: Padding(
              padding: const EdgeInsets.all(8.0),
              child: GestureDetector(
                onTap: () => Navigator.of(context).maybePop(),
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: AppUi.surfaceOf(context).withValues(alpha: 0.9),
                    shape: BoxShape.circle,
                    border: Border.all(color: AppUi.borderOf(context)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.arrow_back_rounded,
                    size: 19,
                    color: AppUi.textPrimaryOf(context),
                  ),
                ),
              ),
            ),
            actions: [
              Consumer<CartProvider>(
                builder: (context, cart, _) {
                  final hasItems = cart.items.isNotEmpty;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        GestureDetector(
                          onTap: () => context.openCart(_stationData),
                          child: Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: AppUi.surfaceOf(context).withValues(alpha: 0.9),
                              shape: BoxShape.circle,
                              border: Border.all(color: AppUi.borderOf(context)),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.06),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Icon(
                              Icons.shopping_cart_outlined,
                              size: 19,
                              color: hasItems ? AppUi.bluePrimary : AppUi.textPrimaryOf(context),
                            ),
                          ),
                        ),
                        if (hasItems)
                          Positioned(
                            top: -2,
                            right: -2,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                color: Color(0xFFEF4444),
                                shape: BoxShape.circle,
                              ),
                              constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                              alignment: Alignment.center,
                              child: Text(
                                '${cart.totalItems}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
              Padding(
                padding: const EdgeInsets.only(right: 12.0),
                child: GestureDetector(
                  onTap: _toggleFav,
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: AppUi.surfaceOf(context).withValues(alpha: 0.9),
                      shape: BoxShape.circle,
                      border: Border.all(color: AppUi.borderOf(context)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.06),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Icon(
                      _isFav
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                      size: 19,
                      color: _isFav
                          ? Colors.redAccent
                          : AppUi.textPrimaryOf(context),
                    ),
                  ),
                ),
              ),
            ],
            flexibleSpace: LayoutBuilder(
              builder: (ctx, constraints) {
                final topPadding = MediaQuery.of(ctx).padding.top;
                final isCollapsed = constraints.biggest.height <=
                    (topPadding + kToolbarHeight + 10);

                return FlexibleSpaceBar(
                  centerTitle: true,
                  title: AnimatedOpacity(
                    duration: const Duration(milliseconds: 180),
                    opacity: isCollapsed ? 1.0 : 0.0,
                    child: Text(
                      stationName,
                      style: TextStyle(
                        color: AppUi.textPrimaryOf(context),
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                      Container(color: Colors.white),
                      Hero(
                        tag: 'station_image_${station['id'] ?? stationName}',
                        child: AppCachedImage(
                          imageUrl: photo,
                          width: double.infinity,
                          height: double.infinity,
                          fit: BoxFit.contain,
                          memCacheWidth: 800,
                          memCacheHeight: 500,
                          fallbackIcon: Icons.water_drop_rounded,
                        ),
                      ),
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        height: 70,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.black.withValues(alpha: 0.12),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),

          // ── Main Content Body ────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. Station Name & Verified
                  _buildStationHeader(context, stationName, isVerified),
                  const SizedBox(height: 8),

                  // 2. Metadata Status Row
                  _buildStationMetaRow(
                    context,
                    isOpen,
                    rawTown,
                    rating,
                    reviewCount,
                  ),
                  const SizedBox(height: 10),

                  // 3. Dedicated Address Row
                  _buildAddressRow(context, completeAddress),
                  const SizedBox(height: 16),

                  // 4. Quick Actions
                  _buildQuickActions(context),
                  const SizedBox(height: 14),

                  // 5. Water Quality & Benefits
                  _buildBenefitsSection(context),
                  const SizedBox(height: 14),

                  // 6. Automated Refill Routine Card
                  _buildAutoRefillCard(context),
                  const SizedBox(height: 20),

                  // 7. Available Water Refills Section
                  _buildRefillProductsSection(context),
                  const SizedBox(height: 20),

                  // 8. Customer Ratings & Reviews
                  _buildReviewsSection(context, rating, reviewCount),
                  const SizedBox(height: 100),
                ],
              ),
            ),
          ),
        ],
      ),

      // ── Sticky Bottom Action Bar ─────────────────────────────────────────
      bottomNavigationBar: Consumer<CartProvider>(
        builder: (context, cart, _) {
          final isThisStation =
              cart.stationId == _stationData['id']?.toString();
          final hasItemsInCart = isThisStation && cart.totalItems > 0;

          return Container(
            decoration: BoxDecoration(
              color: AppUi.surfaceOf(context),
              border: Border(
                top: BorderSide(
                  color: AppUi.dividerOf(context).withValues(alpha: 0.7),
                ),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, -3),
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (hasItemsInCart)
                    Container(
                      margin: const EdgeInsets.fromLTRB(16, 10, 16, 2),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color: AppUi.bluePrimary,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: AppUi.bluePrimary.withValues(alpha: 0.25),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.shopping_bag_outlined,
                            color: Colors.white,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${cart.totalItems} ${cart.totalItems == 1 ? "item" : "items"} in cart · ₱${cart.totalAmount.toStringAsFixed(0)}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          InkWell(
                            onTap: () => context.openCart(_stationData),
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'View Cart',
                                    style: TextStyle(
                                      color: AppUi.bluePrimary,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 12,
                                    ),
                                  ),
                                  SizedBox(width: 2),
                                  Icon(
                                    Icons.chevron_right_rounded,
                                    size: 14,
                                    color: AppUi.bluePrimary,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                    child: Row(
                      children: [
                        // Quantity Stepper Capsule
                        Container(
                          height: 48,
                          decoration: BoxDecoration(
                            color: AppUi.pageBgOf(context),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: AppUi.borderOf(context)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                onPressed: _quantity > 1
                                    ? () {
                                        HapticFeedback.lightImpact();
                                        _setQuantity(_quantity - 1);
                                      }
                                    : null,
                                icon: const Icon(Icons.remove_rounded, size: 18),
                                color: AppUi.textPrimaryOf(context),
                                padding: const EdgeInsets.symmetric(horizontal: 10),
                                constraints: const BoxConstraints(
                                  minWidth: 36,
                                  minHeight: 48,
                                ),
                              ),
                              GestureDetector(
                                onTap: _editQuantity,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 4),
                                  child: Text(
                                    '$_quantity',
                                    style: TextStyle(
                                      color: AppUi.textPrimaryOf(context),
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ),
                              IconButton(
                                onPressed: () {
                                  HapticFeedback.lightImpact();
                                  _setQuantity(_quantity + 1);
                                },
                                icon: const Icon(Icons.add_rounded, size: 18),
                                color: AppUi.textPrimaryOf(context),
                                padding: const EdgeInsets.symmetric(horizontal: 10),
                                constraints: const BoxConstraints(
                                  minWidth: 36,
                                  minHeight: 48,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),

                        // Order Action CTA Button
                        Expanded(
                          child: SizedBox(
                            height: 48,
                            child: FilledButton(
                              onPressed: () => _handleOrderNow(
                                canOrder: canOrder,
                                normalizedAvailability: normalizedAvailability,
                              ),
                              style: FilledButton.styleFrom(
                                backgroundColor: canOrder
                                    ? AppUi.bluePrimary
                                    : AppUi.textMuted,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(24),
                                ),
                                elevation: 0,
                              ),
                              child: _isPlacingOrder
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2.2,
                                      ),
                                    )
                                  : Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          canOrder
                                              ? (hasItemsInCart
                                                  ? 'Add to Cart · ₱${subtotal.toStringAsFixed(0)}'
                                                  : 'Order ($_quantity) · ₱${subtotal.toStringAsFixed(0)}')
                                              : (isOpen
                                                  ? 'Station Busy'
                                                  : 'Station Closed'),
                                          style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: -0.2,
                                          ),
                                        ),
                                        if (canOrder) ...[
                                          const SizedBox(width: 6),
                                          const Icon(
                                            Icons.arrow_forward_rounded,
                                            size: 17,
                                          ),
                                        ],
                                      ],
                                    ),
                            ),
                          ),
                        ),
                      ],
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
}

class _QuantityInputDialog extends StatefulWidget {
  final int initialQuantity;

  const _QuantityInputDialog({required this.initialQuantity});

  @override
  State<_QuantityInputDialog> createState() => _QuantityInputDialogState();
}

class _QuantityInputDialogState extends State<_QuantityInputDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.initialQuantity.toString(),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _applyQuantity() {
    final quantity = int.tryParse(_controller.text);
    if (quantity != null && quantity > 0) {
      Navigator.pop(context, quantity);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppUi.surfaceOf(context),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text(
        'Enter quantity',
        style: TextStyle(fontWeight: FontWeight.w800),
      ),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        textInputAction: TextInputAction.done,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: const InputDecoration(
          labelText: 'Number of refills',
          border: OutlineInputBorder(),
        ),
        onSubmitted: (_) => _applyQuantity(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _applyQuantity,
          style: FilledButton.styleFrom(
            backgroundColor: AppUi.bluePrimary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: const Text('Apply'),
        ),
      ],
    );
  }
}
