import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:erefill/core/constants.dart';
import 'package:erefill/core/widgets/refill_status_widgets.dart';
import 'package:erefill/core/services/local_data_cache.dart';
import 'package:erefill/core/utils/app_haptics.dart';
import 'package:erefill/features/dashboard/admin/utils/admin_csv_export.dart';
import 'package:erefill/features/dashboard/admin/views/admin_live_map_view.dart';
import 'package:erefill/features/dashboard/admin/views/admin_moderation_view.dart';
import 'package:erefill/features/dashboard/admin/views/admin_broadcast_dialog.dart';
import 'package:erefill/features/dashboard/admin/views/admin_audit_log_view.dart';
import 'package:erefill/features/dashboard/admin/views/admin_payment_failures_view.dart';
import 'package:erefill/features/dashboard/admin/views/admin_create_dialogs.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen>
    with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;
  late final TabController _tabController;

  bool _loading = true;
  String? _error;
  String? _dataRefreshError;
  bool _hasFreshMetrics = false;

  // Platform Metrics
  Map<String, dynamic> _stats = {};
  List<Map<String, dynamic>> _stations = [];
  List<Map<String, dynamic>> _orders = [];
  List<Map<String, dynamic>> _users = [];

  // Filter States
  String _stationFilter = 'all';
  String _stationSearch = '';
  String _orderFilter = 'all';
  String _orderSearch = '';
  String _userRoleFilter = 'all';
  String _userSearch = '';

  // Config States
  double _platformFeePercent = 5.0;
  double _platformFeeFixed = 2.0;
  bool _maintenanceMode = false;
  bool _systemConfigLoaded = false;
  String? _systemConfigError;
  int _settingsSubTab = 0;

  RealtimeChannel? _realtimeChannel;
  Timer? _realtimeDebounce;
  int _unreadNotifications = 0;
  final List<Map<String, dynamic>> _liveNotifications = [];

  final currencyFormat = NumberFormat.currency(
    locale: 'en_PH',
    symbol: '₱',
    decimalDigits: 2,
  );

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _loadDiskCache();
    _loadAllData();
    _setupRealtime();
  }

  void _setupRealtime() {
    try {
      _realtimeChannel = supabase.channel('mobile_admin_realtime_events')
        ..onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'orders',
          callback: (payload) {
            final id = payload.newRecord['id']?.toString() ?? '';
            final shortId = id.length >= 8 ? id.substring(0, 8) : id;
            final status = payload.newRecord['status']?.toString() ?? 'updated';
            _onLiveEvent(
              title: 'Order Status: $status',
              description: 'Order #$shortId changed status to $status.',
              icon: Icons.receipt_long_rounded,
              color: AppUi.bluePrimary,
            );
          },
        )
        ..onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'water_refill_stations',
          callback: (payload) {
            final name = payload.newRecord['name']?.toString() ?? 'Station';
            final status = payload.newRecord['status']?.toString() ?? 'updated';
            _onLiveEvent(
              title: 'Station Activity',
              description: 'Station "$name" status: $status.',
              icon: Icons.storefront_rounded,
              color: const Color(0xFF087E8B),
            );
          },
        )
        ..onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'disputes',
          callback: (_) {
            _onLiveEvent(
              title: 'Customer Dispute',
              description: 'A customer dispute was logged or modified.',
              icon: Icons.gavel_rounded,
              color: AppUi.warningFg,
            );
          },
        )
        ..subscribe();
    } catch (_) {}
  }

  void _onLiveEvent({
    required String title,
    required String description,
    required IconData icon,
    required Color color,
  }) {
    if (!mounted) return;
    setState(() {
      _liveNotifications.insert(0, {
        'title': title,
        'description': description,
        'time': DateTime.now(),
        'icon': icon,
        'color': color,
        'read': false,
      });
      _unreadNotifications++;
    });

    _realtimeDebounce?.cancel();
    _realtimeDebounce = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) _loadAllData();
    });
  }

  Future<void> _loadDiskCache() async {
    final cached = await LocalDataCache.instance.get<Map<String, dynamic>>(
      'admin_dashboard_cache',
    );
    if (cached != null && mounted) {
      setState(() {
        _users = List<Map<String, dynamic>>.from(
          cached['users'] as List? ?? const [],
        );
        _stations = List<Map<String, dynamic>>.from(
          cached['stations'] as List? ?? const [],
        );
        _orders = List<Map<String, dynamic>>.from(
          cached['orders'] as List? ?? const [],
        );
        _stats = Map<String, dynamic>.from(cached['stats'] as Map? ?? const {});
        _hasFreshMetrics = false;
        _systemConfigLoaded = false;
        _systemConfigError = null;
        _loading = false; // Zero waiting time for admins!
      });
    }
  }

  @override
  void dispose() {
    _realtimeDebounce?.cancel();
    _realtimeChannel?.unsubscribe();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAllData() async {
    if (!mounted) return;
    if (_users.isEmpty && _stations.isEmpty) {
      setState(() {
        _loading = true;
      });
    }
    setState(() {
      _error = null;
      _dataRefreshError = null;
      _hasFreshMetrics = false;
      _systemConfigLoaded = false;
      _systemConfigError = null;
    });

    try {
      // 1. Fetch Profiles
      final profilesRes = await supabase
          .from('profiles')
          .select(
            'id, full_name, email, phone, role, is_suspended, suspended_reason, created_at',
          )
          .order('created_at', ascending: false);
      final profilesList = List<Map<String, dynamic>>.from(profilesRes);

      // 2. Fetch Stations
      final stationsRes = await supabase
          .from('water_refill_stations')
          .select(
            'id, owner_id, name, address, town, is_accepting_orders, status, rating, price_per_gallon, base_delivery_fee, created_at',
          )
          .order('created_at', ascending: false);
      final stationsList = List<Map<String, dynamic>>.from(stationsRes);

      // 3. Fetch Recent Orders
      final ordersRes = await supabase
          .from('orders')
          .select(
            'id, customer_id, owner_id, rider_id, assigned_rider_id, '
            'station_name, customer_name, customer_phone, customer_address, '
            'status, subtotal, delivery_fee, total_amount, payment_method, '
            'payment_status, items, notes, created_at',
          )
          .order('created_at', ascending: false)
          .limit(100);
      final ordersList = List<Map<String, dynamic>>.from(ordersRes);

      final usersCountResponse = await supabase
          .from('profiles')
          .select('id')
          .count();
      final stationsCountResponse = await supabase
          .from('water_refill_stations')
          .select('id')
          .count();
      final ordersCountResponse = await supabase
          .from('orders')
          .select('id')
          .count();

      // Aggregate Stats
      int customers = 0;
      int owners = 0;
      int riders = 0;
      int admins = 0;
      for (final p in profilesList) {
        final r = p['role']?.toString().toLowerCase();
        if (r == 'customer') customers++;
        if (r == 'owner') owners++;
        if (r == 'rider') riders++;
        if (r == 'admin') admins++;
      }

      int openStations = 0;
      int pendingStations = 0;
      int suspendedStations = 0;
      for (final s in stationsList) {
        if (s['is_accepting_orders'] == true) openStations++;
        final st = s['status']?.toString().toLowerCase();
        if (st == 'pending' || st == 'pending_verification') pendingStations++;
        if (st == 'suspended') suspendedStations++;
      }

      double totalGmv = 0.0;
      double todayGmv = 0.0;
      final todayStr = DateTime.now().toIso8601String().split('T').first;

      for (final o in ordersList) {
        final st = o['status']?.toString().toLowerCase();
        final amt = o['total_amount'] is num
            ? (o['total_amount'] as num).toDouble()
            : (double.tryParse(o['total_amount']?.toString() ?? '') ?? 0.0);
        final createdAt = o['created_at']?.toString() ?? '';
        if (st == 'delivered') {
          totalGmv += amt;
          if (createdAt.startsWith(todayStr)) {
            todayGmv += amt;
          }
        }
      }

      String? systemConfigError;
      var maintenanceConfigFound = false;
      var maintenanceMode = _maintenanceMode;
      var platformFeePercent = _platformFeePercent;
      var platformFeeFixed = _platformFeeFixed;
      try {
        final configRes = await supabase
            .from('system_config')
            .select('key, value')
            .inFilter('key', ['maintenance_mode', 'platform_fee']);
        for (final row in configRes) {
          if (row['key'] == 'maintenance_mode') {
            maintenanceConfigFound = true;
            maintenanceMode = row['value'] == true || row['value'] == 'true';
          } else if (row['key'] == 'platform_fee' && row['value'] is Map) {
            final map = row['value'] as Map;
            platformFeePercent = (map['percent'] as num?)?.toDouble() ?? 5.0;
            platformFeeFixed = (map['fixed'] as num?)?.toDouble() ?? 2.0;
          }
        }
        if (!maintenanceConfigFound) {
          throw StateError('Maintenance mode configuration is missing.');
        }
      } catch (e) {
        systemConfigError = e.toString();
        debugPrint('Admin system configuration load failed: $e');
      }

      if (!mounted) return;
      setState(() {
        _users = profilesList;
        _stations = stationsList;
        _orders = ordersList;
        _stats = {
          'customers': customers,
          'owners': owners,
          'riders': riders,
          'admins': admins,
          'total_users': usersCountResponse.count,
          'stations_count': stationsCountResponse.count,
          'open_stations': openStations,
          'pending_stations': pendingStations,
          'suspended_stations': suspendedStations,
          'orders_count': ordersCountResponse.count,
          'total_gmv': totalGmv,
          'today_gmv': todayGmv,
        };
        _maintenanceMode = maintenanceMode;
        _platformFeePercent = platformFeePercent;
        _platformFeeFixed = platformFeeFixed;
        _systemConfigLoaded = true;
        _systemConfigError = systemConfigError;
        _hasFreshMetrics = true;
        _loading = false;
      });

      LocalDataCache.instance.set('admin_dashboard_cache', {
        'users': profilesList,
        'stations': stationsList,
        'orders': ordersList,
        'stats': _stats,
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _dataRefreshError = e.toString();
        _hasFreshMetrics = false;
        _error = _users.isEmpty && _stations.isEmpty && _orders.isEmpty
            ? 'Failed to load admin telemetry: $e'
            : null;
        _loading = false;
      });
    }
  }

  // --- Actions ---

  Future<void> _approveStation(
    String stationId,
    String? ownerId,
    String stationName,
  ) async {
    HapticFeedback.mediumImpact();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Approve Station Verification'),
        content: Text(
          'Are you sure you want to approve "$stationName"? This allows the station to go live and accept orders.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppUi.bluePrimary,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Verify & Approve'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final nowIso = DateTime.now().toIso8601String();
      await supabase
          .from('water_refill_stations')
          .update({
            'status': 'active',
            'is_accepting_orders': true,
            'updated_at': nowIso,
          })
          .eq('id', stationId);

      if (ownerId != null && ownerId.isNotEmpty) {
        await supabase
            .from('profiles')
            .update({
              'is_suspended': false,
              'station_availability': 'open',
              'is_open': true,
              'updated_at': nowIso,
            })
            .eq('id', ownerId);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Station "$stationName" has been verified and approved.',
            ),
            backgroundColor: AppUi.accentGreen,
          ),
        );
        _loadAllData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not approve station: $e'),
            backgroundColor: AppUi.error,
          ),
        );
      }
    }
  }

  Future<void> _toggleSuspendStation(
    String stationId,
    String? ownerId,
    String stationName,
    bool currentlySuspended,
  ) async {
    HapticFeedback.mediumImpact();
    final newStatus = currentlySuspended ? 'active' : 'suspended';
    final actionName = currentlySuspended ? 'Reactivate' : 'Suspend';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$actionName Station'),
        content: Text('Are you sure you want to $actionName "$stationName"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: currentlySuspended
                  ? AppUi.bluePrimary
                  : AppUi.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(actionName),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final nowIso = DateTime.now().toIso8601String();
      await supabase
          .from('water_refill_stations')
          .update({
            'status': newStatus,
            'is_accepting_orders': currentlySuspended ? true : false,
            'updated_at': nowIso,
          })
          .eq('id', stationId);

      if (ownerId != null && ownerId.isNotEmpty) {
        await supabase
            .from('profiles')
            .update({
              'is_suspended': !currentlySuspended,
              'suspended_reason': !currentlySuspended
                  ? 'Station suspended by administrator'
                  : null,
              'station_availability': currentlySuspended ? 'open' : 'suspended',
              'is_open': currentlySuspended,
              'updated_at': nowIso,
            })
            .eq('id', ownerId);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Station "$stationName" is now $newStatus.'),
            backgroundColor: currentlySuspended
                ? AppUi.accentGreen
                : AppUi.error,
          ),
        );
        _loadAllData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating station status: $e'),
            backgroundColor: AppUi.error,
          ),
        );
      }
    }
  }

  Future<void> _toggleUserSuspension(Map<String, dynamic> user) async {
    HapticFeedback.mediumImpact();
    final isSuspended = user['is_suspended'] == true;
    final userId = user['id'] as String;
    final userName = user['full_name'] ?? user['email'] ?? 'User';
    final role = user['role']?.toString().toLowerCase();

    String reason = '';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isSuspended ? 'Reactivate Account' : 'Suspend Account'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isSuspended
                  ? 'Reactivate account access for "$userName"?'
                  : 'Suspend account access for "$userName"? They will be locked out immediately.',
            ),
            if (!isSuspended) ...[
              const SizedBox(height: 16),
              TextField(
                decoration: InputDecoration(
                  labelText: 'Suspension Reason',
                  hintText: 'e.g. Terms violation, fraudulent activity',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onChanged: (val) => reason = val,
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: isSuspended ? AppUi.bluePrimary : AppUi.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(isSuspended ? 'Reactivate' : 'Suspend'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final nowIso = DateTime.now().toIso8601String();
      await supabase
          .from('profiles')
          .update({
            'is_suspended': !isSuspended,
            'suspended_reason': !isSuspended
                ? (reason.isEmpty ? 'Suspended by admin' : reason)
                : null,
            'updated_at': nowIso,
          })
          .eq('id', userId);

      // If user is a station owner, keep water_refill_stations synchronized
      if (role == 'owner') {
        try {
          await supabase
              .from('water_refill_stations')
              .update({
                'status': !isSuspended ? 'suspended' : 'active',
                'is_accepting_orders': isSuspended,
                'updated_at': nowIso,
              })
              .eq('owner_id', userId);
        } catch (_) {}
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Account for "$userName" ${!isSuspended ? "suspended" : "reactivated"}.',
            ),
            backgroundColor: isSuspended ? AppUi.accentGreen : AppUi.error,
          ),
        );
        _loadAllData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating user state: $e'),
            backgroundColor: AppUi.error,
          ),
        );
      }
    }
  }

  Future<void> _changeUserRole(Map<String, dynamic> u) async {
    final userId = u['id']?.toString() ?? '';
    final currentRole = (u['role'] ?? 'customer').toString().toLowerCase();
    String selectedRole = currentRole;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('Change Role for ${u['full_name'] ?? "User"}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Select the new access role:'),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: selectedRole,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: const [
                  DropdownMenuItem(value: 'customer', child: Text('Customer')),
                  DropdownMenuItem(
                    value: 'owner',
                    child: Text('Station Owner'),
                  ),
                  DropdownMenuItem(
                    value: 'rider',
                    child: Text('Delivery Rider'),
                  ),
                  DropdownMenuItem(value: 'admin', child: Text('System Admin')),
                ],
                onChanged: (v) {
                  if (v != null) setDialogState(() => selectedRole = v);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppUi.bluePrimary,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Update Role'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || !mounted) return;
    try {
      AppHaptics.medium();
      await supabase
          .from('profiles')
          .update({
            'role': selectedRole,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', userId);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('User role updated to ${selectedRole.toUpperCase()}'),
          backgroundColor: AppColors.statusDelivered,
        ),
      );
      _loadAllData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update role: $e'),
          backgroundColor: AppUi.error,
        ),
      );
    }
  }

  Future<void> _resetUserPassword(Map<String, dynamic> u) async {
    final email = u['email']?.toString() ?? '';
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('User has no registered email.'),
          backgroundColor: AppUi.error,
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Send Password Reset?'),
        content: Text('Send a password recovery link to $email?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppUi.bluePrimary,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Send Reset Link'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    try {
      AppHaptics.medium();
      await supabase.auth.resetPasswordForEmail(email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Reset password link sent to $email'),
          backgroundColor: AppColors.statusDelivered,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to send reset link: $e'),
          backgroundColor: AppUi.error,
        ),
      );
    }
  }

  Future<void> _reassignRider(String orderId) async {
    final riders = _users
        .where(
          (u) =>
              u['role']?.toString().toLowerCase() == 'rider' &&
              u['is_suspended'] != true,
        )
        .toList();

    if (riders.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No active riders registered in system.'),
          backgroundColor: AppUi.error,
        ),
      );
      return;
    }

    String? selectedRiderId = riders.first['id']?.toString();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Assign / Reassign Rider'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Select delivery rider for this order:'),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: selectedRiderId,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: riders.map((r) {
                  final isOnline = r['is_online'] == true;
                  return DropdownMenuItem<String>(
                    value: r['id']?.toString(),
                    child: Text(
                      '${r['full_name'] ?? "Rider"} (${isOnline ? "🟢 Online" : "⚪ Offline"})',
                    ),
                  );
                }).toList(),
                onChanged: (v) {
                  if (v != null) setDialogState(() => selectedRiderId = v);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppUi.bluePrimary,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Assign Rider'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || selectedRiderId == null || !mounted) return;
    try {
      AppHaptics.medium();
      await supabase
          .from('orders')
          .update({
            'rider_id': selectedRiderId,
            'assigned_rider_id': selectedRiderId,
            'status': 'accepted',
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', orderId);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Rider assigned successfully!'),
          backgroundColor: AppColors.statusDelivered,
        ),
      );
      _loadAllData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to assign rider: $e'),
          backgroundColor: AppUi.error,
        ),
      );
    }
  }

  Future<void> _markOrderDelivered(String orderId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mark Order as Delivered?'),
        content: Text(
          'Force update status of Order #${orderId.substring(0, 8)} to DELIVERED?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.statusDelivered,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirm Delivered'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    try {
      AppHaptics.medium();
      await supabase
          .from('orders')
          .update({
            'status': 'delivered',
            'payment_status': 'paid',
            'delivered_at': DateTime.now().toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', orderId);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Order marked as DELIVERED.'),
          backgroundColor: AppColors.statusDelivered,
        ),
      );
      _loadAllData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update status: $e'),
          backgroundColor: AppUi.error,
        ),
      );
    }
  }

  Future<void> _rejectStation(
    String stationId,
    String? ownerId,
    String name,
  ) async {
    final reasonController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Reject "$name"?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter compliance rejection feedback for the station owner:',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                labelText: 'Rejection Reason *',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppUi.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reject Station'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    try {
      AppHaptics.medium();
      await supabase
          .from('water_refill_stations')
          .update({
            'status': 'rejected',
            'is_accepting_orders': false,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', stationId);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Station "$name" rejected with feedback.'),
          backgroundColor: AppUi.error,
        ),
      );
      _loadAllData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to reject station: $e'),
          backgroundColor: AppUi.error,
        ),
      );
    }
  }

  void _exportOrdersCsv() {
    AppHaptics.medium();
    final headers = [
      'Order ID',
      'Date',
      'Customer',
      'Station',
      'Total Amount',
      'Status',
      'Payment Method',
      'Payment Status',
    ];
    final rows = _orders
        .map(
          (o) => [
            o['id']?.toString() ?? '',
            (o['created_at']?.toString() ?? '').split('T').first,
            o['customer_name']?.toString() ?? '',
            o['station_name']?.toString() ?? '',
            '₱${o['total_amount'] ?? 0}',
            o['status']?.toString() ?? '',
            o['payment_method']?.toString() ?? '',
            o['payment_status']?.toString() ?? '',
          ],
        )
        .toList();

    final csv = AdminCsvExport.build(headers, rows);
    AdminCsvExport.copyToClipboard(csv);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          '📊 Orders CSV copied to clipboard! Paste directly into Excel or Google Sheets.',
        ),
        backgroundColor: AppColors.statusDelivered,
      ),
    );
  }

  void _exportStationsCsv() {
    AppHaptics.medium();
    final headers = [
      'Station ID',
      'Station Name',
      'Address',
      'Town',
      'Status',
      'Accepting Orders',
      'Price/Gallon',
      'Base Delivery Fee',
      'Rating',
    ];
    final rows = _stations
        .map(
          (s) => [
            s['id']?.toString() ?? '',
            s['name']?.toString() ?? '',
            s['address']?.toString() ?? '',
            s['town']?.toString() ?? '',
            s['status']?.toString() ?? '',
            s['is_accepting_orders'] == true ? 'YES' : 'NO',
            '₱${s['price_per_gallon'] ?? 0}',
            '₱${s['base_delivery_fee'] ?? 0}',
            '${s['rating'] ?? "N/A"}',
          ],
        )
        .toList();

    final csv = AdminCsvExport.build(headers, rows);
    AdminCsvExport.copyToClipboard(csv);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          '📊 Stations CSV copied to clipboard! Paste directly into Excel or Google Sheets.',
        ),
        backgroundColor: AppColors.statusDelivered,
      ),
    );
  }

  void _exportUsersCsv() {
    AppHaptics.medium();
    final headers = [
      'User ID',
      'Full Name',
      'Role',
      'Email',
      'Phone',
      'Town',
      'Suspended',
      'Joined Date',
    ];
    final rows = _users
        .map(
          (u) => [
            u['id']?.toString() ?? '',
            u['full_name']?.toString() ?? '',
            u['role']?.toString() ?? '',
            u['email']?.toString() ?? '',
            u['phone']?.toString() ?? '',
            u['town']?.toString() ?? '',
            u['is_suspended'] == true ? 'YES' : 'NO',
            (u['created_at']?.toString() ?? '').split('T').first,
          ],
        )
        .toList();

    final csv = AdminCsvExport.build(headers, rows);
    AdminCsvExport.copyToClipboard(csv);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          '📊 Users CSV copied to clipboard! Paste directly into Excel or Google Sheets.',
        ),
        backgroundColor: AppColors.statusDelivered,
      ),
    );
  }

  void _showExportReportsSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.download_rounded, color: AppUi.bluePrimary),
                const SizedBox(width: 8),
                Text(
                  'Export Marketplace Reports (CSV)',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: AppUi.textPrimaryOf(context),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(
                Icons.receipt_long_rounded,
                color: AppUi.bluePrimary,
              ),
              title: const Text(
                'Export Orders CSV',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                '${_orders.length} orders with revenue & payment status',
              ),
              onTap: () {
                Navigator.pop(ctx);
                _exportOrdersCsv();
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.storefront_rounded,
                color: Color(0xFF087E8B),
              ),
              title: const Text(
                'Export Water Stations CSV',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                '${_stations.length} stations with compliance & pricing',
              ),
              onTap: () {
                Navigator.pop(ctx);
                _exportStationsCsv();
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.people_alt_rounded,
                color: Color(0xFFEC4899),
              ),
              title: const Text(
                'Export Users & Riders CSV',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                '${_users.length} accounts with roles & contact details',
              ),
              onTap: () {
                Navigator.pop(ctx);
                _exportUsersCsv();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _setSystemConfigValue(
    String key,
    dynamic value, {
    String? reason,
  }) async {
    try {
      await supabase.rpc(
        'admin_set_system_config',
        params: {
          'p_key': key,
          'p_value': value,
          'p_reason': reason ?? 'Updated from admin dashboard',
        },
      );
      return;
    } catch (_) {}

    final nowIso = DateTime.now().toIso8601String();
    final updated = await supabase
        .from('system_config')
        .update({'value': value, 'updated_at': nowIso})
        .eq('key', key)
        .select('key');

    if (updated.isEmpty) {
      await supabase.from('system_config').insert({
        'key': key,
        'value': value,
        'updated_at': nowIso,
      });
    }
  }

  Future<void> _savePlatformFees() async {
    HapticFeedback.lightImpact();
    try {
      final payload = {
        'percent': _platformFeePercent,
        'fixed': _platformFeeFixed,
        'enabled': true,
      };

      await Future.wait([
        _setSystemConfigValue(
          'platform_fee',
          payload,
          reason: 'Updated platform fee configuration',
        ),
        _setSystemConfigValue(
          'platform_fee_percent',
          _platformFeePercent,
          reason: 'Updated platform fee percent',
        ),
        _setSystemConfigValue(
          'platform_fee_fixed',
          _platformFeeFixed,
          reason: 'Updated platform fee fixed',
        ),
        _setSystemConfigValue(
          'platform_fee_enabled',
          true,
          reason: 'Updated platform fee enabled flag',
        ),
      ]);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Platform fee settings saved successfully.'),
            backgroundColor: AppUi.accentGreen,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not save platform fees: $e'),
            backgroundColor: AppUi.error,
          ),
        );
      }
    }
  }

  Future<void> _toggleMaintenanceMode(bool value) async {
    HapticFeedback.mediumImpact();
    try {
      await _setSystemConfigValue(
        'maintenance_mode',
        value,
        reason: value
            ? 'Maintenance mode enabled by admin'
            : 'Maintenance mode disabled by admin',
      );

      setState(() => _maintenanceMode = value);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              value
                  ? 'System maintenance mode activated.'
                  : 'System maintenance mode deactivated.',
            ),
            backgroundColor: value ? AppUi.warningFg : AppUi.accentGreen,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not update maintenance mode: $e'),
            backgroundColor: AppUi.error,
          ),
        );
      }
    }
  }

  Future<void> _cancelOrderAsAdmin(String orderId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Order'),
        content: Text(
          'Are you sure you want to cancel order #$orderId as an administrator? The customer will be notified.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Back'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppUi.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cancel Order'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      try {
        await supabase.rpc(
          'admin_cancel_order',
          params: {'p_order_id': orderId, 'p_reason': 'Cancelled by Admin'},
        );
      } catch (_) {
        await supabase
            .from('orders')
            .update({
              'status': 'cancelled',
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('id', orderId);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Order has been cancelled.'),
            backgroundColor: AppUi.accentGreen,
          ),
        );
        _loadAllData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not cancel order: $e'),
            backgroundColor: AppUi.error,
          ),
        );
      }
    }
  }

  void _showOrderDetailsSheet(BuildContext context, Map<String, dynamic> o) {
    final orderId = o['id']?.toString() ?? '';
    final shortId = orderId.length >= 8 ? orderId.substring(0, 8) : orderId;
    final status = o['status']?.toString() ?? 'pending';
    final amt = o['total_amount'] is num
        ? (o['total_amount'] as num).toDouble()
        : (double.tryParse(o['total_amount']?.toString() ?? '') ?? 0.0);
    final subtotal = o['subtotal'] is num
        ? (o['subtotal'] as num).toDouble()
        : (double.tryParse(o['subtotal']?.toString() ?? '') ?? 0.0);
    final deliveryFee = o['delivery_fee'] is num
        ? (o['delivery_fee'] as num).toDouble()
        : (double.tryParse(o['delivery_fee']?.toString() ?? '') ?? 0.0);
    final items = o['items'] is List ? (o['items'] as List) : [];
    final customerName = o['customer_name']?.toString() ?? 'Unknown Customer';
    final customerPhone = o['customer_phone']?.toString() ?? 'N/A';
    final customerAddress = o['customer_address']?.toString() ?? 'N/A';
    final notes = o['notes']?.toString() ?? '';
    final stationName = o['station_name']?.toString() ?? 'Water Station';
    final date = (o['created_at']?.toString() ?? '').split('T').first;
    final isCancellable =
        status == 'pending' || status == 'accepted' || status == 'preparing';

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppUi.surfaceOf(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.65,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          expand: false,
          builder: (_, scrollCtrl) {
            return ListView(
              controller: scrollCtrl,
              padding: const EdgeInsets.all(20),
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppUi.borderOf(context),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        'Order #$shortId',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppUi.textPrimaryOf(context),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    OrderStatusBadge(status: status),
                  ],
                ),
                Text(
                  'Placed on $date • $stationName',
                  style: TextStyle(fontSize: 12, color: AppUi.textMuted),
                ),
                const Divider(height: 24),
                Text(
                  'Customer Details',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppUi.textPrimaryOf(context),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '• Name: $customerName',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppUi.textSecondaryOf(context),
                  ),
                ),
                Text(
                  '• Phone: $customerPhone',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppUi.textSecondaryOf(context),
                  ),
                ),
                Text(
                  '• Address: $customerAddress',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppUi.textSecondaryOf(context),
                  ),
                ),
                if (notes.isNotEmpty)
                  Text(
                    '• Delivery Notes: $notes',
                    style: TextStyle(
                      fontSize: 13,
                      fontStyle: FontStyle.italic,
                      color: AppUi.textSecondaryOf(context),
                    ),
                  ),
                const Divider(height: 24),
                Text(
                  'Items Ordered (${items.length})',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppUi.textPrimaryOf(context),
                  ),
                ),
                const SizedBox(height: 6),
                if (items.isEmpty)
                  Text(
                    'No item details recorded',
                    style: TextStyle(fontSize: 12, color: AppUi.textMuted),
                  )
                else
                  ...items.map((it) {
                    final itemMap = it is Map ? it : {};
                    final name =
                        itemMap['product_name'] ??
                        itemMap['name'] ??
                        'Refill Water';
                    final qty = itemMap['quantity'] ?? 1;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '$qty × $name',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppUi.textSecondaryOf(context),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                const Divider(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Subtotal',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppUi.textSecondaryOf(context),
                      ),
                    ),
                    Text(
                      currencyFormat.format(subtotal),
                      style: TextStyle(
                        fontSize: 13,
                        color: AppUi.textPrimaryOf(context),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Delivery Fee',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppUi.textSecondaryOf(context),
                      ),
                    ),
                    Text(
                      currencyFormat.format(deliveryFee),
                      style: TextStyle(
                        fontSize: 13,
                        color: AppUi.textPrimaryOf(context),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Total Amount',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppUi.textPrimaryOf(context),
                      ),
                    ),
                    Text(
                      currencyFormat.format(amt),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppUi.bluePrimary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    if (customerPhone != 'N/A' && customerPhone.isNotEmpty) ...[
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          icon: const Icon(Icons.phone_rounded, size: 16),
                          label: const Text('Call Customer'),
                          onPressed: () async {
                            final uri = Uri.parse('tel:$customerPhone');
                            if (await canLaunchUrl(uri)) await launchUrl(uri);
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppUi.bluePrimary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        icon: const Icon(Icons.two_wheeler_rounded, size: 16),
                        label: const Text('Assign Rider'),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _reassignRider(orderId);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (status != 'delivered' && status != 'cancelled')
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.statusDelivered,
                        side: const BorderSide(
                          color: AppColors.statusDelivered,
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      icon: const Icon(
                        Icons.check_circle_outline_rounded,
                        size: 16,
                      ),
                      label: const Text('Force Mark Delivered'),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _markOrderDelivered(orderId);
                      },
                    ),
                  ),
                if (isCancellable) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppUi.error,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _cancelOrderAsAdmin(orderId);
                      },
                      icon: const Icon(Icons.cancel_outlined, size: 16),
                      label: const Text('Cancel Order as Administrator'),
                    ),
                  ),
                ],
              ],
            );
          },
        );
      },
    );
  }

  void _showLiveNotificationsSheet(BuildContext context) {
    setState(() => _unreadNotifications = 0);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppUi.surfaceOf(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (sheetCtx, setSheetState) {
            return DraggableScrollableSheet(
              initialChildSize: 0.65,
              minChildSize: 0.4,
              maxChildSize: 0.9,
              expand: false,
              builder: (_, scrollController) {
                return Column(
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 10, bottom: 8),
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppUi.textMuted.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppUi.blueSoft,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.notifications_active_rounded,
                              color: AppUi.bluePrimary,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Real-Time Notifications',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: AppUi.textPrimaryOf(context),
                                  ),
                                ),
                                Row(
                                  children: [
                                    Container(
                                      width: 6,
                                      height: 6,
                                      decoration: const BoxDecoration(
                                        color: AppUi.accentGreen,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 5),
                                    const Text(
                                      'Supabase Live Feed',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: AppUi.accentGreen,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          TextButton.icon(
                            icon: const Icon(Icons.campaign_rounded, size: 16),
                            label: const Text('Broadcast'),
                            onPressed: () {
                              Navigator.pop(ctx);
                              showAdminBroadcastDialog(context);
                            },
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: _liveNotifications.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.notifications_none_rounded,
                                    size: 48,
                                    color: AppUi.textMuted.withValues(
                                      alpha: 0.5,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    'No real-time events yet',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: AppUi.textSecondaryOf(context),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  const Text(
                                    'New orders and station updates will stream here automatically.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AppUi.textMuted,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : ListView.separated(
                              controller: scrollController,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              itemCount: _liveNotifications.length,
                              separatorBuilder: (_, _) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final n = _liveNotifications[index];
                                final time = n['time'] as DateTime;
                                final timeStr = DateFormat(
                                  'HH:mm:ss',
                                ).format(time);
                                final icon =
                                    n['icon'] as IconData? ??
                                    Icons.notifications_rounded;
                                final color =
                                    n['color'] as Color? ?? AppUi.bluePrimary;

                                return ListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  leading: CircleAvatar(
                                    backgroundColor: color.withValues(
                                      alpha: 0.12,
                                    ),
                                    child: Icon(icon, color: color, size: 20),
                                  ),
                                  title: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          n['title'] as String,
                                          style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 13,
                                            color: AppUi.textPrimaryOf(context),
                                          ),
                                        ),
                                      ),
                                      Text(
                                        timeStr,
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: AppUi.textMuted,
                                        ),
                                      ),
                                    ],
                                  ),
                                  subtitle: Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Text(
                                      n['description'] as String,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: AppUi.textSecondaryOf(context),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  // --- UI Builders ---

  @override
  Widget build(BuildContext context) {
    late final String configStatus;
    late final Color configColor;
    if (_systemConfigError != null) {
      configStatus = 'Config unavailable';
      configColor = AppUi.error;
    } else if (!_systemConfigLoaded) {
      configStatus = 'Checking configuration';
      configColor = AppUi.textMuted;
    } else if (_maintenanceMode) {
      configStatus = 'Maintenance Mode';
      configColor = AppUi.warningFg;
    } else {
      configStatus = 'Telemetry Active';
      configColor = AppUi.accentGreen;
    }

    return Scaffold(
      backgroundColor: AppUi.pageBgOf(context),
      appBar: AppBar(
        backgroundColor: AppUi.surfaceOf(context),
        elevation: 0,
        titleSpacing: 16,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppUi.blueSoft,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.admin_panel_settings_rounded,
                color: AppUi.bluePrimary,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'eRefill Admin',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: AppUi.textPrimaryOf(context),
                  ),
                ),
                Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: configColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        configStatus,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: configColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Live Notifications',
            icon: Badge(
              isLabelVisible: _unreadNotifications > 0,
              label: Text(
                _unreadNotifications > 99 ? '99+' : '$_unreadNotifications',
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
              ),
              child: const Icon(Icons.notifications_rounded),
            ),
            onPressed: () => _showLiveNotificationsSheet(context),
          ),
          IconButton(
            tooltip: 'Refresh Telemetry',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadAllData,
          ),
          IconButton(
            tooltip: 'Sign Out',
            icon: const Icon(Icons.logout_rounded, color: AppUi.error),
            onPressed: () async {
              await supabase.auth.signOut();
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          labelPadding: const EdgeInsets.symmetric(horizontal: 12),
          labelColor: AppUi.bluePrimary,
          unselectedLabelColor: AppUi.textMuted,
          indicatorColor: AppUi.bluePrimary,
          indicatorWeight: 3,
          labelStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
          tabs: [
            const Tab(
              icon: Icon(Icons.space_dashboard_rounded, size: 20),
              text: 'Overview',
            ),
            Tab(
              icon: Badge(
                isLabelVisible:
                    ((_stats['pending_stations'] as num?)?.toInt() ?? 0) > 0,
                label: Text('${_stats['pending_stations'] ?? 0}'),
                child: const Icon(Icons.storefront_rounded, size: 20),
              ),
              text: 'Stations',
            ),
            const Tab(
              icon: Icon(Icons.receipt_long_rounded, size: 20),
              text: 'Orders',
            ),
            const Tab(
              icon: Icon(Icons.two_wheeler_rounded, size: 20),
              text: 'Fleet',
            ),
            const Tab(icon: Icon(Icons.tune_rounded, size: 20), text: 'System'),
          ],
        ),
      ),
      body: SafeArea(
        top: false,
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: AppUi.bluePrimary),
              )
            : _error != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.error_outline_rounded,
                        color: AppUi.error,
                        size: 48,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppUi.textPrimaryOf(context),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: _loadAllData,
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              )
            : TabBarView(
                controller: _tabController,
                children: [
                  _buildCommandCenterTab(context),
                  _buildStationsTab(context),
                  _buildOrdersTab(context),
                  const AdminLiveMapView(),
                  _buildSettingsTab(context),
                ],
              ),
      ),
    );
  }

  // ─── 1. Command Center Overview Tab ─────────────────────────────────────────

  Widget _buildCommandCenterTab(BuildContext context) {
    final gmv = (_stats['total_gmv'] as num?)?.toDouble() ?? 0.0;
    final todayGmv = (_stats['today_gmv'] as num?)?.toDouble() ?? 0.0;
    final pendingCount = (_stats['pending_stations'] as num?)?.toInt() ?? 0;

    return RefreshIndicator(
      onRefresh: _loadAllData,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_maintenanceMode)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppUi.warningBg,
                borderRadius: AppUi.radiusLg,
                border: Border.all(color: AppUi.warningFg),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: AppUi.warningFg),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Maintenance mode is ACTIVE. Users cannot create new orders.',
                      style: TextStyle(
                        color: AppUi.warningFg,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          if (_dataRefreshError != null)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppUi.warningBg,
                borderRadius: AppUi.radiusLg,
                border: Border.all(color: AppUi.warningFg),
              ),
              child: const Row(
                children: [
                  Icon(Icons.sync_problem_rounded, color: AppUi.warningFg),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Refresh failed. The information on this screen may be out of date.',
                      style: TextStyle(
                        color: AppUi.warningFg,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          if (_systemConfigError != null)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppUi.warningBg,
                borderRadius: AppUi.radiusLg,
                border: Border.all(color: AppUi.warningFg),
              ),
              child: const Row(
                children: [
                  Icon(Icons.sync_problem_rounded, color: AppUi.warningFg),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'System settings could not be verified. Refresh before relying on maintenance or platform fee settings.',
                      style: TextStyle(
                        color: AppUi.warningFg,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          if (pendingCount > 0)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.uiWarningBg,
                borderRadius: AppUi.radiusLg,
                border: Border.all(color: AppColors.uiWarning),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.verified_user_rounded,
                    color: AppColors.uiWarning,
                    size: 28,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$pendingCount Water Station${pendingCount > 1 ? "s" : ""} Pending Review',
                          style: const TextStyle(
                            color: AppColors.statusPending,
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'New station registrations require administrative compliance verification.',
                          style: TextStyle(
                            color: AppColors.statusPending,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.uiWarning,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                    ),
                    onPressed: () => _tabController.animateTo(1),
                    child: const Text('Review Now'),
                  ),
                ],
              ),
            ),

          // Bento KPI Grid
          GridView.count(
            crossAxisCount: MediaQuery.sizeOf(context).width < 380 ? 1 : 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: MediaQuery.sizeOf(context).width < 380
                ? 2.4
                : 1.35,
            children: [
              _buildKpiCard(
                context,
                title: 'Recent Delivered GMV',
                value: _hasFreshMetrics ? currencyFormat.format(gmv) : '—',
                subtitle: _hasFreshMetrics
                    ? 'Latest ${_orders.length} orders · today in sample: ${currencyFormat.format(todayGmv)}'
                    : 'Refreshing recent order metrics',
                icon: Icons.payments_rounded,
                color: AppUi.bluePrimary,
              ),
              _buildKpiCard(
                context,
                title: 'Total System Orders',
                value: _hasFreshMetrics
                    ? '${_stats['orders_count'] ?? 0}'
                    : '—',
                subtitle: 'Latest ${_orders.length} shown below',
                icon: Icons.receipt_long_rounded,
                color: const Color(0xFF6366F1),
              ),
              _buildKpiCard(
                context,
                title: 'Water Refill Stations',
                value: _hasFreshMetrics
                    ? '${_stats['stations_count'] ?? 0}'
                    : '—',
                subtitle: _hasFreshMetrics
                    ? '${_stats['open_stations'] ?? 0} open in loaded stations'
                    : 'Refreshing station metrics',
                icon: Icons.store_mall_directory_rounded,
                color: AppUi.accentGreen,
              ),
              _buildKpiCard(
                context,
                title: 'Active Community',
                value: _hasFreshMetrics ? '${_stats['total_users'] ?? 0}' : '—',
                subtitle: _hasFreshMetrics
                    ? '${_stats['customers'] ?? 0} buyers • ${_stats['riders'] ?? 0} riders in loaded profiles'
                    : 'Refreshing community metrics',
                icon: Icons.people_alt_rounded,
                color: const Color(0xFFEC4899),
              ),
            ],
          ),

          const SizedBox(height: 16),

          _buildQuickOperationsHub(context),

          const SizedBox(height: 16),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: AppUi.surfaceOf(context),
              borderRadius: AppUi.radiusLg,
              border: Border.all(color: AppUi.borderOf(context)),
            ),
            child: Row(
              children: [
                Icon(
                  _maintenanceMode
                      ? Icons.build_circle_rounded
                      : Icons.check_circle_rounded,
                  color: _maintenanceMode ? AppUi.warningFg : AppUi.accentGreen,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Maintenance Mode',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: AppUi.textPrimaryOf(context),
                        ),
                      ),
                      Text(
                        _maintenanceMode
                            ? 'Active · Ordering is currently blocked'
                            : 'Normal · System active & orders flowing',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppUi.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch.adaptive(
                  value: _maintenanceMode,
                  activeTrackColor: AppUi.warningFg,
                  onChanged: (val) => _toggleMaintenanceMode(val),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKpiCard(
    BuildContext context, {
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    return RepaintBoundary(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppUi.surfaceOf(context),
          borderRadius: AppUi.radiusLg,
          border: Border.all(color: AppUi.borderOf(context)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppUi.textSecondaryOf(context),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: color, size: 16),
                ),
              ],
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0.0, 0.2),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              ),
              child: Text(
                value,
                key: ValueKey(value),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: AppUi.textPrimaryOf(context),
                ),
              ),
            ),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: AppUi.textMuted,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickOperationsHub(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppUi.surfaceOf(context),
        borderRadius: AppUi.radiusLg,
        border: Border.all(color: AppUi.borderOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppUi.blueSoft,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.bolt_rounded,
                  color: AppUi.bluePrimary,
                  size: 18,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Quick Operations Hub',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: AppUi.textPrimaryOf(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          GridView.count(
            crossAxisCount: MediaQuery.sizeOf(context).width < 600
                ? 2
                : (MediaQuery.sizeOf(context).width < 1000 ? 3 : 4),
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: MediaQuery.sizeOf(context).width < 600
                ? 1.4
                : 0.85,
            children: [
              _buildOpAction(
                icon: Icons.two_wheeler_rounded,
                label: 'Fleet Map',
                color: const Color(0xFF087E8B),
                onTap: () {
                  AppHaptics.light();
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const AdminLiveMapView()),
                  );
                },
              ),
              _buildOpAction(
                icon: Icons.gavel_rounded,
                label: 'Disputes',
                color: const Color(0xFFF59E0B),
                onTap: () {
                  AppHaptics.light();
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const AdminModerationView(),
                    ),
                  );
                },
              ),
              _buildOpAction(
                icon: Icons.campaign_rounded,
                label: 'Broadcast',
                color: AppUi.bluePrimary,
                onTap: () {
                  AppHaptics.light();
                  showAdminBroadcastDialog(context);
                },
              ),
              _buildOpAction(
                icon: Icons.add_business_rounded,
                label: 'Add Station',
                color: const Color(0xFF10B981),
                onTap: () async {
                  AppHaptics.light();
                  final created = await showCreateStationSheet(context);
                  if (created == true) _loadAllData();
                },
              ),
              _buildOpAction(
                icon: Icons.person_add_rounded,
                label: 'Add User',
                color: const Color(0xFF8B5CF6),
                onTap: () async {
                  AppHaptics.light();
                  final created = await showCreateUserSheet(context);
                  if (created == true) _loadAllData();
                },
              ),
              _buildOpAction(
                icon: Icons.shield_rounded,
                label: 'Audit Log',
                color: const Color(0xFF64748B),
                onTap: () {
                  AppHaptics.light();
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const AdminAuditLogView(),
                    ),
                  );
                },
              ),
              _buildOpAction(
                icon: Icons.credit_card_off_rounded,
                label: 'Pay Fails',
                color: AppUi.error,
                onTap: () {
                  AppHaptics.light();
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const AdminPaymentFailuresView(),
                    ),
                  );
                },
              ),
              _buildOpAction(
                icon: Icons.file_download_rounded,
                label: 'Export CSV',
                color: const Color(0xFF0F71C3),
                onTap: () {
                  AppHaptics.light();
                  _showExportReportsSheet();
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOpAction({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppUi.textPrimaryOf(context),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  // ─── 2. Stations Moderation Tab ─────────────────────────────────────────────

  Widget _buildStationsTab(BuildContext context) {
    final filtered = _stations.where((s) {
      final name = (s['name'] ?? '').toString().toLowerCase();
      final town = (s['town'] ?? '').toString().toLowerCase();
      final matchSearch =
          _stationSearch.isEmpty ||
          name.contains(_stationSearch.toLowerCase()) ||
          town.contains(_stationSearch.toLowerCase());

      final status = (s['status'] ?? '').toString().toLowerCase();
      if (!matchSearch) return false;
      if (_stationFilter == 'all') return true;
      if (_stationFilter == 'pending') {
        return status == 'pending' || status == 'pending_verification';
      }
      if (_stationFilter == 'open') return s['is_accepting_orders'] == true;
      if (_stationFilter == 'suspended') return status == 'suspended';
      return true;
    }).toList();

    return Column(
      children: [
        // Search & Filter Header
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          color: AppUi.surfaceOf(context),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppUi.bluePrimary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      icon: const Icon(Icons.add_business_rounded, size: 18),
                      label: const Text(
                        'Onboard Station',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      onPressed: () async {
                        AppHaptics.light();
                        final created = await showCreateStationSheet(context);
                        if (created == true) _loadAllData();
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: const Icon(Icons.download_rounded, size: 18),
                    label: const Text(
                      'Export CSV',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                    onPressed: _exportStationsCsv,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                decoration: InputDecoration(
                  hintText: 'Search station by name or municipality…',
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: AppUi.borderOf(context)),
                  ),
                  filled: true,
                  fillColor: AppUi.pageBgOf(context),
                ),
                onChanged: (val) => setState(() => _stationSearch = val),
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _filterChip('All Stations', 'all', _stationFilter, (v) {
                      setState(() => _stationFilter = v);
                    }),
                    const SizedBox(width: 8),
                    _filterChip(
                      'Pending Review ⚠️',
                      'pending',
                      _stationFilter,
                      (v) {
                        setState(() => _stationFilter = v);
                      },
                    ),
                    const SizedBox(width: 8),
                    _filterChip('Open Now', 'open', _stationFilter, (v) {
                      setState(() => _stationFilter = v);
                    }),
                    const SizedBox(width: 8),
                    _filterChip('Suspended', 'suspended', _stationFilter, (v) {
                      setState(() => _stationFilter = v);
                    }),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Station Cards List
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Text(
                    'No stations match the selected criteria.',
                    style: TextStyle(color: AppUi.textMuted),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: filtered.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (ctx, idx) {
                    final s = filtered[idx];
                    final isPending =
                        s['status'] == 'pending' ||
                        s['status'] == 'pending_verification';
                    final isSuspended = s['status'] == 'suspended';
                    final isOpen = s['is_accepting_orders'] == true;

                    return Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppUi.surfaceOf(context),
                        borderRadius: AppUi.radiusLg,
                        border: Border.all(
                          color: isPending
                              ? AppColors.statusPending
                              : AppUi.borderOf(context),
                          width: isPending ? 1.5 : 1,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  s['name'] ?? 'Unnamed Station',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15,
                                    color: AppUi.textPrimaryOf(context),
                                  ),
                                ),
                              ),
                              if (isPending)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.uiWarningBg,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Text(
                                    'Needs Review',
                                    style: TextStyle(
                                      color: AppColors.uiWarning,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                )
                              else
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isSuspended
                                        ? AppColors.uiErrorBg
                                        : (isOpen
                                              ? AppColors.brandSoft
                                              : AppUi.borderOf(
                                                  context,
                                                ).withValues(alpha: 0.3)),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    isSuspended
                                        ? 'Suspended'
                                        : (isOpen ? 'Open' : 'Closed'),
                                    style: TextStyle(
                                      color: isSuspended
                                          ? AppColors.statusCancelled
                                          : (isOpen
                                                ? AppColors.brandPrimary
                                                : AppUi.textSecondaryOf(
                                                    context,
                                                  )),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Icon(
                                Icons.location_on_outlined,
                                size: 14,
                                color: AppUi.textMuted,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  '${s['town'] ?? ""}, ${s['address'] ?? ""}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppUi.textSecondaryOf(context),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (s['rating'] != null) ...[
                                const Icon(
                                  Icons.star_rounded,
                                  color: Color(0xFFF59E0B),
                                  size: 14,
                                ),
                                const SizedBox(width: 2),
                                Text(
                                  '${s['rating']}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const Divider(height: 20),
                          Align(
                            alignment: Alignment.centerRight,
                            child: Wrap(
                              alignment: WrapAlignment.end,
                              spacing: 8,
                              runSpacing: 6,
                              children: [
                                if (isPending) ...[
                                  OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: AppUi.error,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 8,
                                      ),
                                    ),
                                    onPressed: () => _rejectStation(
                                      s['id'].toString(),
                                      s['owner_id']?.toString(),
                                      s['name'] ?? '',
                                    ),
                                    icon: const Icon(
                                      Icons.close_rounded,
                                      size: 16,
                                    ),
                                    label: const Text('Reject'),
                                  ),
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.statusDelivered,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 8,
                                      ),
                                    ),
                                    onPressed: () => _approveStation(
                                      s['id'].toString(),
                                      s['owner_id']?.toString(),
                                      s['name'] ?? '',
                                    ),
                                    icon: const Icon(
                                      Icons.verified_rounded,
                                      size: 16,
                                    ),
                                    label: const Text('Approve'),
                                  ),
                                ] else ...[
                                  TextButton.icon(
                                    style: TextButton.styleFrom(
                                      foregroundColor: isSuspended
                                          ? AppUi.accentGreen
                                          : AppUi.error,
                                    ),
                                    onPressed: () => _toggleSuspendStation(
                                      s['id'].toString(),
                                      s['owner_id']?.toString(),
                                      s['name'] ?? '',
                                      isSuspended,
                                    ),
                                    icon: Icon(
                                      isSuspended
                                          ? Icons.check_circle_outline_rounded
                                          : Icons.block_rounded,
                                      size: 16,
                                    ),
                                    label: Text(
                                      isSuspended ? 'Reactivate' : 'Suspend',
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // ─── 3. Global Orders Tab ───────────────────────────────────────────────────

  Widget _buildOrdersTab(BuildContext context) {
    final filtered = _orders.where((o) {
      final id = (o['id'] ?? '').toString().toLowerCase();
      final station = (o['station_name'] ?? '').toString().toLowerCase();
      final customer = (o['customer_name'] ?? '').toString().toLowerCase();
      final q = _orderSearch.trim().toLowerCase();
      final matchSearch =
          q.isEmpty ||
          id.contains(q) ||
          station.contains(q) ||
          customer.contains(q);
      final status = (o['status'] ?? '').toString().toLowerCase();
      if (!matchSearch) return false;
      if (_orderFilter == 'all') return true;
      return status == _orderFilter;
    }).toList();

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          color: AppUi.surfaceOf(context),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${filtered.length} Orders Loaded',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppUi.textSecondaryOf(context),
                      ),
                    ),
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: const Icon(Icons.download_rounded, size: 18),
                    label: const Text(
                      'Export CSV',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                    onPressed: _exportOrdersCsv,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                decoration: InputDecoration(
                  hintText: 'Search by Order ID, station, or customer…',
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: AppUi.borderOf(context)),
                  ),
                  filled: true,
                  fillColor: AppUi.pageBgOf(context),
                ),
                onChanged: (val) => setState(() => _orderSearch = val),
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _filterChip('All', 'all', _orderFilter, (v) {
                      setState(() => _orderFilter = v);
                    }),
                    const SizedBox(width: 8),
                    _filterChip('Pending', 'pending', _orderFilter, (v) {
                      setState(() => _orderFilter = v);
                    }),
                    const SizedBox(width: 8),
                    _filterChip('Preparing', 'preparing', _orderFilter, (v) {
                      setState(() => _orderFilter = v);
                    }),
                    const SizedBox(width: 8),
                    _filterChip(
                      'Delivering',
                      'out_for_delivery',
                      _orderFilter,
                      (v) {
                        setState(() => _orderFilter = v);
                      },
                    ),
                    const SizedBox(width: 8),
                    _filterChip('Delivered', 'delivered', _orderFilter, (v) {
                      setState(() => _orderFilter = v);
                    }),
                    const SizedBox(width: 8),
                    _filterChip('Cancelled', 'cancelled', _orderFilter, (v) {
                      setState(() => _orderFilter = v);
                    }),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Text(
                    'No orders match the selected filter.',
                    style: TextStyle(color: AppUi.textMuted),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: filtered.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (ctx, idx) {
                    final o = filtered[idx];
                    final rawId = o['id']?.toString() ?? '';
                    final shortId = rawId.length >= 8
                        ? rawId.substring(0, 8)
                        : rawId;
                    final status = o['status']?.toString() ?? 'pending';
                    final amt = o['total_amount'] is num
                        ? (o['total_amount'] as num).toDouble()
                        : (double.tryParse(
                                o['total_amount']?.toString() ?? '',
                              ) ??
                              0.0);
                    final paymentMethod =
                        o['payment_method']?.toString().toUpperCase() ?? 'COD';
                    final date = (o['created_at']?.toString() ?? '')
                        .split('T')
                        .first;
                    final stationName =
                        o['station_name']?.toString() ?? 'Water Station';
                    final customerName = o['customer_name']?.toString();

                    return InkWell(
                      borderRadius: AppUi.radiusLg,
                      onTap: () => _showOrderDetailsSheet(context, o),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppUi.surfaceOf(context),
                          borderRadius: AppUi.radiusLg,
                          border: Border.all(color: AppUi.borderOf(context)),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          'Order #$shortId',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 14,
                                            color: AppUi.textPrimaryOf(context),
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        '• $date',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: AppUi.textMuted,
                                        ),
                                        maxLines: 1,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    stationName +
                                        (customerName != null
                                            ? ' • $customerName'
                                            : ''),
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: AppUi.textPrimaryOf(context),
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    'Payment: $paymentMethod (${o['payment_status'] ?? "unpaid"})',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: AppUi.textSecondaryOf(context),
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  currencyFormat.format(amt),
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14,
                                    color: AppUi.textPrimaryOf(context),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                OrderStatusBadge(status: status),
                              ],
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              Icons.chevron_right_rounded,
                              size: 18,
                              color: AppUi.textMuted,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // ─── 4. Settings & Users Tab ────────────────────────────────────────────────

  Widget _buildSettingsTab(BuildContext context) {
    return Column(
      children: [
        Container(
          color: AppUi.surfaceOf(context),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: SegmentedButton<int>(
                  segments: [
                    const ButtonSegment<int>(
                      value: 0,
                      label: Text('Fees'),
                      icon: Icon(Icons.tune_rounded, size: 16),
                    ),
                    ButtonSegment<int>(
                      value: 1,
                      label: Text('Users (${_users.length})'),
                      icon: const Icon(Icons.people_outline_rounded, size: 16),
                    ),
                    const ButtonSegment<int>(
                      value: 2,
                      label: Text('Operations'),
                      icon: Icon(Icons.settings_suggest_rounded, size: 16),
                    ),
                  ],
                  selected: {_settingsSubTab},
                  onSelectionChanged: (set) =>
                      setState(() => _settingsSubTab = set.first),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _settingsSubTab == 0
              ? _buildEconomicsContent(context)
              : _settingsSubTab == 1
              ? _buildUsersContent(context)
              : _buildOperationsToolsContent(context),
        ),
      ],
    );
  }

  Widget _buildUsersContent(BuildContext context) {
    final filtered = _users.where((u) {
      final name = (u['full_name'] ?? '').toString().toLowerCase();
      final email = (u['email'] ?? '').toString().toLowerCase();
      final phone = (u['phone'] ?? '').toString().toLowerCase();
      final matchSearch =
          _userSearch.isEmpty ||
          name.contains(_userSearch.toLowerCase()) ||
          email.contains(_userSearch.toLowerCase()) ||
          phone.contains(_userSearch.toLowerCase());

      final role = (u['role'] ?? '').toString().toLowerCase();
      if (!matchSearch) return false;
      if (_userRoleFilter == 'all') return true;
      return role == _userRoleFilter;
    }).toList();

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          color: AppUi.surfaceOf(context),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppUi.bluePrimary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      icon: const Icon(Icons.person_add_rounded, size: 18),
                      label: const Text(
                        'Register User',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      onPressed: () async {
                        AppHaptics.light();
                        final created = await showCreateUserSheet(context);
                        if (created == true) _loadAllData();
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: const Icon(Icons.download_rounded, size: 18),
                    label: const Text(
                      'Export CSV',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                    onPressed: _exportUsersCsv,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                decoration: InputDecoration(
                  hintText: 'Search users by name, phone, or email…',
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: AppUi.borderOf(context)),
                  ),
                  filled: true,
                  fillColor: AppUi.pageBgOf(context),
                ),
                onChanged: (val) => setState(() => _userSearch = val),
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _filterChip('All Users', 'all', _userRoleFilter, (v) {
                      setState(() => _userRoleFilter = v);
                    }),
                    const SizedBox(width: 8),
                    _filterChip('Customers', 'customer', _userRoleFilter, (v) {
                      setState(() => _userRoleFilter = v);
                    }),
                    const SizedBox(width: 8),
                    _filterChip('Owners', 'owner', _userRoleFilter, (v) {
                      setState(() => _userRoleFilter = v);
                    }),
                    const SizedBox(width: 8),
                    _filterChip('Riders', 'rider', _userRoleFilter, (v) {
                      setState(() => _userRoleFilter = v);
                    }),
                    const SizedBox(width: 8),
                    _filterChip('Admins', 'admin', _userRoleFilter, (v) {
                      setState(() => _userRoleFilter = v);
                    }),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Text(
                    'No users match the search filter.',
                    style: TextStyle(color: AppUi.textMuted),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: filtered.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (ctx, idx) {
                    final u = filtered[idx];
                    final isSuspended = u['is_suspended'] == true;
                    final role = u['role']?.toString().toUpperCase() ?? 'USER';

                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppUi.surfaceOf(context),
                        borderRadius: AppUi.radiusLg,
                        border: Border.all(
                          color: isSuspended
                              ? AppUi.error
                              : AppUi.borderOf(context),
                        ),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 20,
                            backgroundColor: AppUi.blueSoft,
                            child: Text(
                              (u['full_name']?.toString() ?? "U")
                                  .substring(0, 1)
                                  .toUpperCase(),
                              style: const TextStyle(
                                color: AppUi.bluePrimary,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        u['full_name'] ?? 'Unnamed',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 14,
                                          color: AppUi.textPrimaryOf(context),
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppUi.blueSoft,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        role,
                                        style: const TextStyle(
                                          color: AppUi.bluePrimary,
                                          fontSize: 9,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${u['email'] ?? ""} • ${u['phone'] ?? ""}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AppUi.textSecondaryOf(context),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (isSuspended)
                                  Text(
                                    'Suspended: ${u['suspended_reason'] ?? "Admin action"}',
                                    style: const TextStyle(
                                      color: AppUi.error,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          PopupMenuButton<String>(
                            icon: const Icon(Icons.more_vert_rounded, size: 20),
                            onSelected: (val) {
                              if (val == 'suspend') {
                                _toggleUserSuspension(u);
                              } else if (val == 'role') {
                                _changeUserRole(u);
                              } else if (val == 'reset') {
                                _resetUserPassword(u);
                              }
                            },
                            itemBuilder: (ctx) => [
                              const PopupMenuItem(
                                value: 'role',
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.badge_rounded,
                                      size: 18,
                                      color: AppUi.bluePrimary,
                                    ),
                                    SizedBox(width: 8),
                                    Text('Change Role'),
                                  ],
                                ),
                              ),
                              const PopupMenuItem(
                                value: 'reset',
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.lock_reset_rounded,
                                      size: 18,
                                      color: Color(0xFFF59E0B),
                                    ),
                                    SizedBox(width: 8),
                                    Text('Reset Password'),
                                  ],
                                ),
                              ),
                              PopupMenuItem(
                                value: 'suspend',
                                child: Row(
                                  children: [
                                    Icon(
                                      isSuspended
                                          ? Icons.lock_open_rounded
                                          : Icons.lock_person_rounded,
                                      size: 18,
                                      color: isSuspended
                                          ? AppUi.accentGreen
                                          : AppUi.error,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      isSuspended
                                          ? 'Reactivate User'
                                          : 'Suspend Account',
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildEconomicsContent(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppUi.surfaceOf(context),
            borderRadius: AppUi.radiusLg,
            border: Border.all(color: AppUi.borderOf(context)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.receipt_long_rounded,
                    color: AppUi.bluePrimary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'App Service Fee',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      color: AppUi.textPrimaryOf(context),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'A small fee added to refill orders to cover 24/7 server hosting, live rider tracking, and customer support.',
                style: TextStyle(
                  fontSize: 12,
                  color: AppUi.textSecondaryOf(context),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Percentage Fee:',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    '${_platformFeePercent.toStringAsFixed(1)}%',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: AppUi.bluePrimary,
                    ),
                  ),
                ],
              ),
              Slider(
                value: _platformFeePercent,
                min: 0.0,
                max: 15.0,
                divisions: 30,
                activeColor: AppUi.bluePrimary,
                label: '${_platformFeePercent.toStringAsFixed(1)}%',
                onChanged: (v) => setState(() => _platformFeePercent = v),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Fixed Fee per order:',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    currencyFormat.format(_platformFeeFixed),
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: AppUi.bluePrimary,
                    ),
                  ),
                ],
              ),
              Slider(
                value: _platformFeeFixed,
                min: 0.0,
                max: 10.0,
                divisions: 20,
                activeColor: AppUi.bluePrimary,
                label: '₱${_platformFeeFixed.toStringAsFixed(1)}',
                onChanged: (v) => setState(() => _platformFeeFixed = v),
              ),
              Container(
                margin: const EdgeInsets.symmetric(vertical: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppUi.blueSoft,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AppUi.bluePrimary.withValues(alpha: 0.2),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(
                          Icons.lightbulb_outline_rounded,
                          size: 16,
                          color: AppUi.bluePrimary,
                        ),
                        SizedBox(width: 6),
                        Text(
                          'Live customer example:',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppUi.bluePrimary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Builder(
                      builder: (context) {
                        const sampleOrder = 100.0;
                        const sampleDelivery = 25.0;
                        const sampleBase = sampleOrder + sampleDelivery;
                        final sampleFee =
                            (sampleBase * _platformFeePercent / 100) +
                            _platformFeeFixed;
                        final sampleTotal = sampleBase + sampleFee;
                        return Text(
                          'On a sample ₱100 refill + ₱25 delivery order:\n'
                          '• Refill subtotal: ₱100.00\n'
                          '• Delivery fee: ₱25.00\n'
                          '• Service fee: ₱${sampleFee.toStringAsFixed(2)}\n'
                          '• Total to Pay: ₱${sampleTotal.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.4,
                            color: AppUi.textPrimaryOf(context),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppUi.bluePrimary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: _savePlatformFees,
                  icon: const Icon(Icons.save_rounded, size: 18),
                  label: const Text('Save Service Fee Settings'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Material(
          color: AppUi.surfaceOf(context),
          shape: RoundedRectangleBorder(
            borderRadius: AppUi.radiusLg,
            side: BorderSide(color: AppUi.borderOf(context)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.build_circle_rounded,
                      color: AppUi.bluePrimary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'System Guard & Maintenance',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: AppUi.textPrimaryOf(context),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Material(
                  color: Colors.transparent,
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Maintenance Mode',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: const Text(
                      'Blocks customers from creating new orders while system updates or upgrades are ongoing.',
                      style: TextStyle(fontSize: 12),
                    ),
                    value: _maintenanceMode,
                    activeTrackColor: AppUi.warningFg,
                    onChanged: (v) => _toggleMaintenanceMode(v),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOperationsToolsContent(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildOpToolTile(
          icon: Icons.two_wheeler_rounded,
          iconColor: const Color(0xFF087E8B),
          title: 'Live Fleet Dispatch Map',
          subtitle:
              'Real-time rider GPS tracking, active deliveries, and direct dispatch.',
          badge: '${_users.where((u) => u['role'] == 'rider').length} Riders',
          onTap: () {
            AppHaptics.light();
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AdminLiveMapView()),
            );
          },
        ),
        const SizedBox(height: 12),
        _buildOpToolTile(
          icon: Icons.gavel_rounded,
          iconColor: const Color(0xFFF59E0B),
          title: 'Customer Disputes & Moderation',
          subtitle:
              'Resolve order disputes, review customer feedback, and moderate ratings.',
          badge: 'Disputes & Reviews',
          onTap: () {
            AppHaptics.light();
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AdminModerationView()),
            );
          },
        ),
        const SizedBox(height: 12),
        _buildOpToolTile(
          icon: Icons.campaign_rounded,
          iconColor: AppUi.bluePrimary,
          title: 'Broadcast Push Alerts',
          subtitle:
              'Send high-priority notifications to all customers, riders, or station owners.',
          badge: 'Broadcast',
          onTap: () {
            AppHaptics.light();
            showAdminBroadcastDialog(context);
          },
        ),
        const SizedBox(height: 12),
        _buildOpToolTile(
          icon: Icons.shield_rounded,
          iconColor: const Color(0xFF64748B),
          title: 'System Audit Trail',
          subtitle:
              'Immutable record of administrative actions, compliance updates, and security events.',
          badge: 'Audit Logs',
          onTap: () {
            AppHaptics.light();
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AdminAuditLogView()),
            );
          },
        ),
        const SizedBox(height: 12),
        _buildOpToolTile(
          icon: Icons.credit_card_off_rounded,
          iconColor: AppUi.error,
          title: 'Payment Failures & Reconciliation',
          subtitle:
              'Inspect failed transactions and reconcile payment gateway discrepancies.',
          badge: 'Reconciliation',
          onTap: () {
            AppHaptics.light();
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const AdminPaymentFailuresView(),
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        _buildOpToolTile(
          icon: Icons.file_download_rounded,
          iconColor: const Color(0xFF10B981),
          title: 'Export Marketplace Data (CSV)',
          subtitle:
              'Generate and copy full CSV data sheets for orders, users, and water stations.',
          badge: 'CSV Reports',
          onTap: () {
            AppHaptics.light();
            _showExportReportsSheet();
          },
        ),
      ],
    );
  }

  Widget _buildOpToolTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required String badge,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: AppUi.radiusLg,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppUi.surfaceOf(context),
          borderRadius: AppUi.radiusLg,
          border: Border.all(color: AppUi.borderOf(context)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: iconColor.withValues(alpha: 0.2)),
              ),
              child: Icon(icon, color: iconColor, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: AppUi.textPrimaryOf(context),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: iconColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          badge,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: iconColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppUi.textSecondaryOf(context),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right_rounded, color: AppUi.textMuted, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _filterChip(
    String label,
    String value,
    String current,
    ValueChanged<String> onSelected,
  ) {
    final selected = current == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      selectedColor: AppUi.blueSoft,
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: selected ? AppUi.bluePrimary : AppUi.textSecondaryOf(context),
      ),
      side: BorderSide(
        color: selected ? AppUi.bluePrimary : AppUi.borderOf(context),
      ),
      onSelected: (_) => onSelected(value),
    );
  }
}
