import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/utils/profile_query_helpers.dart';
import '../../../core/constants.dart';
import '../../../core/widgets/erefill_header.dart';
import '../../../core/widgets/brand/axo_states.dart';
import 'widgets/payment_method_selector.dart';
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
  String _paymentMethod = 'cod';
  List<CheckoutPaymentOption> _paymentMethods = [];
  Map<String, dynamic>? _customerProfile;
  List<Map<String, dynamic>> _savedAddresses = [];
  String? _selectedAddressId;
  double _deliveryFee = 25.0;
  Map<String, dynamic>? _platformFeeConfig;
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
    _loadInitialData();
  }

  @override
  void dispose() {
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
    final ownerId = widget.station['id']?.toString();
    if (ownerId == null || ownerId.isEmpty) return;

    try {
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
        if (!CheckoutRules.isPaymentAvailable(_paymentMethod, options)) {
          _paymentMethod = availableOptions.isEmpty
              ? ''
              : availableOptions.first.type;
        }
      });
    } catch (e) {
      debugPrint('Error loading payment methods: $e. Defaulting to Cash on Delivery (COD).');
      if (!mounted) return;
      final fallbackOptions = CheckoutRules.normalizePaymentOptions([
        {'method': 'cod', 'available': true}
      ]);
      setState(() {
        _paymentMethods = fallbackOptions;
        _paymentMethod = 'cod';
      });
    }
  }

  Future<void> _loadStationSettings() async {
    try {
      final ownerId = widget.station['id']?.toString();
      if (ownerId == null) return;

      final settings = await supabase
          .from('owner_settings')
          .select('base_delivery_fee')
          .eq('owner_id', ownerId)
          .maybeSingle();

      if (settings != null && mounted) {
        setState(() {
          _deliveryFee =
              (settings['base_delivery_fee'] as num?)?.toDouble() ?? 25.0;
        });
      }
    } catch (e) {
      debugPrint('Error loading station settings: $e');
    }
  }

  Future<void> _loadPlatformFeeConfig() async {
    try {
      final cfg = await supabase.rpc('get_platform_fee_config');
      if (!mounted) return;
      setState(() {
        _platformFeeConfig = Map<String, dynamic>.from(cfg as Map);
      });
    } catch (e) {
      debugPrint('Platform fee config unavailable: $e');
    }
  }

  double _platformFeeFor(double subtotal) {
    final cfg = _platformFeeConfig;
    if (cfg == null || cfg['enabled'] != true) return 0;
    final percent = (cfg['percent'] as num?)?.toDouble() ?? 0;
    final fixed = (cfg['fixed'] as num?)?.toDouble() ?? 0;
    final base = subtotal + _deliveryFee;
    final fee = (base * percent / 100) + fixed;
    if (fee <= 0) return 0;
    return double.parse(fee.toStringAsFixed(2));
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
                    Icon(Icons.local_offer_rounded, color: AppUi.bluePrimary, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Select Reward Voucher',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
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
                        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: const Color(0xFF10B981).withValues(alpha: 0.1),
                          child: const Icon(
                            Icons.check_rounded,
                            color: Color(0xFF10B981),
                            size: 18,
                          ),
                        ),
                        title: Text(
                          v.title,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                        ),
                        subtitle: Text(
                          v.description,
                          style: const TextStyle(fontSize: 11, color: Colors.grey),
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
      final profile = await ProfileQueryHelpers.fetchProfile(
        supabase,
        customerId,
      );

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
        _stationAvailabilityMessage = availability['status'] != 'OK'
            ? availability['message']?.toString() ??
                  'This station is not available for your location right now.'
            : null;
        _checkingStationAvailability = false;
      });
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

    final totalAmount = (cart.totalAmount +
            _deliveryFee +
            _platformFeeFor(cart.totalAmount) -
            voucherDiscount)
        .clamp(0.0, double.infinity);

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

    setState(() {
      _isSubmitting = true;
      _checkoutHint = null;
    });
    try {
      if (paymentMethod == null) {
        throw StateError('Selected payment method is not available.');
      }

      final notesText = _appliedVoucher != null
          ? '${_notesController.text.trim()} [Voucher: ${_appliedVoucher!.code} -₱${voucherDiscount.toStringAsFixed(2)}]'.trim()
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
        'idempotency_key': const Uuid().v4(),
        'subtotal': cart.totalAmount,
        'delivery_fee': _deliveryFee,
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

      if (CheckoutRules.isOnlinePayment(paymentMethod)) {
        try {
          final checkoutUrl = await _createOnlinePaymentCheckout(
            orderId: orderId,
            paymentMethod: paymentMethod,
          );
          if (!mounted) return;
          final launched = await PaymentLaunchService.launchCheckoutUrl(checkoutUrl);
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
      if (_appliedVoucher != null && customerId != null && customerId.isNotEmpty) {
        _loyaltyService.markVoucherUsed(
          voucherId: _appliedVoucher!.id,
          userId: customerId,
        );
      }
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
      context.replaceOrderTracker(orderRecord);
    } catch (e) {
      debugPrint('Checkout submission failed: $e');
      final errStr = e.toString().toLowerCase();
      final isOfflineLikely = errStr.contains('socket') ||
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
            notes: _notesController.text.trim(),
          );

          cart.clearCart();
          if (_appliedVoucher != null && userId.isNotEmpty) {
            _loyaltyService.markVoucherUsed(
              voucherId: _appliedVoucher!.id,
              userId: userId,
            );
          }
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
              'status': 'pending',
              'created_at': DateTime.now().toIso8601String(),
              'items': itemsData,
              'is_offline_queued': true,
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
  }) async {
    final normalizedMethod = paymentMethod.trim().toLowerCase().replaceAll('paymaya', 'maya');
    final response = await supabase.functions.invoke(
      'create-payment-checkout',
      body: {'order_id': orderId, 'payment_method': normalizedMethod},
    );

    final data = response.data;
    if (data is Map && data['checkout_url'] is String) {
      return data['checkout_url'] as String;
    }
    throw Exception('Payment checkout was not created.');
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
                  content: Text('Payment verified! Tracking your refill order.'),
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
      fallback: 'Online payment could not be processed. Retry payment to continue your order.',
    );

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: const [
            Icon(Icons.error_outline, color: Colors.redAccent),
            SizedBox(width: 8),
            Text('Payment Notice', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
      final launched = await PaymentLaunchService.launchCheckoutUrl(checkoutUrl);
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
    final totalWithDelivery = (cart.totalAmount +
            _deliveryFee +
            platformFee -
            voucherDiscount)
        .clamp(0.0, double.infinity);
    final textTheme = Theme.of(context).textTheme;
    final paymentOptions = _selectablePaymentMethods;
    final profileReady = CheckoutRules.isDeliveryProfileReady(_customerProfile);
    final deliveryIssue = CheckoutRules.deliveryProfileIssue(_customerProfile);
    final bannerMessage =
        _checkoutHint ??
        (_checkingStationAvailability
            ? 'Checking station availability…'
            : deliveryIssue ?? _stationAvailabilityMessage);
    final stationName =
        widget.station['station_name']?.toString() ??
        widget.station['name']?.toString() ??
        'Water Station';

    if (cart.items.isEmpty && !_isBootstrapping) {
      return Scaffold(
        backgroundColor: AppUi.pageBgOf(context),
        appBar: const ERefillHeader(
          title: 'Confirm Refill',
          subtitle: 'Review delivery, summary & payment',
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: const BoxDecoration(
                    color: AppUi.blueSoft,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.shopping_cart_outlined,
                    color: AppUi.bluePrimary,
                    size: 36,
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
      appBar: const ERefillHeader(
        title: 'Confirm Refill',
        subtitle: 'Review delivery, summary & payment',
      ),
      body: _isBootstrapping
          ? const AxoLoader(message: 'Loading checkout...')
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Alert Banner (if any)
                  if (bannerMessage != null) ...[
                    _checkoutBanner(bannerMessage),
                    const SizedBox(height: 16),
                  ],

                  // ── 1. DELIVERY ADDRESS ──────────────────────────
                  KeyedSubtree(
                    key: _deliverySectionKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _sectionTitle('Delivery Address'),
                            TextButton(
                              style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              onPressed: _openAddressSetup,
                              child: Text(
                                profileReady ? 'Change' : 'Add',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                  color: AppUi.bluePrimary,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: const BoxDecoration(
                                color: AppUi.blueSoft,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.location_on_rounded,
                                color: AppUi.bluePrimary,
                                size: 19,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    profileReady
                                        ? (_customerProfile?['complete_address'] ??
                                                  'Address not set')
                                              .toString()
                                        : 'Add your delivery address to continue',
                                    style: textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                      color: profileReady
                                          ? AppUi.textPrimaryOf(context)
                                          : AppUi.textSecondary,
                                    ),
                                  ),
                                  if (profileReady) ...[
                                    const SizedBox(height: 3),
                                    Text(
                                      '${_customerProfile?['barangay'] ?? ''}, ${_customerProfile?['town'] ?? ''}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: AppUi.textSecondaryOf(context),
                                      ),
                                    ),
                                    if ((_customerProfile?['landmark']
                                            ?.toString()
                                            .isNotEmpty ??
                                        false)) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        'Landmark: ${_customerProfile!['landmark']}',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: AppUi.textMuted,
                                        ),
                                      ),
                                    ],
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                        if (_savedAddresses.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: _savedAddresses.map((address) {
                                final id = address['id']?.toString();
                                final isSelected = id == _selectedAddressId;
                                return Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: ChoiceChip(
                                    label: Text(
                                      address['label']?.toString() ?? 'Address',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: isSelected
                                            ? FontWeight.w700
                                            : FontWeight.w500,
                                      ),
                                    ),
                                    selected: isSelected,
                                    onSelected: (_) =>
                                        _selectSavedAddress(address),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  _sectionDivider(context),

                  // ── 2. REFILL SUMMARY ───────────────────────────
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          _sectionTitle('Refill Summary'),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                const Icon(
                                  Icons.storefront_rounded,
                                  size: 14,
                                  color: AppUi.textMuted,
                                ),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    stationName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: AppUi.textMuted,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ...cart.items.values.map(
                        (item) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: AppUi.blueSoft,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '${item.quantity}\u00D7',
                                  style: const TextStyle(
                                    color: AppUi.bluePrimary,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  item.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                              Text(
                                '\u20B1${(item.price * item.quantity).toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Divider(
                          height: 1,
                          color: AppUi.dividerOf(
                            context,
                          ).withValues(alpha: 0.6),
                        ),
                      ),
                      const SizedBox(height: 8),
                      _amountRow(
                        'Subtotal',
                        '\u20B1${cart.totalAmount.toStringAsFixed(2)}',
                        muted: true,
                      ),
                      _amountRow(
                        'Delivery fee',
                        '\u20B1${_deliveryFee.toStringAsFixed(2)}',
                        muted: true,
                      ),
                      if (platformFee > 0)
                        _amountRow(
                          'Service fee',
                          '\u20B1${platformFee.toStringAsFixed(2)}',
                          muted: true,
                          onInfo: () {
                            showDialog(
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
                                    Text(
                                      'What is this fee?',
                                      style: TextStyle(fontSize: 16),
                                    ),
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
                          },
                        ),
                      if (_appliedVoucher != null)
                        _amountRow(
                          'Reward Voucher (${_appliedVoucher!.title})',
                          '-\u20B1${voucherDiscount.toStringAsFixed(2)}',
                          muted: true,
                          valueColor: const Color(0xFF10B981),
                        ),
                      // Voucher selection card
                      Container(
                        margin: const EdgeInsets.only(top: 6, bottom: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: _appliedVoucher != null
                              ? const Color(0xFF10B981).withValues(alpha: 0.08)
                              : AppUi.surfaceOf(context),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: _appliedVoucher != null
                                ? const Color(0xFF10B981)
                                : AppUi.borderOf(context),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.local_offer_outlined,
                              size: 16,
                              color: _appliedVoucher != null
                                  ? const Color(0xFF10B981)
                                  : AppUi.bluePrimary,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _appliedVoucher != null
                                    ? 'Applied: ${_appliedVoucher!.title}'
                                    : (_availableVouchers.isEmpty
                                        ? 'No reward vouchers available'
                                        : '${_availableVouchers.length} reward voucher(s) available'),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: _appliedVoucher != null
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: _appliedVoucher != null
                                      ? const Color(0xFF10B981)
                                      : null,
                                ),
                              ),
                            ),
                            if (_appliedVoucher != null)
                              InkWell(
                                onTap: () => setState(() => _appliedVoucher = null),
                                child: const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  child: Text(
                                    'Remove',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.redAccent,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              )
                            else if (_availableVouchers.isNotEmpty)
                              InkWell(
                                onTap: _showSelectVoucherSheet,
                                child: const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  child: Text(
                                    'Apply',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      color: AppUi.bluePrimary,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Divider(
                          height: 1,
                          color: AppUi.dividerOf(
                            context,
                          ).withValues(alpha: 0.6),
                        ),
                      ),
                      const SizedBox(height: 4),
                      _amountRow(
                        'Total',
                        '\u20B1${totalWithDelivery.toStringAsFixed(2)}',
                        bold: true,
                      ),
                    ],
                  ),

                  _sectionDivider(context),

                  // ── 3. PAYMENT METHOD ───────────────────────────
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _sectionTitle('Payment Method'),
                      const SizedBox(height: 10),
                      PaymentMethodSelector(
                        selectedMethod: _paymentMethod,
                        methods: paymentOptions,
                        onSelected: (method) {
                          setState(() => _paymentMethod = method);
                        },
                      ),
                      if (_paymentMethod != 'cod') ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 9,
                          ),
                          decoration: BoxDecoration(
                            color: AppUi.blueSoft.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Row(
                            children: [
                              Icon(
                                Icons.lock_outline_rounded,
                                size: 14,
                                color: AppUi.bluePrimary,
                              ),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'You will complete payment securely via PayMongo after placing your order.',
                                  style: TextStyle(
                                    color: AppUi.bluePrimary,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),

                  _sectionDivider(context),

                  // ── 4. DELIVERY NOTES ───────────────────────────
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          _sectionTitle('Delivery Notes'),
                          const SizedBox(width: 6),
                          Text(
                            '(optional)',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppUi.textSecondaryOf(context),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      AppFormField(
                        controller: _notesController,
                        label: 'Special Instructions',
                        hintText:
                            'e.g. Leave at front gate, call upon arrival...',
                        prefixIcon: Icons.notes_rounded,
                        maxLines: 2,
                        compact: true,
                      ),
                    ],
                  ),

                  const SizedBox(height: 36),
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
                  !_checkingStationAvailability,
              onConfirm: () => _confirmOrder(cart),
            ),
    );
  }

  // ── helper widgets ────────────────────────────────────────────────────────

  Widget _sectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.2,
      ),
    );
  }

  Widget _sectionDivider(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Divider(
        height: 1,
        color: AppUi.dividerOf(context).withValues(alpha: 0.6),
      ),
    );
  }

  Widget _amountRow(
    String label,
    String value, {
    bool muted = false,
    bool bold = false,
    Color? valueColor,
    VoidCallback? onInfo,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: muted ? AppUi.textSecondary : null,
                  fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
                  fontSize: bold ? 15 : 13,
                ),
              ),
              if (onInfo != null) ...[
                const SizedBox(width: 5),
                GestureDetector(
                  onTap: onInfo,
                  child: const Icon(
                    Icons.info_outline_rounded,
                    size: 15,
                    color: AppUi.textMuted,
                  ),
                ),
              ],
            ],
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: bold ? FontWeight.w900 : FontWeight.w700,
              fontSize: bold ? 16 : 13,
              color: valueColor ?? (bold ? AppUi.bluePrimary : null),
            ),
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
        borderRadius: BorderRadius.circular(12),
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
    final latitude = (address['latitude'] as num?)?.toDouble();
    final longitude = (address['longitude'] as num?)?.toDouble();
    if (latitude == null || longitude == null) {
      _setCheckoutHint(
        'This address has no map pin. Tap "Change" to edit and set its location.',
      );
      return;
    }
    setState(() {
      _selectedAddressId = address['id']?.toString();
      _customerProfile = CheckoutRules.useSavedAddress(
        _customerProfile ?? const {},
        address,
      );
      _checkoutHint = null;
    });
    _refreshStationAvailability();
  }
}

// ── private reusable widgets ───────────────────────────────────────────────

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
                    'Total to pay',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppUi.textSecondaryOf(context),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '\u20B1${total.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            SizedBox(
              height: 48,
              child: FilledButton(
                onPressed: canSubmit ? onConfirm : null,
                style: FilledButton.styleFrom(
                  backgroundColor: AppUi.bluePrimary,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: AppUi.bluePrimary.withValues(
                    alpha: 0.35,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
                child: isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      )
                    : const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Confirm Refill',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          SizedBox(width: 6),
                          Icon(Icons.arrow_forward_rounded, size: 18),
                        ],
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
  State<_PaymentVerificationModal> createState() => _PaymentVerificationModalState();
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
            final status = (newRecord['payment_status'] ?? '').toString().toLowerCase();
            if (mounted) {
              setState(() {
                _paymentStatus = status;
              });
            }
            if (status == 'success' || status == 'paid' || status == 'succeeded') {
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
      final record = await _supabase
          .from('orders')
          .select()
          .eq('id', widget.orderId)
          .single();

      final status = (record['payment_status'] ?? '').toString().toLowerCase();
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
            content: Text(FriendlyErrors.message(e, fallback: 'Could not check payment status.')),
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
      final normalizedMethod = widget.paymentMethod.trim().toLowerCase().replaceAll('paymaya', 'maya');
      final response = await _supabase.functions.invoke(
        'create-payment-checkout',
        body: {
          'order_id': widget.orderId,
          'payment_method': normalizedMethod,
          // The saved URL could not be opened, so request a clean session
          // instead of receiving the same inaccessible checkout again.
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
      throw Exception('Could not reopen payment checkout.');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(FriendlyErrors.message(e, fallback: 'Could not reopen payment checkout.')),
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
                color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
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
                      const Icon(Icons.cancel, color: Colors.redAccent, size: 24),
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
                          valueColor: AlwaysStoppedAnimation<Color>(AppUi.bluePrimary),
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
