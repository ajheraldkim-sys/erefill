import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CartItem {
  final String id;
  final String name;
  final double price;
  final String? imageUrl;
  int quantity;

  CartItem({
    required this.id,
    required this.name,
    required this.price,
    this.imageUrl,
    this.quantity = 1,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'price': price,
        'imageUrl': imageUrl,
        'quantity': quantity,
      };

  factory CartItem.fromJson(Map<String, dynamic> json) => CartItem(
        id: json['id'] as String,
        name: json['name'] as String,
        price: (json['price'] as num).toDouble(),
        imageUrl: json['imageUrl'] as String?,
        quantity: (json['quantity'] as num?)?.toInt() ?? 1,
      );
}

class CartProvider extends ChangeNotifier {
  static const String _prefKeyCart = 'erefill_local_cart';

  final Map<String, CartItem> _items = {};
  String? _stationId;
  String? _stationName;
  final Map<String, Timer> _debounceTimers = {};

  CartProvider() {
    _restoreCartFromStorage();
  }

  String? get stationId => _stationId;
  String? get stationName => _stationName;

  void setStation(String? id, String? name) {
    _stationId = id;
    _stationName = name;
    _persistCartToStorage();
  }

  Map<String, CartItem> get items => {..._items};

  int get totalItems =>
      _items.values.fold(0, (sum, item) => sum + item.quantity);

  double get totalAmount => _items.values.fold(
        0.0,
        (sum, item) => sum + (item.price * item.quantity),
      );

  /// Optimistic, instant addition to cart.
  void addItem(String id, String name, double price, {String? imageUrl}) {
    if (_items.containsKey(id)) {
      _items.update(
        id,
        (existing) => CartItem(
          id: id,
          name: name,
          price: price,
          imageUrl: imageUrl ?? existing.imageUrl,
          quantity: existing.quantity + 1,
        ),
      );
    } else {
      _items.putIfAbsent(
        id,
        () => CartItem(
          id: id,
          name: name,
          price: price,
          imageUrl: imageUrl,
        ),
      );
    }
    notifyListeners();
    _persistCartToStorage();
  }

  /// Optimistic, instant item removal from cart.
  void removeItem(String id) {
    _debounceTimers[id]?.cancel();
    _debounceTimers.remove(id);
    _items.remove(id);
    notifyListeners();
    _persistCartToStorage();
  }

  /// Instant quantity update.
  void updateQuantity(String id, int quantity) {
    if (quantity <= 0) {
      removeItem(id);
      return;
    }
    if (_items.containsKey(id)) {
      _items.update(
        id,
        (existing) => CartItem(
          id: id,
          name: existing.name,
          price: existing.price,
          imageUrl: existing.imageUrl,
          quantity: quantity,
        ),
      );
      notifyListeners();
      _persistCartToStorage();
    }
  }

  /// Debounced quantity updater for rapid button tapping (e.g. + / - on gallon counts).
  ///
  /// Immediately updates local state optimistically, but coalesces multiple rapid
  /// taps into a single persistence write after [delayMs].
  void updateQuantityDebounced(
    String id,
    int quantity, {
    int delayMs = 400,
    VoidCallback? onDebouncedCommit,
  }) {
    // 1. Instant optimistic state update
    updateQuantity(id, quantity);

    // 2. Coalesce background persistence / remote notification
    _debounceTimers[id]?.cancel();
    _debounceTimers[id] = Timer(Duration(milliseconds: delayMs), () {
      _persistCartToStorage();
      onDebouncedCommit?.call();
      _debounceTimers.remove(id);
    });
  }

  void clearCart() {
    for (final timer in _debounceTimers.values) {
      timer.cancel();
    }
    _debounceTimers.clear();
    _items.clear();
    _stationId = null;
    _stationName = null;
    notifyListeners();
    _clearCartFromStorage();
  }

  Future<void> _persistCartToStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final payload = {
        'stationId': _stationId,
        'stationName': _stationName,
        'items': _items.values.map((item) => item.toJson()).toList(),
      };
      await prefs.setString(_prefKeyCart, jsonEncode(payload));
    } catch (_) {}
  }

  Future<void> _restoreCartFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefKeyCart);
      if (raw == null || raw.isEmpty) return;

      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        _stationId = decoded['stationId'] as String?;
        _stationName = decoded['stationName'] as String?;
        final rawItems = decoded['items'];
        if (rawItems is List) {
          _items.clear();
          for (final itemMap in rawItems) {
            if (itemMap is Map) {
              final item = CartItem.fromJson(Map<String, dynamic>.from(itemMap));
              _items[item.id] = item;
            }
          }
          notifyListeners();
        }
      }
    } catch (_) {}
  }

  Future<void> _clearCartFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefKeyCart);
    } catch (_) {}
  }

  @override
  void dispose() {
    for (final timer in _debounceTimers.values) {
      timer.cancel();
    }
    _debounceTimers.clear();
    super.dispose();
  }
}
