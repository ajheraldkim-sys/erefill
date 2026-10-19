import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/utils/profile_query_helpers.dart';
import '../../../core/widgets/app_ui_kit.dart';
import '../../../core/constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/map_tiles.dart';
import '../../../core/widgets/brand/axo_states.dart';
import '../../../core/widgets/brand/refill_lottie.dart';
import 'widgets/payment_method_selector.dart';
import 'widgets/payment_brand_mark.dart';
import 'package:erefill/core/models/cart_model.dart';
import 'checkout_rules.dart';
import '../../../core/routing/app_navigation.dart';
import '../../../core/routing/app_routes.dart';
import '../../account/saved_addresses_screen.dart';
import '../../settings/customer/user_settings_service.dart';
import 'package:go_router/go_router.dart';
import '../../../core/widgets/app_form_fields.dart';
import '../../../core/services/offline_order_sync_service.dart';
import '../../../core/services/payment_launch_service.dart';
import '../../../core/services/local_data_cache.dart';
import '../../../core/utils/friendly_errors.dart';
import '../../loyalty/models/loyalty_model.dart';
import '../../loyalty/services/loyalty_service.dart';

class CheckoutScreen extends StatefulWidget {
  final Map<String, dynamic> station;

  const CheckoutScreen({super.key, required this.station});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final supabase = Supabase.instance.client;
  final _notesController = TextEditingController();
  final _deliverySectionKey = GlobalKey();

  bool _isBootstrapping = true;
  bool _isSubmitting = false;
  bool _isLoadingCheckoutConfiguration = false;
  bool _stationSettingsLoaded = false;
  bool _platformFeeConfigLoaded = false;
  bool _paymentMethodsLoaded = false;
  String? _orderAttemptFingerprint;
  String? _orderAttemptKey;
  String _paymentMethod = 'cod';
  List<CheckoutPaymentOption> _paymentMethods = [];
  Map<String, dynamic>? _customerProfile;
  List<Map<String, dynamic>> _savedAddresses = [];
  String? _selectedAddressId;
  double _deliveryFee = 20.0;
  double _deliveryDistanceKm = 1.0;
  double _deliveryRatePerKm = 10.0;
  double _deliveryMinFee = 20.0;
  double _deliveryMinDistance = 1.0;
  String _deliveryRoundingRule = 'exact';
  bool _deliveryFeeEnabled = true;
  Map<String, dynamic>? _deliveryFeeConfig;
  double? _stationLat;
  double? _stationLng;
  RealtimeChannel? _configRealtimeChannel;
  Map<String, dynamic>? _platformFeeConfig;
  String? _pricingSetupError;
  String? _paymentMethodsError;
  String? _checkoutHint;
  String? _stationAvailabilityMessage;
  bool _checkingStationAvailability = false;
  int _availabilityRequestId = 0;

  final LoyaltyService _loyaltyService = LoyaltyService();
  List<LoyaltyRewardVoucher> _availableVouchers = [];
  LoyaltyRewardVoucher? _appliedVoucher;

  String _containerOption = 'swap';
  bool _isFeeBreakdownExpanded = false;
  String? _stationOpeningTime;
  String? _stationClosingTime;
  List<String> _stationOperatingDays = [];
  bool _isOutsideHours = false;
  bool _scheduleForNextOpen = false;

  @override
  void initState() {
    super.initState();
    _stationLat =
        (widget.station['latitude'] as num?)?.toDouble() ??
        (widget.station['lat'] as num?)?.toDouble();
    _stationLng =
        (widget.station['longitude'] as num?)?.toDouble() ??
        (widget.station['lng'] as num?)?.toDouble();
    _setupConfigRealtimeChannel();
    _loadInitialData();
  }

  void _setupConfigRealtimeChannel() {
    try {
      _configRealtimeChannel = supabase
          .channel('public:checkout_system_config')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'system_config',
            callback: (payload) {
              final key = payload.newRecord['key'] ?? payload.oldRecord['key'];
              if (key == 'delivery_fee_config') {
                _loadStationSettings();
              } else if (key == 'platform_fee') {
                _loadPlatformFeeConfig();
              }
            },
          )
          .subscribe();
    } catch (e) {
      debugPrint('Realtime config channel subscription failed: $e');
    }
  }

  @override
  void dispose() {
    final channel = _configRealtimeChannel;
    if (channel != null) {
      supabase.removeChannel(channel);
    }
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    setState(() => _isBootstrapping = true);
    await Future.wait([
      _loadCustomerLocation(),
      _loadStationSettings(),
      _loadPaymentMethods(),
      _loadPlatformFeeConfig(),
      _loadLoyaltyVouchers(),
    ]);
    if (mounted) {
      setState(() {
        _isBootstrapping = false;
      });
      await _refreshStationAvailability();
    }
  }

  Future<void> _loadPaymentMethods() async {
    try {
      final ownerId = widget.station['id']?.toString();
      if (ownerId == null || ownerId.isEmpty) {
        throw StateError('Station ID is missing.');
      }
      final response = await supabase.rpc(
        'get_station_available_payment_methods',
        params: {'p_owner_id': ownerId},
      );

      final rows = response is List ? response : <dynamic>[];
      final options = CheckoutRules.normalizePaymentOptions(rows);
      final availableOptions = options
          .where((option) => option.available)
          .toList();

      final user = supabase.auth.currentUser;
      String? lastUsedMethod;
      if (user != null) {
        lastUsedMethod =
            LocalDataCache.instance.getMemory<String>(
              'last_used_payment_method_${user.id}',
            ) ??
            await LocalDataCache.instance.get<String>(
              'last_used_payment_method_${user.id}',
            );
      }

      if (!mounted) return;
      setState(() {
        _paymentMethods = options;
        _paymentMethodsLoaded = true;
        _paymentMethodsError = null;
        if (lastUsedMethod != null &&
            CheckoutRules.isPaymentAvailable(lastUsedMethod, options)) {
          _paymentMethod = lastUsedMethod;
        } else if (!CheckoutRules.isPaymentAvailable(_paymentMethod, options)) {
          _paymentMethod = availableOptions.isEmpty
              ? ''
              : availableOptions.first.type;
        }
      });
    } catch (e) {
      debugPrint('Error loading payment methods: $e');
      if (!mounted) return;
      setState(() {
        _paymentMethods = [];
        _paymentMethodsLoaded = false;
        _paymentMethodsError =
            'Station payment options could not be verified. Retry before placing your order.';
      });
    }
  }

  Future<void> _loadStationSettings() async {
    try {
      final ownerId = widget.station['id']?.toString();
      if (ownerId == null || ownerId.isEmpty) {
        throw StateError('Station ID is missing.');
      }

      // Ensure station coordinates are available
      if (_stationLat == null || _stationLng == null) {
        final stationProfile = await supabase
            .from('profiles')
            .select('latitude, longitude')
            .eq('id', ownerId)
            .maybeSingle();
        if (stationProfile != null) {
          _stationLat = (stationProfile['latitude'] as num?)?.toDouble();
          _stationLng = (stationProfile['longitude'] as num?)?.toDouble();
        }
      }

      final cfg = await supabase.rpc('get_delivery_fee_config');
      if (cfg is! Map) {
        throw StateError('Delivery fee configuration was invalid.');
      }

      if (mounted) {
        setState(() {
          _deliveryFeeConfig = Map<String, dynamic>.from(cfg);
          _deliveryFeeEnabled = _deliveryFeeConfig?['enabled'] != false;
          _deliveryRatePerKm =
              (_deliveryFeeConfig?['rate_per_km'] as num?)?.toDouble() ?? 10.0;
          _deliveryMinFee =
              (_deliveryFeeConfig?['minimum_fee'] as num?)?.toDouble() ?? 20.0;
          _deliveryMinDistance =
              (_deliveryFeeConfig?['min_billable_distance_km'] as num?)
                  ?.toDouble() ??
              1.0;
          _deliveryRoundingRule =
              (_deliveryFeeConfig?['rounding_rule'] ?? 'exact').toString();
          _stationSettingsLoaded = true;
        });
        _recalculateDeliveryFee();

        try {
          final sett = await supabase
              .from('owner_settings')
              .select('opening_time, closing_time, operating_days')
              .eq('owner_id', ownerId)
              .maybeSingle();
          if (sett != null && mounted) {
            _stationOpeningTime = sett['opening_time']?.toString();
            _stationClosingTime = sett['closing_time']?.toString();
            if (sett['operating_days'] is List) {
              _stationOperatingDays = List<String>.from(sett['operating_days']);
            }
            _evaluateOperatingHours();
          }
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('Error loading delivery fee settings: $e');
      if (mounted) {
        setState(() {
          _stationSettingsLoaded = false;
          _pricingSetupError =
              'Delivery fees could not be verified. Retry before placing your order.';
        });
      }
    }
  }

  void _evaluateOperatingHours() {
    if (_stationOpeningTime == null || _stationClosingTime == null) {
      if (mounted) setState(() => _isOutsideHours = false);
      return;
    }
    final now = DateTime.now();
    bool outside = false;

    if (_stationOperatingDays.isNotEmpty) {
      const days = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];
      final currentDay = days[now.weekday - 1];
      if (!_stationOperatingDays.any(
        (d) => d.toLowerCase().startsWith(currentDay),
      )) {
        outside = true;
      }
    }

    if (!outside) {
      try {
        final openParts = _stationOpeningTime!.split(':');
        final closeParts = _stationClosingTime!.split(':');
        final openMin =
            int.parse(openParts[0].trim()) * 60 +
            int.parse(openParts[1].trim());
        final closeMin =
            int.parse(closeParts[0].trim()) * 60 +
            int.parse(closeParts[1].trim());
        final nowMin = now.hour * 60 + now.minute;

        if (nowMin < openMin || nowMin > closeMin) {
          outside = true;
        }
      } catch (_) {}
    }

    if (mounted) {
      setState(() {
        _isOutsideHours = outside;
        if (outside) _scheduleForNextOpen = true;
      });
    }
  }

  void _recalculateDeliveryFee() {
    final customerLat = (_customerProfile?['latitude'] as num?)?.toDouble();
    final customerLng = (_customerProfile?['longitude'] as num?)?.toDouble();
    final stationLat =
        _stationLat ??
        (widget.station['latitude'] as num?)?.toDouble() ??
        (widget.station['lat'] as num?)?.toDouble();
    final stationLng =
        _stationLng ??
        (widget.station['longitude'] as num?)?.toDouble() ??
        (widget.station['lng'] as num?)?.toDouble();

    double distance = _deliveryDistanceKm;
    if (customerLat != null &&
        customerLng != null &&
        stationLat != null &&
        stationLng != null &&
        customerLat != 0 &&
        customerLng != 0 &&
        stationLat != 0 &&
        stationLng != 0) {
      final meters = Geolocator.distanceBetween(
        stationLat,
        stationLng,
        customerLat,
        customerLng,
      );
      distance = meters / 1000.0;
      distance = (distance * 100).roundToDouble() / 100.0;
      if (distance < 0.1) distance = 0.1;
    }

    final calculated = CheckoutRules.calculateDeliveryFee(
      distanceKm: distance,
      enabled: _deliveryFeeEnabled,
      ratePerKm: _deliveryRatePerKm,
      minimumFee: _deliveryMinFee,
      minBillableDistanceKm: _deliveryMinDistance,
      roundingRule: _deliveryRoundingRule,
    );

    if (mounted) {
      setState(() {
        _deliveryDistanceKm = distance;
        _deliveryFee = calculated;
      });
    }
  }

  Future<void> _loadPlatformFeeConfig() async {
    try {
      final cfg = await supabase.rpc('get_platform_fee_config');
      if (cfg is! Map) {
        throw StateError('Platform fee configuration response was invalid.');
      }
      if (!mounted) return;
      setState(() {
        _platformFeeConfig = Map<String, dynamic>.from(cfg);
        _platformFeeConfigLoaded = true;
      });
    } catch (e) {
      debugPrint('Platform fee config unavailable: $e');
      if (mounted) {
        setState(() {
          _platformFeeConfigLoaded = false;
          _pricingSetupError =
              'Order fees could not be verified. Retry before placing your order.';
        });
      }
    }
  }

  Future<void> _retryCheckoutConfiguration() async {
    if (_isLoadingCheckoutConfiguration) return;
    setState(() {
      _isLoadingCheckoutConfiguration = true;
      _pricingSetupError = null;
      _paymentMethodsError = null;
      _stationSettingsLoaded = false;
      _platformFeeConfigLoaded = false;
      _paymentMethodsLoaded = false;
    });
    await Future.wait([
      _loadStationSettings(),
      _loadPlatformFeeConfig(),
      _loadPaymentMethods(),
    ]);
    if (!mounted) return;
    setState(() {
      if (_stationSettingsLoaded &&
          _platformFeeConfigLoaded &&
          _paymentMethodsLoaded) {
        _pricingSetupError = null;
        _paymentMethodsError = null;
      } else if (!_stationSettingsLoaded || !_platformFeeConfigLoaded) {
        _pricingSetupError ??=
            'Order fees could not be verified. Retry before placing your order.';
      }
      _isLoadingCheckoutConfiguration = false;
    });
  }

  double _platformFeeFor(double subtotal) {
    final cfg = _platformFeeConfig;
    return CheckoutRules.calculatePlatformFee(
      subtotal: subtotal,
      deliveryFee: _deliveryFee,
      enabled: cfg?['enabled'] == true,
      percent: (cfg?['percent'] as num?)?.toDouble() ?? 0,
      fixed: (cfg?['fixed'] as num?)?.toDouble() ?? 0,
    );
  }

  Future<void> _loadLoyaltyVouchers() async {
    final customerId = supabase.auth.currentUser?.id;
    if (customerId == null) return;
    try {
      final vouchers = await _loyaltyService.getUserVouchers(customerId);
      if (mounted) {
        setState(() => _availableVouchers = vouchers);
      }
    } catch (e) {
      debugPrint('Error loading customer reward vouchers: $e');
    }
  }

  void _showSelectVoucherSheet() {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppUi.radiusSheet)),
      ),
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.local_offer_rounded,
                      color: AppUi.brandOf(context),
                      size: 20,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Select Reward Voucher',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
            const Divider(height: 12),
            if (_availableVouchers.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    'No active vouchers available to claim.',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _availableVouchers.length,
                  itemBuilder: (context, idx) {
                    final v = _availableVouchers[idx];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Colors.grey.withValues(alpha: 0.2),
                        ),
                        borderRadius: BorderRadius.circular(AppUi.radiusCard),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(AppUi.radiusCard),
                        clipBehavior: Clip.antiAlias,
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: const Color(
                              0xFF10B981,
                            ).withValues(alpha: 0.1),
                            child: const Icon(
                              Icons.check_rounded,
                              color: AppColors.uiSuccess,
                              size: 18,
                            ),
                          ),
                          title: Text(
                            v.title,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                          subtitle: Text(
                            v.description,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.grey,
                            ),
                          ),
                          trailing: Text(
                            v.isDeliveryDiscount
                                ? 'Free Delivery'
                                : '-${formatPeso(v.discountAmount, whole: true)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AppColors.uiSuccess,
                            ),
                          ),
                          onTap: () {
                            setState(() => _appliedVoucher = v);
                            Navigator.pop(ctx);
                          },
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _loadCustomerLocation() async {
    final customerId = supabase.auth.currentUser?.id;
    if (customerId == null) return;

    try {
      final profile =
          await ProfileQueryHelpers.fetchProfile(supabase, customerId) ??
          <String, dynamic>{};

      List<Map<String, dynamic>> addresses = [];
      try {
        final savedAddresses = await supabase
            .from('customer_addresses')
            .select()
            .eq('customer_id', customerId)
            .order('is_default', ascending: false)
            .order('created_at', ascending: false);
        addresses = List<Map<String, dynamic>>.from(savedAddresses);
      } catch (e) {
        debugPrint('Saved addresses unavailable: $e');
      }

      final selected = addresses.isEmpty ? null : addresses.first;

      if (!mounted) return;
      setState(() {
        _savedAddresses = addresses;
        _selectedAddressId = selected?['id']?.toString();
        _customerProfile = selected == null
            ? profile
            : CheckoutRules.useSavedAddress(profile, selected);
        _checkoutHint = CheckoutRules.deliveryProfileIssue(_customerProfile);
        if (context.read<UserSettingsService>().defaultOrderNotes &&
            _notesController.text.isEmpty) {
          _notesController.text =
              _customerProfile?['landmark']?.toString() ?? '';
        }
      });
      _recalculateDeliveryFee();
      await _refreshStationAvailability();
    } catch (e) {
      debugPrint('Error loading customer location: $e');
    }
  }

  String _resolveCustomerName() {
    final profile = _customerProfile;
    if (profile == null) return 'Customer';

    final fullName = profile['full_name']?.toString().trim();
    if (fullName != null && fullName.isNotEmpty && fullName != 'New User') {
      return fullName;
    }

    final firstName = profile['first_name']?.toString().trim() ?? '';
    final lastName = profile['last_name']?.toString().trim() ?? '';
    final composed = '$firstName $lastName'.trim();
    if (composed.isNotEmpty) return composed;

    return profile['email']?.toString().split('@').first ?? 'Customer';
  }

  Future<void> _refreshStationAvailability() async {
    final requestId = ++_availabilityRequestId;
    if (!CheckoutRules.hasUsableDeliveryCoordinates(_customerProfile)) {
      if (mounted) {
        setState(() {
          _stationAvailabilityMessage = null;
          _checkingStationAvailability = false;
        });
      }
      return;
    }
    final lat = (_customerProfile?['latitude'] as num?)?.toDouble();
    final lng = (_customerProfile?['longitude'] as num?)?.toDouble();
    if (lat == null || lng == null) {
      if (mounted) {
        setState(() {
          _stationAvailabilityMessage = null;
          _checkingStationAvailability = false;
        });
      }
      return;
    }

    if (mounted) {
      setState(() => _checkingStationAvailability = true);
    }
    try {
      final availability = await supabase.rpc(
        'check_station_availability',
        params: {
          'p_station_id': widget.station['id'],
          'p_customer_lat': lat,
          'p_customer_lng': lng,
        },
      );

      if (!mounted || requestId != _availabilityRequestId) return;
      if (availability is! Map) {
        setState(() {
          _stationAvailabilityMessage =
              'Could not verify station availability. Please try again.';
          _checkingStationAvailability = false;
        });
        return;
      }
      setState(() {
        if (availability['distance'] is num) {
          _deliveryDistanceKm = (availability['distance'] as num).toDouble();
        }

        // Service radius is removed across the app. We never block checkout
        // due to distance or zone limits, allowing the centralized per-km rate to apply.
        if (availability['status'] != 'OK' &&
            availability['status'] != 'OUT_OF_ZONE') {
          _stationAvailabilityMessage =
              availability['message']?.toString() ??
              'This station is not available for your location right now.';
        } else {
          _stationAvailabilityMessage = null;
        }
        _checkingStationAvailability = false;
      });
      _recalculateDeliveryFee();
    } catch (e) {
      debugPrint('Station availability check failed: $e');
      if (!mounted || requestId != _availabilityRequestId) return;
      setState(() {
        _stationAvailabilityMessage =
            'Could not verify station availability. Please try again.';
        _checkingStationAvailability = false;
      });
    }
  }

  void _scrollToDeliverySection() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final sectionContext = _deliverySectionKey.currentContext;
      if (sectionContext != null && mounted) {
        Scrollable.ensureVisible(
          sectionContext,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _setCheckoutHint(String? message) {
    if (!mounted) return;
    setState(() => _checkoutHint = message);
  }

  bool _isValidUuid(String value) {
    return RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
      caseSensitive: false,
    ).hasMatch(value);
  }

  List<CheckoutPaymentOption> get _selectablePaymentMethods {
    if (!_paymentMethodsLoaded) return const [];
    return CheckoutRules.selectableMethods(_paymentMethods);
  }

  String _friendlyCheckoutError(Object error) {
    if (error is PostgrestException) {
      final msg = error.message.trim();
      if (msg.isNotEmpty) {
        if (msg.contains('Only customer accounts can place orders')) {
          return 'Only customer accounts can place orders.';
        }
        if (msg.contains('closed or unavailable')) {
          return 'This water station is currently closed or unavailable.';
        }
        if (msg.contains('payment method is not available') ||
            msg.contains('payment method')) {
          return 'This payment method is not available for this station.';
        }
        if (msg.contains('unavailable at this station') ||
            msg.contains('Product not found')) {
          return 'One or more items in your cart are unavailable at this station.';
        }
        return msg;
      }
    }
    final message = error.toString().replaceFirst('Exception: ', '');
    if (message.contains('Not authorized')) {
      return 'Please sign in again to place your order.';
    }
    if (message.contains('payment method')) {
      return 'Cash on delivery is available for this station. Online payment is not set up yet.';
    }
    if (message.contains('Product not found') ||
        message.contains('Product id is required')) {
      return 'Ordering is unavailable for this station right now. Please choose another station.';
    }
    if (message.contains('Station is not available') ||
        message.contains('not available')) {
      return message;
    }
    if (message.contains('customer_latitude') ||
        message.contains('customer_longitude')) {
      return 'The checkout database schema is incomplete. Please sync the Supabase orders table with the latest delivery-location columns.';
    }
    if (message.contains('SocketException') ||
        message.contains('Failed host lookup') ||
        message.contains('NetworkImage') ||
        message.contains('ClientException')) {
      return 'Could not reach the server. Check your connection and try again.';
    }
    return message.isNotEmpty
        ? message
        : 'We could not place your order. Please try again.';
  }

  Future<void> _confirmOrder(CartProvider cart) async {
    if (_isBootstrapping || _isSubmitting) return;
    if (_pricingSetupError != null ||
        !_stationSettingsLoaded ||
        !_platformFeeConfigLoaded) {
      _setCheckoutHint(
        _pricingSetupError ??
            'Order fees are still being verified. Retry before placing your order.',
      );
      return;
    }
    if (!_paymentMethodsLoaded) {
      _setCheckoutHint(
        _paymentMethodsError ??
            'Station payment options are still being verified. Retry before placing your order.',
      );
      return;
    }

    final customerId = supabase.auth.currentUser?.id;
    final isStationOpen = (widget.station['is_open'] as bool?) ?? true;

    final preflight = CheckoutRules.validate(
      cart: cart,
      customerId: customerId,
      isStationOpen: isStationOpen,
      customerProfile: _customerProfile,
    );
    if (!preflight.canSubmit) {
      _setCheckoutHint(preflight.message);
      _scrollToDeliverySection();
      return;
    }

    final hasInvalidProducts = cart.items.values.any((item) {
      final ownerId = widget.station['id']?.toString();
      return !_isValidUuid(item.id) || item.id == ownerId;
    });
    if (hasInvalidProducts) {
      _setCheckoutHint(
        'Ordering is unavailable for this station right now. Please choose another station.',
      );
      return;
    }

    if (_checkingStationAvailability) {
      _setCheckoutHint('Checking station availability. Please wait.');
      return;
    }

    if (_stationAvailabilityMessage != null) {
      _setCheckoutHint(_stationAvailabilityMessage);
      _scrollToDeliverySection();
      return;
    }

    if (!CheckoutRules.isPaymentAvailable(_paymentMethod, _paymentMethods)) {
      _setCheckoutHint(
        _paymentMethods.isEmpty
            ? 'Payment options could not be loaded. Please retry checkout.'
            : 'Choose an available payment method for this station.',
      );
      return;
    }

    final completeAddress = _customerProfile!['complete_address']
        .toString()
        .trim();
    final customerLat = (_customerProfile!['latitude'] as num).toDouble();
    final customerLng = (_customerProfile!['longitude'] as num).toDouble();

    final stationName =
        widget.station['station_name']?.toString() ??
        widget.station['name']?.toString() ??
        'Water Station';

    final voucherDiscount = _appliedVoucher != null
        ? (_appliedVoucher!.isDeliveryDiscount
              ? _deliveryFee.clamp(0.0, _appliedVoucher!.discountAmount)
              : _appliedVoucher!.discountAmount)
        : 0.0;

    var totalAmount = CheckoutRules.calculateOrderTotal(
      subtotal: cart.totalAmount,
      deliveryFee: _deliveryFee,
      platformFee: _platformFeeFor(cart.totalAmount),
      voucherDiscount: voucherDiscount,
    );

    final paymentMethod =
        CheckoutRules.isPaymentAvailable(_paymentMethod, _paymentMethods)
        ? _paymentMethod
        : null;

    final itemsData = cart.items.values
        .map(
          (item) => {
            'product_id': item.id,
            'product_name': item.name,
            'quantity': item.quantity,
          },
        )
        .toList();

    final sortedItems = [...itemsData]
      ..sort(
        (a, b) =>
            a['product_id']!.toString().compareTo(b['product_id']!.toString()),
      );
    final requestFingerprint = jsonEncode({
      'customer_id': customerId,
      'station_id': widget.station['id'],
      'payment_method': paymentMethod,
      'address': completeAddress,
      'barangay': _customerProfile?['barangay'],
      'town': _customerProfile?['town'],
      'landmark': _customerProfile?['landmark'],
      'latitude': customerLat,
      'longitude': customerLng,
      'notes': _notesController.text.trim(),
      'voucher_id': _appliedVoucher?.id,
      'items': sortedItems,
    });
    if (_orderAttemptFingerprint != requestFingerprint) {
      _orderAttemptFingerprint = requestFingerprint;
      _orderAttemptKey = const Uuid().v4();
    }

    setState(() {
      _isSubmitting = true;
      _checkoutHint = null;
    });
    try {
      if (paymentMethod == null) {
        throw StateError('Selected payment method is not available.');
      }

      final containerNotice = _containerOption == 'swap'
          ? '[Container: 1-to-1 Bottle Swap]'
          : '[Container: No Empty Bottle (Deposit / New Container Needed)]';

      final scheduleNotice = _isOutsideHours && _scheduleForNextOpen
          ? '[Scheduled for next station opening (${_stationOpeningTime ?? '8:00 AM'})]'
          : null;

      final userNotes = _notesController.text.trim();
      final combinedNotes = [
        containerNotice,
        ?scheduleNotice,
        if (userNotes.isNotEmpty) userNotes,
      ].join(' · ');

      final orderData = {
        'customer_id': customerId,
        'owner_id': widget.station['id'],
        'station_name': stationName,
        'customer_name': _resolveCustomerName(),
        'customer_phone': _customerProfile?['phone'],
        'customer_address': completeAddress,
        'customer_barangay': _customerProfile?['barangay'],
        'customer_municipality': _customerProfile?['town'],
        'customer_landmark': _customerProfile?['landmark'],
        'idempotency_key': _orderAttemptKey,
        'voucher_id': _appliedVoucher?.id,
        'subtotal': cart.totalAmount,
        'delivery_fee': _deliveryFee,
        'delivery_distance_km': _deliveryDistanceKm,
        'delivery_rate_per_km': _deliveryRatePerKm,
        'total_amount': totalAmount,
        'payment_method': paymentMethod,
        'payment_proof_url': null,
        'notes': combinedNotes,
        'region_id': _customerProfile?['region_id'],
        'customer_latitude': customerLat,
        'customer_longitude': customerLng,
        'container_exchange_type': _containerOption,
        if (_isOutsideHours && _scheduleForNextOpen)
          'scheduled_for_next_open': true,
      };

      final response = await supabase.rpc(
        'create_order_atomic',
        params: {'p_order_data': orderData, 'p_items_data': itemsData},
      );
      if (response == null || response is! Map) {
        throw StateError('Order creation failed: invalid server response.');
      }
      final orderMap = Map<String, dynamic>.from(response);
      final orderId = orderMap['id']?.toString();
      if (orderId == null || orderId.isEmpty) {
        throw StateError('Order creation failed: missing order ID.');
      }
      final serverTotal = orderMap['total_amount'];
      if (serverTotal is num) {
        totalAmount = serverTotal.toDouble();
      }

      if (CheckoutRules.isOnlinePayment(paymentMethod)) {
        try {
          final checkoutUrl = await _createOnlinePaymentCheckout(
            orderId: orderId,
            paymentMethod: paymentMethod,
          );
          if (!mounted) return;
          final launched = await PaymentLaunchService.launchCheckoutUrl(
            checkoutUrl,
          );
          if (!mounted) return;
          if (!launched) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'The payment page could not open automatically. Use Reopen Payment below to continue.',
                ),
              ),
            );
          }

          // Await payment verification. Do NOT proceed to order tracker until payment is confirmed!
          await _showPaymentVerificationSheet(
            orderId: orderId,
            checkoutUrl: checkoutUrl,
            stationName: stationName,
            totalAmount: totalAmount,
            paymentMethod: paymentMethod,
            cart: cart,
          );
          return;
        } catch (e) {
          debugPrint('Online payment failed: $e');
          if (!mounted) return;
          await _showPaymentFailedDialog(
            orderId: orderId,
            paymentMethod: paymentMethod,
            stationName: stationName,
            totalAmount: totalAmount,
            cart: cart,
            error: e,
          );
          return;
        }
      }

      cart.clearCart();
      if (customerId != null && customerId.isNotEmpty) {
        _loyaltyService.earnPointsForOrder(
          userId: customerId,
          orderAmount: totalAmount,
        );
      }

      final orderRecord = await supabase
          .from('orders')
          .select()
          .eq('id', orderId)
          .single();

      if (!mounted) return;
      final shortId = orderId.length >= 8
          ? orderId.substring(0, 8).toUpperCase()
          : orderId;
      await RefillLottie.showOrderSuccessDialog(
        context,
        orderNumber: shortId,
        stationName: stationName,
        onTrackOrder: () {
          if (mounted) context.replaceOrderTracker(orderRecord);
        },
      );
    } catch (e) {
      debugPrint('Checkout submission failed: $e');
      final errStr = e.toString().toLowerCase();
      final isOfflineLikely =
          errStr.contains('socket') ||
          errStr.contains('network') ||
          errStr.contains('timeout') ||
          errStr.contains('connection') ||
          errStr.contains('failed host lookup') ||
          errStr.contains('clientexception');

      final selectedPayment = paymentMethod ?? 'cod';
      if (CheckoutRules.isOnlinePayment(selectedPayment) && isOfflineLikely) {
        if (mounted) {
          _setCheckoutHint(
            'Internet connection required for online payment. Please select Cash on Delivery (COD) to place this order offline.',
          );
        }
        return;
      }
      if (!CheckoutRules.isOnlinePayment(selectedPayment) && isOfflineLikely) {
        if (_appliedVoucher != null) {
          if (mounted) {
            _setCheckoutHint(
              'Reward vouchers need an online connection to validate. Reconnect and retry checkout to keep this voucher on your order.',
            );
          }
          return;
        }
        try {
          final userId = supabase.auth.currentUser?.id ?? '';
          final queuedId = await OfflineOrderSyncService().queueOfflineOrder(
            customerId: userId,
            stationId: widget.station['id']?.toString() ?? '',
            stationName: stationName,
            items: itemsData,
            totalAmount: totalAmount,
            subtotal: cart.totalAmount,
            deliveryFee: _deliveryFee,
            platformFee: _platformFeeFor(cart.totalAmount),
            deliveryAddress: completeAddress,
            paymentMethod: selectedPayment,
            idempotencyKey: _orderAttemptKey,
            notes: _notesController.text.trim(),
          );

          cart.clearCart();
          if (userId.isNotEmpty) {
            _loyaltyService.earnPointsForOrder(
              userId: userId,
              orderAmount: totalAmount,
            );
          }

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Network offline. Your order is queued locally and will submit automatically once connected.',
                ),
                backgroundColor: AppUi.accentGreen,
                duration: Duration(seconds: 4),
              ),
            );

            context.replaceOrderTracker({
              'id': queuedId,
              'station_name': stationName,
              'total_amount': totalAmount,
              'subtotal': cart.totalAmount,
              'delivery_fee': _deliveryFee,
              'payment_method': paymentMethod,
              'status': 'pending_sync',
              'is_offline_queued': true,
              'created_at': DateTime.now().toIso8601String(),
              'items': itemsData,
            });
            return;
          }
        } catch (queueErr) {
          debugPrint('Offline queueing error: $queueErr');
        }
      }

      if (mounted) {
        _setCheckoutHint(_friendlyCheckoutError(e));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<String> _createOnlinePaymentCheckout({
    required String orderId,
    required String paymentMethod,
    bool forceNewCheckout = false,
  }) async {
    final normalizedMethod = paymentMethod.trim().toLowerCase().replaceAll(
      'paymaya',
      'maya',
    );
    try {
      final response = await supabase.functions.invoke(
        'create-payment-checkout',
        body: {
          'order_id': orderId,
          'payment_method': normalizedMethod,
          if (forceNewCheckout) 'force_new_checkout': true,
        },
      );

      final data = response.data;
      if (data is Map) {
        final checkoutUrl = data['checkout_url']?.toString().trim();
        if (checkoutUrl != null && checkoutUrl.isNotEmpty) {
          return checkoutUrl;
        }
        if (data['error'] != null) {
          throw Exception(data['error'].toString());
        }
      }
      if (response.status != 200) {
        throw Exception(
          'Payment gateway server returned status ${response.status}.',
        );
      }
      throw Exception('Payment checkout session was not created.');
    } on FunctionException catch (fe) {
      final details = fe.details;
      if (details is Map && details['error'] != null) {
        throw Exception(details['error'].toString());
      } else if (details is String && details.isNotEmpty) {
        throw Exception(details);
      } else if (fe.reasonPhrase != null && fe.reasonPhrase!.isNotEmpty) {
        throw Exception(fe.reasonPhrase!);
      }
      rethrow;
    }
  }

  Future<void> _showPaymentVerificationSheet({
    required String orderId,
    required String checkoutUrl,
    required String stationName,
    required double totalAmount,
    required String paymentMethod,
    required CartProvider cart,
  }) async {
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (bottomSheetContext) {
        return _PaymentVerificationModal(
          orderId: orderId,
          initialCheckoutUrl: checkoutUrl,
          stationName: stationName,
          totalAmount: totalAmount,
          paymentMethod: paymentMethod,
          onPaymentSuccess: (orderRecord) {
            Navigator.of(bottomSheetContext).pop();
            if (mounted) {
              cart.clearCart();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Payment verified! Tracking your refill order.',
                  ),
                  backgroundColor: AppUi.accentGreen,
                  duration: Duration(seconds: 4),
                ),
              );
              context.replaceOrderTracker(orderRecord);
            }
          },
          onClose: () async {
            Navigator.of(bottomSheetContext).pop();
            if (mounted) {
              // Online orders stay out of order details and tracking until the
              // payment webhook confirms success.
              context.go(AppRoutes.home);
            }
          },
        );
      },
    );
  }

  Future<void> _showPaymentFailedDialog({
    required String orderId,
    required String paymentMethod,
    required String stationName,
    required double totalAmount,
    required CartProvider cart,
    required Object error,
  }) async {
    if (!mounted) return;
    final message = FriendlyErrors.message(
      error,
      fallback:
          'Online payment could not be processed. Retry payment to continue your order.',
    );

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppUi.radiusSheet)),
        title: Row(
          children: const [
            Icon(Icons.error_outline, color: AppColors.uiError),
            SizedBox(width: 8),
            Text(
              'Payment Notice',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(dialogCtx).pop();
              context.go(AppRoutes.home);
            },
            child: const Text('Cancel payment'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppUi.bluePrimary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppUi.radiusControl),
              ),
            ),
            onPressed: () async {
              Navigator.of(dialogCtx).pop();
              await _resumeOnlinePayment(
                orderId: orderId,
                paymentMethod: paymentMethod,
                stationName: stationName,
                totalAmount: totalAmount,
                cart: cart,
              );
            },
            child: const Text('Retry payment'),
          ),
        ],
      ),
    );
  }

  Future<void> _resumeOnlinePayment({
    required String orderId,
    required String paymentMethod,
    required String stationName,
    required double totalAmount,
    required CartProvider cart,
  }) async {
    try {
      final checkoutUrl = await _createOnlinePaymentCheckout(
        orderId: orderId,
        paymentMethod: paymentMethod,
      );
      if (!mounted) return;
      final launched = await PaymentLaunchService.launchCheckoutUrl(
        checkoutUrl,
      );
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'The payment page could not open automatically. Use Reopen Payment below.',
            ),
          ),
        );
      }
      if (!mounted) return;
      await _showPaymentVerificationSheet(
        orderId: orderId,
        checkoutUrl: checkoutUrl,
        stationName: stationName,
        totalAmount: totalAmount,
        paymentMethod: paymentMethod,
        cart: cart,
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            FriendlyErrors.message(
              error,
              fallback: 'Could not reopen payment checkout. Please try again.',
            ),
          ),
          backgroundColor: AppColors.uiError,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();
    final platformFee = _platformFeeFor(cart.totalAmount);
    final voucherDiscount = _appliedVoucher != null
        ? (_appliedVoucher!.isDeliveryDiscount
              ? _deliveryFee.clamp(0.0, _appliedVoucher!.discountAmount)
              : _appliedVoucher!.discountAmount)
        : 0.0;
    final totalWithDelivery = CheckoutRules.calculateOrderTotal(
      subtotal: cart.totalAmount,
      deliveryFee: _deliveryFee,
      platformFee: platformFee,
      voucherDiscount: voucherDiscount,
    );
    final textTheme = Theme.of(context).textTheme;
    final profileReady = CheckoutRules.isDeliveryProfileReady(_customerProfile);
    final deliveryIssue = CheckoutRules.deliveryProfileIssue(_customerProfile);
    final bannerMessage =
        _checkoutHint ??
        (_pricingSetupError ??
            _paymentMethodsError ??
            (_checkingStationAvailability
                ? 'Checking station availability…'
                : deliveryIssue ?? _stationAvailabilityMessage));
    final stationName =
        widget.station['station_name']?.toString() ??
        widget.station['name']?.toString() ??
        'Water Station';

    if (cart.items.isEmpty && !_isBootstrapping) {
      return Scaffold(
        backgroundColor: AppUi.pageBgOf(context),
        appBar: _buildCustomHeader(context),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 76,
                  height: 76,
                  decoration: const BoxDecoration(
                    color: AppUi.blueSoft,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.shopping_cart_outlined,
                    color: AppUi.brandOf(context),
                    size: 38,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Your cart is empty',
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Add water refill products from the station to proceed with checkout.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppUi.textSecondaryOf(context),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.arrow_back_rounded, size: 18),
                  label: const Text('Back to Station'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppUi.bluePrimary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppUi.radiusCard),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppUi.pageBgOf(context),
      appBar: _buildCustomHeader(context),
      body: _isBootstrapping
          ? const AxoLoader(message: 'Loading checkout...')
          : SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Alert Banner (if any)
                  if (bannerMessage != null) ...[
                    _checkoutBanner(bannerMessage),
                    if (_pricingSetupError != null ||
                        _paymentMethodsError != null) ...[
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: _isLoadingCheckoutConfiguration
                              ? null
                              : _retryCheckoutConfiguration,
                          child: Text(
                            _isLoadingCheckoutConfiguration
                                ? 'Retrying…'
                                : 'Retry checkout setup',
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                  ],

                  // ── 1. DELIVERY ADDRESS CARD ──────────────────────
                  _buildDeliveryAddressCard(context, profileReady),
                  const SizedBox(height: 12),

                  if (_isOutsideHours) ...[
                    _buildStationScheduleNotice(context),
                    const SizedBox(height: 12),
                  ],

                  // ── 2. STATION & REFILL ITEMS CARD ───────────────
                  _buildStationAndItemsCard(context, stationName, cart),
                  const SizedBox(height: 12),

                  // ── CONTAINER EXCHANGE OPTION ────────────────────
                  _buildContainerExchangeCard(context, cart),
                  const SizedBox(height: 12),

                  // ── 3. VOUCHER / PROMOTION CARD ──────────────────
                  _buildVoucherCard(context, voucherDiscount),
                  const SizedBox(height: 12),

                  // ── 4. PAYMENT METHOD CARD ────────────────────────
                  _buildPaymentMethodCard(context),
                  const SizedBox(height: 12),

                  // ── 5. ORDER SUMMARY CARD ─────────────────────────
                  _buildOrderSummaryCard(
                    context,
                    cart,
                    platformFee,
                    voucherDiscount,
                    totalWithDelivery,
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
      bottomNavigationBar: _isBootstrapping
          ? null
          : _CheckoutBottomBar(
              total: totalWithDelivery,
              isSubmitting: _isSubmitting,
              canSubmit:
                  cart.totalItems > 0 &&
                  !_isSubmitting &&
                  _pricingSetupError == null &&
                  _stationSettingsLoaded &&
                  _platformFeeConfigLoaded &&
                  _paymentMethodsLoaded &&
                  !_checkingStationAvailability &&
                  _stationAvailabilityMessage == null,
              onConfirm: () => _confirmOrder(cart),
            ),
    );
  }

  // ── CUSTOM TOP NAVIGATION ──────────────────────────────────────────────────

  PreferredSize _buildCustomHeader(BuildContext context) {
    return PreferredSize(
      preferredSize: const Size.fromHeight(56),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                tooltip: 'Back',
                onPressed: () => Navigator.of(context).maybePop(),
                style: IconButton.styleFrom(
                  side: BorderSide(color: AppUi.borderOf(context)),
                  shape: const CircleBorder(),
                ),
                icon: Icon(
                  Icons.arrow_back_rounded,
                  size: 20,
                  color: AppUi.textPrimaryOf(context),
                ),
              ),
              Text(
                'Checkout',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                  color: AppUi.textPrimaryOf(context),
                ),
              ),
              const SizedBox(width: 48),
            ],
          ),
        ),
      ),
    );
  }

  // ── 1. DELIVERY ADDRESS CARD ──────────────────────────────────────────────

  Widget _buildDeliveryAddressCard(BuildContext context, bool profileReady) {
    final lat = (_customerProfile?['latitude'] as num?)?.toDouble();
    final lng = (_customerProfile?['longitude'] as num?)?.toDouble();
    final hasCoords = lat != null && lng != null && (lat != 0 || lng != 0);

    return Container(
      key: _deliverySectionKey,
      decoration: BoxDecoration(
        color: AppUi.surfaceOf(context),
        borderRadius: BorderRadius.circular(AppUi.radiusSheet),
        border: Border.all(color: AppUi.borderOf(context), width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Map preview thumbnail on top
          if (hasCoords)
            SizedBox(
              height: 110,
              width: double.infinity,
              child: IgnorePointer(
                child: FlutterMap(
                  options: MapOptions(
                    initialCenter: LatLng(lat, lng),
                    initialZoom: 15.5,
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.none,
                    ),
                  ),
                  children: [
                    AppMapTiles.layer(context: context),
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: LatLng(lat, lng),
                          width: 38,
                          height: 38,
                          alignment: Alignment.topCenter,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.25),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            padding: const EdgeInsets.all(4),
                            child: const Icon(
                              Icons.location_on_rounded,
                              color: AppColors.uiError,
                              size: 24,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            )
          else
            Container(
              height: 80,
              width: double.infinity,
              color: AppUi.brandSoftOf(context).withValues(alpha: 0.6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.map_outlined,
                    color: AppUi.bluePrimary.withValues(alpha: 0.8),
                    size: 22,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Set delivery pin on map',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppUi.brandOf(context),
                    ),
                  ),
                ],
              ),
            ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Deliver to',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppUi.textSecondaryOf(context),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _deliveryDestinationLabel(),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                          color: AppUi.textPrimaryOf(context),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    InkWell(
                      onTap: _openAddressSetup,
                      borderRadius: BorderRadius.circular(AppUi.radiusControl),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 2,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Text(
                              'Change',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: AppColors.uiSuccess,
                              ),
                            ),
                            SizedBox(width: 2),
                            Icon(
                              Icons.chevron_right_rounded,
                              size: 18,
                              color: AppColors.uiSuccess,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  profileReady
                      ? (_customerProfile?['complete_address'] ??
                                'No address provided')
                            .toString()
                      : 'Add your delivery address to continue',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.35,
                    color: AppUi.textSecondaryOf(context),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (_savedAddresses.length > 1) ...[
                  const SizedBox(height: 12),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _savedAddresses.map((addr) {
                        final id = addr['id']?.toString();
                        final isSelected = id == _selectedAddressId;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: InkWell(
                            onTap: () => _selectSavedAddress(addr),
                            borderRadius: BorderRadius.circular(AppUi.radiusSheet),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? AppUi.bluePrimary.withValues(alpha: 0.12)
                                    : AppUi.pageBgOf(context),
                                borderRadius: BorderRadius.circular(AppUi.radiusSheet),
                                border: Border.all(
                                  color: isSelected
                                      ? AppUi.bluePrimary
                                      : AppUi.borderOf(context),
                                  width: 1,
                                ),
                              ),
                              child: Text(
                                addr['label']?.toString() ?? 'Address',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: isSelected
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: isSelected
                                      ? AppUi.brandOf(context)
                                      : AppUi.textSecondaryOf(context),
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── 2. STATION & REFILL ITEMS CARD ────────────────────────────────────────

  Widget _buildStationAndItemsCard(
    BuildContext context,
    String stationName,
    CartProvider cart,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: AppUi.surfaceOf(context),
        borderRadius: BorderRadius.circular(AppUi.radiusSheet),
        border: Border.all(color: AppUi.borderOf(context), width: 1),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Station branding header
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: AppUi.brandSoftOf(context),
                  borderRadius: BorderRadius.circular(AppUi.radiusControl),
                ),
                child: Icon(
                  Icons.water_drop_rounded,
                  color: AppUi.brandOf(context),
                  size: 16,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  stationName,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppUi.textPrimaryOf(context),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Items list
          ...cart.items.values.map((item) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: AppUi.brandSoftOf(context).withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(AppUi.radiusCard),
                        ),
                        alignment: Alignment.center,
                        child:
                            item.imageUrl != null && item.imageUrl!.isNotEmpty
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(AppUi.radiusCard),
                                child: CachedNetworkImage(
                                  imageUrl: item.imageUrl!,
                                  width: 52,
                                  height: 52,
                                  fit: BoxFit.cover,
                                  errorWidget: (context, url, error) =>
                                      Icon(
                                        Icons.water_drop_outlined,
                                        color: AppUi.brandOf(context),
                                        size: 26,
                                      ),
                                ),
                              )
                            : Icon(
                                Icons.water_drop_rounded,
                                color: AppUi.brandOf(context),
                                size: 26,
                              ),
                      ),
                      Positioned(
                        right: -3,
                        bottom: -3,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1.5,
                          ),
                          decoration: BoxDecoration(
                            color: AppUi.textPrimary,
                            borderRadius: BorderRadius.circular(AppUi.radiusControl),
                            border: Border.all(color: Colors.white, width: 1.5),
                          ),
                          child: Text(
                            '${item.quantity}x',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.name,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppUi.textPrimaryOf(context),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _deriveContainerOrRefillType(item.name),
                          style: TextStyle(
                            fontSize: 12,
                            color: AppUi.textSecondaryOf(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    formatPeso((item.price * item.quantity)),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppUi.textPrimaryOf(context),
                    ),
                  ),
                ],
              ),
            );
          }),

          Divider(
            height: 1,
            color: AppUi.dividerOf(context).withValues(alpha: 0.6),
          ),
          const SizedBox(height: 10),

          // Delivery notes / special instructions row
          InkWell(
            onTap: () => _showNotesDialog(context),
            borderRadius: BorderRadius.circular(AppUi.radiusControl),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(
                    Icons.notes_rounded,
                    size: 16,
                    color: AppUi.textSecondaryOf(context),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _notesController.text.trim().isEmpty
                          ? 'Add delivery notes / gate instructions...'
                          : 'Note: ${_notesController.text.trim()}',
                      style: TextStyle(
                        fontSize: 13,
                        fontStyle: _notesController.text.trim().isEmpty
                            ? FontStyle.italic
                            : FontStyle.normal,
                        color: _notesController.text.trim().isEmpty
                            ? AppUi.textSecondaryOf(context)
                            : AppUi.textPrimaryOf(context),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(
                    _notesController.text.trim().isEmpty
                        ? Icons.add_rounded
                        : Icons.edit_outlined,
                    size: 16,
                    color: AppColors.uiSuccess,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStationScheduleNotice(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final openTime = _stationOpeningTime ?? '8:00 AM';
    final closeTime = _stationClosingTime ?? '5:00 PM';

    return Container(
      decoration: BoxDecoration(
        color: AppColors.uiWarning.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppUi.radiusSheet),
        border: Border.all(
          color: AppColors.uiWarning.withValues(alpha: 0.3),
        ),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.schedule_rounded,
                color: AppColors.uiWarning,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Station Closed (Operating Hours: $openTime - $closeTime)',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.uiWarning,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'The refilling station is closed right now. You can schedule this order for delivery when the station opens.',
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.grey[300] : AppUi.textSecondary,
            ),
          ),
          const SizedBox(height: 10),
          InkWell(
            onTap: () =>
                setState(() => _scheduleForNextOpen = !_scheduleForNextOpen),
            borderRadius: BorderRadius.circular(AppUi.radiusControl),
            child: Row(
              children: [
                Checkbox(
                  value: _scheduleForNextOpen,
                  activeColor: AppColors.uiWarning,
                  onChanged: (v) =>
                      setState(() => _scheduleForNextOpen = v ?? false),
                ),
                Expanded(
                  child: Text(
                    'Schedule for next opening ($openTime delivery queue)',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : AppUi.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContainerExchangeCard(BuildContext context, CartProvider cart) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF161F30) : Colors.white;
    final borderColor = isDark
        ? const Color(0xFF1E2D4A)
        : AppUi.borderLight;

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(AppUi.radiusSheet),
        border: Border.all(color: borderColor),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.brandPrimary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppUi.radiusControl),
                ),
                child: Icon(
                  Icons.swap_horizontal_circle_outlined,
                  size: 20,
                  color: AppUi.brandOf(context),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Container Exchange Option',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : AppUi.textPrimary,
                      ),
                    ),
                    Text(
                      'Do you have empty bottles to swap?',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark
                            ? Colors.grey[400]
                            : AppUi.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => setState(() => _containerOption = 'swap'),
                  borderRadius: BorderRadius.circular(AppUi.radiusCard),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    constraints: const BoxConstraints(
                      minHeight: AppUi.kMinTouchTarget,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: _containerOption == 'swap'
                          ? AppColors.brandPrimary.withValues(alpha: 0.1)
                          : (isDark
                                ? AppUi.darkSurfaceRaised
                                : AppUi.pageBg),
                      borderRadius: BorderRadius.circular(AppUi.radiusCard),
                      border: Border.all(
                        color: _containerOption == 'swap'
                            ? AppColors.brandPrimary
                            : borderColor,
                        width: _containerOption == 'swap' ? 1.5 : 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              _containerOption == 'swap'
                                  ? Icons.radio_button_checked_rounded
                                  : Icons.radio_button_off_rounded,
                              size: 16,
                              color: _containerOption == 'swap'
                                  ? AppUi.brandOf(context)
                                  : Colors.grey,
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                '1-to-1 Swap',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: _containerOption == 'swap'
                                      ? AppUi.brandOf(context)
                                      : (isDark
                                            ? Colors.white
                                            : AppUi.textPrimary),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Hand over your empty gallon, no deposit',
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark
                                ? Colors.grey[400]
                                : AppUi.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: InkWell(
                  onTap: () => setState(() => _containerOption = 'deposit'),
                  borderRadius: BorderRadius.circular(AppUi.radiusCard),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    constraints: const BoxConstraints(
                      minHeight: AppUi.kMinTouchTarget,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: _containerOption == 'deposit'
                          ? AppColors.brandPrimary.withValues(alpha: 0.1)
                          : (isDark
                                ? AppUi.darkSurfaceRaised
                                : AppUi.pageBg),
                      borderRadius: BorderRadius.circular(AppUi.radiusCard),
                      border: Border.all(
                        color: _containerOption == 'deposit'
                            ? AppColors.brandPrimary
                            : borderColor,
                        width: _containerOption == 'deposit' ? 1.5 : 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              _containerOption == 'deposit'
                                  ? Icons.radio_button_checked_rounded
                                  : Icons.radio_button_off_rounded,
                              size: 16,
                              color: _containerOption == 'deposit'
                                  ? AppUi.brandOf(context)
                                  : Colors.grey,
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                'New / Deposit',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: _containerOption == 'deposit'
                                      ? AppUi.brandOf(context)
                                      : (isDark
                                            ? Colors.white
                                            : AppUi.textPrimary),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Buy or deposit new container',
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark
                                ? Colors.grey[400]
                                : AppUi.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── 3. VOUCHER / PROMOTION CARD ───────────────────────────────────────────

  Widget _buildVoucherCard(BuildContext context, double voucherDiscount) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _showSelectVoucherSheet,
        borderRadius: BorderRadius.circular(AppUi.radiusSheet),
        child: Container(
          decoration: BoxDecoration(
            color: AppUi.surfaceOf(context),
            borderRadius: BorderRadius.circular(AppUi.radiusSheet),
            border: Border.all(
              color: _appliedVoucher != null
                  ? AppColors.uiSuccess
                  : AppUi.borderOf(context),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Left soft-green badge matching reference screenshot
                Container(
                  width: 64,
                  color: isDark
                      ? const Color(0xFF132D21)
                      : const Color(0xFFE8F5E9),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.confirmation_number_outlined,
                          color: AppColors.uiSuccess,
                          size: 16,
                        ),
                      ),
                      const SizedBox(height: 3),
                      const Text(
                        'Voucher',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.uiSuccess,
                        ),
                      ),
                    ],
                  ),
                ),

                // Middle text
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 14,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _appliedVoucher != null
                              ? 'Voucher: ${_appliedVoucher!.title}'
                              : 'Select a voucher',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: _appliedVoucher != null
                                ? AppColors.uiSuccess
                                : AppUi.textPrimaryOf(context),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _appliedVoucher != null
                              ? (_appliedVoucher!.isDeliveryDiscount
                                    ? 'Free delivery discount applied'
                                    : '-${formatPeso(voucherDiscount, whole: true)} discount applied')
                              : (_availableVouchers.isEmpty
                                    ? 'No vouchers available for this order'
                                    : '${_availableVouchers.length} available for this order'),
                          style: TextStyle(
                            fontSize: 12,
                            color: AppUi.textSecondaryOf(context),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),

                // Right pill button matching reference screenshot
                Padding(
                  padding: const EdgeInsets.only(right: 14),
                  child: Center(
                    child: _appliedVoucher != null
                        ? TextButton(
                            onPressed: () {
                              setState(() => _appliedVoucher = null);
                            },
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: const Text(
                              'Remove',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppColors.uiError,
                              ),
                            ),
                          )
                        : Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF2E5E3B),
                              borderRadius: BorderRadius.circular(AppUi.radiusSheet),
                            ),
                            child: const Text(
                              'Select',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
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

  // ── 4. PAYMENT METHOD CARD ────────────────────────────────────────────────

  Widget _buildPaymentMethodCard(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _showPaymentSelectorSheet,
        borderRadius: BorderRadius.circular(AppUi.radiusSheet),
        child: Container(
          decoration: BoxDecoration(
            color: AppUi.surfaceOf(context),
            borderRadius: BorderRadius.circular(AppUi.radiusSheet),
            border: Border.all(color: AppUi.borderOf(context), width: 1),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Payment method',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppUi.textSecondaryOf(context),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _paymentBrandBadge(_paymentMethod),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          CheckoutRules.paymentLabel(_paymentMethod),
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppUi.textPrimaryOf(context),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _paymentSubtitle(_paymentMethod),
                          style: TextStyle(
                            fontSize: 12,
                            color: AppUi.textSecondaryOf(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Text(
                        'Change',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.uiSuccess,
                        ),
                      ),
                      SizedBox(width: 2),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 18,
                        color: AppColors.uiSuccess,
                      ),
                    ],
                  ),
                ],
              ),
              if (_paymentMethod != 'cod') ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: AppUi.brandSoftOf(context).withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(AppUi.radiusControl),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.lock_outline_rounded,
                        size: 14,
                        color: AppUi.brandOf(context),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Secure checkout powered by PayMongo Philippines',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppUi.brandOf(context),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ── 5. ORDER SUMMARY CARD ─────────────────────────────────────────────────

  Widget _buildOrderSummaryCard(
    BuildContext context,
    CartProvider cart,
    double platformFee,
    double voucherDiscount,
    double totalWithDelivery,
  ) {
    // "Free" only when no fee is charged. A delivery voucher is shown as its
    // own deduction so the lines always add up to the total.
    final isFreeDelivery = _deliveryFee == 0;
    final hasVoucher = _appliedVoucher != null && voucherDiscount > 0;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _summaryRow(
            context,
            'Subtotal (${cart.totalItems} item${cart.totalItems == 1 ? '' : 's'})',
            formatPeso(cart.totalAmount),
          ),
          const SizedBox(height: AppUi.spacingSm),
          _feeRow(
            context,
            label: 'Delivery fee',
            infoTooltip: 'How the delivery fee is calculated',
            onInfo: () => _showDeliveryFeeInfoDialog(context),
            value: isFreeDelivery ? 'Free' : formatPeso(_deliveryFee),
            valueColor: isFreeDelivery ? AppColors.uiSuccess : null,
          ),
          TextButton.icon(
            onPressed: () => setState(
              () => _isFeeBreakdownExpanded = !_isFeeBreakdownExpanded,
            ),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
              minimumSize: const Size(0, 36),
              textStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            icon: Icon(
              _isFeeBreakdownExpanded
                  ? Icons.keyboard_arrow_up_rounded
                  : Icons.keyboard_arrow_down_rounded,
              size: 18,
            ),
            label: Text(
              _isFeeBreakdownExpanded
                  ? 'Hide fee calculation'
                  : 'Show fee calculation',
            ),
          ),
          if (_isFeeBreakdownExpanded) ...[
            Container(
              padding: const EdgeInsets.all(AppUi.spacingMd),
              decoration: BoxDecoration(
                color: AppUi.surfaceRaisedOf(context),
                borderRadius: AppUi.controlRadius,
              ),
              child: Column(
                children: [
                  _summaryRow(
                    context,
                    'Distance from station',
                    '${_deliveryDistanceKm.toStringAsFixed(1)} km',
                  ),
                  const SizedBox(height: 6),
                  _summaryRow(
                    context,
                    'Rate',
                    '${formatPeso(_deliveryRatePerKm)}/km',
                  ),
                  const SizedBox(height: 6),
                  _summaryRow(
                    context,
                    'Minimum fee',
                    formatPeso(_deliveryMinFee),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppUi.spacingSm),
          ],
          if (platformFee > 0) ...[
            const SizedBox(height: AppUi.spacingXs),
            _feeRow(
              context,
              label: 'Service fee',
              infoTooltip: 'What the service fee covers',
              onInfo: () => _showServiceFeeInfoDialog(context),
              value: formatPeso(platformFee),
            ),
          ],
          if (hasVoucher) ...[
            const SizedBox(height: AppUi.spacingSm),
            _summaryRow(
              context,
              _appliedVoucher!.isDeliveryDiscount
                  ? 'Delivery voucher'
                  : 'Voucher discount',
              '−${formatPeso(voucherDiscount)}',
              valueColor: AppColors.uiSuccess,
            ),
          ],
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppUi.spacingMd),
            child: Divider(height: 1),
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Total',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppUi.textPrimaryOf(context),
                  ),
                ),
              ),
              Text(
                formatPeso(totalWithDelivery),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppUi.textPrimaryOf(context),
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _feeRow(
    BuildContext context, {
    required String label,
    required String infoTooltip,
    required VoidCallback onInfo,
    required String value,
    Color? valueColor,
  }) {
    return Row(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            color: AppUi.textSecondaryOf(context),
            fontWeight: FontWeight.w500,
          ),
        ),
        IconButton(
          tooltip: infoTooltip,
          onPressed: onInfo,
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.info_outline_rounded, size: 18),
          color: AppUi.textMuted,
        ),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: valueColor ?? AppUi.textPrimaryOf(context),
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }

  Widget _summaryRow(
    BuildContext context,
    String label,
    String value, {
    Color? valueColor,
  }) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: AppUi.textSecondaryOf(context),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(width: AppUi.spacingMd),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: valueColor ?? AppUi.textPrimaryOf(context),
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }

  // ── HELPER METHODS ────────────────────────────────────────────────────────

  String _deliveryDestinationLabel() {
    if (_selectedAddressId != null && _savedAddresses.isNotEmpty) {
      final matched = _savedAddresses.firstWhere(
        (a) => a['id']?.toString() == _selectedAddressId,
        orElse: () => const {},
      );
      final label = matched['label']?.toString();
      if (label != null && label.isNotEmpty) return label;
    }
    final landmark = _customerProfile?['landmark']?.toString().trim();
    if (landmark != null && landmark.isNotEmpty) return landmark;

    final barangay = _customerProfile?['barangay']?.toString().trim();
    if (barangay != null && barangay.isNotEmpty) return barangay;

    return 'Home';
  }

  String _deriveContainerOrRefillType(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('slim')) return '5-Gallon Slim Refill';
    if (lower.contains('round')) return '5-Gallon Round Refill';
    if (lower.contains('gallon') || lower.contains('gal')) {
      return '5-Gallon Refill';
    }
    if (lower.contains('alkaline')) return 'Alkaline Refill';
    if (lower.contains('mineral')) return 'Mineral Refill';
    if (lower.contains('purified')) return 'Purified Refill';
    return 'Water Refill';
  }

  Widget _paymentBrandBadge(String method) {
    return PaymentBrandMark(method: method, width: 58, height: 36);
  }

  String _paymentSubtitle(String method) {
    return switch (method) {
      'gcash' => 'Fast e-wallet payment',
      'maya' => 'Fast e-wallet payment',
      'card' => 'Debit or credit card',
      _ => 'Pay in cash upon arrival',
    };
  }

  void _showPaymentSelectorSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: AppUi.surfaceOf(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(AppUi.radiusPill)),
        ),
        padding: EdgeInsets.fromLTRB(
          20,
          16,
          20,
          MediaQuery.of(ctx).padding.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Select Payment Method',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppUi.textPrimaryOf(context),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
            const SizedBox(height: 12),
            PaymentMethodSelector(
              selectedMethod: _paymentMethod,
              methods: _selectablePaymentMethods,
              onSelected: (method) {
                setState(() => _paymentMethod = method);
                final user = supabase.auth.currentUser;
                if (user != null) {
                  LocalDataCache.instance.set(
                    'last_used_payment_method_${user.id}',
                    method,
                  );
                }
                Navigator.pop(ctx);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showNotesDialog(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          decoration: BoxDecoration(
            color: AppUi.surfaceOf(context),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(AppUi.radiusPill)),
          ),
          padding: EdgeInsets.fromLTRB(
            20,
            16,
            20,
            MediaQuery.of(ctx).padding.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Special Instructions',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: AppUi.textPrimaryOf(context),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              AppFormField(
                controller: _notesController,
                label: 'Delivery Notes',
                hintText:
                    'e.g., Leave gallon at front porch, call upon arrival...',
                prefixIcon: Icons.notes_rounded,
                maxLines: 3,
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  onPressed: () {
                    setState(() {});
                    Navigator.pop(ctx);
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: AppUi.bluePrimary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppUi.radiusCard),
                    ),
                  ),
                  child: const Text(
                    'Save Instructions',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDeliveryFeeInfoDialog(BuildContext context) {
    final dist = _deliveryDistanceKm;
    final rate = _deliveryRatePerKm;
    final minFee = _deliveryMinFee;
    final rounding = _deliveryRoundingRule;

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(
              Icons.local_shipping_outlined,
              color: AppUi.brandOf(context),
              size: 20,
            ),
            SizedBox(width: 8),
            Text('Delivery Fee Breakdown', style: TextStyle(fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Delivery rates are managed centrally by the Administrator across all stations for fair and transparent pricing.',
              style: TextStyle(fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppUi.brandSoftOf(context),
                borderRadius: BorderRadius.circular(AppUi.radiusControl),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '• Route Distance: ${dist.toStringAsFixed(2)} km',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    '• Centralized Rate: ${formatPeso(rate)} / km',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (minFee > 0)
                    Text(
                      '• Minimum Delivery Fee: ${formatPeso(minFee)}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  if (rounding == 'ceil')
                    const Text(
                      '• Rounding Rule: Round up to next whole km',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    )
                  else if (rounding == 'round')
                    const Text(
                      '• Rounding Rule: Round to nearest whole km',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    )
                  else
                    const Text(
                      '• Calculation: Exact proportional distance',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  const Divider(height: 16),
                  Text(
                    'Final Delivery Fee: ${formatPeso(_deliveryFee)}',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppUi.brandOf(context),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showServiceFeeInfoDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(
              Icons.info_outline_rounded,
              color: AppUi.brandOf(context),
              size: 20,
            ),
            SizedBox(width: 8),
            Text('What is this fee?', style: TextStyle(fontSize: 16)),
          ],
        ),
        content: const Text(
          'A small fee that covers 24/7 app maintenance, real-time rider tracking, and customer support so your water refills arrive smoothly.',
          style: TextStyle(fontSize: 13, height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  Widget _checkoutBanner(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppUi.warningBg,
        borderRadius: BorderRadius.circular(AppUi.radiusCard),
        border: Border.all(color: AppUi.warningFg.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline_rounded,
            color: AppUi.warningFg,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: AppUi.warningFg,
                fontWeight: FontWeight.w600,
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openAddressSetup() async {
    final profile = _customerProfile;
    await context.push(
      AppRoutes.savedAddresses,
      extra: SavedAddressLaunchContext(
        address: profile?['complete_address']?.toString() ?? '',
        landmark: profile?['landmark']?.toString() ?? '',
        town: profile?['town']?.toString(),
        barangay: profile?['barangay']?.toString(),
        latitude: (profile?['latitude'] as num?)?.toDouble() ?? 0,
        longitude: (profile?['longitude'] as num?)?.toDouble() ?? 0,
      ).toMap(),
    );
    if (mounted) await _loadCustomerLocation();
  }

  void _selectSavedAddress(Map<String, dynamic> address) {
    final deliveryProfile = CheckoutRules.useSavedAddress(
      _customerProfile ?? const {},
      address,
    );
    final deliveryIssue = CheckoutRules.deliveryProfileIssue(deliveryProfile);
    if (deliveryIssue != null) {
      _setCheckoutHint('$deliveryIssue Tap "Change" to edit it.');
      return;
    }
    setState(() {
      _selectedAddressId = address['id']?.toString();
      _customerProfile = deliveryProfile;
      _checkoutHint = null;
    });
    _recalculateDeliveryFee();
    _refreshStationAvailability();
  }
}

// ── FIXED BOTTOM ACTION BAR ──────────────────────────────────────────────────

class _CheckoutBottomBar extends StatelessWidget {
  final double total;
  final bool isSubmitting;
  final bool canSubmit;
  final VoidCallback onConfirm;

  const _CheckoutBottomBar({
    required this.total,
    required this.isSubmitting,
    required this.canSubmit,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      decoration: BoxDecoration(
        color: AppUi.surfaceOf(context),
        border: Border(
          top: BorderSide(
            color: AppUi.dividerOf(context).withValues(alpha: 0.7),
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Total',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppUi.textSecondaryOf(context),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    formatPeso(total),
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                      color: AppUi.textPrimaryOf(context),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            SizedBox(
              height: 52,
              child: FilledButton(
                onPressed: canSubmit ? onConfirm : null,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  minimumSize: const Size(0, 52),
                ),
                child: isSubmitting
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      )
                    : const Text(
                        'Checkout',
                        style: TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
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

class _PaymentVerificationModal extends StatefulWidget {
  final String orderId;
  final String initialCheckoutUrl;
  final String stationName;
  final double totalAmount;
  final String paymentMethod;
  final void Function(Map<String, dynamic> orderRecord) onPaymentSuccess;
  final VoidCallback onClose;

  const _PaymentVerificationModal({
    required this.orderId,
    required this.initialCheckoutUrl,
    required this.stationName,
    required this.totalAmount,
    required this.paymentMethod,
    required this.onPaymentSuccess,
    required this.onClose,
  });

  @override
  State<_PaymentVerificationModal> createState() =>
      _PaymentVerificationModalState();
}

class _PaymentVerificationModalState extends State<_PaymentVerificationModal> {
  final _supabase = Supabase.instance.client;
  bool _isCheckingStatus = false;
  String _paymentStatus = 'processing';
  String? _checkoutUrl;
  RealtimeChannel? _orderSubscription;

  @override
  void initState() {
    super.initState();
    _checkoutUrl = widget.initialCheckoutUrl;
    _subscribeToOrder();
  }

  void _subscribeToOrder() {
    _orderSubscription = _supabase
        .channel('order-payment-${widget.orderId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'orders',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: widget.orderId,
          ),
          callback: (payload) {
            final newRecord = payload.newRecord;
            final status = (newRecord['payment_status'] ?? '')
                .toString()
                .toLowerCase();
            if (mounted) {
              setState(() {
                _paymentStatus = status;
              });
            }
            if (status == 'success' ||
                status == 'paid' ||
                status == 'succeeded') {
              widget.onPaymentSuccess(newRecord);
            }
          },
        )
        .subscribe();
  }

  @override
  void dispose() {
    if (_orderSubscription != null) {
      _supabase.removeChannel(_orderSubscription!);
    }
    super.dispose();
  }

  Future<void> _checkStatusManually() async {
    if (_isCheckingStatus) return;
    setState(() => _isCheckingStatus = true);

    try {
      var record = await _supabase
          .from('orders')
          .select()
          .eq('id', widget.orderId)
          .single();

      var status = (record['payment_status'] ?? '').toString().toLowerCase();

      // If still awaiting confirmation, verify directly against PayMongo via Edge Function
      if (status != 'success' && status != 'paid' && status != 'succeeded') {
        try {
          final verifyRes = await _supabase.functions.invoke(
            'create-payment-checkout',
            body: {'action': 'verify', 'order_id': widget.orderId},
          );
          final vData = verifyRes.data;
          if (vData is Map && vData['payment_status'] != null) {
            final verifiedStatus = vData['payment_status']
                .toString()
                .toLowerCase();
            if (verifiedStatus == 'success' || verifiedStatus == 'paid') {
              record = await _supabase
                  .from('orders')
                  .select()
                  .eq('id', widget.orderId)
                  .single();
              status = 'success';
            }
          }
        } catch (_) {}
      }

      if (mounted) {
        setState(() {
          _paymentStatus = status;
          final updatedUrl = record['payment_checkout_url']?.toString();
          if (updatedUrl != null && updatedUrl.isNotEmpty) {
            _checkoutUrl = updatedUrl;
          }
        });
      }

      if (status == 'success' || status == 'paid' || status == 'succeeded') {
        widget.onPaymentSuccess(record);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                status == 'failed'
                    ? 'Payment was marked as failed. Tap Reopen Payment to try again.'
                    : 'Payment is still awaiting confirmation.',
              ),
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              FriendlyErrors.message(
                e,
                fallback: 'Could not check payment status.',
              ),
            ),
            backgroundColor: AppColors.uiError,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isCheckingStatus = false);
    }
  }

  Future<void> _reopenCheckout() async {
    final url = _checkoutUrl;
    if (url != null && url.isNotEmpty) {
      final launched = await PaymentLaunchService.launchCheckoutUrl(url);
      if (launched) return;
    }

    try {
      final normalizedMethod = widget.paymentMethod
          .trim()
          .toLowerCase()
          .replaceAll('paymaya', 'maya');
      final response = await _supabase.functions.invoke(
        'create-payment-checkout',
        body: {
          'order_id': widget.orderId,
          'payment_method': normalizedMethod,
          'force_new_checkout': true,
        },
      );
      final data = response.data;
      if (data is Map && data['checkout_url'] is String) {
        final newUrl = data['checkout_url'] as String;
        if (mounted) {
          setState(() => _checkoutUrl = newUrl);
        }
        final launched = await PaymentLaunchService.launchCheckoutUrl(newUrl);
        if (!launched) {
          throw Exception('Unable to open the renewed payment checkout page.');
        }
        return;
      }
      final err = data is Map ? data['error'] : null;
      throw Exception(err?.toString() ?? 'Could not reopen payment checkout.');
    } on FunctionException catch (fe) {
      final details = fe.details;
      final msg = details is Map && details['error'] != null
          ? details['error'].toString()
          : details is String && details.isNotEmpty
          ? details
          : fe.reasonPhrase ?? 'Could not reopen payment checkout.';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: AppColors.uiError),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              FriendlyErrors.message(
                e,
                fallback: 'Could not reopen payment checkout.',
              ),
            ),
            backgroundColor: AppColors.uiError,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final methodName = widget.paymentMethod.toUpperCase();

    return Container(
      decoration: BoxDecoration(
        color: AppUi.surfaceOf(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(AppUi.radiusPill)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(
        24,
        16,
        24,
        MediaQuery.of(context).padding.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark
                    ? AppUi.borderDark
                    : AppUi.borderStrongLight,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppUi.brandSoftOf(context),
                  borderRadius: BorderRadius.circular(AppUi.radiusCard),
                ),
                child: Icon(
                  Icons.account_balance_wallet_outlined,
                  color: AppUi.brandOf(context),
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Complete $methodName Payment',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppUi.textPrimaryOf(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${formatPeso(widget.totalAmount)} • ${widget.stationName}',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppUi.textSecondaryOf(context),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? AppUi.textPrimary : AppUi.pageBg,
              borderRadius: BorderRadius.circular(AppUi.radiusSheet),
              border: Border.all(color: AppUi.borderOf(context)),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (_paymentStatus == 'failed') ...[
                      const Icon(
                        Icons.cancel,
                        color: AppColors.uiError,
                        size: 24,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Payment Unsuccessful',
                        style: TextStyle(
                          color: AppColors.uiError,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                    ] else ...[
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            AppUi.bluePrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Waiting for confirmation…',
                        style: TextStyle(
                          color: AppUi.textPrimaryOf(context),
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _paymentStatus == 'failed'
                      ? 'The checkout session failed or expired. Please tap Reopen Payment to try again.'
                      : 'Please authorize the payment in your $methodName wallet or browser. Once completed, your order will update automatically.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: AppUi.textSecondaryOf(context),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: _reopenCheckout,
            icon: const Icon(Icons.open_in_browser_rounded, size: 18),
            label: Text('Reopen $methodName Checkout'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppUi.bluePrimary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppUi.radiusCard),
              ),
              elevation: 0,
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _isCheckingStatus ? null : _checkStatusManually,
            icon: _isCheckingStatus
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('I Have Paid (Check Status)'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppUi.textPrimaryOf(context),
              side: BorderSide(color: AppUi.borderOf(context)),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppUi.radiusCard),
              ),
            ),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: widget.onClose,
            child: Text(
              'Cancel payment',
              style: TextStyle(
                color: AppUi.textSecondaryOf(context),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
