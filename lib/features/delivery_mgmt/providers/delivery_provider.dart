import 'package:flutter/material.dart';
import '../models/delivery_model.dart';
import '../services/delivery_service.dart';

class DeliveryProvider extends ChangeNotifier {
  final DeliveryService _service;
  String _ownerId = '';
  String? _riderIdFilter;
  DateTime? _fromFilter;
  DateTime? _toFilter;

  List<DmDelivery> _deliveries = [];
  DmDelivery? _lastDeleted;
  bool _isLoading = false;
  String? _error;

  List<DmDelivery> get deliveries => _deliveries;
  bool get isLoading => _isLoading;
  String? get error => _error;
  DmDelivery? get lastDeleted => _lastDeleted;

  DeliveryProvider(this._service);

  void initialize(String ownerId) {
    _ownerId = ownerId;
    loadDeliveries();
  }

  void setFilters({String? riderId, DateTime? from, DateTime? to}) {
    _riderIdFilter = riderId;
    _fromFilter = from;
    _toFilter = to;
    loadDeliveries();
  }

  void clearFilters() {
    _riderIdFilter = null;
    _fromFilter = null;
    _toFilter = null;
    loadDeliveries();
  }

  Future<void> loadDeliveries() async {
    if (_ownerId.isEmpty) return;
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      _deliveries = await _service.getDeliveries(
        ownerId: _ownerId,
        riderId: _riderIdFilter,
        from: _fromFilter,
        to: _toFilter,
      );
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<DmDelivery> addDelivery({
    required DmDelivery delivery,
    required double commissionPerGallon,
  }) async {
    final saved = await _service.addDeliveryWithCommission(
      delivery: delivery,
      commissionPerGallon: commissionPerGallon,
    );
    _deliveries.insert(0, saved);
    notifyListeners();
    return saved;
  }

  Future<void> updateDelivery(DmDelivery delivery) async {
    await _service.updateDelivery(delivery);
    final idx = _deliveries.indexWhere((d) => d.id == delivery.id);
    if (idx != -1) {
      _deliveries[idx] = delivery;
      notifyListeners();
    }
  }

  Future<void> deleteDelivery(String id) async {
    final idx = _deliveries.indexWhere((d) => d.id == id);
    if (idx != -1) {
      _lastDeleted = _deliveries[idx];
      _deliveries.removeAt(idx);
      notifyListeners();
    }
    await _service.deleteDelivery(id, _ownerId);
  }

  Future<void> undoDelete() async {
    if (_lastDeleted == null) return;
    final toRestore = _lastDeleted!;
    _lastDeleted = null;
    await _service.restoreDeletedDelivery(toRestore);
    _deliveries.insert(0, toRestore);
    notifyListeners();
  }
}
