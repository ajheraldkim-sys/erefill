import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/constants.dart';
import '../../../core/routing/app_navigation.dart';
import '../../../core/widgets/app_ui_kit.dart';
import '../../../core/widgets/brand/axo_states.dart';
import '../../../core/widgets/brand/hero_header.dart';
import '../../../models/cart_model.dart';

import 'package:erefill/core/theme/app_colors.dart';

class CartScreen extends StatefulWidget {
  final Map<String, dynamic>? station;

  const CartScreen({super.key, this.station});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  SupabaseClient? get _supabase {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic>? _resolvedStation;

  // Null until the platform config loads, so the cart never shows an
  // invented fee. Checkout computes the exact distance-based fee.
  double? _ratePerKm;
  double? _minDeliveryFee;
  bool _deliveryFeeEnabled = true;

  @override
  void initState() {
    super.initState();
    _resolvedStation = widget.station;
    _loadDeliveryConfig();
    _resolveStationIfNeeded();
  }

  Future<void> _loadDeliveryConfig() async {
    final client = _supabase;
    if (client == null) return;
    try {
      final res = await client.rpc('get_delivery_fee_config');
      if (res is Map && mounted) {
        // Same keys checkout reads from get_delivery_fee_config
        // (`minimum_fee`, `enabled`), so cart and checkout always agree.
        setState(() {
          _ratePerKm = (res['rate_per_km'] as num?)?.toDouble();
          _minDeliveryFee = (res['minimum_fee'] as num?)?.toDouble();
          _deliveryFeeEnabled = res['enabled'] != false;
        });
      }
    } catch (_) {}
  }

  Future<void> _resolveStationIfNeeded() async {
    if (_resolvedStation != null) return;
    final cart = context.read<CartProvider>();
    final sId = cart.stationId;
    if (sId == null || sId.isEmpty) return;

    final client = _supabase;
    if (client == null) return;

    try {
      final res = await client
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

  Future<void> _confirmClearCart() async {
    final confirmed = await showAppConfirmDialog(
      context,
      title: 'Clear cart?',
      message: 'All items from this station will be removed.',
      confirmLabel: 'Clear cart',
      destructive: true,
    );
    if (confirmed && mounted) {
      context.read<CartProvider>().clearCart();
    }
  }

  void _removeWithUndo(CartProvider cart, CartItem item) {
    cart.removeItem(item.id);
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text('${item.name} removed'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            cart.addItem(item.id, item.name, item.price, imageUrl: item.imageUrl);
            if (item.quantity > 1) {
              cart.updateQuantity(item.id, item.quantity);
            }
          },
        ),
      ),
    );
  }

  /// Lowest delivery fee the customer could pay, or null when unknown.
  double? get _deliveryFeeFloor {
    if (!_deliveryFeeEnabled) return 0;
    return _minDeliveryFee;
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
            title: 'Cart',
            subtitle: cart.stationName ?? 'Your selected items',
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              tooltip: 'Back',
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            actions: [
              if (hasItems)
                IconButton(
                  icon: const Icon(Icons.delete_sweep_outlined),
                  tooltip: 'Clear cart',
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
                      message:
                          'Browse water refilling stations to add fresh water, containers, or accessories.',
                      actionLabel: 'Browse stations',
                      onAction: () {
                        if (Navigator.of(context).canPop()) {
                          Navigator.of(context).pop();
                        } else {
                          context.openStationList();
                        }
                      },
                    ),
                  )
                : ResponsiveCenter(
                    maxWidth: AppBreakpoints.formMaxWidth,
                    child: ListView(
                      padding: AppUi.pagePadding.copyWith(top: AppUi.spacingMd),
                      children: [
                        _StationStrip(
                          name: cart.stationName ?? 'Water Station',
                          itemCount: cart.totalItems,
                        ),
                        const SizedBox(height: AppUi.spacingLg),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Items',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            TextButton.icon(
                              onPressed: () {
                                if (Navigator.of(context).canPop()) {
                                  Navigator.of(context).pop();
                                } else {
                                  context.openStationList();
                                }
                              },
                              icon: const Icon(Icons.add_rounded, size: 18),
                              label: const Text('Add more'),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppUi.spacingXs),
                        ...itemsList.map(
                          (item) => Padding(
                            padding: const EdgeInsets.only(
                              bottom: AppUi.spacingSm,
                            ),
                            child: _CartLineItem(
                              item: item,
                              onQuantityChanged: (q) =>
                                  cart.updateQuantity(item.id, q),
                              onRemove: () => _removeWithUndo(cart, item),
                            ),
                          ),
                        ),
                        const SizedBox(height: AppUi.spacingLg),
                        AppCard(child: _buildSummary(cart)),
                      ],
                    ),
                  ),
          ),
          if (hasItems) _buildBottomBar(context, cart),
        ],
      ),
    );
  }

  Widget _buildSummary(CartProvider cart) {
    final floor = _deliveryFeeFloor;
    final String? deliveryNote;
    if (!_deliveryFeeEnabled) {
      deliveryNote = null;
    } else if (_ratePerKm != null) {
      deliveryNote =
          '${formatPeso(_ratePerKm)}/km from the station · exact fee set at checkout';
    } else {
      deliveryNote = 'Based on distance to your delivery address';
    }

    return PriceBreakdown(
      title: 'Order summary',
      lines: [
        PriceLine(
          label:
              'Subtotal (${cart.totalItems} item${cart.totalItems == 1 ? '' : 's'})',
          amount: cart.totalAmount,
        ),
        PriceLine(
          label: _deliveryFeeEnabled ? 'Delivery fee' : 'Delivery',
          amount: _deliveryFeeEnabled ? null : 0,
          placeholder: floor != null && floor > 0
              ? 'from ${formatPeso(floor)}'
              : 'At checkout',
          note: deliveryNote,
        ),
      ],
      totalLabel: 'Estimated total',
      total: cart.totalAmount + (floor ?? 0),
    );
  }

  Widget _buildBottomBar(BuildContext context, CartProvider cart) {
    final estimate = cart.totalAmount + (_deliveryFeeFloor ?? 0);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppUi.surfaceOf(context),
        border: Border(top: BorderSide(color: AppUi.borderOf(context))),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Estimated total',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      formatPeso(estimate),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppUi.textPrimaryOf(context),
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppUi.spacingMd),
              FilledButton.icon(
                onPressed: _proceedToCheckout,
                iconAlignment: IconAlignment.end,
                icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                label: const Text('Checkout'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StationStrip extends StatelessWidget {
  final String name;
  final int itemCount;

  const _StationStrip({required this.name, required this.itemCount});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppUi.brandSoftOf(context),
              borderRadius: AppUi.controlRadius,
            ),
            child: Icon(
              Icons.storefront_rounded,
              color: AppUi.onBrandSoftOf(context),
              size: 20,
            ),
          ),
          const SizedBox(width: AppUi.spacingMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 2),
                Text(
                  '$itemCount item${itemCount == 1 ? '' : 's'} · one station per order',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CartLineItem extends StatelessWidget {
  final CartItem item;
  final ValueChanged<int> onQuantityChanged;
  final VoidCallback onRemove;

  const _CartLineItem({
    required this.item,
    required this.onQuantityChanged,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final name = item.name.toLowerCase();
    final isAccessory = name.contains('container') ||
        name.contains('cap') ||
        name.contains('accessory');
    final accent = isAccessory
        ? (AppUi.isDark(context)
              ? const Color(0xFFC4B5FD)
              : AppColors.statusPreparing)
        : AppUi.brandOf(context);

    return AppCard(
      padding: const EdgeInsets.all(AppUi.spacingMd),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: AppUi.isDark(context) ? 0.16 : 0.1),
              borderRadius: AppUi.controlRadius,
            ),
            child: Icon(
              isAccessory ? Icons.inventory_2_outlined : Icons.water_drop_rounded,
              color: accent,
              size: 22,
            ),
          ),
          const SizedBox(width: AppUi.spacingMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 2),
                Text(
                  '${formatPeso(item.price)} each',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: AppUi.spacingXs),
                Text(
                  formatPeso(item.price * item.quantity),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppUi.textPrimaryOf(context),
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppUi.spacingSm),
          QuantitySelector(
            value: item.quantity,
            itemLabel: item.name,
            onChanged: onQuantityChanged,
            onRemove: onRemove,
          ),
        ],
      ),
    );
  }
}
