import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/constants.dart';
import '../../../../core/theme/app_colors.dart';

/// Shows customers where a station delivers for free and what it costs
/// elsewhere. Hidden if the coverage cannot be loaded.
class DeliveryCoverageCard extends StatefulWidget {
  const DeliveryCoverageCard({super.key, required this.stationId});

  final String stationId;

  static String _n(num v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  /// Plain-language lines, free rules first.
  static List<String> describe({
    required double radiusKm,
    required List<String> barangays,
    required int? minGallons,
    required double ratePerKm,
    required double minimumFee,
  }) {
    final free = <String>[
      if (radiusKm > 0) 'Free within ${radiusKm.toStringAsFixed(1)} km of the station',
      if (barangays.isNotEmpty) 'Free to ${([...barangays]..sort()).join(', ')}',
      if (minGallons != null) 'Free for orders of $minGallons+ gallons',
    ];
    final rate = '₱${_n(ratePerKm)}/km'
        '${minimumFee > 0 ? ', ₱${_n(minimumFee)} minimum' : ''}';
    return [
      ...free,
      free.isEmpty ? 'Delivery: $rate' : 'Elsewhere: $rate',
    ];
  }

  @override
  State<DeliveryCoverageCard> createState() => _DeliveryCoverageCardState();
}

class _DeliveryCoverageCardState extends State<DeliveryCoverageCard> {
  List<String>? _lines;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final db = Supabase.instance.client;
      final zone = await db
          .from('owner_settings')
          .select(
            'free_delivery_radius_km, free_delivery_barangays, free_delivery_min_gallons',
          )
          .eq('owner_id', widget.stationId)
          .maybeSingle();
      final cfgRow = await db
          .from('system_config')
          .select('value')
          .eq('key', 'delivery_fee_config')
          .maybeSingle();
      final cfg = (cfgRow?['value'] as Map?) ?? const {};
      if (!mounted) return;
      setState(() {
        _lines = DeliveryCoverageCard.describe(
          radiusKm: (zone?['free_delivery_radius_km'] as num?)?.toDouble() ?? 1.0,
          barangays: [
            for (final b in (zone?['free_delivery_barangays'] as List? ?? []))
              b.toString(),
          ],
          minGallons: (zone?['free_delivery_min_gallons'] as num?)?.toInt(),
          ratePerKm: (cfg['rate_per_km'] as num?)?.toDouble() ?? 10,
          minimumFee: (cfg['minimum_fee'] as num?)?.toDouble() ?? 20,
        );
      });
    } catch (e) {
      debugPrint('Delivery coverage unavailable: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final lines = _lines;
    if (lines == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppUi.surfaceOf(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppUi.borderOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.local_shipping_outlined, color: AppUi.brandOf(context)),
              const SizedBox(width: 8),
              Text('Delivery coverage', style: theme.textTheme.titleSmall),
            ],
          ),
          const SizedBox(height: 8),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    line.startsWith('Free')
                        ? Icons.check_circle_rounded
                        : Icons.route_rounded,
                    size: 18,
                    color: line.startsWith('Free')
                        ? AppColors.uiSuccess
                        : AppUi.textSecondaryOf(context),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(line, style: theme.textTheme.bodyMedium),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
