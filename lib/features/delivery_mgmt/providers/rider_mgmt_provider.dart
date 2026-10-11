import 'package:flutter/material.dart';
import '../models/rider_model.dart';
import '../services/delivery_service.dart';

class RiderMgmtProvider extends ChangeNotifier {
  final DeliveryService _service;
  String _ownerId = '';

  List<DmRider> _riders = [];
  bool _isLoading = false;
  String? _error;

  List<DmRider> get riders => _riders;
  bool get isLoading => _isLoading;
  String? get error => _error;

  RiderMgmtProvider(this._service);

  void initialize(String ownerId) {
    _ownerId = ownerId;
    loadRiders();
  }

  Future<void> loadRiders() async {
    if (_ownerId.isEmpty) return;
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      _riders = await _service.getRiders(_ownerId);
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<DmRider> addRider(DmRider rider) async {
    final saved = await _service.addRider(rider);
    _riders.insert(0, saved);
    notifyListeners();
    return saved;
  }

  Future<void> updateRider(DmRider rider) async {
    await _service.updateRider(rider);
    final idx = _riders.indexWhere((r) => r.id == rider.id);
    if (idx != -1) {
      _riders[idx] = rider;
      notifyListeners();
    }
  }

  Future<void> deleteRider(String id) async {
    await _service.deleteRider(id, _ownerId);
    _riders.removeWhere((r) => r.id == id);
    notifyListeners();
  }

  Future<String?> findUserIdByEmail(String email) =>
      _service.findUserIdByEmail(email);

  DmRider? getRiderById(String id) {
    try {
      return _riders.firstWhere((r) => r.id == id);
    } catch (_) {
      return null;
    }
  }
}
