import 'package:flutter/material.dart';
import '../models/delivery_model.dart';
import '../models/rider_model.dart';
import '../services/delivery_service.dart';

enum ReportRange { today, thisWeek, thisMonth, thisYear, allTime, custom }

class RiderStat {
  final DmRider rider;
  final int deliveryCount;
  final double totalGallons;
  final double totalIncome;
  final double totalCommission;

  const RiderStat({
    required this.rider,
    required this.deliveryCount,
    required this.totalGallons,
    required this.totalIncome,
    required this.totalCommission,
  });
}

class DailyPoint {
  final DateTime date;
  final double income;
  final double gallons;

  const DailyPoint({
    required this.date,
    required this.income,
    required this.gallons,
  });
}

class ReportProvider extends ChangeNotifier {
  final DeliveryService _service;
  String _ownerId = '';

  ReportRange _range = ReportRange.thisMonth;
  DateTime? _customFrom;
  DateTime? _customTo;

  List<DmDelivery> _deliveries = [];
  List<DmRider> _riders = [];
  bool _isLoading = false;
  String? _error;

  ReportRange get range => _range;
  bool get isLoading => _isLoading;
  String? get error => _error;

  // ─── Summary metrics
  int get totalDeliveries => _deliveries.length;
  double get totalGallons => _deliveries.fold(0, (s, d) => s + d.gallons);
  double get totalIncome => _deliveries.fold(0, (s, d) => s + d.income);
  double get totalExpenses => _deliveries.fold(0, (s, d) => s + d.expenses);
  double get totalCommission => _deliveries.fold(0, (s, d) => s + d.commission);
  double get netProfit => _deliveries.fold(0, (s, d) => s + d.ownerProfit);

  // ─── Daily series for chart
  List<DailyPoint> get dailySeries {
    final Map<String, DailyPoint> map = {};
    for (final d in _deliveries) {
      final key =
          '${d.deliveryDate.year}-${d.deliveryDate.month.toString().padLeft(2, '0')}-${d.deliveryDate.day.toString().padLeft(2, '0')}';
      final existing = map[key];
      if (existing == null) {
        map[key] = DailyPoint(
          date: d.deliveryDate,
          income: d.income,
          gallons: d.gallons,
        );
      } else {
        map[key] = DailyPoint(
          date: existing.date,
          income: existing.income + d.income,
          gallons: existing.gallons + d.gallons,
        );
      }
    }
    final list = map.values.toList();
    list.sort((a, b) => a.date.compareTo(b.date));
    return list;
  }

  // ─── Rider leaderboard
  List<RiderStat> get leaderboard {
    final Map<String, _RiderAggData> agg = {};
    for (final d in _deliveries) {
      if (d.riderId == null) continue;
      final entry =
          agg[d.riderId!] ??
          _RiderAggData(riderId: d.riderId!, riderName: d.riderName ?? '');
      entry.count++;
      entry.gallons += d.gallons;
      entry.income += d.income;
      entry.commission += d.commission;
      agg[d.riderId!] = entry;
    }

    final result = <RiderStat>[];
    for (final entry in agg.values) {
      final rider = _riders.firstWhere(
        (r) => r.id == entry.riderId,
        orElse: () => DmRider(
          id: entry.riderId,
          ownerId: _ownerId,
          fullName: entry.riderName,
          commissionPerGallon: 0,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );
      result.add(
        RiderStat(
          rider: rider,
          deliveryCount: entry.count,
          totalGallons: entry.gallons,
          totalIncome: entry.income,
          totalCommission: entry.commission,
        ),
      );
    }

    result.sort((a, b) => b.totalGallons.compareTo(a.totalGallons));
    return result;
  }

  ReportProvider(this._service);

  void initialize(String ownerId) {
    _ownerId = ownerId;
    loadReport();
  }

  void setRange(ReportRange range, {DateTime? from, DateTime? to}) {
    _range = range;
    if (range == ReportRange.custom) {
      _customFrom = from;
      _customTo = to;
    }
    loadReport();
  }

  (DateTime?, DateTime?) get _dateRange {
    final now = DateTime.now();
    switch (_range) {
      case ReportRange.today:
        final start = DateTime(now.year, now.month, now.day);
        return (start, start);
      case ReportRange.thisWeek:
        final weekday = now.weekday;
        final start = now.subtract(Duration(days: weekday - 1));
        return (
          DateTime(start.year, start.month, start.day),
          DateTime(now.year, now.month, now.day),
        );
      case ReportRange.thisMonth:
        return (
          DateTime(now.year, now.month, 1),
          DateTime(now.year, now.month, now.day),
        );
      case ReportRange.thisYear:
        return (
          DateTime(now.year, 1, 1),
          DateTime(now.year, now.month, now.day),
        );
      case ReportRange.allTime:
        return (null, null);
      case ReportRange.custom:
        return (_customFrom, _customTo);
    }
  }

  Future<void> loadReport() async {
    if (_ownerId.isEmpty) return;
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final (from, to) = _dateRange;
      _deliveries = await _service.getDeliveries(
        ownerId: _ownerId,
        from: from,
        to: to,
      );
      _riders = await _service.getRiders(_ownerId);
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}

class _RiderAggData {
  final String riderId;
  final String riderName;
  int count = 0;
  double gallons = 0;
  double income = 0;
  double commission = 0;

  _RiderAggData({required this.riderId, required this.riderName});
}
