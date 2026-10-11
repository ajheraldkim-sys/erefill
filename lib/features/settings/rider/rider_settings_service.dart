import 'package:shared_preferences/shared_preferences.dart';

class RiderSettingsService {
  static const _notifyAssignmentsKey = 'rider_notify_assignments';
  static const _notifyOrderUpdatesKey = 'rider_notify_order_updates';

  String _key(String base, String userId) => '${base}_$userId';

  Future<Map<String, dynamic>> load(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'notifyAssignments':
          prefs.getBool(_key(_notifyAssignmentsKey, userId)) ?? true,
      'notifyOrderUpdates':
          prefs.getBool(_key(_notifyOrderUpdatesKey, userId)) ?? true,
    };
  }

  Future<void> save({
    required String userId,
    required bool notifyAssignments,
    required bool notifyOrderUpdates,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key(_notifyAssignmentsKey, userId), notifyAssignments);
    await prefs.setBool(
      _key(_notifyOrderUpdatesKey, userId),
      notifyOrderUpdates,
    );
  }
}
