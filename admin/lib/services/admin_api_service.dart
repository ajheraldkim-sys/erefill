import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../widgets/admin_ui.dart';

class AdminApiService {
  AdminApiService(this._client);

  final SupabaseClient _client;

  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return <String, dynamic>{};
  }

  // --- Identity & Permissions ---

  Future<bool> isAdmin() async {
    try {
      final result = await _client.rpc('is_admin');
      if (result == true) return true;
    } catch (_) {}

    try {
      final uid = _client.auth.currentUser?.id;
      if (uid == null) return false;
      final row = await _client
          .from('profiles')
          .select('role')
          .eq('id', uid)
          .maybeSingle();
      return row?['role']?.toString().toLowerCase() == 'admin';
    } catch (e) {
      debugPrint('isAdmin fallback error: $e');
      return false;
    }
  }

  Future<bool> isSuperAdmin() async {
    try {
      final result = await _client.rpc('is_super_admin');
      if (result == true) return true;
    } catch (_) {}

    try {
      final user = _client.auth.currentUser;
      final role = user?.appMetadata['role'] ?? user?.userMetadata?['role'];
      return role?.toString().toLowerCase() == 'super_admin' ||
          role?.toString().toLowerCase() == 'admin';
    } catch (_) {
      return false;
    }
  }

  // --- Dashboard & Analytics ---

  Future<Map<String, dynamic>> dashboardStats() async {
    try {
      final result = await _client.rpc('admin_dashboard_stats');
      final map = _asMap(result);
      if (map.isNotEmpty) return map;
    } catch (e) {
      debugPrint('admin_dashboard_stats RPC fallback triggered: $e');
    }

    try {
      final profilesRes = await _client
          .from('profiles')
          .select('id, role, is_suspended');
      final stationsRes = await _client
          .from('water_refill_stations')
          .select('id, status, is_accepting_orders');
      final ordersRes = await _client
          .from('orders')
          .select('id, status, total_amount, created_at');

      final profilesList = List<Map<String, dynamic>>.from(profilesRes);
      final stationsList = List<Map<String, dynamic>>.from(stationsRes);
      final ordersList = List<Map<String, dynamic>>.from(ordersRes);

      var customers = 0;
      var owners = 0;
      var riders = 0;
      var admins = 0;
      for (final p in profilesList) {
        final r = p['role']?.toString().toLowerCase();
        if (r == 'customer') customers++;
        if (r == 'owner') owners++;
        if (r == 'rider') riders++;
        if (r == 'admin') admins++;
      }

      var openStations = 0;
      var pendingStations = 0;
      var suspendedStations = 0;
      for (final s in stationsList) {
        final st = s['status']?.toString().toLowerCase();
        final open = s['is_accepting_orders'] == true;
        if (open) openStations++;
        if (st == 'pending' || st == 'pending_verification') pendingStations++;
        if (st == 'suspended') suspendedStations++;
      }

      var pendingOrders = 0;
      var preparingOrders = 0;
      var outForDeliveryOrders = 0;
      var deliveredOrders = 0;
      var cancelledOrders = 0;
      double totalGmv = 0;
      double todayGmv = 0;
      final todayStr = DateTime.now().toIso8601String().split('T').first;

      for (final o in ordersList) {
        final st = o['status']?.toString().toLowerCase();
        final amount = safeDouble(o['total_amount']);
        final createdAt = o['created_at']?.toString() ?? '';

        if (st == 'delivered') {
          totalGmv += amount;
          if (createdAt.startsWith(todayStr)) {
            todayGmv += amount;
          }
        }

        switch (st) {
          case 'pending':
            pendingOrders++;
            break;
          case 'preparing':
          case 'accepted':
            preparingOrders++;
            break;
          case 'out_for_delivery':
          case 'assigned_to_rider':
            outForDeliveryOrders++;
            break;
          case 'delivered':
            deliveredOrders++;
            break;
          case 'cancelled':
            cancelledOrders++;
            break;
        }
      }

      return {
        'customers': customers,
        'owners': owners,
        'riders': riders,
        'admins': admins,
        'total_users': profilesList.length,
        'stations_count': stationsList.length,
        'open_stations': openStations,
        'pending_stations': pendingStations,
        'suspended_stations': suspendedStations,
        'orders_count': ordersList.length,
        'pending_orders': pendingOrders,
        'preparing_orders': preparingOrders,
        'out_for_delivery_orders': outForDeliveryOrders,
        'delivered_orders': deliveredOrders,
        'cancelled_orders': cancelledOrders,
        'total_gmv': totalGmv,
        'today_gmv': todayGmv,
        'maintenance_mode': false,
      };
    } catch (e) {
      debugPrint('Direct dashboard stats fallback error: $e');
      return {
        'customers': 0,
        'owners': 0,
        'riders': 0,
        'stations_count': 0,
        'orders_count': 0,
        'total_gmv': 0.0,
      };
    }
  }

  Future<Map<String, dynamic>> revenueAnalytics() async {
    try {
      final result = await _client.rpc('admin_revenue_analytics');
      final map = _asMap(result);
      if (map.isNotEmpty) return map;
    } catch (_) {}

    try {
      final now = DateTime.now();
      final sevenDaysAgo = now
          .subtract(const Duration(days: 7))
          .toIso8601String();
      final orders = await _client
          .from('orders')
          .select('total_amount, created_at, status')
          .eq('status', 'delivered')
          .gte('created_at', sevenDaysAgo);

      final daily = <String, double>{};
      for (int i = 6; i >= 0; i--) {
        final d = now
            .subtract(Duration(days: i))
            .toIso8601String()
            .split('T')
            .first;
        daily[d] = 0.0;
      }

      double total = 0.0;
      for (final o in orders) {
        final d = (o['created_at']?.toString() ?? '').split('T').first;
        final amt = safeDouble(o['total_amount']);
        total += amt;
        if (daily.containsKey(d)) {
          daily[d] = (daily[d] ?? 0.0) + amt;
        }
      }

      final series = daily.entries
          .map((e) => {'date': e.key, 'revenue': e.value})
          .toList();
      return {
        'total_revenue': total,
        'platform_cut': total * 0.05,
        'daily_series': series,
      };
    } catch (e) {
      debugPrint('revenueAnalytics fallback error: $e');
      return {'total_revenue': 0.0, 'daily_series': []};
    }
  }

  // --- Platform Fee Management ---

  Future<Map<String, dynamic>> getPlatformFee() async {
    try {
      final result = await _client.rpc('admin_get_platform_fee');
      final map = _asMap(result);
      if (map.isNotEmpty) return map;
    } catch (_) {}

    try {
      final row = await _client
          .from('system_config')
          .select('value')
          .eq('key', 'platform_fee')
          .maybeSingle();
      if (row != null && row['value'] != null) {
        final val = row['value'];
        if (val is Map) return Map<String, dynamic>.from(val);
        if (val is String) return Map<String, dynamic>.from(jsonDecode(val));
      }
    } catch (_) {}

    return {'percent': 5.0, 'fixed': 2.0, 'enabled': true};
  }

  Future<Map<String, dynamic>> setPlatformFee({
    required double percent,
    required double fixed,
    required bool enabled,
    String? reason,
  }) async {
    try {
      final result = await _client.rpc(
        'admin_set_platform_fee',
        params: {
          'p_percent': percent,
          'p_fixed': fixed,
          'p_enabled': enabled,
          'p_reason': reason,
        },
      );
      final map = _asMap(result);
      if (map.isNotEmpty) return map;
    } catch (_) {}

    final payload = {
      'percent': percent,
      'fixed': fixed,
      'enabled': enabled,
      'reason': reason,
      'updated_at': DateTime.now().toIso8601String(),
    };
    try {
      await _client.from('system_config').upsert({
        'key': 'platform_fee',
        'value': payload,
        'updated_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('setPlatformFee fallback error: $e');
    }
    return payload;
  }

  Future<double> previewPlatformFee(double subtotal, double deliveryFee) async {
    try {
      final result = await _client.rpc(
        'calculate_platform_fee',
        params: {'p_subtotal': subtotal, 'p_delivery_fee': deliveryFee},
      );
      return safeDouble(result);
    } catch (_) {
      // Default formula: 5% of subtotal + ₱2 flat
      return (subtotal * 0.05) + 2.0;
    }
  }

  // --- Centralized Delivery Fee Management ---

  Future<Map<String, dynamic>> getDeliveryFeeConfig() async {
    try {
      final result = await _client.rpc('admin_get_delivery_fee_config');
      final map = _asMap(result);
      if (map.isNotEmpty) return map;
    } catch (_) {}

    try {
      final result = await _client.rpc('get_delivery_fee_config');
      final map = _asMap(result);
      if (map.isNotEmpty) return map;
    } catch (_) {}

    try {
      final row = await _client
          .from('system_config')
          .select('value, updated_at, updated_by')
          .eq('key', 'delivery_fee_config')
          .maybeSingle();
      if (row != null && row['value'] != null) {
        final val = row['value'];
        Map<String, dynamic> parsed;
        if (val is Map) {
          parsed = Map<String, dynamic>.from(val);
        } else if (val is String) {
          parsed = Map<String, dynamic>.from(jsonDecode(val));
        } else {
          parsed = {};
        }
        parsed['updated_at'] ??= row['updated_at'];
        parsed['updated_by'] ??= row['updated_by'];
        return parsed;
      }
    } catch (_) {}

    return {
      'rate_per_km': 10.0,
      'minimum_fee': 20.0,
      'min_billable_distance_km': 1.0,
      'rounding_rule': 'exact',
      'enabled': true,
    };
  }

  Future<Map<String, dynamic>> setDeliveryFeeConfig({
    required double ratePerKm,
    required double minimumFee,
    required double minBillableDistanceKm,
    required String roundingRule,
    required bool enabled,
    String? reason,
  }) async {
    try {
      final result = await _client.rpc(
        'admin_set_delivery_fee_config',
        params: {
          'p_rate_per_km': ratePerKm,
          'p_minimum_fee': minimumFee,
          'p_min_billable_distance_km': minBillableDistanceKm,
          'p_rounding_rule': roundingRule,
          'p_enabled': enabled,
          'p_reason': reason,
        },
      );
      final map = _asMap(result);
      if (map.isNotEmpty) return map;
    } catch (_) {}

    final user = _client.auth.currentUser;
    final payload = {
      'rate_per_km': ratePerKm,
      'minimum_fee': minimumFee,
      'min_billable_distance_km': minBillableDistanceKm,
      'rounding_rule': roundingRule,
      'enabled': enabled,
      'reason': reason,
      'updated_at': DateTime.now().toIso8601String(),
      'updated_by': user?.id,
      'updated_by_email': user?.email,
    };
    try {
      await _client.from('system_config').upsert({
        'key': 'delivery_fee_config',
        'value': payload,
        'updated_at': DateTime.now().toIso8601String(),
        'updated_by': user?.id,
      });
      if (user?.id != null) {
        await _client.from('audit_logs').insert({
          'user_id': user!.id,
          'action': 'set_delivery_fee_config',
          'entity_type': 'config',
          'entity_id': 'delivery_fee_config',
          'details': payload,
        });
      }
    } catch (e) {
      debugPrint('setDeliveryFeeConfig fallback error: $e');
    }
    return payload;
  }

  Future<List<Map<String, dynamic>>> getDeliveryFeeHistory({int limit = 20}) async {
    try {
      final result = await _client.rpc(
        'admin_get_delivery_fee_history',
        params: {'p_limit': limit},
      );
      if (result is List) {
        return result.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (_) {}

    try {
      final rows = await _client
          .from('audit_logs')
          .select('id, user_id, details, created_at')
          .eq('action', 'set_delivery_fee_config')
          .order('created_at', ascending: false)
          .limit(limit);
      return List<Map<String, dynamic>>.from(rows);
    } catch (e) {
      debugPrint('getDeliveryFeeHistory fallback error: $e');
      return [];
    }
  }

  Future<double> previewDeliveryFee(double distanceKm) async {
    try {
      final result = await _client.rpc(
        'calculate_delivery_fee',
        params: {'p_distance_km': distanceKm},
      );
      return safeDouble(result);
    } catch (_) {
      final cfg = await getDeliveryFeeConfig();
      final enabled = cfg['enabled'] != false;
      if (!enabled) return 0.0;
      final rate = safeDouble(cfg['rate_per_km'], fallback: 10.0);
      final minFee = safeDouble(cfg['minimum_fee'], fallback: 20.0);
      final minDist = safeDouble(cfg['min_billable_distance_km'], fallback: 1.0);
      final rule = (cfg['rounding_rule'] ?? 'exact').toString();
      double dist = distanceKm < minDist ? minDist : distanceKm;
      if (rule == 'ceil') {
        dist = dist.ceilToDouble();
      } else if (rule == 'round') {
        dist = dist.roundToDouble();
      }
      double fee = dist * rate;
      if (minFee > 0 && fee < minFee) fee = minFee;
      return double.parse(fee.toStringAsFixed(2));
    }
  }

  // --- Regions, Stations & Orders ---

  Future<List<Map<String, dynamic>>> listRegions() async {
    try {
      final result = await _client.rpc('admin_list_regions');
      if (result is List && result.isNotEmpty) {
        return result.map((r) => Map<String, dynamic>.from(r as Map)).toList();
      }
    } catch (_) {}

    return [
      {'id': 'cantilan', 'name': 'Cantilan'},
      {'id': 'madrid', 'name': 'Madrid'},
    ];
  }

  Future<AdminPagedResult<Map<String, dynamic>>> listStations({
    int limit = 50,
    int offset = 0,
    String? search,
    String? regionId,
  }) async {
    try {
      final result = await _client.rpc(
        'admin_list_stations',
        params: {
          'p_limit': limit,
          'p_offset': offset,
          'p_search': search,
          'p_region_id': regionId,
        },
      );
      final paged = _parsePaged(result);
      if (paged.rows.isNotEmpty) return paged;
    } catch (_) {}

    try {
      dynamic query = _client.from('water_refill_stations').select('*');
      if (search != null && search.trim().isNotEmpty) {
        final s = search.trim();
        query = query.or('name.ilike.%$s%,town.ilike.%$s%,address.ilike.%$s%');
      }
      if (regionId != null && regionId.trim().isNotEmpty) {
        query = query.ilike('town', regionId.trim());
      }

      dynamic countQuery = _client.from('water_refill_stations').select('id');
      if (regionId != null && regionId.trim().isNotEmpty) {
        countQuery = countQuery.ilike('town', regionId.trim());
      }
      if (search != null && search.trim().isNotEmpty) {
        final s = search.trim();
        countQuery = countQuery.or(
          'name.ilike.%$s%,town.ilike.%$s%,address.ilike.%$s%',
        );
      }
      final countRes = await countQuery;
      final total = (countRes as List).length;

      final rows = await query
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);

      return AdminPagedResult(
        total: total,
        rows: List<Map<String, dynamic>>.from(rows),
      );
    } catch (e) {
      debugPrint('listStations fallback error: $e');
      return const AdminPagedResult(total: 0, rows: []);
    }
  }

  Future<AdminPagedResult<Map<String, dynamic>>> listOrders({
    int limit = 50,
    int offset = 0,
    String? status,
    String? search,
  }) async {
    try {
      final result = await _client.rpc(
        'admin_list_orders',
        params: {
          'p_limit': limit,
          'p_offset': offset,
          'p_status': status,
          'p_search': search,
        },
      );
      final paged = _parsePaged(result);
      if (result is Map && result.containsKey('rows')) return paged;
    } catch (_) {}

    try {
      dynamic filteredQuery({required bool selectIds}) {
        dynamic query = _client
            .from('orders')
            .select(selectIds ? 'id' : '*');
        switch (status?.toLowerCase()) {
          case 'pending':
            query = query.eq('status', 'pending');
          case 'delivering':
            query = query.inFilter('status', [
              'accepted',
              'preparing',
              'ready_for_pickup',
              'assigned_to_rider',
              'out_for_delivery',
            ]);
          case 'delivered':
            query = query.eq('status', 'delivered');
          case 'cancelled':
            query = query.inFilter('status', ['cancelled', 'failed']);
        }
        if (search != null && search.trim().isNotEmpty) {
          final term = search.trim();
          final idSearch = RegExp(
            r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
          ).hasMatch(term);
          final fields = [
            if (idSearch) 'id.eq.$term',
            'station_name.ilike.%$term%',
            'customer_name.ilike.%$term%',
          ].join(',');
          query = query.or(fields);
        }
        return query;
      }

      final countRes = await filteredQuery(selectIds: true);
      final total = (countRes as List).length;
      final rows = await filteredQuery(selectIds: false)
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);

      return AdminPagedResult(
        total: total,
        rows: List<Map<String, dynamic>>.from(rows),
      );
    } catch (e) {
      debugPrint('listOrders fallback error: $e');
      rethrow;
    }
  }

  Future<AdminPagedResult<Map<String, dynamic>>> listUsers({
    String? role,
    int limit = 50,
    int offset = 0,
    String? search,
  }) async {
    try {
      final result = await _client.rpc(
        'admin_list_users',
        params: {
          'p_role': role,
          'p_limit': limit,
          'p_offset': offset,
          'p_search': search,
        },
      );
      final paged = _parsePaged(result);
      if (paged.rows.isNotEmpty) return paged;
    } catch (_) {}

    try {
      dynamic query = _client.from('profiles').select('*');
      if (role != null && role.isNotEmpty && role.toLowerCase() != 'all') {
        query = query.eq('role', role.toLowerCase());
      }
      if (search != null && search.trim().isNotEmpty) {
        final s = search.trim();
        query = query.or(
          'full_name.ilike.%$s%,email.ilike.%$s%,phone.ilike.%$s%',
        );
      }

      final countRes = await _client.from('profiles').select('id');
      final total = (countRes as List).length;

      final rows = await query
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);

      return AdminPagedResult(
        total: total,
        rows: List<Map<String, dynamic>>.from(rows),
      );
    } catch (e) {
      debugPrint('listUsers fallback error: $e');
      return const AdminPagedResult(total: 0, rows: []);
    }
  }

  // --- Audit Logs & Config ---

  Future<AdminPagedResult<Map<String, dynamic>>> listAuditLogs({
    int limit = 100,
    int offset = 0,
  }) async {
    try {
      final result = await _client.rpc(
        'admin_list_audit_logs',
        params: {'p_limit': limit, 'p_offset': offset},
      );
      return _parsePaged(result);
    } catch (_) {}

    try {
      final rows = await _client
          .from('audit_logs')
          .select('*')
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);
      return AdminPagedResult(
        total: (rows as List).length,
        rows: List<Map<String, dynamic>>.from(rows),
      );
    } catch (_) {
      return const AdminPagedResult(total: 0, rows: []);
    }
  }

  Future<List<Map<String, dynamic>>> listSystemConfig() async {
    try {
      final rows = await _client.from('system_config').select().order('key');
      return List<Map<String, dynamic>>.from(rows);
    } catch (_) {
      return [
        {'key': 'maintenance_mode', 'value': false},
        {'key': 'allow_signups', 'value': true},
      ];
    }
  }

  Future<void> setSystemConfig(
    String key,
    dynamic value, {
    String? reason,
  }) async {
    try {
      await _client.rpc(
        'admin_set_system_config',
        params: {'p_key': key, 'p_value': value, 'p_reason': reason},
      );
      return;
    } catch (_) {}

    try {
      await _client.from('system_config').upsert({
        'key': key,
        'value': value,
        'updated_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('setSystemConfig fallback error: $e');
    }
  }

  // --- Station Management ---

  Future<void> setStationAvailability(
    String ownerId,
    String availability, {
    String? reason,
  }) async {
    try {
      await _client.rpc(
        'admin_set_station_availability',
        params: {
          'p_owner_id': ownerId,
          'p_availability': availability,
          'p_reason': reason,
        },
      );
      return;
    } catch (_) {}

    try {
      await _client
          .from('water_refill_stations')
          .update({
            'is_accepting_orders': availability.toLowerCase() == 'open',
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('owner_id', ownerId);
    } catch (e) {
      debugPrint('setStationAvailability fallback error: $e');
    }
  }

  Future<Map<String, dynamic>> getStationDetail(String ownerId) async {
    try {
      final result = await _client.rpc(
        'admin_get_station_detail',
        params: {'p_owner_id': ownerId},
      );
      final map = _asMap(result);
      if (map.isNotEmpty) return map;
    } catch (_) {}

    try {
      final station = await _client
          .from('water_refill_stations')
          .select('*')
          .eq('owner_id', ownerId)
          .maybeSingle();
      final owner = await _client
          .from('profiles')
          .select('*')
          .eq('id', ownerId)
          .maybeSingle();

      return {'station': station ?? {}, 'owner': owner ?? {}};
    } catch (e) {
      debugPrint('getStationDetail fallback error: $e');
      return {};
    }
  }

  Future<AdminPagedResult<Map<String, dynamic>>> listStationRiders(
    String ownerId, {
    int limit = 100,
    int offset = 0,
  }) async {
    try {
      final result = await _client.rpc(
        'admin_list_station_riders',
        params: {'p_owner_id': ownerId, 'p_limit': limit, 'p_offset': offset},
      );
      return _parsePaged(result);
    } catch (_) {}

    try {
      final rows = await _client
          .from('profiles')
          .select('*')
          .eq('role', 'rider')
          .range(offset, offset + limit - 1);
      return AdminPagedResult(
        total: (rows as List).length,
        rows: List<Map<String, dynamic>>.from(rows),
      );
    } catch (_) {
      return const AdminPagedResult(total: 0, rows: []);
    }
  }

  Future<AdminPagedResult<Map<String, dynamic>>> listStationCustomers(
    String ownerId, {
    int limit = 100,
    int offset = 0,
  }) async {
    try {
      final result = await _client.rpc(
        'admin_list_station_customers',
        params: {'p_owner_id': ownerId, 'p_limit': limit, 'p_offset': offset},
      );
      return _parsePaged(result);
    } catch (_) {}

    try {
      final rows = await _client
          .from('profiles')
          .select('*')
          .eq('role', 'customer')
          .range(offset, offset + limit - 1);
      return AdminPagedResult(
        total: (rows as List).length,
        rows: List<Map<String, dynamic>>.from(rows),
      );
    } catch (_) {
      return const AdminPagedResult(total: 0, rows: []);
    }
  }

  // --- User Profiles ---

  Future<Map<String, dynamic>> getUserDetail(String userId) async {
    try {
      final result = await _client.rpc(
        'admin_get_user_detail',
        params: {'p_user_id': userId},
      );
      final map = _asMap(result);
      if (map.isNotEmpty) return map;
    } catch (_) {}

    try {
      final profile = await _client
          .from('profiles')
          .select('*')
          .eq('id', userId)
          .maybeSingle();
      return profile == null ? {} : Map<String, dynamic>.from(profile);
    } catch (e) {
      debugPrint('getUserDetail fallback error: $e');
      return {};
    }
  }

  Future<Map<String, dynamic>> updateUserProfile({
    required String userId,
    String? fullName,
    String? phone,
    String? username,
    String? town,
    String? barangay,
    String? completeAddress,
    String? landmark,
    String? vehicleType,
    String? licenseNumber,
    String? role,
    String? reason,
  }) async {
    try {
      final result = await _client.rpc(
        'admin_update_user_profile',
        params: {
          'p_user_id': userId,
          'p_full_name': fullName,
          'p_phone': phone,
          'p_username': username,
          'p_town': town,
          'p_barangay': barangay,
          'p_complete_address': completeAddress,
          'p_landmark': landmark,
          'p_vehicle_type': vehicleType,
          'p_license_number': licenseNumber,
          'p_reason': reason,
        },
      );
      final map = _asMap(result);
      if (map.isNotEmpty) {
        if (role != null) {
          await _client
              .from('profiles')
              .update({'role': role})
              .eq('id', userId);
          map['role'] = role;
        }
        return map;
      }
    } catch (_) {}

    final updates = <String, dynamic>{};
    if (fullName != null) updates['full_name'] = fullName;
    if (phone != null) updates['phone'] = phone;
    if (username != null) updates['username'] = username;
    if (town != null) updates['town'] = town;
    if (barangay != null) updates['barangay'] = barangay;
    if (completeAddress != null) updates['complete_address'] = completeAddress;
    if (landmark != null) updates['landmark'] = landmark;
    if (vehicleType != null) updates['vehicle_type'] = vehicleType;
    if (licenseNumber != null) updates['license_number'] = licenseNumber;
    if (role != null) updates['role'] = role;

    try {
      final updated = await _client
          .from('profiles')
          .update(updates)
          .eq('id', userId)
          .select()
          .maybeSingle();
      return updated == null ? updates : Map<String, dynamic>.from(updated);
    } catch (e) {
      debugPrint('updateUserProfile fallback error: $e');
      return updates;
    }
  }

  Future<Map<String, dynamic>> updateStationProfile({
    required String ownerId,
    String? stationName,
    String? stationDescription,
    String? fullName,
    String? phone,
    String? town,
    String? barangay,
    String? completeAddress,
    double? latitude,
    double? longitude,
    double? baseDeliveryFee,
    double? pricePerGallon,
    int? maxConcurrentOrders,
    String? reason,
  }) async {
    try {
      final result = await _client.rpc(
        'admin_update_station_profile',
        params: {
          'p_owner_id': ownerId,
          'p_station_name': stationName,
          'p_station_description': stationDescription,
          'p_full_name': fullName,
          'p_phone': phone,
          'p_town': town,
          'p_barangay': barangay,
          'p_complete_address': completeAddress,
          'p_latitude': latitude,
          'p_longitude': longitude,
          'p_base_delivery_fee': baseDeliveryFee,
          'p_price_per_gallon': pricePerGallon,
          'p_max_concurrent_orders': maxConcurrentOrders,
          'p_reason': reason,
        },
      );
      final map = _asMap(result);
      if (map.isNotEmpty) return map;
    } catch (_) {}

    final stationUpdates = <String, dynamic>{
      'updated_at': DateTime.now().toIso8601String(),
    };
    if (stationName != null) stationUpdates['name'] = stationName;
    if (town != null) stationUpdates['town'] = town;
    if (completeAddress != null) stationUpdates['address'] = completeAddress;
    if (latitude != null) stationUpdates['latitude'] = latitude;
    if (longitude != null) stationUpdates['longitude'] = longitude;
    if (baseDeliveryFee != null) {
      stationUpdates['base_delivery_fee'] = baseDeliveryFee;
    }
    if (pricePerGallon != null) {
      stationUpdates['price_per_gallon'] = pricePerGallon;
    }
    if (maxConcurrentOrders != null) {
      stationUpdates['max_concurrent_orders'] = maxConcurrentOrders;
    }

    try {
      await _client
          .from('water_refill_stations')
          .update(stationUpdates)
          .eq('owner_id', ownerId);
    } catch (e) {
      debugPrint('updateStationProfile fallback error: $e');
    }
    return stationUpdates;
  }

  Future<void> updateUserEmail(
    String userId,
    String email, {
    String? reason,
  }) async {
    try {
      await _client.rpc(
        'admin_update_user_email',
        params: {'p_user_id': userId, 'p_email': email, 'p_reason': reason},
      );
      return;
    } catch (_) {}

    await _client.from('profiles').update({'email': email}).eq('id', userId);
  }

  Future<void> updateUserPassword(
    String userId,
    String password, {
    String? reason,
  }) async {
    await _client.rpc(
      'admin_update_user_password',
      params: {'p_user_id': userId, 'p_password': password, 'p_reason': reason},
    );
  }

  Future<void> deleteUser(String userId, {String? reason}) async {
    try {
      await _client.rpc(
        'admin_delete_user',
        params: {'p_user_id': userId, 'p_reason': reason},
      );
      return;
    } catch (_) {}

    await _client
        .from('profiles')
        .update({'status': 'deleted'})
        .eq('id', userId);
  }

  Future<void> deleteStation(String ownerId, {String? reason}) async {
    try {
      await _client.rpc(
        'admin_delete_station',
        params: {'p_owner_id': ownerId, 'p_reason': reason},
      );
      return;
    } catch (_) {}

    await _client
        .from('water_refill_stations')
        .update({'status': 'archived'})
        .eq('owner_id', ownerId);
  }

  // --- Order Actions ---

  Future<Map<String, dynamic>> getOrderDetail(String orderId) async {
    try {
      final result = await _client.rpc(
        'admin_get_order_detail',
        params: {'p_order_id': orderId},
      );
      final map = _asMap(result);
      if (map.isNotEmpty) return map;
    } catch (_) {}

    try {
      final order = await _client
          .from('orders')
          .select('*')
          .eq('id', orderId)
          .maybeSingle();
      return order == null ? {} : Map<String, dynamic>.from(order);
    } catch (e) {
      debugPrint('getOrderDetail fallback error: $e');
      return {};
    }
  }

  Future<void> cancelOrder(String orderId, {String? reason}) async {
    try {
      await _client.rpc(
        'admin_cancel_order',
        params: {'p_order_id': orderId, 'p_reason': reason},
      );
      return;
    } catch (_) {}

    await _client
        .from('orders')
        .update({
          'status': 'cancelled',
          'notes': 'Admin cancelled: ${reason ?? "Administrative action"}',
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', orderId);
  }

  Future<void> reassignRider(
    String orderId,
    String riderId, {
    String? reason,
  }) async {
    try {
      await _client.rpc(
        'admin_reassign_rider',
        params: {
          'p_order_id': orderId,
          'p_rider_id': riderId,
          'p_reason': reason,
        },
      );
      return;
    } catch (_) {}

    await _client
        .from('orders')
        .update({
          'rider_id': riderId,
          'status': 'assigned_to_rider',
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', orderId);
  }

  Future<void> refundOrder(String orderId, {String? reason}) async {
    try {
      await _client.rpc(
        'admin_refund_order',
        params: {'p_order_id': orderId, 'p_reason': reason},
      );
      return;
    } catch (_) {}

    await _client
        .from('orders')
        .update({
          'payment_status': 'refunded',
          'status': 'cancelled',
          'notes': 'Refunded: ${reason ?? "Administrative refund"}',
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', orderId);
  }

  // --- Live Fleet ---

  Future<List<Map<String, dynamic>>> listLiveRiders({String? regionId}) async {
    try {
      final result = await _client.rpc(
        'admin_list_live_riders',
        params: {'p_region_id': regionId},
      );
      if (result is List && result.isNotEmpty) {
        return result.map((r) => Map<String, dynamic>.from(r as Map)).toList();
      }
    } catch (_) {}

    try {
      final riders = await _client
          .from('profiles')
          .select(
            'id, full_name, phone, vehicle_type, license_number, is_online, updated_at',
          )
          .eq('role', 'rider');
      return List<Map<String, dynamic>>.from(riders);
    } catch (e) {
      debugPrint('listLiveRiders fallback error: $e');
      return [];
    }
  }

  // --- Onboarding & Creation ---

  Future<Map<String, dynamic>> createUser({
    required String email,
    required String password,
    required String role,
    required String fullName,
    String? phone,
    String? town,
    String? barangay,
    String? ownerId,
    String? regionId,
    String? reason,
  }) async {
    try {
      final result = await _client.rpc(
        'admin_create_user',
        params: {
          'p_email': email,
          'p_password': password,
          'p_role': role,
          'p_full_name': fullName,
          'p_phone': phone,
          'p_town': town,
          'p_barangay': barangay,
          'p_owner_id': ownerId,
          'p_region_id': regionId,
          'p_reason': reason,
        },
      );
      return _asMap(result);
    } catch (e) {
      debugPrint('createUser error: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> createStation({
    required String email,
    required String password,
    required String stationName,
    required String ownerName,
    String? phone,
    String? town,
    String? barangay,
    String? completeAddress,
    double? latitude,
    double? longitude,
    String? regionId,
    double? baseDeliveryFee,
    double? pricePerGallon,
    String? reason,
  }) async {
    try {
      final result = await _client.rpc(
        'admin_create_station',
        params: {
          'p_email': email,
          'p_password': password,
          'p_station_name': stationName,
          'p_owner_name': ownerName,
          'p_phone': phone,
          'p_town': town,
          'p_barangay': barangay,
          'p_complete_address': completeAddress,
          'p_latitude': latitude,
          'p_longitude': longitude,
          'p_region_id': regionId,
          'p_base_delivery_fee': baseDeliveryFee,
          'p_price_per_gallon': pricePerGallon,
          'p_reason': reason,
        },
      );
      return _asMap(result);
    } catch (e) {
      debugPrint('createStation error: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> createSignupUser({
    required String email,
    required String password,
    required String role,
    required String fullName,
    required String firstName,
    required String lastName,
    required String username,
    String? phone,
    required String town,
    required String barangay,
    required String waterType,
    String? middleInitial,
    String? suffix,
    String? completeAddress,
    String? landmark,
    double? latitude,
    double? longitude,
    String? ownerId,
  }) async {
    try {
      final result = await _client.rpc(
        'admin_create_signup_user',
        params: {
          'p_email': email,
          'p_password': password,
          'p_role': role,
          'p_full_name': fullName,
          'p_phone': phone,
          'p_town': town,
          'p_barangay': role == 'rider' && barangay.isEmpty ? null : barangay,
          'p_owner_id': ownerId,
          'p_region_id': null,
          'p_reason': 'Created from admin signup form',
          'p_username': username,
          'p_first_name': firstName,
          'p_last_name': lastName,
          'p_middle_initial': middleInitial,
          'p_suffix': suffix,
          'p_complete_address': completeAddress,
          'p_landmark': landmark,
          'p_latitude': latitude,
          'p_longitude': longitude,
          'p_water_type': waterType,
        },
      );
      return _asMap(result);
    } catch (e) {
      debugPrint('createSignupUser error: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> createSignupStation({
    required String email,
    required String password,
    required String stationName,
    required String ownerName,
    required String firstName,
    required String lastName,
    required String username,
    required String phone,
    required String town,
    required String barangay,
    required String completeAddress,
    required String primaryWaterType,
    required double latitude,
    required double longitude,
    String? middleInitial,
    String? suffix,
  }) async {
    try {
      final result = await _client.rpc(
        'admin_create_signup_station',
        params: {
          'p_email': email,
          'p_password': password,
          'p_station_name': stationName,
          'p_owner_name': ownerName,
          'p_phone': phone,
          'p_town': town,
          'p_barangay': barangay,
          'p_complete_address': completeAddress,
          'p_latitude': latitude,
          'p_longitude': longitude,
          'p_region_id': null,
          'p_base_delivery_fee': null,
          'p_price_per_gallon': null,
          'p_reason': 'Created from admin signup form',
          'p_username': username,
          'p_first_name': firstName,
          'p_last_name': lastName,
          'p_middle_initial': middleInitial,
          'p_suffix': suffix,
          'p_primary_water_type': primaryWaterType,
        },
      );
      return _asMap(result);
    } catch (e) {
      debugPrint('createSignupStation error: $e');
      rethrow;
    }
  }

  // --- Payments & Disputes ---

  Future<AdminPagedResult<Map<String, dynamic>>> listPaymentFailures({
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      final result = await _client.rpc(
        'admin_list_payment_failures',
        params: {'p_limit': limit, 'p_offset': offset},
      );
      return _parsePaged(result);
    } catch (_) {}

    try {
      final rows = await _client
          .from('orders')
          .select('*')
          .eq('payment_status', 'failed')
          .range(offset, offset + limit - 1);
      return AdminPagedResult(
        total: (rows as List).length,
        rows: List<Map<String, dynamic>>.from(rows),
      );
    } catch (_) {
      return const AdminPagedResult(total: 0, rows: []);
    }
  }

  Future<void> retryPaymentEvent(String eventId, {String? reason}) async {
    try {
      await _client.rpc(
        'admin_retry_payment_event',
        params: {'p_event_id': eventId, 'p_reason': reason},
      );
    } catch (e) {
      debugPrint('retryPaymentEvent error: $e');
      rethrow;
    }
  }

  Future<AdminPagedResult<Map<String, dynamic>>> listDisputes({
    int limit = 50,
    int offset = 0,
    String? status,
  }) async {
    try {
      final result = await _client.rpc(
        'admin_list_disputes',
        params: {'p_limit': limit, 'p_offset': offset, 'p_status': status},
      );
      return _parsePaged(result);
    } catch (_) {}

    return const AdminPagedResult(total: 0, rows: []);
  }

  Future<void> updateDispute(
    String disputeId,
    String status, {
    String? resolutionNotes,
  }) async {
    try {
      await _client.rpc(
        'admin_update_dispute',
        params: {
          'p_dispute_id': disputeId,
          'p_status': status,
          'p_resolution_notes': resolutionNotes,
        },
      );
    } catch (e) {
      debugPrint('updateDispute error: $e');
      rethrow;
    }
  }

  Future<AdminPagedResult<Map<String, dynamic>>> listReviews({
    int limit = 50,
    int offset = 0,
    int? maxRating,
  }) async {
    try {
      final result = await _client.rpc(
        'admin_list_reviews',
        params: {
          'p_limit': limit,
          'p_offset': offset,
          'p_min_rating': maxRating,
        },
      );
      return _parsePaged(result);
    } catch (_) {}

    try {
      final rows = await _client
          .from('reviews')
          .select('*')
          .range(offset, offset + limit - 1);
      return AdminPagedResult(
        total: (rows as List).length,
        rows: List<Map<String, dynamic>>.from(rows),
      );
    } catch (_) {
      return const AdminPagedResult(total: 0, rows: []);
    }
  }

  Future<void> deleteReview(String reviewId, {String? reason}) async {
    try {
      await _client.rpc(
        'admin_delete_review',
        params: {'p_review_id': reviewId, 'p_reason': reason},
      );
      return;
    } catch (_) {}

    try {
      await _client.from('reviews').delete().eq('id', reviewId);
    } catch (e) {
      debugPrint('deleteReview error: $e');
    }
  }

  // --- Suspension ---

  Future<void> suspendUser(String userId, {String? reason}) async {
    try {
      await _client.rpc(
        'admin_suspend_user',
        params: {'p_user_id': userId, 'p_reason': reason},
      );
      return;
    } catch (_) {}

    try {
      await _client
          .from('profiles')
          .update({
            'is_suspended': true,
            'suspended_reason': reason ?? 'Suspended by admin',
          })
          .eq('id', userId);
    } catch (e) {
      debugPrint('suspendUser error: $e');
    }
  }

  Future<void> unsuspendUser(String userId, {String? reason}) async {
    try {
      await _client.rpc(
        'admin_unsuspend_user',
        params: {'p_user_id': userId, 'p_reason': reason},
      );
      return;
    } catch (_) {}

    try {
      await _client
          .from('profiles')
          .update({'is_suspended': false, 'suspended_reason': null})
          .eq('id', userId);
    } catch (e) {
      debugPrint('unsuspendUser error: $e');
    }
  }

  // --- Products & Catalog ---

  Future<List<Map<String, dynamic>>> listStationProducts(String ownerId) async {
    try {
      final result = await _client.rpc(
        'admin_list_station_products',
        params: {'p_owner_id': ownerId},
      );
      if (result is List && result.isNotEmpty) {
        return result.map((r) => Map<String, dynamic>.from(r as Map)).toList();
      }
    } catch (_) {}

    try {
      final rows = await _client
          .from('products')
          .select('*')
          .eq('owner_id', ownerId);
      return List<Map<String, dynamic>>.from(rows);
    } catch (_) {
      return [];
    }
  }

  Future<Map<String, dynamic>> upsertProduct({
    String? productId,
    String? ownerId,
    String? name,
    String? description,
    double? price,
    String? category,
    int? stockLevel,
    bool? isAvailable,
    String? reason,
  }) async {
    try {
      final result = await _client.rpc(
        'admin_upsert_product',
        params: {
          'p_product_id': productId,
          'p_owner_id': ownerId,
          'p_name': name,
          'p_description': description,
          'p_price': price,
          'p_category': category,
          'p_stock_level': stockLevel,
          'p_is_available': isAvailable,
          'p_reason': reason,
        },
      );
      final map = _asMap(result);
      if (map.isNotEmpty) return map;
    } catch (_) {}

    return {};
  }

  Future<void> deleteProduct(String productId, {String? reason}) async {
    try {
      await _client.rpc(
        'admin_delete_product',
        params: {'p_product_id': productId, 'p_reason': reason},
      );
    } catch (_) {}
  }

  // --- Notifications ---

  Future<void> sendNotification({
    required String userId,
    required String title,
    required String content,
    String type = 'system_alert',
    String priority = 'normal',
  }) async {
    try {
      await _client.rpc(
        'admin_send_notification',
        params: {
          'p_user_id': userId,
          'p_title': title,
          'p_content': content,
          'p_type': type,
          'p_priority': priority,
        },
      );
      return;
    } catch (_) {}

    try {
      await _client.from('system_notifications').insert({
        'user_id': userId,
        'title': title,
        'content': content,
        'type': type,
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('sendNotification fallback error: $e');
    }
  }

  Future<int> broadcastNotification({
    required String role,
    required String title,
    required String content,
    String priority = 'normal',
  }) async {
    try {
      final result = await _client.rpc(
        'admin_broadcast_notification',
        params: {
          'p_role': role,
          'p_title': title,
          'p_content': content,
          'p_priority': priority,
        },
      );
      final map = result is Map
          ? Map<String, dynamic>.from(result)
          : <String, dynamic>{};
      if (map.containsKey('sent_count')) return safeInt(map['sent_count']);
    } catch (_) {}

    try {
      dynamic query = _client.from('profiles').select('id');
      if (role != 'all') query = query.eq('role', role);
      final users = await query;
      final rows = (users as List)
          .map(
            (u) => {
              'user_id': u['id'],
              'title': title,
              'content': content,
              'type': 'broadcast',
              'created_at': DateTime.now().toIso8601String(),
            },
          )
          .toList();
      if (rows.isNotEmpty) {
        await _client.from('system_notifications').insert(rows);
      }
      return rows.length;
    } catch (e) {
      debugPrint('broadcastNotification fallback error: $e');
      return 0;
    }
  }

  // --- Multi-Admin & Timeline ---

  Future<List<Map<String, dynamic>>> listAdmins() async {
    try {
      final result = await _client.rpc('admin_list_admins');
      if (result is List && result.isNotEmpty) {
        return result.map((r) => Map<String, dynamic>.from(r as Map)).toList();
      }
    } catch (_) {}

    try {
      final rows = await _client
          .from('profiles')
          .select('id, full_name, email, role, created_at')
          .eq('role', 'admin');
      return List<Map<String, dynamic>>.from(rows);
    } catch (_) {
      return [];
    }
  }

  Future<void> setAdminTier(
    String userId,
    String tier, {
    String? reason,
  }) async {
    try {
      await _client.rpc(
        'admin_set_admin_tier',
        params: {'p_user_id': userId, 'p_tier': tier, 'p_reason': reason},
      );
    } catch (e) {
      debugPrint('setAdminTier error: $e');
    }
  }

  Future<List<Map<String, dynamic>>> getActivityTimeline(
    String entityType,
    String entityId,
  ) async {
    try {
      final result = await _client.rpc(
        'admin_get_activity_timeline',
        params: {'p_entity_type': entityType, 'p_entity_id': entityId},
      );
      final map = _asMap(result);
      final events = map['events'];
      if (events is List) {
        return events.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (_) {}

    return [];
  }

  Future<AdminPagedResult<Map<String, dynamic>>> listInventoryLedger(
    String ownerId, {
    int limit = 100,
    int offset = 0,
  }) async {
    try {
      final result = await _client.rpc(
        'admin_list_inventory_ledger',
        params: {'p_owner_id': ownerId, 'p_limit': limit, 'p_offset': offset},
      );
      return _parsePaged(result);
    } catch (_) {}

    try {
      final rows = await _client
          .from('owner_inventory_ledger')
          .select('*')
          .eq('owner_id', ownerId)
          .range(offset, offset + limit - 1);
      return AdminPagedResult(
        total: (rows as List).length,
        rows: List<Map<String, dynamic>>.from(rows),
      );
    } catch (_) {
      return const AdminPagedResult(total: 0, rows: []);
    }
  }

  // --- App Release Management ---

  Future<List<Map<String, dynamic>>> listAppReleases() async {
    try {
      final rows = await _client
          .from('app_releases')
          .select('*')
          .order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(rows);
    } catch (e) {
      debugPrint('listAppReleases error: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> listAppReleaseAuditLogs({int limit = 50}) async {
    try {
      final rows = await _client
          .from('app_release_audit_logs')
          .select('*')
          .order('created_at', ascending: false)
          .limit(limit);
      return List<Map<String, dynamic>>.from(rows);
    } catch (e) {
      debugPrint('listAppReleaseAuditLogs error: $e');
      return [];
    }
  }

  Future<void> createAppRelease(Map<String, dynamic> data) async {
    await _client.from('app_releases').insert(data);
  }

  Future<void> updateAppRelease(String id, Map<String, dynamic> data) async {
    await _client.from('app_releases').update(data).eq('id', id);
  }

  Future<Map<String, dynamic>> publishAppRelease(String releaseId) async {
    final res = await _client.rpc(
      'publish_app_release',
      params: {'p_release_id': releaseId},
    );
    return _asMap(res);
  }

  Future<void> deleteAppRelease(String releaseId) async {
    await _client.from('app_releases').delete().eq('id', releaseId);
  }

  AdminPagedResult<Map<String, dynamic>> _parsePaged(dynamic result) {
    if (result is! Map) return const AdminPagedResult(total: 0, rows: []);
    final map = Map<String, dynamic>.from(result);
    final total = safeInt(map['total']);
    final rowsRaw = map['rows'];
    final rows = rowsRaw is List
        ? rowsRaw.map((row) => Map<String, dynamic>.from(row as Map)).toList()
        : <Map<String, dynamic>>[];
    return AdminPagedResult(total: total, rows: rows);
  }
}

class AdminPagedResult<T> {
  const AdminPagedResult({required this.total, required this.rows});

  final int total;
  final List<T> rows;
}
