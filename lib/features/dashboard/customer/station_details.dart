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
import '../../../core/utils/order_product_helpers.dart';
import '../../../core/utils/station_price_helpers.dart';
import '../../../core/water_types.dart';
import '../../../core/widgets/app_cached_image.dart';
import '../../../core/widgets/auth_dialogs.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../models/cart_model.dart';
import '../../chat/models/chat_room.dart';
import '../../chat/services/chat_service.dart';
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
  double? _baseDeliveryFee;
  String? _waterType;
  bool _isFav = false;
  bool _isPlacingOrder = false;

  StreamSubscription<String>? _cacheSub;

  // Real-time refill options configured by this station.
  List<dynamic> _products = [];
  List<int> _ratingCounts = List.filled(5, 0);
  bool _isLoadingPurified = true;
  Map<String, dynamic>? _selectedProduct;
  final Map<String, int> _productQuantities = {};

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
      _pricePerGallon = cached.pricePerGallon;
      _baseDeliveryFee = cached.baseDeliveryFee;
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
      _baseDeliveryFee =
          (_stationData['base_delivery_fee'] as num?)?.toDouble() ?? 25.0;
      if (ownerId != null) _resolveSelectedProduct(ownerId);
      // Immediately allow instant user interaction with display fallback product (0ms)
      _isLoadingPurified = false;
    }

    _checkIsFav();
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
    final defaultProduct = OrderProductHelpers.defaultFromList(
      _products,
      stationWaterType: _waterType,
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
      _baseDeliveryFee = bundle.baseDeliveryFee;
      _waterType = bundle.waterType;
      _ratingCounts = bundle.ratingCounts;
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
                              const Text(
                                'Schedule Auto-Refill',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
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

                  const Text(
                    'Water Type',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
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
                          const Text(
                            'Bottles per Delivery',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
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
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
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

                  const Text(
                    'Refill Routine Frequency',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
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

                  const Text(
                    'Preferred Delivery Time Slot',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
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

                  const Text(
                    'Delivery Address',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
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
                        const Text(
                          'Estimated Total / Refill:',
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
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

  Widget _buildAutoRefillBanner() {
    final stationName = _stationData['station_name']?.toString() ?? 'this station';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppUi.bluePrimary.withValues(alpha: 0.08),
            AppUi.bluePrimary.withValues(alpha: 0.16),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppUi.bluePrimary.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppUi.bluePrimary,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.autorenew_rounded,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Automated Refill Routine',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Never run out of water. Set a recurring schedule with $stationName.',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppUi.textSecondaryOf(context),
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: _scheduleAutoRefill,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppUi.bluePrimary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              'Set Up',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
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
      settingsPrice:
          _pricePerGallon ??
          (_stationData['price_per_gallon'] as num?)?.toDouble(),
    );
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
        if (!mounted || !context.mounted) return;
        if (replace != true) {
          setState(() => _isPlacingOrder = false);
          return;
        }
      }

      HapticFeedback.mediumImpact();
      cart.clearCart();
      cart.setStation(
        targetStationId,
        _stationData['station_name']?.toString() ?? 'Water Station',
      );

      bool addedFromList = false;
      for (final prod in _products) {
        final pId = prod['id']?.toString() ?? '';
        final pQty = _productQuantities[pId] ?? 0;
        if (pQty > 0) {
          final pName = prod['name']?.toString() ?? 'Water Refill';
          final pPrice = (prod['price'] as num?)?.toDouble() ?? 25.0;
          cart.addItem(pId, pName, pPrice);
          cart.updateQuantity(pId, pQty);
          addedFromList = true;
        }
      }

      if (!addedFromList) {
        final itemId = orderProduct['id'].toString();
        final itemName = orderProduct['name']?.toString() ?? 'Water Refill';
        final itemPrice = (orderProduct['price'] as num?)?.toDouble() ??
            (_stationData['price_per_gallon'] as num?)?.toDouble() ??
            25.0;

        cart.addItem(itemId, itemName, itemPrice);
        cart.updateQuantity(itemId, _quantity);
      }

      if (!mounted || !context.mounted) return;
      context.openCheckout(_stationData);
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

  Widget _buildProductCard(
    Map<String, dynamic> product, {
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final category = product['category']?.toString() ?? product['name']?.toString() ?? '';
    final waterType = WaterTypes.byName(category);
    final price = (product['price'] as num?)?.toDouble();
    final containerSize = product['container_size']?.toString() ?? '5-Gallon';
    final prepMinutes = (product['preparation_minutes'] as num?)?.toInt() ?? 15;

    // Distinct theme accents per water category
    Color badgeColor;
    Color iconColor;
    if (category.toLowerCase().contains('alkaline')) {
      badgeColor = const Color(0xFFF3E8FF);
      iconColor = const Color(0xFF8B5CF6);
    } else if (category.toLowerCase().contains('mineral')) {
      badgeColor = const Color(0xFFE6FFFA);
      iconColor = const Color(0xFF0D9488);
    } else {
      badgeColor = AppUi.bluePale;
      iconColor = AppUi.bluePrimary;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isSelected
                  ? AppUi.bluePrimary.withValues(alpha: 0.04)
                  : AppUi.surfaceOf(context),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: isSelected ? AppUi.bluePrimary : AppUi.borderOf(context),
                width: isSelected ? 1.8 : 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: isSelected
                      ? AppUi.bluePrimary.withValues(alpha: 0.1)
                      : Colors.black.withValues(alpha: 0.02),
                  blurRadius: isSelected ? 12 : 4,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              children: [
                // Product icon container
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: badgeColor,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    Icons.water_drop_rounded,
                    color: iconColor,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 14),

                // Name, category, container specs
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
                                fontSize: 15,
                                color: isSelected
                                    ? AppUi.bluePrimary
                                    : AppUi.textPrimaryOf(context),
                              ),
                            ),
                          ),
                          if (isSelected) ...[
                            const SizedBox(width: 6),
                            const Icon(
                              Icons.check_circle_rounded,
                              size: 16,
                              color: AppUi.bluePrimary,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
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
                          Text(
                            '•  ~$prepMinutes min prep',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: AppUi.textSecondaryOf(context),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Price display
                if (price != null) ...[
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '₱${price.toStringAsFixed(0)}',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                          color: AppUi.bluePrimary,
                          letterSpacing: -0.5,
                        ),
                      ),
                      Text(
                        '/ refill',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w500,
                          color: AppUi.textSecondaryOf(context),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
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
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: AppUi.surfaceRaisedOf(context),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppUi.borderOf(context)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 20, color: AppUi.bluePrimary),
                const SizedBox(height: 4),
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

  Widget _buildTrustChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppUi.surfaceRaisedOf(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppUi.borderOf(context).withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppUi.bluePrimary),
          const SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: AppUi.textSecondaryOf(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRatingSummary({
    required double rating,
    required int reviewCount,
  }) {
    final maxRatingCount = _ratingCounts.isEmpty
        ? 0
        : _ratingCounts.reduce((a, b) => a > b ? a : b);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppUi.surfaceOf(context),
        borderRadius: BorderRadius.circular(18),
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
                    rating > 0 ? rating.toStringAsFixed(1) : 'New',
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -1,
                      height: 1,
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
                  return Icon(icon, color: const Color(0xFFFFC107), size: 18);
                }),
              ),
              const SizedBox(height: 6),
              Text(
                reviewCount > 0
                    ? '$reviewCount verified reviews'
                    : 'No customer reviews yet',
                style: TextStyle(
                  color: AppUi.textSecondaryOf(context),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(width: 20),

          // Right: Compact rating bars
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
                              value: maxRatingCount == 0
                                  ? 0
                                  : _ratingCounts[stars - 1] / maxRatingCount,
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
      ),
    );
  }

  // ─── BUILD ─────────────────────────────────────────────────────────────────

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

    final rating = (station['average_rating'] as num?)?.toDouble() ?? 0;
    final reviewCount = (station['review_count'] as num?)?.toInt() ?? 0;
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
    final isDark = AppUi.isDark(context);

    // Dynamic Subtotal calculation for bottom CTA
    final selectedProduct = _selectedProduct ?? _displayProduct;
    final unitPrice = (selectedProduct['price'] as num?)?.toDouble() ??
        _pricePerGallon ??
        25.0;
    final subtotal = unitPrice * _quantity;

    return Scaffold(
      backgroundColor: AppUi.pageBgOf(context),
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        slivers: [
          // ── Collapsible Hero AppBar ──────────────────────────────────────
          SliverAppBar(
            expandedHeight: 250,
            pinned: true,
            stretch: true,
            backgroundColor: AppUi.surfaceOf(context),
            leading: Padding(
              padding: const EdgeInsets.all(8.0),
              child: CircleAvatar(
                backgroundColor: isDark
                    ? Colors.black.withValues(alpha: 0.6)
                    : Colors.white.withValues(alpha: 0.85),
                child: IconButton(
                  icon: Icon(
                    Icons.arrow_back_ios_new_rounded,
                    size: 18,
                    color: AppUi.textPrimaryOf(context),
                  ),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ),
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 12.0),
                child: CircleAvatar(
                  backgroundColor: isDark
                      ? Colors.black.withValues(alpha: 0.6)
                      : Colors.white.withValues(alpha: 0.85),
                  child: IconButton(
                    icon: Icon(
                      _isFav
                          ? Icons.favorite_rounded
                          : Icons.favorite_outline_rounded,
                      size: 20,
                      color: _isFav
                          ? Colors.redAccent
                          : AppUi.textPrimaryOf(context),
                    ),
                    onPressed: _toggleFav,
                  ),
                ),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  Hero(
                    tag: 'station_image_${station['id'] ?? stationName}',
                    child: AppCachedImage(
                      imageUrl: photo,
                      width: double.infinity,
                      height: double.infinity,
                      fit: BoxFit.cover,
                      memCacheWidth: 800,
                      memCacheHeight: 500,
                      fallbackIcon: Icons.water_drop_rounded,
                    ),
                  ),
                  // Dark gradient at bottom for smooth contrast
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.35),
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.55),
                        ],
                        stops: const [0.0, 0.4, 1.0],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Main Content Body ────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Station Name & Verified Badge
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          stationName,
                          style: TextStyle(
                            color: AppUi.textPrimaryOf(context),
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(
                        Icons.verified_rounded,
                        color: AppUi.bluePrimary,
                        size: 22,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Metadata Badges Row (Open/Closed, Rating, Town, Delivery)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      // Open / Closed Status Pill
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: isOpen
                              ? (isDark
                                  ? const Color(0xFF163828)
                                  : const Color(0xFFEAF7F0))
                              : (isDark
                                  ? const Color(0xFF381616)
                                  : const Color(0xFFFDE8E8)),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                color: isOpen
                                    ? const Color(0xFF10B981)
                                    : const Color(0xFFEF4444),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              isOpen ? 'Open Now' : 'Closed',
                              style: TextStyle(
                                color: isOpen
                                    ? (isDark
                                        ? const Color(0xFF6EE7B7)
                                        : const Color(0xFF047857))
                                    : (isDark
                                        ? const Color(0xFFFCA5A5)
                                        : const Color(0xFFB91C1C)),
                                fontWeight: FontWeight.w700,
                                fontSize: 11.5,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Rating Pill
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF3C7),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.star_rounded,
                              size: 14,
                              color: Color(0xFFD97706),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              rating > 0
                                  ? '${rating.toStringAsFixed(1)} ($reviewCount)'
                                  : 'New',
                              style: const TextStyle(
                                color: Color(0xFFB45309),
                                fontWeight: FontWeight.w800,
                                fontSize: 11.5,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Municipality Pill
                      if (rawTown.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppUi.surfaceRaisedOf(context),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppUi.borderOf(context)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.location_on_rounded,
                                size: 13,
                                color: AppUi.textSecondaryOf(context),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                rawTown,
                                style: TextStyle(
                                  color: AppUi.textSecondaryOf(context),
                                  fontWeight: FontWeight.w600,
                                  fontSize: 11.5,
                                ),
                              ),
                            ],
                          ),
                        ),

                      // Delivery Fee Pill
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppUi.bluePale,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.delivery_dining_rounded,
                              size: 14,
                              color: AppUi.bluePrimary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '₱${_baseDeliveryFee?.toStringAsFixed(0) ?? '25'} Delivery',
                              style: const TextStyle(
                                color: AppUi.bluePrimary,
                                fontWeight: FontWeight.w800,
                                fontSize: 11.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Complete Address with Location Pin
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Icon(
                          Icons.place_outlined,
                          size: 16,
                          color: AppUi.textSecondaryOf(context),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          completeAddress,
                          style: TextStyle(
                            color: AppUi.textSecondaryOf(context),
                            fontSize: 13.5,
                            height: 1.3,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),

                  // Quick Action Buttons Row (Call, Chat, Routine, Directions)
                  Row(
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
                  ),
                  const SizedBox(height: 18),

                  // Trust & Water Quality Badges
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildTrustChip(
                        Icons.shield_outlined,
                        'UV Sterilized',
                      ),
                      _buildTrustChip(
                        Icons.water_drop_outlined,
                        'Purity Tested',
                      ),
                      _buildTrustChip(
                        Icons.clean_hands_outlined,
                        'Free Sanitization',
                      ),
                      _buildTrustChip(
                        Icons.speed_rounded,
                        '~15m Fast Prep',
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),

                  // Auto-Refill Routine Discovery Banner
                  _buildAutoRefillBanner(),
                  const SizedBox(height: 24),

                  // Section Title: Refill Options
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Available Water Refills',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          color: AppUi.textPrimaryOf(context),
                          letterSpacing: -0.3,
                        ),
                      ),
                      if (_products.length > 1)
                        Text(
                          '${_products.length} options',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppUi.textSecondaryOf(context),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Product Cards List
                  if (_isLoadingPurified && _products.isEmpty)
                    Column(
                      children: List.generate(
                        2,
                        (index) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Skeleton(
                            height: 84,
                            borderRadius: 18,
                          ),
                        ),
                      ),
                    )
                  else if (_products.isNotEmpty)
                    ..._products.map((p) {
                      final pMap = OrderProductHelpers.withDisplayDefaults(
                        Map<String, dynamic>.from(p),
                      );
                      final isSelected =
                          _selectedProduct?['id']?.toString() ==
                          pMap['id']?.toString();
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
                  const SizedBox(height: 20),

                  // Customer Reviews & Rating Breakdown
                  Text(
                    'Customer Ratings & Reviews',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: AppUi.textPrimaryOf(context),
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _buildRatingSummary(
                    rating: rating,
                    reviewCount: reviewCount,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),

      // ── Sticky Bottom Action Bar ─────────────────────────────────────────
      bottomNavigationBar: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        decoration: BoxDecoration(
          color: AppUi.surfaceOf(context),
          border: Border(
            top: BorderSide(
              color: AppUi.borderOf(context).withValues(alpha: 0.8),
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, -3),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Row(
            children: [
              // Quantity Stepper Capsule
              Container(
                decoration: BoxDecoration(
                  color: AppUi.pageBgOf(context),
                  borderRadius: BorderRadius.circular(16),
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
                      icon: const Icon(Icons.remove_rounded, size: 20),
                      color: AppUi.textPrimaryOf(context),
                      constraints: const BoxConstraints(minWidth: 38, minHeight: 46),
                    ),
                    GestureDetector(
                      onTap: _editQuantity,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Text(
                          '$_quantity',
                          style: TextStyle(
                            color: AppUi.textPrimaryOf(context),
                            fontSize: 17,
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
                      icon: const Icon(Icons.add_rounded, size: 20),
                      color: AppUi.textPrimaryOf(context),
                      constraints: const BoxConstraints(minWidth: 38, minHeight: 46),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),

              // Order Action CTA Button with dynamic subtotal
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () => _handleOrderNow(
                      canOrder: canOrder,
                      normalizedAvailability: normalizedAvailability,
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          canOrder ? AppUi.bluePrimary : AppUi.textMuted,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: canOrder ? 2 : 0,
                      shadowColor: AppUi.bluePrimary.withValues(alpha: 0.3),
                    ),
                    child: _isPlacingOrder
                        ? const SizedBox(
                            width: 22,
                            height: 22,
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
                                    ? 'Order ($_quantity) · ₱${subtotal.toStringAsFixed(0)}'
                                    : (isOpen
                                        ? 'Station Busy'
                                        : 'Station Closed'),
                                style: const TextStyle(
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.2,
                                ),
                              ),
                              if (canOrder) ...[
                                const SizedBox(width: 6),
                                const Icon(
                                  Icons.arrow_forward_rounded,
                                  size: 18,
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
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: const Text('Apply'),
        ),
      ],
    );
  }
}
