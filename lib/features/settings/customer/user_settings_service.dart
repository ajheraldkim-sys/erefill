import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class UserSettingsService extends ChangeNotifier {
  static const _keyNotifyOrders = 'notify_orders';
  static const _keyNotifyPromos = 'notify_promos';
  static const _keyDefaultOrderNotes = 'default_order_notes';

  bool _notifyOrderUpdates = true;
  bool _notifyPromotions = true;
  bool _defaultOrderNotes = false;
  String? _activeUserId;
  late final StreamSubscription<AuthState> _authSubscription;

  bool get notifyOrderUpdates => _notifyOrderUpdates;
  bool get notifyPromotions => _notifyPromotions;
  bool get defaultOrderNotes => _defaultOrderNotes;

  UserSettingsService() {
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen(
      (state) => _load(state.session?.user.id),
    );
    _load(Supabase.instance.client.auth.currentUser?.id);
  }

  String _key(String base, String? userId) =>
      userId == null ? base : '${base}_$userId';

  Future<void> _load(String? userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _activeUserId = userId;
      _notifyOrderUpdates =
          prefs.getBool(_key(_keyNotifyOrders, userId)) ?? true;
      _notifyPromotions = prefs.getBool(_key(_keyNotifyPromos, userId)) ?? true;
      _defaultOrderNotes =
          prefs.getBool(_key(_keyDefaultOrderNotes, userId)) ?? false;
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading user settings: $e');
    }
  }

  Future<void> setNotifyOrderUpdates(bool val) async {
    _notifyOrderUpdates = val;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key(_keyNotifyOrders, _activeUserId), val);
    } catch (e) {
      debugPrint('Error saving user settings: $e');
    }
  }

  Future<void> setNotifyPromotions(bool val) async {
    _notifyPromotions = val;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key(_keyNotifyPromos, _activeUserId), val);
    } catch (e) {
      debugPrint('Error saving user settings: $e');
    }
  }

  Future<void> setDefaultOrderNotes(bool val) async {
    _defaultOrderNotes = val;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key(_keyDefaultOrderNotes, _activeUserId), val);
    } catch (e) {
      debugPrint('Error saving order preference: $e');
    }
  }

  @override
  void dispose() {
    _authSubscription.cancel();
    super.dispose();
  }
}
