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
import '../../../core/constants.dart';
import '../../../core/widgets/map_tiles.dart';
import '../../../core/widgets/brand/axo_states.dart';
import '../../../core/widgets/brand/refill_lottie.dart';
import 'widgets/payment_method_selector.dart';
import 'widgets/payment_brand_mark.dart';
import '../../../models/cart_model.dart';
import 'checkout_rules.dart';
import '../../../core/routing/app_navigation.dart';
import '../../../core/routing/app_routes.dart';
import '../../account/saved_addresses_screen.dart';
import '../../settings/customer/user_settings_service.dart';
import 'package:go_router/go_router.dart';
import '../../../core/widgets/app_form_fields.dart';
import '../../../core/services/offline_order_sync_service.dart';
import '../../../core/services/payment_launch_service.dart';
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

  @override
  void initState() {
    super.initState();
    _stationLat = (widget.station['latitude'] as num?)?.toDouble() ??
        (widget.station['lat'] as num?)?.toDouble();
    _stationLng = (widget.station['longitude'] as num?)?.toDouble() ??
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

      if (!mounted) return;
      setState(() {
        _paymentMethods = options;
        _paymentMethodsLoaded = true;
        _paymentMethodsError = null;
        if (!CheckoutRules.isPaymentAvailable(_paymentMethod, options)) {
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
              (_deliveryFeeConfig?['min_billable_distance_km'] as num?)?.toDouble() ?? 1.0;
          _deliveryRoundingRule =
              (_deliveryFeeConfig?['rounding_rule'] ?? 'exact').toString();
          _stationSettingsLoaded = true;
        });
        _recalculateDeliveryFee();
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

  void _recalculateDeliveryFee() {
    final customerLat = (_customerProfile?['latitude'] as num?)?.toDouble();
    final customerLng = (_customerProfile?['longitude'] as num?)?.toDouble();
    final stationLat = _stationLat ??
        (widget.station['latitude'] as num?)?.toDouble() ??
        (widget.station['lat'] as num?)?.toDouble();
    final stationLng = _stationLng ??
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
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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
                  children: const [
                    Icon(
                      Icons.local_offer_rounded,
                      color: AppUi.bluePrimary,
                      size: 20,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Select Reward Voucher',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
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
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: const Color(
                            0xFF10B981,
                          ).withValues(alpha: 0.1),
                          child: const Icon(
                            Icons.check_rounded,
                            color: Color(0xFF10B981),
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
                              : '-\u20B1${v.discountAmount.toStringAsFixed(0)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF10B981),
                          ),
                        ),
                        onTap: () {
                          setState(() => _appliedVoucher = v);
                          Navigator.pop(ctx);
                        },
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
        if (availability['status'] != 'OK') {
          if (availability['status'] == 'OUT_OF_ZONE') {
            final stationTown =
                (widget.station['town'] ?? widget.station['municipality'] ?? '')
                    .toString()
                    .trim();
            final customerTown =
                _customerProfile?['town']?.toString().trim() ?? '';
            if (stationTown.isNotEmpty &&
                customerTown.isNotEmpty &&
                stationTown.toLowerCase() != customerTown.toLowerCase()) {
              _stationAvailabilityMessage =
                  'This station is located in $stationTown and cannot deliver to $customerTown (outside delivery radius). Please select a station in $customerTown or change your delivery address.';
            } else {
              _stationAvailabilityMessage =
                  availability['message']?.toString() ??
                  'You are outside the service area of this station.';
            }
          } else {
            _stationAvailabilityMessage =
                availability['message']?.toString() ??
                'This station is not available for your location right now.';
          }
        } else {
          _stationAvailabilityMessage = null;
          if (availability['distance'] is num) {
            _deliveryDistanceKm = (availability['distance'] as num).toDouble();
          }
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

      final notesText = _appliedVoucher != null
          ? '${_notesController.text.trim()} [Voucher: ${_appliedVoucher!.code} -₱${voucherDiscount.toStringAsFixed(2)}]'
                .trim()
          : _notesController.text.trim();

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
        'notes': notesText,
        'region_id': _customerProfile?['region_id'],
        'customer_latitude': customerLat,
        'customer_longitude': customerLng,
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: const [
            Icon(Icons.error_outline, color: Colors.redAccent),
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
                borderRadius: BorderRadius.circular(10),
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
          backgroundColor: Colors.redAccent,
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
                  child: const Icon(
                    Icons.shopping_cart_outlined,
                    color: AppUi.bluePrimary,
                    size: 38,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Your cart is empty',
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
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
                      borderRadius: BorderRadius.circular(12),
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

                  // ── 2. STATION & REFILL ITEMS CARD ───────────────
                  _buildStationAndItemsCard(context, stationName, cart),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return PreferredSize(
      preferredSize: const Size.fromHeight(56),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              GestureDetector(
                onTap: () => Navigator.of(context).maybePop(),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppUi.surfaceOf(context),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppUi.borderOf(context),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: isDark ? 0.2 : 0.04,
                        ),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.arrow_back_rounded,
                    size: 20,
                    color: AppUi.textPrimaryOf(context),
                  ),
                ),
              ),
              Text(
                'Confirm Refill',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                  color: AppUi.textPrimaryOf(context),
                ),
              ),
              const SizedBox(width: 40),
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
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppUi.borderOf(context), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
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
                              color: Color(0xFFEF4444),
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
              color: AppUi.blueSoft.withValues(alpha: 0.6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.map_outlined,
                    color: AppUi.bluePrimary.withValues(alpha: 0.8),
                    size: 22,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Set delivery pin on map',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppUi.bluePrimary,
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
                  'Deliver to \u00B7 ~20-30 min',
                  style: TextStyle(
                    fontSize: 12.5,
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
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.2,
                          color: AppUi.textPrimaryOf(context),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    InkWell(
                      onTap: _openAddressSetup,
                      borderRadius: BorderRadius.circular(8),
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
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF2E7D32),
                              ),
                            ),
                            SizedBox(width: 2),
                            Icon(
                              Icons.chevron_right_rounded,
                              size: 18,
                              color: Color(0xFF2E7D32),
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
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? AppUi.bluePrimary.withValues(alpha: 0.12)
                                    : AppUi.pageBgOf(context),
                                borderRadius: BorderRadius.circular(16),
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
                                  fontSize: 11.5,
                                  fontWeight: isSelected
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: isSelected
                                      ? AppUi.bluePrimary
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
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppUi.borderOf(context), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
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
                  color: AppUi.blueSoft,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.water_drop_rounded,
                  color: AppUi.bluePrimary,
                  size: 16,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  stationName,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
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
                          color: AppUi.blueSoft.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        alignment: Alignment.center,
                        child:
                            item.imageUrl != null && item.imageUrl!.isNotEmpty
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: CachedNetworkImage(
                                  imageUrl: item.imageUrl!,
                                  width: 52,
                                  height: 52,
                                  fit: BoxFit.cover,
                                  errorWidget: (context, url, error) =>
                                      const Icon(
                                        Icons.water_drop_outlined,
                                        color: AppUi.bluePrimary,
                                        size: 26,
                                      ),
                                ),
                              )
                            : const Icon(
                                Icons.water_drop_rounded,
                                color: AppUi.bluePrimary,
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
                            color: const Color(0xFF1E293B),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.white, width: 1.5),
                          ),
                          child: Text(
                            '${item.quantity}x',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
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
                            fontSize: 14.5,
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
                    '\u20B1${(item.price * item.quantity).toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 14.5,
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
            borderRadius: BorderRadius.circular(8),
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
                        fontSize: 12.5,
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
                    color: const Color(0xFF2E7D32),
                  ),
                ],
              ),
            ),
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
        borderRadius: BorderRadius.circular(20),
        child: Container(
          decoration: BoxDecoration(
            color: AppUi.surfaceOf(context),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: _appliedVoucher != null
                  ? const Color(0xFF10B981)
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
                          color: Color(0xFF2E7D32),
                          size: 16,
                        ),
                      ),
                      const SizedBox(height: 3),
                      const Text(
                        'Voucher',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF2E7D32),
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
                            fontWeight: FontWeight.w800,
                            color: _appliedVoucher != null
                                ? const Color(0xFF16A34A)
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
                                    : '-\u20B1${voucherDiscount.toStringAsFixed(0)} discount applied')
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
                                color: Colors.redAccent,
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
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text(
                              'Select',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12.5,
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
        borderRadius: BorderRadius.circular(20),
        child: Container(
          decoration: BoxDecoration(
            color: AppUi.surfaceOf(context),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppUi.borderOf(context), width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Payment method',
                style: TextStyle(
                  fontSize: 12.5,
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
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800,
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
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF2E7D32),
                        ),
                      ),
                      SizedBox(width: 2),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 18,
                        color: Color(0xFF2E7D32),
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
                    color: AppUi.blueSoft.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.lock_outline_rounded,
                        size: 14,
                        color: AppUi.bluePrimary,
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Secure checkout powered by PayMongo Philippines',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppUi.bluePrimary,
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
    final isFreeDelivery =
        _deliveryFee == 0 ||
        (_appliedVoucher != null && _appliedVoucher!.isDeliveryDiscount);

    return Container(
      decoration: BoxDecoration(
        color: AppUi.surfaceOf(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppUi.borderOf(context), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _summaryRow(
            context,
            'Subtotal',
            '\u20B1${cart.totalAmount.toStringAsFixed(2)}',
          ),
          const SizedBox(height: 10),
          _summaryRow(
            context,
            'Delivery distance',
            '${_deliveryDistanceKm.toStringAsFixed(1)} km',
          ),
          const SizedBox(height: 10),
          _summaryRow(
            context,
            'Delivery rate',
            '\u20B1${_deliveryRatePerKm.toStringAsFixed(2)}/km',
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Delivery fee',
                    style: TextStyle(
                      fontSize: 13.5,
                      color: AppUi.textSecondaryOf(context),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 5),
                  GestureDetector(
                    onTap: () => _showDeliveryFeeInfoDialog(context),
                    child: const Icon(
                      Icons.info_outline_rounded,
                      size: 14,
                      color: AppUi.textMuted,
                    ),
                  ),
                ],
              ),
              isFreeDelivery
                  ? const Text(
                      'Free',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF2E7D32),
                      ),
                    )
                  : Text(
                      '\u20B1${_deliveryFee.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: AppUi.textPrimaryOf(context),
                      ),
                    ),
            ],
          ),
          if (platformFee > 0) ...[
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Service fee',
                      style: TextStyle(
                        fontSize: 13.5,
                        color: AppUi.textSecondaryOf(context),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 5),
                    GestureDetector(
                      onTap: () => _showServiceFeeInfoDialog(context),
                      child: const Icon(
                        Icons.info_outline_rounded,
                        size: 14,
                        color: AppUi.textMuted,
                      ),
                    ),
                  ],
                ),
                Text(
                  '\u20B1${platformFee.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: AppUi.textPrimaryOf(context),
                  ),
                ),
              ],
            ),
          ],
          if (_appliedVoucher != null && voucherDiscount > 0) ...[
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Voucher discount',
                  style: TextStyle(
                    fontSize: 13.5,
                    color: Color(0xFF2E7D32),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '-\u20B1${voucherDiscount.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF2E7D32),
                  ),
                ),
              ],
            ),
          ],
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Divider(
              height: 1,
              color: AppUi.dividerOf(context).withValues(alpha: 0.6),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Total',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppUi.textPrimaryOf(context),
                ),
              ),
              Text(
                '\u20B1${totalWithDelivery.toStringAsFixed(2)}',
                style: TextStyle(
                  fontSize: 16.5,
                  fontWeight: FontWeight.w900,
                  color: AppUi.textPrimaryOf(context),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(BuildContext context, String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13.5,
            color: AppUi.textSecondaryOf(context),
            fontWeight: FontWeight.w500,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            color: AppUi.textPrimaryOf(context),
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
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
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
                    fontWeight: FontWeight.w800,
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
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
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
                      fontWeight: FontWeight.w800,
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
                      borderRadius: BorderRadius.circular(14),
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
        title: const Row(
          children: [
            Icon(
              Icons.local_shipping_outlined,
              color: AppUi.bluePrimary,
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
                color: AppUi.blueSoft,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '• Route Distance: ${dist.toStringAsFixed(2)} km',
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                  ),
                  Text(
                    '• Centralized Rate: ₱${rate.toStringAsFixed(2)} / km',
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                  ),
                  if (minFee > 0)
                    Text(
                      '• Minimum Delivery Fee: ₱${minFee.toStringAsFixed(2)}',
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                    ),
                  if (rounding == 'ceil')
                    const Text(
                      '• Rounding Rule: Round up to next whole km',
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                    )
                  else if (rounding == 'round')
                    const Text(
                      '• Rounding Rule: Round to nearest whole km',
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                    )
                  else
                    const Text(
                      '• Calculation: Exact proportional distance',
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                    ),
                  const Divider(height: 16),
                  Text(
                    'Final Delivery Fee: ₱${_deliveryFee.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: AppUi.bluePrimary,
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
        title: const Row(
          children: [
            Icon(
              Icons.info_outline_rounded,
              color: AppUi.bluePrimary,
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
        borderRadius: BorderRadius.circular(14),
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
                      fontSize: 12.5,
                      color: AppUi.textSecondaryOf(context),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '\u20B1${total.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
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
                  backgroundColor: const Color(0xFF88BA3A),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: const Color(
                    0xFF88BA3A,
                  ).withValues(alpha: 0.35),
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(26),
                  ),
                  elevation: 0,
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
                        'Confirm Refill',
                        style: TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w800,
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
            backgroundColor: Colors.redAccent,
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
          SnackBar(content: Text(msg), backgroundColor: Colors.redAccent),
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
            backgroundColor: Colors.redAccent,
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
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
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
                    ? const Color(0xFF334155)
                    : const Color(0xFFCBD5E1),
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
                  color: AppUi.blueSoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.account_balance_wallet_outlined,
                  color: AppUi.bluePrimary,
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
                        fontWeight: FontWeight.w800,
                        color: AppUi.textPrimaryOf(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '₱${widget.totalAmount.toStringAsFixed(2)} • ${widget.stationName}',
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
              color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(16),
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
                        color: Colors.redAccent,
                        size: 24,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Payment Unsuccessful',
                        style: TextStyle(
                          color: Colors.redAccent,
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
                    fontSize: 12.5,
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
                borderRadius: BorderRadius.circular(14),
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
                borderRadius: BorderRadius.circular(14),
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
