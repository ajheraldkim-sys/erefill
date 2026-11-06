import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'demand_forecast.dart';
import 'forecast_card.dart';

/// Loads the station's last 8 weeks of orders and shows [ForecastCard].
class OwnerForecastSection extends StatefulWidget {
  const OwnerForecastSection({super.key, this.stock});

  /// Filled gallons on hand, for the stock warning.
  final int? stock;

  @override
  State<OwnerForecastSection> createState() => _OwnerForecastSectionState();
}

class _OwnerForecastSectionState extends State<OwnerForecastSection> {
  DemandForecastResult? _forecast;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = Supabase.instance.client;
    final uid = db.auth.currentUser?.id;
    if (uid == null) return;
    try {
      final since = DateTime.now()
          .subtract(const Duration(days: 7 * DemandForecast.lookbackWeeks + 7));
      final rows = await db
          .from('orders')
          .select('created_at, items, quantity, status')
          .eq('owner_id', uid)
          .gte('created_at', since.toUtc().toIso8601String())
          .not('status', 'in', '(cancelled,failed)');
      final points = [
        for (final r in rows)
          if (DateTime.tryParse(r['created_at'].toString()) case final d?)
            DemandPoint(d.toLocal(), DemandForecast.gallonsOf(r)),
      ];
      if (!mounted) return;
      setState(() => _forecast = DemandForecast.compute(points, today: DateTime.now()));
    } catch (e) {
      debugPrint('Forecast unavailable: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = _forecast;
    if (f == null) return const SizedBox.shrink();
    return ForecastCard(forecast: f, stock: widget.stock);
  }
}
