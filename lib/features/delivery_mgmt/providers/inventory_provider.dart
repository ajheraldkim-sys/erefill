import 'package:flutter/material.dart';
import '../models/inventory_model.dart';
import '../services/delivery_service.dart';

class InventoryProvider extends ChangeNotifier {
  final DeliveryService _service;
  String _ownerId = '';

  List<DmInventoryTx> _transactions = [];
  double _currentStock = 0;
  bool _isLoading = false;
  String? _error;

  List<DmInventoryTx> get transactions => _transactions;
  double get currentStock => _currentStock;
  bool get isLoading => _isLoading;
  String? get error => _error;

  InventoryProvider(this._service);

  void initialize(String ownerId) {
    _ownerId = ownerId;
    loadInventory();
  }

  Future<void> loadInventory() async {
    if (_ownerId.isEmpty) return;
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      _transactions = await _service.getInventoryTxs(_ownerId);
      _currentStock = await _service.getCurrentStock(_ownerId);
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> logLoad(double gallons, {String? notes}) async {
    final tx = DmInventoryTx(
      id: '',
      ownerId: _ownerId,
      transactionDate: DateTime.now(),
      transactionType: InventoryTxType.load,
      gallons: gallons,
      notes: notes,
      createdAt: DateTime.now(),
    );
    await _service.addInventoryTx(tx);
    await loadInventory();
  }

  Future<void> logAdjustment(double gallons, {String? notes}) async {
    final tx = DmInventoryTx(
      id: '',
      ownerId: _ownerId,
      transactionDate: DateTime.now(),
      transactionType: InventoryTxType.adjustment,
      gallons: gallons,
      notes: notes,
      createdAt: DateTime.now(),
    );
    await _service.addInventoryTx(tx);
    await loadInventory();
  }
}
