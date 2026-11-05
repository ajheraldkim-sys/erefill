import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants.dart';
import '../../../../core/models/cart_model.dart';
import '../../../../core/utils/money.dart';
import '../../owner/services/accessory_repository.dart';

/// "Add-ons & accessories" on a station page: empty gallons, caps, seals,
/// dispensers… added to the same cart as the station's water.
class StationAccessoriesSection extends StatefulWidget {
  const StationAccessoriesSection({
    super.key,
    required this.stationId,
    required this.stationName,
    this.repository,
  });

  final String stationId;
  final String? stationName;
  final AccessoryRepository? repository;

  @override
  State<StationAccessoriesSection> createState() =>
      _StationAccessoriesSectionState();
}

class _StationAccessoriesSectionState extends State<StationAccessoriesSection> {
  late final AccessoryRepository _repo =
      widget.repository ?? SupabaseAccessoryRepository();
  List<Accessory> _items = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final all = await _repo.list(widget.stationId);
      if (!mounted) return;
      setState(() => _items = [for (final a in all) if (a.isAvailable) a]);
    } catch (e) {
      debugPrint('Accessories unavailable: $e');
    }
  }

  void _change(CartProvider cart, Accessory a, int delta) {
    final current = cart.items[a.id]?.quantity ?? 0;
    final next = (current + delta).clamp(0, a.stock);
    if (next == current) return;

    if (delta > 0 &&
        cart.totalItems > 0 &&
        cart.stationId != null &&
        cart.stationId != widget.stationId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Your cart has items from another station. Check out or clear it first.',
          ),
        ),
      );
      return;
    }
    if (current == 0) {
      cart.setStation(widget.stationId, widget.stationName);
      cart.addItem(a.id, a.name, a.price, kind: 'accessory');
    } else {
      cart.updateQuantity(a.id, next);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) return const SizedBox.shrink();
    final cart = context.watch<CartProvider>();
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Add-ons & accessories', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        for (final a in _items)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppUi.surfaceOf(context),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppUi.borderOf(context)),
            ),
            child: Row(
              children: [
                Icon(Accessory.iconFor(a.category), color: AppUi.brandOf(context)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(a.name, style: theme.textTheme.titleSmall),
                      Text(
                        a.inStock ? formatPeso(a.price) : 'Sold out',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                if (a.inStock) ...[
                  if ((cart.items[a.id]?.quantity ?? 0) > 0) ...[
                    IconButton(
                      tooltip: 'Remove one ${a.name}',
                      icon: const Icon(Icons.remove_circle_outline_rounded),
                      onPressed: () => _change(cart, a, -1),
                    ),
                    Text(
                      '${cart.items[a.id]!.quantity}',
                      style: theme.textTheme.titleSmall,
                    ),
                  ],
                  IconButton(
                    tooltip: 'Add ${a.name}',
                    icon: Icon(
                      Icons.add_circle_rounded,
                      color: AppUi.brandOf(context),
                    ),
                    onPressed: () => _change(cart, a, 1),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}
