import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/constants.dart';
import '../../../core/routing/app_navigation.dart';
import '../../../core/widgets/brand/axo_states.dart';
import '../../../core/widgets/brand/hero_header.dart';
import '../../../models/cart_model.dart';

class CartScreen extends StatefulWidget {
  final Map<String, dynamic>? station;

  const CartScreen({super.key, this.station});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  final _supabase = Supabase.instance.client;
  Map<String, dynamic>? _resolvedStation;
  double _ratePerKm = 10.0;
  double _minDeliveryFee = 20.0;
  bool _deliveryFeeEnabled = true;

  @override
  void initState() {
    super.initState();
    _resolvedStation = widget.station;
    _loadDeliveryConfig();
    _resolveStationIfNeeded();
  }

  Future<void> _loadDeliveryConfig() async {
    try {
      final res = await _supabase.rpc('get_delivery_fee_config');
      if (res is Map && mounted) {
        setState(() {
          _ratePerKm = (res['rate_per_km'] as num?)?.toDouble() ?? _ratePerKm;
          _minDeliveryFee = (res['min_delivery_fee'] as num?)?.toDouble() ?? _minDeliveryFee;
          _deliveryFeeEnabled = res['is_enabled'] != false;
        });
      }
    } catch (_) {}
  }

  Future<void> _resolveStationIfNeeded() async {
    if (_resolvedStation != null) return;
    final cart = context.read<CartProvider>();
    final sId = cart.stationId;
    if (sId == null || sId.isEmpty) return;

    try {
      final res = await _supabase
          .from('profiles')
          .select(
            'id, station_name, complete_address, town, barangay, latitude, longitude, lat, lng, price_per_gallon, primary_water_type, is_open, station_availability',
          )
          .eq('id', sId)
          .maybeSingle();

      if (mounted && res != null) {
        setState(() {
          _resolvedStation = Map<String, dynamic>.from(res);
        });
      }
    } catch (e) {
      debugPrint('Error resolving station for cart: $e');
    }
  }

  void _proceedToCheckout() {
    final cart = context.read<CartProvider>();
    if (cart.totalItems == 0) return;

    final stationData = _resolvedStation ??
        {
          'id': cart.stationId,
          'station_name': cart.stationName ?? 'Water Station',
        };

    context.openCheckout(stationData);
  }

  void _confirmClearCart() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppUi.surfaceOf(ctx),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Clear Cart?',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        content: const Text('Are you sure you want to remove all items from your cart?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              context.read<CartProvider>().clearCart();
            },
            child: const Text('Clear Cart'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();
    final itemsList = cart.items.values.toList();
    final hasItems = itemsList.isNotEmpty;

    return Scaffold(
      backgroundColor: AppUi.pageBgOf(context),
      body: Column(
        children: [
          TabScreenHeroHeader(
            title: 'Shopping Cart',
            subtitle: cart.stationName ?? 'Your selected items',
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            actions: [
              if (hasItems)
                IconButton(
                  icon: const Icon(Icons.delete_sweep_outlined),
                  tooltip: 'Clear Cart',
                  onPressed: _confirmClearCart,
                ),
            ],
          ),
          Expanded(
            child: !hasItems
                ? Center(
                    child: AxoEmptyState(
                      pose: AxoPose.empty,
                      title: 'Your cart is empty',
                      message: 'Browse water refilling stations to add fresh water, containers, or accessories.',
                      actionLabel: 'Browse Stations',
                      onAction: () {
                        if (Navigator.of(context).canPop()) {
                          Navigator.of(context).pop();
                        } else {
                          context.openStationList();
                        }
                      },
                    ),
                  )
                : ListView(
                    padding: AppUi.pagePadding.copyWith(top: 14, bottom: 24),
                    children: [
                      // Station Header Banner
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: AppUi.blueSoft,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: AppUi.bluePrimary.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppUi.bluePrimary,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.storefront_rounded,
                                color: Colors.white,
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    cart.stationName ?? 'Water Station',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 15,
                                      color: AppUi.textPrimaryOf(context),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Single-station order · ${cart.totalItems} item${cart.totalItems > 1 ? "s" : ""}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AppUi.textSecondaryOf(context),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Cart Items List
                      ...itemsList.map((item) => _buildCartItemCard(context, cart, item)),

                      const SizedBox(height: 16),

                      // Order Summary Breakdown
                      _buildSummaryCard(context, cart),
                    ],
                  ),
          ),
          if (hasItems) _buildBottomBar(context, cart),
        ],
      ),
    );
  }

  Widget _buildCartItemCard(BuildContext context, CartProvider cart, CartItem item) {
    final lineTotal = item.price * item.quantity;
    final isContainerOrCap = item.name.toLowerCase().contains('container') ||
        item.name.toLowerCase().contains('cap') ||
        item.name.toLowerCase().contains('accessory');

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppUi.surfaceOf(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppUi.borderOf(context)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Item Icon
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: isContainerOrCap
                  ? const Color(0xFFF3E8FF)
                  : AppUi.bluePrimary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              isContainerOrCap
                  ? Icons.inventory_2_outlined
                  : Icons.water_drop_rounded,
              color: isContainerOrCap
                  ? const Color(0xFF8B5CF6)
                  : AppUi.bluePrimary,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),

          // Name & Unit Price
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: AppUi.textPrimaryOf(context),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '₱${item.price.toStringAsFixed(2)} each',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppUi.textSecondaryOf(context),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),

          // Stepper & Remove Action
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Quantity Stepper
              Container(
                decoration: BoxDecoration(
                  color: AppUi.surfaceRaisedOf(context),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppUi.borderOf(context)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove, size: 16),
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.all(4),
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        cart.updateQuantity(item.id, item.quantity - 1);
                      },
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Text(
                        '${item.quantity}',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                          color: AppUi.textPrimaryOf(context),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add, size: 16),
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.all(4),
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        cart.updateQuantity(item.id, item.quantity + 1);
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),

              // Line total
              SizedBox(
                width: 65,
                child: Text(
                  '₱${lineTotal.toStringAsFixed(0)}',
                  textAlign: TextAlign.end,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                    color: AppUi.bluePrimary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(BuildContext context, CartProvider cart) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppUi.surfaceOf(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppUi.borderOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Order Breakdown',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 15,
              color: AppUi.textPrimaryOf(context),
            ),
          ),
          const SizedBox(height: 12),
          _summaryRow(
            'Items Subtotal (${cart.totalItems} items)',
            '₱${cart.totalAmount.toStringAsFixed(2)}',
            context,
          ),
          const SizedBox(height: 8),
          _summaryRow(
            'Centralized Delivery Fee',
            _deliveryFeeEnabled
                ? '₱${_minDeliveryFee.toStringAsFixed(2)} min (₱${_ratePerKm.toStringAsFixed(0)}/km)'
                : 'Free',
            context,
            isDelivery: true,
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Divider(height: 1),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Total Estimated',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                  color: AppUi.textPrimaryOf(context),
                ),
              ),
              Text(
                '₱${(cart.totalAmount + (_deliveryFeeEnabled ? _minDeliveryFee : 0)).toStringAsFixed(2)}',
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                  color: AppUi.bluePrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Exact distance and final fee verified at checkout based on your delivery address.',
            style: TextStyle(
              fontSize: 11,
              color: AppUi.textSecondaryOf(context),
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value, BuildContext context, {bool isDelivery = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: AppUi.textSecondaryOf(context),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: isDelivery ? AppUi.bluePrimary : AppUi.textPrimaryOf(context),
          ),
        ),
      ],
    );
  }

  Widget _buildBottomBar(BuildContext context, CartProvider cart) {
    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 14,
        bottom: MediaQuery.of(context).padding.bottom + 12,
      ),
      decoration: BoxDecoration(
        color: AppUi.surfaceOf(context),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: Row(
        children: [
          // Continue Shopping Button
          Expanded(
            flex: 2,
            child: OutlinedButton(
              onPressed: () {
                if (Navigator.of(context).canPop()) {
                  Navigator.of(context).pop();
                } else {
                  context.openStationList();
                }
              },
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                side: BorderSide(color: AppUi.borderOf(context)),
              ),
              child: const Text(
                'Add More',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Proceed to Checkout Button
          Expanded(
            flex: 3,
            child: FilledButton(
              onPressed: _proceedToCheckout,
              style: FilledButton.styleFrom(
                backgroundColor: AppUi.bluePrimary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'Checkout',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Icon(Icons.arrow_forward_rounded, size: 18),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
