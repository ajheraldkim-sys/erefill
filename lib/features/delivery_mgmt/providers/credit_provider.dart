import 'package:flutter/material.dart';
import '../models/credit_model.dart';
import '../services/delivery_service.dart';

class CreditProvider extends ChangeNotifier {
  final DeliveryService _service;
  String _ownerId = '';
  String? _riderIdFilter;

  List<DmCredit> _credits = [];
  bool _isLoading = false;
  String? _error;

  List<DmCredit> get credits => _credits;
  List<DmCredit> get customerCredits =>
      _credits.where((c) => c.creditType == CreditType.customer).toList();
  List<DmCredit> get riderCredits =>
      _credits.where((c) => c.creditType == CreditType.rider).toList();
  bool get isLoading => _isLoading;
  String? get error => _error;

  CreditProvider(this._service);

  void initialize(String ownerId) {
    _ownerId = ownerId;
    loadCredits();
  }

  void setRiderFilter(String? riderId) {
    _riderIdFilter = riderId;
    loadCredits();
  }

  Future<void> loadCredits() async {
    if (_ownerId.isEmpty) return;
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      _credits = await _service.getCredits(
        ownerId: _ownerId,
        riderId: _riderIdFilter,
      );
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<DmCredit> addCredit(DmCredit credit) async {
    final saved = await _service.addCredit(credit);
    _credits.insert(0, saved);
    notifyListeners();
    return saved;
  }

  Future<void> markPaid(String id) async {
    final idx = _credits.indexWhere((c) => c.id == id);
    if (idx == -1) return;
    final updated = _credits[idx].copyWith(
      isPaid: true,
      paidAmount: _credits[idx].amount,
      paymentDate: DateTime.now(),
    );
    await _service.updateCredit(updated);
    _credits[idx] = updated;
    notifyListeners();
  }

  Future<void> applyPartialPayment(String id, double amount) async {
    final idx = _credits.indexWhere((c) => c.id == id);
    if (idx == -1) return;
    final credit = _credits[idx];
    final newPaid = (credit.paidAmount + amount).clamp(0.0, credit.amount);
    final isPaid = newPaid >= credit.amount;
    final updated = credit.copyWith(
      paidAmount: newPaid,
      isPaid: isPaid,
      paymentDate: isPaid ? DateTime.now() : credit.paymentDate,
    );
    await _service.updateCredit(updated);
    _credits[idx] = updated;
    notifyListeners();
  }

  Future<void> deleteCredit(String id) async {
    await _service.deleteCredit(id, _ownerId);
    _credits.removeWhere((c) => c.id == id);
    notifyListeners();
  }
}
