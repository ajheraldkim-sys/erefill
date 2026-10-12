import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';
import 'package:image_picker/image_picker.dart';
import 'package:signature/signature.dart';
import 'package:url_launcher/url_launcher.dart' as url;
import 'package:erefill/features/chat/services/chat_service.dart';
import 'package:erefill/features/chat/models/chat_room.dart';
import 'package:provider/provider.dart';
import 'package:erefill/core/providers/user_provider.dart';
import 'package:erefill/core/widgets/app_form_fields.dart';
import 'package:erefill/core/widgets/account/account_ui.dart';
import 'package:erefill/core/providers/theme_provider.dart';
import 'package:erefill/core/widgets/brand/hero_header.dart';
import 'package:erefill/core/widgets/brand/axo_states.dart';
import 'package:erefill/core/widgets/experience_widgets.dart';
import 'package:erefill/core/widgets/refill_components.dart';
import 'package:erefill/core/widgets/notification_preview_sheet.dart';
import 'package:erefill/core/utils/safe_supabase.dart';
import 'package:erefill/core/utils/profile_query_helpers.dart';
import 'package:erefill/core/widgets/rider_active_delivery_card.dart';
import 'package:erefill/core/widgets/role_bottom_nav_bar.dart';
import 'package:erefill/core/widgets/lazy_indexed_stack.dart';
import 'package:erefill/core/widgets/skeleton.dart';
import '../../../core/constants.dart';
import 'package:erefill/core/widgets/delivery_completion_sheet.dart';
import '../customer/checkout_rules.dart';

import '../../chat/inbox_screen.dart';
import 'package:erefill/core/routing/app_navigation.dart';
import 'package:erefill/core/services/external_navigation_service.dart';
import 'package:erefill/core/services/local_data_cache.dart';
import 'services/location_service.dart';
import 'services/order_cache_service.dart';
import 'services/offline_delivery_queue_service.dart';
import '../../payouts/widgets/rider_payout_sheet.dart';

import 'rider_history_screen.dart';
export 'rider_history_screen.dart';

double _safeDouble(dynamic value, {double fallback = 0}) {
  if (value == null) return fallback;
  if (value is num) return value.toDouble();
  if (value is String) {
    final cleaned = value.replaceAll(RegExp(r'[^0-9.-]'), '').trim();
    if (cleaned.isEmpty || cleaned == '-' || cleaned == '.') {
      return fallback;
    }
    return double.tryParse(cleaned) ?? fallback;
  }
  return double.tryParse(value.toString()) ?? fallback;
}

int _safeInt(dynamic value, {int fallback = 0}) {
  if (value == null) return fallback;
  if (value is num) return value.toInt();
  if (value is String) {
    final cleaned = value.replaceAll(RegExp(r'[^0-9.-]'), '').trim();
    if (cleaned.isEmpty || cleaned == '-' || cleaned == '.') {
      return fallback;
    }
    return int.tryParse(cleaned) ?? _safeDouble(cleaned).toInt();
  }
  return int.tryParse(value.toString()) ?? _safeDouble(value).toInt();
}

Map<String, dynamic>? _safeMap(dynamic value) {
  if (value is Map) {
    return Map<String, dynamic>.from(value);
  }
  return null;
}

class RiderDashboard extends StatefulWidget {
  const RiderDashboard({super.key});

  @override
  State<RiderDashboard> createState() => _RiderDashboardState();
}

class _RiderDashboardState extends State<RiderDashboard> {
  final supabase = Supabase.instance.client;
  final _locationService = LocationService();
  final _orderCache = OrderCacheService();
  int _pendingOfflineCount = 0;
  bool _isSyncingOffline = false;
  RealtimeChannel? _ordersChannel;
  StreamSubscription<List<Map<String, dynamic>>>? _profileSubscription;

  List<Map<String, dynamic>> _myActiveOrders = [];
  // Location mapping
  final Map<String, List<String>> _municipalityData =
      AppConstants.municipalityData;

  Map<String, dynamic>? _profile;
  bool _isLoading = true;
  int _selectedIndex = 0;
  int _completedDeliveries = 0;
  double _totalEarnings = 0;
  bool _soundAlertsEnabled = true;

  Future<void> _toggleOnlineStatus(bool value) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    setState(() {
      if (_profile != null) _profile!['is_online'] = value;
    });
    try {
      await supabase
          .from('profiles')
          .update({'is_online': value})
          .eq('id', user.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              value
                  ? 'You are now online and ready for deliveries'
                  : 'You are now offline',
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error toggling online status: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    final initialUser = context.read<UserProvider>().user;
    if (initialUser != null) {
      _profile = {
        'full_name': initialUser.fullName,
        'first_name': initialUser.firstName,
        'last_name': initialUser.lastName,
        'mi': initialUser.mi,
        'suffix': initialUser.suffix,
        'username': initialUser.username,
        'phone': initialUser.phone,
        'town': initialUser.town,
        'barangay': initialUser.barangay,
        'vehicle_type': initialUser.vehicleType,
        'license_number': initialUser.licenseNumber,
        'avatar_url': initialUser.avatarUrl,
      };
      _isLoading = false;
    }
    _loadInitialCache();
    _loadRiderData(); // START NETWORK FETCH
    _setupProfileListener();
    _listenForNewJobs();
    _locationService.startTracking();
  }

  void _setupProfileListener() {
    final myId = supabase.auth.currentUser?.id;
    if (myId == null) return;

    _profileSubscription = SafeSupabase.listen(
      supabase.from('profiles').stream(primaryKey: ['id']).eq('id', myId),
      (data) {
        if (data.isNotEmpty && mounted) {
          setState(() => _profile = data.first);
        }
      },
      onError: (error, stackTrace) {
        debugPrint('Rider profile stream error: $error');
        debugPrint('Rider profile stream stack: $stackTrace');
      },
    );
    _fetchCompletedStats();
  }

  Future<void> _fetchCompletedStats() async {
    final myId = supabase.auth.currentUser?.id;
    if (myId == null) return;
    try {
      final deliveredData = await supabase
          .from('orders')
          .select('id, delivery_fee')
          .eq('assigned_rider_id', myId)
          .eq('status', 'delivered');

      if (mounted) {
        setState(() {
          _completedDeliveries = deliveredData.length;
          _totalEarnings = (deliveredData as List? ?? const []).fold<double>(
            0,
            (sum, o) {
              final fee = _safeDouble((o is Map ? o['delivery_fee'] : null));
              return sum + fee;
            },
          );
        });
      }
    } catch (e) {
      debugPrint("Error loading stats: $e");
    }
  }

  Future<void> _loadInitialCache() async {
    // 1. Load active tasks from cache instantly
    final cachedActive = await _orderCache.getCachedActiveOrders();
    if (cachedActive.isNotEmpty && mounted) {
      setState(() {
        _myActiveOrders = cachedActive;
        _isLoading = false; // Hide if we have cache
      });
    }
  }

  Future<void> _checkOfflineQueue() async {
    try {
      final pending = await OfflineDeliveryQueueService()
          .getPendingDeliveries();
      if (mounted) {
        setState(() => _pendingOfflineCount = pending.length);
      }
    } catch (_) {}
  }

  Future<void> _syncOfflineQueue() async {
    if (_isSyncingOffline) return;
    setState(() => _isSyncingOffline = true);
    try {
      final synced = await OfflineDeliveryQueueService()
          .syncPendingDeliveries();
      await _checkOfflineQueue();
      if (synced > 0) {
        await _loadRiderData();
        if (mounted) {
          _showSuccess('Synced $synced offline deliveries successfully!');
        }
      }
    } catch (e) {
      debugPrint('Sync offline error: $e');
    } finally {
      if (mounted) setState(() => _isSyncingOffline = false);
    }
  }

  Future<void> _loadRiderData() async {
    unawaited(_syncOfflineQueue());

    final myId = supabase.auth.currentUser?.id;
    if (myId == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    Map<String, dynamic>? profileResult;
    List<Map<String, dynamic>> activeResult = [];
    int completedCount = 0;
    double earningsTotal = 0;

    // Fetch Profile, Active Deliveries, and Earnings in parallel for super fast load
    try {
      final results = await Future.wait([
        supabase
            .from('profiles')
            .select(
              'full_name, first_name, last_name, mi, suffix, username, phone, town, barangay, vehicle_type, license_number, avatar_url, created_at',
            )
            .eq('id', myId)
            .maybeSingle(),
        supabase
            .from('orders')
            .select('''
              id, status, created_at, customer_id, total_amount, items, subtotal, payment_method, payment_status,
              customer:profiles!orders_customer_id_fkey(full_name, complete_address, phone, barangay, latitude, longitude)
            ''')
            .eq('assigned_rider_id', myId)
            .inFilter('status', [
              'assigned_to_rider',
              'out_for_delivery',
              'preparing',
            ])
            .order('created_at', ascending: false),
        supabase
            .from('orders')
            .select('id, delivery_fee')
            .eq('assigned_rider_id', myId)
            .eq('status', 'delivered'),
      ]);

      profileResult = results[0] as Map<String, dynamic>? ?? _profile;
      activeResult = List<Map<String, dynamic>>.from(
        results[1] as List? ?? const [],
      );
      final deliveredData = results[2] as List? ?? const [];
      completedCount = deliveredData.length;
      earningsTotal = deliveredData.fold<double>(0, (sum, o) {
        final fee = _safeDouble(o is Map ? o['delivery_fee'] : null);
        return sum + fee;
      });
    } catch (e) {
      debugPrint("Warning: Error loading rider data: $e. Checking offline caches...");
      final cachedActive = await _orderCache.getCachedActiveOrders();
      if (cachedActive.isNotEmpty) {
        activeResult = cachedActive;
      } else if (_myActiveOrders.isNotEmpty) {
        activeResult = _myActiveOrders;
      }
      final cachedProfile = await LocalDataCache.instance.get<Map<String, dynamic>>(
        'rider_profile_$myId',
      );
      if (cachedProfile != null) {
        profileResult = cachedProfile;
      }
    }

    if (!mounted) return;
    if (profileResult != null) {
      if ((profileResult['first_name'] == null ||
              profileResult['first_name'].toString().trim().isEmpty) &&
          (profileResult['last_name'] == null ||
              profileResult['last_name'].toString().trim().isEmpty)) {
        final raw = profileResult['full_name']?.toString().trim() ?? '';
        if (raw.isNotEmpty) {
          final parts = raw.split(RegExp(r'\s+'));
          if (parts.length == 1) {
            profileResult['first_name'] = parts.first;
          } else if (parts.length >= 2) {
            profileResult['first_name'] = parts.first;
            profileResult['last_name'] = parts.sublist(1).join(' ');
          }
        }
      }
    }
    setState(() {
      if (profileResult != null) _profile = profileResult;
      _myActiveOrders = activeResult;
      _completedDeliveries = completedCount;
      _totalEarnings = earningsTotal;
      _isLoading = false;
    });

    // Cache updated data for offline/instant-load
    if (activeResult.isNotEmpty) {
      _orderCache.cacheActiveOrders(activeResult);
    }
    if (profileResult != null) {
      unawaited(
        LocalDataCache.instance.set('rider_profile_$myId', profileResult),
      );
    }
  }

  void _listenForNewJobs() {
    final myId = supabase.auth.currentUser?.id;
    if (myId == null) return;

    _ordersChannel = supabase
        .channel('public:orders:rider:$myId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'orders',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'assigned_rider_id',
            value: myId,
          ),
          callback: (payload) {
            final newRecord = payload.newRecord;
            final oldRecord = payload.oldRecord;

            if (payload.eventType == PostgresChangeEvent.delete) {
              // Handle Delete or Unassignment
              _loadRiderData();
              return;
            }

            final newStatus = (newRecord['status'] ?? '').toString();
            final oldStatus = (oldRecord['status'] ?? '').toString();

            // 1. Assignment Detection (Newly assigned to current rider)
            final isNewlyAssigned =
                (oldRecord['assigned_rider_id'] == null ||
                    oldRecord['assigned_rider_id'] != myId) &&
                newRecord['assigned_rider_id'] == myId;

            // 2. Explicit assignment status raised by the owner workflow.
            final isStatusAssigned =
                (payload.eventType == PostgresChangeEvent.update &&
                newStatus == 'assigned_to_rider' &&
                oldStatus != 'assigned_to_rider');

            if (isNewlyAssigned || isStatusAssigned) {
              HapticFeedback.heavyImpact();
              _showNewJobAlert(newRecord);
            }

            // 3. Refresh ALL Data for accuracy
            _loadRiderData().then((_) {
              if (isNewlyAssigned || isStatusAssigned) {
                HapticFeedback.vibrate();
              }
            });
          },
        )
        .subscribe();
  }

  void _showNewJobAlert(Map<String, dynamic> rawOrder) {
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.fromLTRB(
          AppUi.spacingXl,
          AppUi.spacingMd,
          AppUi.spacingXl,
          AppUi.bottomPadding,
        ),
        decoration: BoxDecoration(
          color: AppUi.surfaceOf(context),
          borderRadius: AppUi.radiusSheetTop,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppUi.borderOf(context),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 32),
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.rocket_launch_rounded,
                color: Color(0xFF10B981),
                size: 40,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'New Assignment Ready!',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: AppUi.textPrimaryOf(context),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'A new water refill delivery is assigned to you. View the task to see pickup and drop-off details.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                color: AppUi.textSecondaryOf(context),
                fontWeight: FontWeight.w600,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  setState(() => _selectedIndex = 1); // Switch to Dispatch Tab
                  _loadRiderData(); // Refresh to ensure data is fresh
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppUi.bluePrimary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: AppUi.cardRadius),
                  elevation: 0,
                ),
                child: const Text(
                  'View Task Now',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _updateOrderStatus(String orderId, String newStatus) async {
    if (newStatus == 'delivered') {
      await _confirmDeliveryWithProof(orderId);
      return;
    }

    HapticFeedback.mediumImpact();
    // Optimistic UI Update
    final index = _myActiveOrders.indexWhere((o) => o['id'] == orderId);
    if (index != -1) {
      _myActiveOrders[index]['status'] = newStatus;
      setState(() {});
    }

    try {
      final result = await SafeSupabase.transitionOrderStatus(
        orderId: orderId,
        newStatus: newStatus,
      );
      if (result['success'] != true) {
        throw StateError(
          result['message']?.toString() ?? 'Order status update was rejected.',
        );
      }
      await _loadRiderData();
      if (mounted) {
        _showSuccess('Status updated to ${newStatus.replaceAll('_', ' ')}');
      }
    } catch (e) {
      try {
        await OfflineDeliveryQueueService().enqueueDelivery(
          QueuedDelivery(orderId: orderId, status: newStatus),
        );
        await _checkOfflineQueue();
        if (mounted) {
          _showSuccess(
            'Status updated offline. Will sync automatically when online.',
          );
        }
      } catch (_) {
        await _loadRiderData(); // Revert on failure
        if (mounted) _showError('Failed: $e');
      }
    }
  }

  Future<void> _confirmDeliveryWithProof(String orderId) async {
    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 70,
      maxWidth: 1000,
    );

    if (image == null) return;
    if (!mounted) return;

    // 1. Optional: Capture Customer Signature
    String? signaturePath;
    final Uint8List? sigData = await _showSignatureDialog();
    if (!mounted) return;

    // 2. Capture Empty Gallons & Note
    var suggestedEmpty = 0;
    try {
      final items = await supabase
          .from('order_items')
          .select('quantity')
          .eq('order_id', orderId);
      for (final item in (items as List? ?? const [])) {
        if (item is Map) {
          suggestedEmpty += _safeInt(item['quantity']);
        }
      }
    } catch (_) {}

    if (!mounted) return;

    final completionSheetResult = await showDeliveryCompletionSheet(
      context,
      suggestedEmptyGallons: suggestedEmpty,
    );
    if (!mounted) return;
    final completion =
        completionSheetResult ??
        DeliveryCompletionDetails(emptyGallonsReturned: suggestedEmpty);

    // 3. Show non-dismissible progress indicator during upload and verification
    var progressShown = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: Dialog(
          backgroundColor: AppUi.surfaceOf(context),
          shape: RoundedRectangleBorder(borderRadius: AppUi.cardRadius),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
                const SizedBox(width: 16),
                Text(
                  'Finalizing delivery...',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppUi.textPrimaryOf(context),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      // 4. Capture GPS Snapshot (gracefully continue if unavailable)
      final position = await _locationService.getCurrentPosition();

      // 5. Upload Photo Proof
      final file = File(image.path);
      final fileName =
          '${orderId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final photoPath = 'proofs/$orderId/$fileName';

      try {
        await supabase.storage.from('delivery_proofs').upload(photoPath, file);
      } catch (uploadErr) {
        debugPrint('Warning: Photo proof storage upload skipped: $uploadErr');
      }

      // 6. Upload Signature Proof (if captured)
      if (sigData != null) {
        final sigName =
            'sig_${orderId}_${DateTime.now().millisecondsSinceEpoch}.png';
        final sigPath = 'proofs/$orderId/$sigName';
        try {
          await supabase.storage
              .from('delivery_proofs')
              .uploadBinary(sigPath, sigData);
          signaturePath = sigPath;
        } catch (sigErr) {
          debugPrint('Warning: Signature storage upload skipped: $sigErr');
        }
      }

      // 7. Finalize Order with full proof-of-delivery metadata via server RPC or fallback transition
      bool serverConfirmed = false;
      try {
        final response = await supabase.rpc(
          'confirm_delivery_safely',
          params: {
            'p_order_id': orderId,
            'p_lat': position?.latitude,
            'p_lng': position?.longitude,
            'p_photo_url': photoPath,
            'p_signature_url': signaturePath,
            'p_delivery_note': completion.deliveryNote,
            'p_empty_gallons_returned': completion.emptyGallonsReturned,
          },
        );
        final result = _safeMap(response) ?? <String, dynamic>{};
        if (result['success'] == true) {
          serverConfirmed = true;
        }
      } catch (rpcErr) {
        debugPrint(
          'confirm_delivery_safely RPC unavailable, applying direct transition: $rpcErr',
        );
      }

      if (!serverConfirmed) {
        final transitionResult = await SafeSupabase.transitionOrderStatus(
          orderId: orderId,
          newStatus: 'delivered',
        );
        if (transitionResult['success'] != true) {
          throw StateError(
            transitionResult['message']?.toString() ??
                'Delivery completion was rejected.',
          );
        }
        try {
          await supabase
              .from('orders')
              .update({
                'delivery_note': completion.deliveryNote,
                'empty_gallons_returned': completion.emptyGallonsReturned,
              })
              .eq('id', orderId);
        } catch (_) {}
      }

      // Dismiss progress dialog
      if (mounted && progressShown) {
        Navigator.of(context, rootNavigator: true).pop();
        progressShown = false;
      }

      // Update UI after delivery confirms
      setState(() {
        _myActiveOrders.removeWhere((o) => o['id'] == orderId);
      });

      if (mounted) {
        _showSuccess('Delivery verified and completed.');
      }
    } catch (e) {
      if (mounted && progressShown) {
        Navigator.of(context, rootNavigator: true).pop();
        progressShown = false;
      }
      try {
        await OfflineDeliveryQueueService().enqueueDelivery(
          QueuedDelivery(
            orderId: orderId,
            status: 'delivered',
            localPhotoPath: image.path,
            deliveryNote: completion.deliveryNote,
            emptyGallonsReturned: completion.emptyGallonsReturned,
          ),
        );
        setState(() {
          _myActiveOrders.removeWhere((o) => o['id'] == orderId);
        });
        await _checkOfflineQueue();
        if (mounted) {
          _showSuccess(
            'Saved offline! Delivery will sync automatically when online.',
          );
        }
      } catch (_) {
        if (mounted) _showError('Could not complete delivery: $e');
      }
    } finally {
      await _loadRiderData();
    }
  }

  Future<Uint8List?> _showSignatureDialog() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final SignatureController controller = SignatureController(
      penStrokeWidth: 3,
      penColor: isDark ? const Color(0xFFE8F0F2) : AppUi.textPrimary,
      exportBackgroundColor: AppUi.surfaceOf(context),
    );

    final signature = await showModalBottomSheet<Uint8List?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppUi.surfaceOf(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Customer Signature',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    'Skip / No Sig',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Please have the customer sign below to confirm receipt.',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: AppUi.borderColor),
                  borderRadius: AppUi.cardRadius,
                ),
                child: ClipRRect(
                  borderRadius: AppUi.cardRadius,
                  child: Signature(
                    controller: controller,
                    backgroundColor: AppUi.pageBgOf(context),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => controller.clear(),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: AppUi.controlRadius,
                      ),
                    ),
                    child: const Text('Clear'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () async {
                      if (controller.isNotEmpty) {
                        final data = await controller.toPngBytes();
                        if (context.mounted) Navigator.pop(context, data);
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppUi.bluePrimary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: AppUi.controlRadius,
                      ),
                      elevation: 0,
                    ),
                    child: const Text('Confirm Sig'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    return signature;
  }

  void _showSuccess(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: const Color(0xFF10B981),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Future<void> _contactCustomer(Map<String, dynamic> order) async {
    final orderId = (order['id'] ?? '').toString();
    final customerId = (order['customer_id'] ?? '').toString();
    final ownerId = (order['owner_id'] ?? '').toString();
    final riderId = supabase.auth.currentUser!.id;
    final customerName = order['customer_name'] ?? 'Customer';

    if (orderId.isEmpty || customerId.isEmpty || ownerId.isEmpty) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final chatService = ChatService();
      final room = await chatService.getOrCreateCustomerRiderRoom(
        orderId: orderId,
        customerId: customerId,
        riderId: riderId,
        customerName: customerName,
      );
      if (mounted) Navigator.pop(context);

      if (mounted) {
        context.openChat(
          roomId: room.id,
          roomTitle: 'Chat with $customerName',
          roomType: ChatRoomType.orderDelivery,
        );
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Chat error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _openNavigation(Map<String, dynamic> order) async {
    final customer = _safeMap(order['customer']);
    final rawLat = _safeDouble(order['customer_latitude']);
    final customerLat = _safeDouble(customer?['latitude']);
    final rawLng = _safeDouble(order['customer_longitude']);
    final customerLng = _safeDouble(customer?['longitude']);

    final double? lat = rawLat != 0
        ? rawLat
        : (customerLat == 0 ? null : customerLat);
    final double? lng = rawLng != 0
        ? rawLng
        : (customerLng == 0 ? null : customerLng);

    final address = customer?['complete_address']?.toString() ?? '';
    final barangay = customer?['barangay']?.toString() ?? '';
    final addressFallback = [
      address,
      barangay,
    ].where((s) => s.isNotEmpty).join(', ');
    final customerName = customer?['full_name']?.toString() ?? 'Customer';

    final success = await ExternalNavigationService.openNavigation(
      latitude: lat,
      longitude: lng,
      title: customerName,
      addressFallback: addressFallback,
    );

    if (!success && mounted) {
      _showError('Could not open external navigation');
    }
  }

  String _formatItems(dynamic itemsObj) {
    if (itemsObj == null) return 'Refill details unavailable';
    try {
      List<dynamic> itemsList = [];
      if (itemsObj is String) {
        itemsList = jsonDecode(itemsObj);
      } else if (itemsObj is List) {
        itemsList = itemsObj;
      }
      if (itemsList.isEmpty) return 'No refill gallons listed';

      return itemsList
          .map((i) {
            final qty = i['quantity'] ?? 1;
            final name = i['product_name'] ?? i['water_type'] ?? 'Water refill';
            return '${qty}x $name';
          })
          .join(', ');
    } catch (e) {
      return 'Water refill';
    }
  }

  @override
  void dispose() {
    if (_ordersChannel != null) {
      supabase.removeChannel(_ordersChannel!);
    }
    _profileSubscription?.cancel();
    _locationService.stopTracking();
    super.dispose();
  }

  void _changeTab(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final myId = supabase.auth.currentUser?.id;

    final pages = [
      _RiderHomeOverview(
        profile: _profile,
        completedCount: _completedDeliveries,
        totalEarnings: _totalEarnings,
        activeOrders: _myActiveOrders,
        onNavigate: (index) => _changeTab(index),
        onRefresh: _loadRiderData,
      ),
      _buildDispatchTab(),
      RiderHistoryScreen(riderId: myId ?? ''),
      const InboxScreen(),
      _buildProfileTab(),
    ];
    final activeDispatchCount = _myActiveOrders
        .where(
          (o) => [
            'assigned_to_rider',
            'preparing',
            'out_for_delivery',
          ].contains(o['status']),
        )
        .length;

    return PopScope(
      canPop: _selectedIndex == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_selectedIndex != 0) {
          _changeTab(0);
        }
      },
      child: Scaffold(
        backgroundColor: AppUi.pageBgOf(context),
        body: SafeArea(
          bottom: false,
          child: _isLoading
              ? const AxoLoader(message: 'Preparing your rider dashboard...')
              : LazyIndexedStack(index: _selectedIndex, children: pages),
        ),
        bottomNavigationBar: RoleBottomNavBar(
          currentIndex: _selectedIndex,
          onTap: (i) => _changeTab(i),
          items: [
            const RoleBottomNavItem(
              icon: Icons.dashboard_outlined,
              activeIcon: Icons.dashboard_rounded,
              label: 'Overview',
            ),
            RoleBottomNavItem(
              icon: Icons.delivery_dining_outlined,
              activeIcon: Icons.delivery_dining_rounded,
              label: 'Dispatch',
              badgeCount: activeDispatchCount,
            ),
            const RoleBottomNavItem(
              icon: Icons.history_rounded,
              activeIcon: Icons.history_sharp,
              label: 'Logs',
            ),
            const RoleBottomNavItem(
              icon: Icons.chat_bubble_outline_rounded,
              activeIcon: Icons.chat_bubble_rounded,
              label: 'Messages',
            ),
            const RoleBottomNavItem(
              icon: Icons.person_outline_rounded,
              activeIcon: Icons.person_rounded,
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }

  // ── Dispatch Tab ─────────────────────────────────────────────────────────────

  Widget _buildDispatchTab() {
    final myId = supabase.auth.currentUser?.id;
    if (myId == null) return const Center(child: Text("Not authenticated"));

    // Filter local state based on active statuses
    final activeStatuses = [
      'assigned_to_rider',
      'preparing',
      'out_for_delivery',
    ];
    final activeOrders = _myActiveOrders
        .where((o) => activeStatuses.contains(o['status']))
        .toList();

    final count = activeOrders.length;

    return Scaffold(
      backgroundColor: AppUi.pageBgOf(context),
      body: Column(
        children: [
          TabScreenHeroHeader(
            title: 'Dispatch',
            subtitle: '$count active jobs · Online',
            actions: [
              IconButton(
                onPressed: _loadRiderData,
                icon: const Icon(Icons.refresh_rounded, color: Colors.white),
                tooltip: 'Refresh dispatch',
              ),
            ],
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadRiderData,
              color: AppUi.bluePrimary,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: AppUi.pagePaddingLoose.copyWith(top: 12),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: _buildSmallStatTile(
                                  'Active tasks',
                                  '${activeOrders.length}',
                                  Icons.navigation_rounded,
                                  AppUi.bluePrimary,
                                ),
                              ),
                              AppUi.hGapMd,
                              Expanded(
                                child: _buildSmallStatTile(
                                  'Earnings',
                                  '₱${_totalEarnings.toStringAsFixed(0)}',
                                  Icons.payments_rounded,
                                  const Color(0xFF10B981),
                                ),
                              ),
                            ],
                          ),
                          if (_pendingOfflineCount > 0) ...[
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.amber.withValues(alpha: 0.15),
                                borderRadius: AppUi.cardRadius,
                                border: Border.all(
                                  color: Colors.amber.withValues(alpha: 0.4),
                                ),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.cloud_off_rounded,
                                    color: Colors.amber,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      '$_pendingOfflineCount ${_pendingOfflineCount == 1 ? "delivery" : "deliveries"} waiting to sync',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: _isSyncingOffline
                                        ? null
                                        : _syncOfflineQueue,
                                    child: _isSyncingOffline
                                        ? const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Text(
                                            'Sync Now',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  if (_isLoading && activeOrders.isEmpty)
                    const SliverFillRemaining(child: SkeletonList(itemCount: 4))
                  else if (activeOrders.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Padding(
                        padding: const EdgeInsets.all(AppUi.spacingLg),
                        child: FriendlyHeroCard(
                          role: ExperienceRole.rider,
                          scene: ExperienceScene.delivery,
                          eyebrow: 'All clear',
                          title: 'No active dispatches',
                          message:
                              'New jobs will appear here in real time. Keep your profile complete and stay ready for pickup.',
                          actionLabel: 'Refresh',
                          actionIcon: Icons.refresh_rounded,
                          onAction: _loadRiderData,
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: _buildOrderCard(activeOrders[index]),
                          ),
                          childCount: activeOrders.length,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderCard(Map<String, dynamic> order) {
    final orderId = (order['id'] ?? '').toString();
    final status = (order['status'] ?? 'assigned_to_rider').toString();
    final isOutForDelivery = status == 'out_for_delivery';
    final total = _safeDouble(order['total_amount']);
    final rawPaymentMethod = (order['payment_method'] ?? 'cod')
        .toString()
        .toLowerCase();
    final paymentStatus = (order['payment_status'] ?? 'pending')
        .toString()
        .toLowerCase();
    final isCod = rawPaymentMethod == 'cod' || rawPaymentMethod == 'cash';
    final isPaid = paymentStatus == 'success' || paymentStatus == 'paid';
    final paymentLabel = CheckoutRules.paymentLabel(rawPaymentMethod);

    // Support both direct fields and joined profile object
    final customerObj = _safeMap(order['customer']);
    final customerName =
        order['customer_name'] ?? customerObj?['full_name'] ?? 'Guest Customer';
    final address =
        order['customer_address'] ??
        customerObj?['complete_address'] ??
        'No address provided';
    final phone = order['customer_phone'] ?? customerObj?['phone'] ?? '';
    final rawBarangay =
        order['customer_barangay'] ?? customerObj?['barangay'] ?? '';
    final barangayText = rawBarangay.isNotEmpty ? ' • $rawBarangay' : '';

    final itemsString = _formatItems(order['items']);

    return Container(
      decoration: BoxDecoration(
        color: AppUi.surfaceOf(context),
        borderRadius: AppUi.cardRadius,
        border: Border.all(
          color: isOutForDelivery ? AppUi.bluePrimary : AppUi.borderOf(context),
          width: isOutForDelivery ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: Theme.of(context).brightness == Brightness.dark
                  ? 0.2
                  : 0.04,
            ),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Header
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isOutForDelivery
                        ? AppUi.blueSoft
                        : AppUi.chipBgOf(context),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    status == 'out_for_delivery'
                        ? Icons.local_shipping_rounded
                        : Icons.pending_actions_rounded,
                    color: isOutForDelivery
                        ? AppUi.bluePrimary
                        : AppUi.textSecondaryOf(context),
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Order #${orderId.length > 8 ? orderId.substring(0, 8).toUpperCase() : orderId.toUpperCase()}',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          color: AppUi.textPrimaryOf(context),
                        ),
                      ),
                      Text(
                        isPaid
                            ? 'PAID ONLINE (${paymentLabel.toUpperCase()})'
                            : isCod
                            ? 'CASH ON DELIVERY'
                            : 'AWAITING PAYMENT (${paymentLabel.toUpperCase()})',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          color: isPaid
                              ? const Color(0xFF059669)
                              : isCod
                              ? const Color(0xFFD97706)
                              : const Color(0xFFDC2626),
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                ),
                _statusChip(status),
              ],
            ),
          ),
          Divider(height: 1, color: AppUi.dividerOf(context)),

          // 1b. Live Delivery Progress Timeline
          _buildDeliveryTimeline(status),
          Divider(height: 1, color: AppUi.dividerOf(context)),

          // 2. Customer Info
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.person_rounded,
                      color: AppUi.textSecondaryOf(context),
                      size: 14,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      customerName,
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                        color: AppUi.textPrimaryOf(context),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.location_on_rounded,
                      color: AppUi.bluePrimary,
                      size: 14,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '$address$barangayText',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: AppUi.textSecondaryOf(context),
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
                if (order['customer_landmark'] != null) ...[
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.only(left: 20),
                    child: Text(
                      'Landmark: ${order['customer_landmark']}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: AppUi.textMuted,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),

          // 3. Refill details & amount
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            margin: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: AppUi.surfaceRaisedOf(context),
              borderRadius: AppUi.cardRadius,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    itemsString,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: AppUi.textPrimaryOf(context),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '₱${total.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                        color: AppUi.bluePrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isPaid
                          ? 'PAID (Do not collect)'
                          : isCod
                          ? 'COLLECT CASH'
                          : 'VERIFY PAYMENT',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        color: isPaid
                            ? const Color(0xFF059669)
                            : isCod
                            ? const Color(0xFFD97706)
                            : const Color(0xFFDC2626),
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // 4. Actions
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Row(
              children: [
                IconButton.outlined(
                  onPressed: () => _openNavigation(order),
                  icon: const Icon(Icons.navigation_rounded, size: 18),
                  tooltip: 'Navigate',
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppUi.bluePrimary,
                    side: BorderSide(color: AppUi.borderOf(context)),
                    shape: RoundedRectangleBorder(
                      borderRadius: AppUi.controlRadius,
                    ),
                    fixedSize: const Size(48, 48),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.outlined(
                  onPressed: () => _contactCustomer(order),
                  icon: const Icon(Icons.chat_bubble_rounded, size: 18),
                  tooltip: 'Chat',
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppUi.textSecondaryOf(context),
                    side: BorderSide(color: AppUi.borderOf(context)),
                    shape: RoundedRectangleBorder(
                      borderRadius: AppUi.controlRadius,
                    ),
                    fixedSize: const Size(48, 48),
                  ),
                ),
                if (phone.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  IconButton.outlined(
                    onPressed: () => url.launchUrl(Uri.parse('tel:$phone')),
                    icon: const Icon(Icons.phone_rounded, size: 18),
                    tooltip: 'Call Customer',
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF10B981),
                      side: BorderSide(color: AppUi.borderOf(context)),
                      shape: RoundedRectangleBorder(
                        borderRadius: AppUi.controlRadius,
                      ),
                      fixedSize: const Size(48, 48),
                    ),
                  ),
                ],
                const SizedBox(width: 8),
                Expanded(
                  child: status == 'assigned_to_rider'
                      ? _RiderSwipeToAcceptSlider(
                          label: 'Slide to Accept Order',
                          onAccepted: () =>
                              _updateOrderStatus(orderId, 'out_for_delivery'),
                        )
                      : SizedBox(
                          height: 48,
                          child: ElevatedButton.icon(
                            onPressed: () {
                              if (status == 'preparing') {
                                _updateOrderStatus(orderId, 'out_for_delivery');
                              } else if (status == 'out_for_delivery') {
                                _updateOrderStatus(orderId, 'delivered');
                              }
                            },
                            icon: Icon(
                              status == 'out_for_delivery'
                                  ? Icons.check_circle_rounded
                                  : Icons.arrow_forward_rounded,
                              size: 18,
                            ),
                            label: Text(
                              status == 'preparing'
                                  ? 'Start Delivery'
                                  : 'Complete Delivery',
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.5,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: status == 'out_for_delivery'
                                  ? const Color(0xFF10B981)
                                  : AppUi.bluePrimary,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: AppUi.controlRadius,
                              ),
                            ),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeliveryTimeline(String status) {
    int currentStep = 0;
    if (status == 'assigned_to_rider') {
      currentStep = 0;
    } else if (status == 'preparing') {
      currentStep = 1;
    } else if (status == 'out_for_delivery') {
      currentStep = 2;
    } else if (status == 'delivered') {
      currentStep = 3;
    }

    final steps = [
      {'title': 'Assigned', 'icon': Icons.assignment_ind_rounded},
      {'title': 'Prepared', 'icon': Icons.inventory_2_outlined},
      {'title': 'En Route', 'icon': Icons.moped_rounded},
      {'title': 'Delivered', 'icon': Icons.check_circle_rounded},
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(color: AppUi.bluePale.withValues(alpha: 0.35)),
      child: Row(
        children: [
          for (int i = 0; i < steps.length; i++) ...[
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      if (i > 0)
                        Expanded(
                          child: Container(
                            height: 2,
                            color: i <= currentStep
                                ? AppUi.bluePrimary
                                : AppUi.borderColor,
                          ),
                        )
                      else
                        const Spacer(),
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: i <= currentStep
                              ? AppUi.bluePrimary
                              : Colors.white,
                          border: Border.all(
                            color: i <= currentStep
                                ? AppUi.bluePrimary
                                : AppUi.borderColor,
                            width: 2,
                          ),
                          boxShadow: i == currentStep
                              ? [
                                  BoxShadow(
                                    color: AppUi.bluePrimary.withValues(
                                      alpha: 0.25,
                                    ),
                                    blurRadius: 6,
                                    spreadRadius: 1,
                                  ),
                                ]
                              : null,
                        ),
                        child: Icon(
                          steps[i]['icon'] as IconData,
                          size: 12,
                          color: i <= currentStep
                              ? Colors.white
                              : AppUi.textMuted,
                        ),
                      ),
                      if (i < steps.length - 1)
                        Expanded(
                          child: Container(
                            height: 2,
                            color: i < currentStep
                                ? AppUi.bluePrimary
                                : AppUi.borderColor,
                          ),
                        )
                      else
                        const Spacer(),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    steps[i]['title'] as String,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: i == currentStep
                          ? FontWeight.w800
                          : FontWeight.w600,
                      color: i <= currentStep
                          ? AppUi.bluePrimary
                          : AppUi.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _statusChip(String status) {
    Color color;
    String label;
    switch (status) {
      case 'assigned_to_rider':
        color = AppUi.bluePrimary;
        label = 'Assigned';
        break;
      case 'preparing':
        color = const Color(0xFFF59E0B);
        label = 'Legacy pickup';
        break;
      case 'out_for_delivery':
        color = AppUi.bluePrimary;
        label = 'En route';
        break;
      default:
        color = AppUi.textSecondary;
        label = status.replaceAll('_', ' ');
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          color: color,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Future<bool> _saveRiderProfile() async {
    final myId = supabase.auth.currentUser?.id;
    if (myId == null) return false;
    try {
      final fname = _profile?['first_name']?.toString() ?? '';
      final lname = _profile?['last_name']?.toString() ?? '';
      final mi = _profile?['mi']?.toString() ?? '';
      final suffix = _profile?['suffix']?.toString() ?? '';

      final composedName = "$fname $mi $lname $suffix"
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();

      await ProfileQueryHelpers.updateProfile(supabase, {
        'full_name': composedName,
        'first_name': fname,
        'last_name': lname,
        'mi': mi,
        'suffix': suffix,
        'phone': _profile?['phone'],
        'town': _profile?['town'],
        'barangay': _profile?['barangay'],
        'license_number': _profile?['license_number'],
        'vehicle_type': _profile?['vehicle_type'],
      }, userId: myId);

      if (mounted) {
        await context.read<UserProvider>().refreshProfile();
        await _loadRiderData();
        if (!mounted) return true;
        setState(() {
          _profile?['full_name'] = composedName;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile updated successfully.'),
            backgroundColor: AppUi.successFg,
          ),
        );
      }
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error updating profile: $e')));
      }
      return false;
    }
  }

  String get _riderFullName =>
      (_profile?['full_name'] ?? 'Rider').toString().trim();

  String get _riderServiceArea {
    return [
      _profile?['barangay'],
      _profile?['town'],
    ].where((part) => (part ?? '').toString().trim().isNotEmpty).join(', ');
  }

  bool get _profileIsComplete {
    final hasName =
        (_profile?['first_name'] ?? '').toString().trim().isNotEmpty &&
        (_profile?['last_name'] ?? '').toString().trim().isNotEmpty;
    final hasPhone = (_profile?['phone'] ?? '').toString().trim().isNotEmpty;
    final hasArea =
        (_profile?['town'] ?? '').toString().trim().isNotEmpty &&
        (_profile?['barangay'] ?? '').toString().trim().isNotEmpty;
    final hasVehicle =
        (_profile?['vehicle_type'] ?? '').toString().trim().isNotEmpty &&
        (_profile?['license_number'] ?? '').toString().trim().isNotEmpty;
    return hasName && hasPhone && hasArea && hasVehicle;
  }

  String get _profileCompletionMessage {
    if ((_profile?['first_name'] ?? '').toString().trim().isEmpty ||
        (_profile?['phone'] ?? '').toString().trim().isEmpty) {
      return 'Add your name and phone so stations can reach you.';
    }
    if (_riderServiceArea.isEmpty) {
      return 'Set your town and barangay for nearby dispatch.';
    }
    if ((_profile?['vehicle_type'] ?? '').toString().trim().isEmpty) {
      return 'Add vehicle and license details for accountability.';
    }
    return 'Complete your rider profile for faster assignments.';
  }

  void _openEditProfileSheet({int initialCategory = 0}) {
    int selectedCategory = initialCategory;
    bool isSaving = false;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setModalState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
          ),
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(sheetContext).size.height * 0.92,
            ),
            decoration: BoxDecoration(
              color: AppUi.surfaceOf(context),
              borderRadius: AppUi.radiusSheetTop,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppUi.borderOf(context),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 12, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Edit Profile',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: AppUi.textPrimaryOf(context),
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () {
                          if (!isSaving && sheetContext.mounted) {
                            final nav = Navigator.of(sheetContext);
                            if (nav.canPop()) nav.pop();
                          }
                        },
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                // Categorized Tab Selector Bar
                Container(
                  margin: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: AppUi.pageBgOf(context),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppUi.borderOf(context)),
                  ),
                  child: Row(
                    children: [
                      _buildCategoryTabItem(
                        context: context,
                        label: 'Personal',
                        icon: Icons.person_outline_rounded,
                        isSelected: selectedCategory == 0,
                        onTap: () => setModalState(() => selectedCategory = 0),
                      ),
                      _buildCategoryTabItem(
                        context: context,
                        label: 'Location',
                        icon: Icons.location_on_outlined,
                        isSelected: selectedCategory == 1,
                        onTap: () => setModalState(() => selectedCategory = 1),
                      ),
                      _buildCategoryTabItem(
                        context: context,
                        label: 'Vehicle',
                        icon: Icons.two_wheeler_rounded,
                        isSelected: selectedCategory == 2,
                        onTap: () => setModalState(() => selectedCategory = 2),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    child: _buildRiderProfileForm(
                      sheetContext,
                      setModalState,
                      selectedCategory,
                      isSaving,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryTabItem({
    required BuildContext context,
    required String label,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? AppUi.surfaceOf(context) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 15,
                color: isSelected
                    ? AppUi.bluePrimary
                    : AppUi.textSecondaryOf(context),
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                  color: isSelected
                      ? AppUi.textPrimaryOf(context)
                      : AppUi.textSecondaryOf(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRiderProfileForm(
    BuildContext sheetContext,
    void Function(void Function()) setModalState,
    int categoryIndex,
    bool isSaving,
  ) {
    final currentTown = _getNormalizedTown(_profile?['town']?.toString());
    final currentBarangay = _getNormalizedBarangay(
      _profile?['town']?.toString(),
      _profile?['barangay']?.toString(),
    );
    final barangayList =
        currentTown != null && _municipalityData.containsKey(currentTown)
        ? _municipalityData[currentTown]!
        : <String>[];

    if (categoryIndex == 1) {
      // Category 1: Service Location
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AppFormSectionHeader(
            title: 'SERVICE LOCATION',
            subtitle: 'Your primary dispatch municipality and barangay',
          ),
          AppUi.vGapMd,
          AppDropdownField<String>.fromStrings(
            label: 'Town Center',
            value: currentTown,
            prefixIcon: Icons.location_city_outlined,
            items: _municipalityData.keys.toList(),
            compact: true,
            onChanged: (v) => setModalState(() {
              _profile?['town'] = v;
              _profile?['barangay'] = null;
            }),
          ),
          AppUi.vGapMd,
          AppDropdownField<String>.fromStrings(
            label: 'Barangay',
            value: currentBarangay,
            prefixIcon: Icons.home_work_outlined,
            items: barangayList,
            compact: true,
            onChanged: (v) => setModalState(() => _profile?['barangay'] = v),
          ),
          AppUi.vGapLg,
          AppFormSubmitButton(
            text: 'Save Location',
            icon: Icons.save_outlined,
            isLoading: isSaving,
            onPressed: isSaving
                ? null
                : () async {
                    setModalState(() => isSaving = true);
                    try {
                      final ok = await _saveRiderProfile();
                      if (ok && sheetContext.mounted) {
                        final nav = Navigator.of(sheetContext);
                        if (nav.canPop()) nav.pop();
                      }
                    } finally {
                      if (sheetContext.mounted) {
                        setModalState(() => isSaving = false);
                      }
                    }
                  },
          ),
        ],
      );
    }

    if (categoryIndex == 2) {
      // Category 2: Vehicle & License
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AppFormSectionHeader(
            title: 'VEHICLE & CREDENTIALS',
            subtitle: 'Delivery transport type and driver identification',
          ),
          AppUi.vGapMd,
          AppFormField(
            label: 'Vehicle Type',
            initialValue: _profile?['vehicle_type'] ?? '',
            prefixIcon: Icons.delivery_dining_rounded,
            compact: true,
            onChanged: (v) => _profile?['vehicle_type'] = v,
          ),
          AppUi.vGapMd,
          AppFormField(
            label: 'License Number',
            initialValue: _profile?['license_number'] ?? '',
            prefixIcon: Icons.badge_rounded,
            compact: true,
            onChanged: (v) => _profile?['license_number'] = v,
          ),
          AppUi.vGapLg,
          AppFormSubmitButton(
            text: 'Save Vehicle Details',
            icon: Icons.save_outlined,
            isLoading: isSaving,
            onPressed: isSaving
                ? null
                : () async {
                    setModalState(() => isSaving = true);
                    try {
                      final ok = await _saveRiderProfile();
                      if (ok && sheetContext.mounted) {
                        final nav = Navigator.of(sheetContext);
                        if (nav.canPop()) nav.pop();
                      }
                    } finally {
                      if (sheetContext.mounted) {
                        setModalState(() => isSaving = false);
                      }
                    }
                  },
          ),
        ],
      );
    }

    // Default: Category 0: Personal Details
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AppFormSectionHeader(
          title: 'PERSONAL INFORMATION',
          subtitle: 'Your full name and mobile contact number',
        ),
        AppUi.vGapMd,
        AppFormField(
          label: 'First Name',
          initialValue: _profile?['first_name'] ?? '',
          prefixIcon: Icons.person_outline,
          compact: true,
          onChanged: (v) => _profile?['first_name'] = v,
        ),
        AppUi.vGapMd,
        AppFormField(
          label: 'Last Name',
          initialValue: _profile?['last_name'] ?? '',
          prefixIcon: Icons.badge_outlined,
          compact: true,
          onChanged: (v) => _profile?['last_name'] = v,
        ),
        AppUi.vGapMd,
        AppFormField(
          label: 'Middle Initial (Optional)',
          initialValue: _profile?['mi'] ?? '',
          prefixIcon: Icons.text_fields_rounded,
          compact: true,
          onChanged: (v) => _profile?['mi'] = v,
        ),
        AppUi.vGapMd,
        AppDropdownField<String>.fromStrings(
          label: 'Suffix (Optional)',
          value: _profile?['suffix'] ?? 'None',
          prefixIcon: Icons.star_border_rounded,
          items: const ['None', 'Jr.', 'Sr.', 'II', 'III', 'IV', 'V'],
          compact: true,
          onChanged: (v) => setModalState(() {
            _profile?['suffix'] = (v == 'None' || v == null) ? null : v;
          }),
        ),
        AppUi.vGapMd,
        AppFormField(
          label: 'Phone Number',
          initialValue: _profile?['phone'] ?? '',
          prefixIcon: Icons.phone_outlined,
          keyboardType: TextInputType.phone,
          compact: true,
          onChanged: (v) => _profile?['phone'] = v,
        ),
        AppUi.vGapLg,
        AppFormSubmitButton(
          text: 'Save Personal Info',
          icon: Icons.save_outlined,
          isLoading: isSaving,
          onPressed: isSaving
              ? null
              : () async {
                  setModalState(() => isSaving = true);
                  try {
                    final ok = await _saveRiderProfile();
                    if (ok && sheetContext.mounted) {
                      final nav = Navigator.of(sheetContext);
                      if (nav.canPop()) nav.pop();
                    }
                  } finally {
                    if (sheetContext.mounted) {
                      setModalState(() => isSaving = false);
                    }
                  }
                },
        ),
      ],
    );
  }

  Widget _buildProfileTab() {
    final isOnline = _profile?['is_online'] == true;

    return Scaffold(
      backgroundColor: AppUi.pageBgOf(context),
      body: Column(
        children: [
          TabScreenHeroHeader(
            title: 'Account',
            subtitle: isOnline
                ? 'Online · Profile and delivery history'
                : 'Offline · Profile and delivery history',
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadRiderData,
              color: AppUi.bluePrimary,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverPadding(
                    padding: AppUi.pagePadding.copyWith(top: 12, bottom: 32),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        AccountIdentityBlock(
                          name: _riderFullName,
                          email: supabase.auth.currentUser?.email ?? '',
                          avatarUrl: _profile?['avatar_url']?.toString(),
                          onAvatarTap: _pickAndUploadImage,
                        ),
                        if (!_profileIsComplete)
                          AccountCompletenessHint(
                            message: _profileCompletionMessage,
                            onTap: () =>
                                _openEditProfileSheet(initialCategory: 0),
                          ),

                        const AccountSectionLabel('Profile'),
                        AccountGroup(
                          children: [
                            AccountNavTile(
                              icon: Icons.person_outline_rounded,
                              title: 'Personal information',
                              subtitle:
                                  '${_profile?['first_name'] ?? ''} ${_profile?['last_name'] ?? ''} · Phone: ${_profile?['phone'] ?? 'Set phone'}',
                              onTap: () =>
                                  _openEditProfileSheet(initialCategory: 0),
                            ),
                            AccountNavTile(
                              icon: Icons.location_on_outlined,
                              title: 'Service location',
                              subtitle: _riderServiceArea.isEmpty
                                  ? 'Set town & barangay'
                                  : _riderServiceArea,
                              onTap: () =>
                                  _openEditProfileSheet(initialCategory: 1),
                            ),
                            AccountNavTile(
                              icon: Icons.two_wheeler_rounded,
                              title: 'Vehicle & license',
                              subtitle:
                                  '${_profile?['vehicle_type'] ?? 'Motorcycle'} · License: ${_profile?['license_number'] ?? 'Not set'}',
                              onTap: () =>
                                  _openEditProfileSheet(initialCategory: 2),
                            ),
                          ],
                        ),

                        const AccountSectionLabel('Operations'),
                        AccountGroup(
                          children: [
                            AccountNavTile(
                              icon: Icons.account_balance_wallet_outlined,
                              title: 'Earnings breakdown',
                              subtitle:
                                  '₱${_totalEarnings.toStringAsFixed(2)} total payout earned',
                              onTap: _showEarningsStatement,
                            ),
                          ],
                        ),

                        const AccountSectionLabel('Preferences'),
                        AccountGroup(
                          children: [
                            AccountToggleTile(
                              icon: Icons.power_settings_new_rounded,
                              title: 'Available for delivery',
                              value: isOnline,
                              onChanged: _toggleOnlineStatus,
                            ),
                            AccountToggleTile(
                              icon: Icons.notifications_active_outlined,
                              title: 'Delivery dispatch alerts',
                              value: _soundAlertsEnabled,
                              onChanged: (v) =>
                                  setState(() => _soundAlertsEnabled = v),
                            ),
                            AccountToggleTile(
                              icon: Icons.dark_mode_outlined,
                              title: 'Dark mode',
                              value: context.select<ThemeProvider, bool>(
                                (t) => t.isDarkMode,
                              ),
                              onChanged: (v) =>
                                  context.read<ThemeProvider>().setDarkMode(v),
                            ),
                          ],
                        ),

                        const AccountSectionLabel('Account'),
                        AccountGroup(
                          children: [
                            AccountNavTile(
                              icon: Icons.logout_rounded,
                              iconColor: const Color(0xFFEF4444),
                              title: 'Sign out',
                              titleColor: const Color(0xFFEF4444),
                              subtitle:
                                  'Log out of your account on this device',
                              onTap: () => _showLogoutConfirmation(context),
                            ),
                            AccountNavTile(
                              icon: Icons.delete_outline_rounded,
                              iconColor: const Color(0xFFDC2626),
                              title: 'Delete account',
                              titleColor: const Color(0xFFDC2626),
                              subtitle:
                                  'Permanently remove your account and data',
                              onTap: () => _showDeleteAccountDialog(context),
                            ),
                          ],
                        ),
                      ]),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showDeleteAccountDialog(BuildContext context) {
    final deleteController = TextEditingController();
    bool isDeleting = false;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Container(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          decoration: BoxDecoration(
            color: AppUi.surfaceOf(context),
            borderRadius: AppUi.radiusSheetTop,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppUi.dividerOf(context),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      color: Color(0xFFEF4444),
                      size: 48,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Delete account',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: AppUi.textPrimaryOf(context),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'This permanently removes your account, delivery records, and profile.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppUi.textSecondary,
                        fontWeight: FontWeight.w600,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: deleteController,
                      textAlign: TextAlign.center,
                      decoration: AppUi.fieldDecorationOf(
                        context,
                        'Type DELETE',
                      ),
                      onChanged: (_) => setSheetState(() {}),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: FilledButton(
                        onPressed:
                            isDeleting ||
                                deleteController.text.toUpperCase() != 'DELETE'
                            ? null
                            : () async {
                                setSheetState(() => isDeleting = true);
                                try {
                                  await _locationService.stopTracking();
                                  await supabase.rpc('delete_user_account');
                                  await supabase.auth.signOut();
                                  if (context.mounted) {
                                    context.resetToAuth();
                                  }
                                } catch (e) {
                                  if (!context.mounted) return;
                                  setSheetState(() => isDeleting = false);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Deletion failed: $e'),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                }
                              },
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFEF4444),
                        ),
                        child: isDeleting
                            ? const CircularProgressIndicator(
                                color: Colors.white,
                              )
                            : const Text(
                                'Delete everything',
                                style: TextStyle(fontWeight: FontWeight.w800),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showEarningsStatement() {
    RiderPayoutSheet.show(
      context,
      totalEarnings: _totalEarnings,
      completedDeliveries: _completedDeliveries,
      profile: _profile,
    );
  }

  String? _getNormalizedTown(String? raw) {
    if (raw == null) return null;
    return _municipalityData.keys
            .firstWhere(
              (k) => k.toLowerCase() == raw.toLowerCase(),
              orElse: () => '',
            )
            .isEmpty
        ? null
        : _municipalityData.keys.firstWhere(
            (k) => k.toLowerCase() == raw.toLowerCase(),
          );
  }

  String? _getNormalizedBarangay(String? town, String? brgy) {
    if (town == null || brgy == null) return null;
    final normalizedTown = _getNormalizedTown(town);
    if (normalizedTown == null) return null;
    return _municipalityData[normalizedTown]!
            .firstWhere(
              (b) => b.toLowerCase() == brgy.toLowerCase(),
              orElse: () => '',
            )
            .isEmpty
        ? null
        : _municipalityData[normalizedTown]!.firstWhere(
            (b) => b.toLowerCase() == brgy.toLowerCase(),
          );
  }

  Widget _buildSmallStatTile(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: AppUi.pillRadius,
        border: Border.all(color: AppUi.bluePale),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(height: 12),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: AppUi.textMuted,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: AppUi.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  void _showLogoutConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: AppUi.cardRadius),
        title: const Text('Sign out?'),
        content: const Text(
          'Are you sure you want to end your session? Your location tracking will stop.',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: AppUi.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              await _locationService.stopTracking();
              await supabase.auth.signOut();
              if (!context.mounted) return;
              context.resetToAuth();
            },
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickAndUploadImage() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 600,
        maxHeight: 600,
        imageQuality: 85,
      );
      if (image == null) return;

      final fileBytes = await image.readAsBytes();
      final extension = image.name.split('.').last;
      final fileName = 'avatar_${user.id}.$extension';

      await supabase.storage
          .from('avatars')
          .uploadBinary(
            fileName,
            fileBytes,
            fileOptions: const FileOptions(upsert: true),
          );

      final publicUrl = supabase.storage.from('avatars').getPublicUrl(fileName);
      await supabase
          .from('profiles')
          .update({'avatar_url': publicUrl})
          .eq('id', user.id);

      if (mounted) {
        setState(() {
          _profile?['avatar_url'] =
              '$publicUrl?t=${DateTime.now().millisecondsSinceEpoch}';
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Avatar updated! ✨')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Upload failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}

// RiderHistoryScreen extracted to rider_history_screen.dart

// ── Rider Home Overview Tab ───────────────────────────────────────────────────

class _RiderHomeOverview extends StatelessWidget {
  final Map<String, dynamic>? profile;
  final int completedCount;
  final double totalEarnings;
  final List<Map<String, dynamic>> activeOrders;
  final ValueChanged<int> onNavigate;
  final Future<void> Function()? onRefresh;

  const _RiderHomeOverview({
    required this.profile,
    required this.completedCount,
    required this.totalEarnings,
    required this.activeOrders,
    required this.onNavigate,
    this.onRefresh,
  });

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final fullName = profile?['full_name'] ?? 'Rider';
    final firstName = fullName.split(' ').first;
    final active = activeOrders.isNotEmpty ? activeOrders.first : null;

    return Scaffold(
      backgroundColor: AppUi.pageBgOf(context),
      body: Column(
        children: [
          RiderHeroHeader(
            greeting: '$_greeting, $firstName',
            subtitle:
                '$completedCount completed · ₱${totalEarnings.toStringAsFixed(0)} earned',
            onNotificationTap: () => showNotificationPreviewSheet(
              context,
              onViewAll: () => context.openInbox(),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: onRefresh ?? () async {},
              color: AppUi.bluePrimary,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverPadding(
                    padding: AppUi.pagePaddingLoose.copyWith(
                      top: AppUi.spacingMd,
                    ),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        if (active != null) ...[
                          RiderActiveDeliveryCard(
                            order: active,
                            onTap: () => onNavigate(1),
                          ),
                          AppUi.vGapLg,
                        ] else ...[
                          FriendlyHeroCard(
                            role: ExperienceRole.rider,
                            scene: ExperienceScene.delivery,
                            eyebrow: 'Ready mode',
                            title: 'Dispatches will land here',
                            message:
                                'When your station assigns a refill, you will see pickup, customer, and route details immediately.',
                            actionLabel: 'Open dispatch',
                            actionIcon: Icons.delivery_dining_rounded,
                            onAction: () => onNavigate(1),
                          ),
                          AppUi.vGapLg,
                        ],
                        Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: DashboardStatCard(
                                    label: 'Total earnings',
                                    value:
                                        '₱${totalEarnings.toStringAsFixed(0)}',
                                    icon: Icons.payments_rounded,
                                    color: AppUi.accentGreen,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: DashboardStatCard(
                                    label: 'Completed',
                                    value: '$completedCount',
                                    icon: Icons.check_circle_rounded,
                                    color: AppUi.bluePrimary,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: DashboardStatCard(
                                    label: 'Active jobs',
                                    value: '${activeOrders.length}',
                                    icon: Icons.local_shipping_rounded,
                                    color: AppUi.accentCyan,
                                    onTap: () => onNavigate(1),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: DashboardStatCard(
                                    label: 'Pending pickup',
                                    value:
                                        '${activeOrders.where((o) => o['status'] == 'assigned_to_rider').length}',
                                    icon: Icons.inventory_2_outlined,
                                    color: const Color(0xFFF59E0B),
                                    onTap: () => onNavigate(1),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        AppUi.vGapLg,
                        AxoTipCard(
                          title: 'Deliver fast, earn more',
                          message:
                              'Quick deliveries and proof-of-delivery photos help you get priority jobs from your station.',
                          trailingIcon: Icons.bolt_rounded,
                        ),
                      ]),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Interactive swipe-to-accept slider for riders with haptic feedback
class _RiderSwipeToAcceptSlider extends StatefulWidget {
  final VoidCallback onAccepted;
  final String label;

  const _RiderSwipeToAcceptSlider({
    required this.onAccepted,
    this.label = 'Slide to Accept Order',
  });

  @override
  State<_RiderSwipeToAcceptSlider> createState() =>
      _RiderSwipeToAcceptSliderState();
}

class _RiderSwipeToAcceptSliderState extends State<_RiderSwipeToAcceptSlider> {
  double _position = 0.0;
  bool _accepted = false;

  @override
  Widget build(BuildContext context) {
    if (_accepted) {
      return Container(
        height: 48,
        decoration: BoxDecoration(
          color: AppUi.accentGreen,
          borderRadius: AppUi.controlRadius,
        ),
        alignment: Alignment.center,
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
            SizedBox(width: 8),
            Text(
              'Accepted & Starting!',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 13,
              ),
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxSlide = (constraints.maxWidth - 48).clamp(0.0, 500.0);

        return Container(
          height: 48,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppUi.bluePrimary,
                AppUi.bluePrimary.withValues(alpha: 0.85),
              ],
            ),
            borderRadius: AppUi.controlRadius,
          ),
          child: Stack(
            children: [
              Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: Colors.white70,
                      size: 18,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      widget.label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                left: _position,
                top: 2,
                bottom: 2,
                child: GestureDetector(
                  onHorizontalDragUpdate: (details) {
                    setState(() {
                      _position = (_position + details.delta.dx).clamp(
                        0.0,
                        maxSlide,
                      );
                    });
                  },
                  onHorizontalDragEnd: (details) {
                    if (_position >= maxSlide * 0.72) {
                      setState(() {
                        _position = maxSlide;
                        _accepted = true;
                      });
                      HapticFeedback.heavyImpact();
                      widget.onAccepted();
                    } else {
                      setState(() {
                        _position = 0.0;
                      });
                    }
                  },
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x33000000),
                          blurRadius: 6,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.double_arrow_rounded,
                      color: AppUi.bluePrimary,
                      size: 20,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
