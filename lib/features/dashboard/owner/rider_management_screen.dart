import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:erefill/core/constants.dart';
import 'package:erefill/core/widgets/app_form_fields.dart';
import 'package:erefill/core/widgets/app_widgets.dart';
import 'package:erefill/core/routing/app_navigation.dart';
import 'package:erefill/core/utils/safe_supabase.dart';
import 'package:erefill/core/utils/friendly_errors.dart';
import 'package:erefill/core/services/local_data_cache.dart';

import 'package:erefill/core/theme/app_colors.dart';
class RiderManagementScreen extends StatefulWidget {
  const RiderManagementScreen({super.key});

  static Future<bool?> showUnlinkRiderDialog(
    BuildContext context,
    Map<String, dynamic> rider, {
    VoidCallback? onUnlinked,
  }) async {
    final riderId = rider['id']?.toString() ?? '';
    final riderName = rider['full_name']?.toString() ?? 'this rider';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppUi.surfaceOf(context),
        shape: RoundedRectangleBorder(borderRadius: AppUi.cardRadius),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.uiError.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(AppUi.radiusControl),
              ),
              child: const Icon(
                Icons.person_remove_rounded,
                color: AppColors.uiError,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Unlink Rider',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
              ),
            ),
          ],
        ),
        content: Text(
          'Are you sure you want to remove $riderName from your station? They will no longer receive or deliver refill orders for your station.',
          style: TextStyle(
            fontSize: 14,
            color: AppUi.textSecondaryOf(context),
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.uiError,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppUi.radiusControl),
              ),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Unlink Rider'),
          ),
        ],
      ),
    );

    if (confirmed != true) return false;

    try {
      await SafeSupabase.unlinkRider(riderId: riderId);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$riderName has been unlinked from your station.'),
            backgroundColor: AppUi.bluePrimary,
          ),
        );
      }
      onUnlinked?.call();
      return true;
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              FriendlyErrors.message(
                e,
                fallback: 'Could not unlink rider. Please try again.',
              ),
            ),
            backgroundColor: AppColors.uiError,
          ),
        );
      }
      return false;
    }
  }

  static Future<bool?> showToggleStatusDialog(
    BuildContext context,
    Map<String, dynamic> rider, {
    VoidCallback? onStatusChanged,
  }) async {
    final riderId = rider['id']?.toString() ?? '';
    final riderName = rider['full_name']?.toString() ?? 'this rider';
    final isSuspended = rider['is_suspended'] == true;
    final willSuspend = !isSuspended;
    final reasonController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppUi.surfaceOf(context),
        shape: RoundedRectangleBorder(borderRadius: AppUi.cardRadius),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: (willSuspend ? AppColors.uiWarning : AppColors.uiSuccess)
                    .withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(AppUi.radiusControl),
              ),
              child: Icon(
                willSuspend ? Icons.block_rounded : Icons.check_circle_rounded,
                color: willSuspend ? AppColors.uiWarning : AppColors.uiSuccess,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                willSuspend ? 'Suspend Rider' : 'Activate Rider',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              willSuspend
                  ? 'Suspending $riderName will prevent them from accepting new deliveries until reactivated.'
                  : 'Reactivate $riderName so they can resume accepting delivery assignments?',
              style: TextStyle(
                fontSize: 14,
                color: AppUi.textSecondaryOf(context),
                height: 1.4,
              ),
            ),
            if (willSuspend) ...[
              const SizedBox(height: 14),
              TextField(
                controller: reasonController,
                decoration: InputDecoration(
                  labelText: 'Reason for suspension (optional)',
                  hintText: 'e.g. Temporary leave, policy review',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppUi.radiusControl),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
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
              backgroundColor: willSuspend
                  ? AppColors.uiWarning
                  : AppColors.uiSuccess,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppUi.radiusControl),
              ),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(willSuspend ? 'Suspend' : 'Activate'),
          ),
        ],
      ),
    );

    if (confirmed != true) return false;

    try {
      await SafeSupabase.setRiderStatus(
        riderId: riderId,
        isSuspended: willSuspend,
        reason: reasonController.text.trim().isEmpty
            ? null
            : reasonController.text.trim(),
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '$riderName is now ${willSuspend ? "suspended" : "active"}.',
            ),
            backgroundColor: willSuspend
                ? AppColors.uiWarning
                : AppColors.uiSuccess,
          ),
        );
      }
      onStatusChanged?.call();
      return true;
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              FriendlyErrors.message(
                e,
                fallback: 'Could not update rider status. Please try again.',
              ),
            ),
            backgroundColor: AppColors.uiError,
          ),
        );
      }
      return false;
    }
  }

  static Future<bool?> showEditRiderCredentialsDialog(
    BuildContext context,
    Map<String, dynamic> rider, {
    VoidCallback? onUpdated,
  }) {
    return _RiderManagementScreenState.showEditRiderCredentialsDialog(
      context,
      rider,
      onUpdated: onUpdated,
    );
  }

  @override
  State<RiderManagementScreen> createState() => _RiderManagementScreenState();
}

class _RiderManagementScreenState extends State<RiderManagementScreen> {
  final supabase = Supabase.instance.client;
  List<dynamic> _riders = [];
  bool _isLoading = true;
  StreamSubscription? _ridersSub;

  @override
  void initState() {
    super.initState();
    _loadDiskCache();
    _fetchRidersDirect();
    _setupRidersListener();
  }

  Future<void> _loadDiskCache() async {
    final ownerId = SafeSupabase.currentUserId;
    if (ownerId == null) return;
    final cached = await LocalDataCache.instance.get<List<dynamic>>('owner_riders_$ownerId');
    if (cached != null && cached.isNotEmpty && mounted) {
      setState(() {
        _riders = cached;
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _ridersSub?.cancel();
    super.dispose();
  }

  Future<void> _fetchRidersDirect() async {
    final ownerId = SafeSupabase.currentUserId;
    if (ownerId == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    try {
      final res = await supabase
          .from('profiles')
          .select()
          .eq('owner_id', ownerId)
          .eq('role', 'rider')
          .order('full_name', ascending: true);
      if (mounted) {
        setState(() {
          _riders = res;
          _isLoading = false;
        });
        LocalDataCache.instance.set('owner_riders_$ownerId', res);
      }
    } catch (e) {
      debugPrint('Error fetching riders directly: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _setupRidersListener() {
    final ownerId = SafeSupabase.currentUserId;
    if (ownerId == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    _ridersSub = supabase
        .from('profiles')
        .stream(primaryKey: ['id'])
        .eq('owner_id', ownerId)
        .order('full_name', ascending: true)
        .listen(
          (data) {
            if (mounted) {
              setState(() {
                _riders = data.where((r) => r['role'] == 'rider').toList();
                _isLoading = false;
              });
            }
          },
          onError: (e) {
            debugPrint('Riders stream error: $e');
            if (mounted) setState(() => _isLoading = false);
          },
        );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppUi.pageBgOf(context),
      body: _isLoading
          ? const LoadingState(message: 'Loading station riders...')
          : RefreshIndicator(
              onRefresh: () async {
                _ridersSub?.cancel();
                _setupRidersListener();
              },
              child: _riders.isEmpty
                  ? const EmptyState(
                      icon: Icons.two_wheeler_rounded,
                      title: 'No riders yet',
                      message: 'Add a rider to begin delivering refill orders.',
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(20),
                      itemCount: _riders.length,
                      itemBuilder: (context, index) {
                        final rider = _riders[index];
                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: AppUi.cardDecorationOf(
                            context,
                            borderRadius: AppUi.pillRadius,
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () async {
                                HapticFeedback.selectionClick();
                                await context.openRiderPerformance(
                                  riderId: rider['id'].toString(),
                                  riderName:
                                      rider['full_name']?.toString() ??
                                      'Rider Profile',
                                );
                                if (mounted) {
                                  _fetchRidersDirect();
                                }
                              },
                              borderRadius: AppUi.pillRadius,
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 52,
                                      height: 52,
                                      decoration: BoxDecoration(
                                        color: AppUi.bluePrimary.withValues(
                                          alpha: 0.1,
                                        ),
                                        borderRadius: AppUi.cardRadius,
                                      ),
                                      child: Icon(
                                        Icons.two_wheeler_rounded,
                                        color: AppUi.brandOf(context),
                                        size: 24,
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            rider['full_name'] ??
                                                'Rider Profile',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 16,
                                              color: AppUi.textPrimaryOf(
                                                context,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            "@${rider['username'] ?? 'username'}",
                                            style: const TextStyle(
                                              color: AppUi.textMuted,
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 5,
                                          ),
                                          decoration: BoxDecoration(
                                            color:
                                                (rider['is_suspended'] == true
                                                        ? const Color(
                                                            0xFFEF4444,
                                                          )
                                                        : const Color(
                                                            0xFF10B981,
                                                          ))
                                                    .withValues(alpha: 0.1),
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                          child: Text(
                                            rider['is_suspended'] == true
                                                ? 'Suspended'
                                                : 'Active',
                                            style: TextStyle(
                                              color:
                                                  rider['is_suspended'] == true
                                                  ? AppColors.uiError
                                                  : AppColors.uiSuccess,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: 0.5,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        PopupMenuButton<String>(
                                          icon: const Icon(
                                            Icons.more_vert_rounded,
                                            size: 20,
                                            color: AppUi.textMuted,
                                          ),
                                          tooltip: 'Rider Actions',
                                          shape: RoundedRectangleBorder(
                                            borderRadius: AppUi.cardRadius,
                                          ),
                                          onSelected: (val) {
                                            HapticFeedback.lightImpact();
                                            if (val == 'edit') {
                                              _showEditRiderDialog(rider);
                                            } else if (val == 'status') {
                                              RiderManagementScreen.showToggleStatusDialog(
                                                context,
                                                rider,
                                                onStatusChanged:
                                                    _fetchRidersDirect,
                                              );
                                            } else if (val == 'unlink') {
                                              RiderManagementScreen.showUnlinkRiderDialog(
                                                context,
                                                rider,
                                                onUnlinked: _fetchRidersDirect,
                                              );
                                            }
                                          },
                                          itemBuilder: (ctx) => [
                                            PopupMenuItem(
                                              value: 'edit',
                                              child: Row(
                                                children: [
                                                  Icon(
                                                    Icons.edit_outlined,
                                                    size: 18,
                                                    color: AppUi.brandOf(context),
                                                  ),
                                                  SizedBox(width: 10),
                                                  Text('Edit Credentials'),
                                                ],
                                              ),
                                            ),
                                            PopupMenuItem(
                                              value: 'status',
                                              child: Row(
                                                children: [
                                                  Icon(
                                                    rider['is_suspended'] ==
                                                            true
                                                        ? Icons
                                                              .check_circle_outline
                                                        : Icons.block_outlined,
                                                    size: 18,
                                                    color:
                                                        rider['is_suspended'] ==
                                                            true
                                                        ? const Color(
                                                            0xFF10B981,
                                                          )
                                                        : AppColors.uiWarning,
                                                  ),
                                                  const SizedBox(width: 10),
                                                  Text(
                                                    rider['is_suspended'] ==
                                                            true
                                                        ? 'Activate Rider'
                                                        : 'Suspend Rider',
                                                  ),
                                                ],
                                              ),
                                            ),
                                            PopupMenuItem(
                                              value: 'unlink',
                                              child: Row(
                                                children: [
                                                  Icon(
                                                    Icons
                                                        .person_remove_outlined,
                                                    size: 18,
                                                    color: AppColors.uiError,
                                                  ),
                                                  const SizedBox(width: 10),
                                                  Text(
                                                    'Unlink from Station',
                                                    style: TextStyle(
                                                      color: AppColors.uiError,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppUi.bluePrimary,
        onPressed: _showAddRiderDialog,
        elevation: 4,
        highlightElevation: 0,
        shape: RoundedRectangleBorder(borderRadius: AppUi.cardRadius),
        label: const Text(
          "Register Rider",
          style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.2),
        ),
        icon: const Icon(Icons.person_add_rounded, size: 20),
      ),
    );
  }

  void _showEditRiderDialog(Map<String, dynamic> rider) async {
    final updated = await showEditRiderCredentialsDialog(
      context,
      rider,
      onUpdated: _fetchRidersDirect,
    );
    if (updated == true && mounted) {
      _fetchRidersDirect();
    }
  }

  static Future<bool?> showEditRiderCredentialsDialog(
    BuildContext context,
    Map<String, dynamic> rider, {
    VoidCallback? onUpdated,
  }) async {
    final supabase = Supabase.instance.client;
    final riderId = rider['id']?.toString() ?? '';

    // Always fetch the authoritative current profile record from Supabase
    // so the edit form immediately displays current authorized information, not stale list cache
    Map<String, dynamic> activeRider = Map<String, dynamic>.from(rider);
    try {
      final fresh = await supabase
          .from('profiles')
          .select()
          .eq('id', riderId)
          .maybeSingle();
      if (fresh != null) {
        activeRider = Map<String, dynamic>.from(fresh);
      }
    } catch (e) {
      debugPrint('Warning: Could not fetch fresh rider profile before edit: $e');
    }

    String initialFirst = activeRider['first_name']?.toString().trim() ?? '';
    String initialLast = activeRider['last_name']?.toString().trim() ?? '';
    String initialMi = activeRider['mi']?.toString().trim() ?? '';
    String? initialSuffix = activeRider['suffix']?.toString().trim();
    if (initialSuffix == '' || initialSuffix == 'null' || initialSuffix == 'None') {
      initialSuffix = null;
    }

    // Fallback name parsing for existing rows where first_name and last_name are null
    if (initialFirst.isEmpty && initialLast.isEmpty) {
      final rawFullName = activeRider['full_name']?.toString().trim() ?? '';
      if (rawFullName.isNotEmpty) {
        final parts = rawFullName.split(RegExp(r'\s+'));
        const suffixes = {'Jr.', 'Sr.', 'II', 'III', 'IV', 'V'};
        if (parts.length > 2 && suffixes.contains(parts.last)) {
          initialSuffix ??= parts.last;
          parts.removeLast();
        }
        if (parts.length == 1) {
          initialFirst = parts.first;
        } else if (parts.length == 2) {
          initialFirst = parts.first;
          initialLast = parts[1];
        } else if (parts.length >= 3) {
          if (parts[1].length <= 2) {
            initialFirst = parts[0];
            initialMi = parts[1].replaceAll('.', '');
            initialLast = parts.sublist(2).join(' ');
          } else {
            initialFirst = parts[0];
            initialLast = parts.sublist(1).join(' ');
          }
        }
      }
    }

    final firstNameController = TextEditingController(text: initialFirst);
    final lastNameController = TextEditingController(text: initialLast);
    final miController = TextEditingController(text: initialMi);
    String? selectedSuffix = initialSuffix;
    final phoneController = TextEditingController(
      text: activeRider['phone']?.toString().trim() ?? '',
    );
    final vehicleController = TextEditingController(
      text: activeRider['vehicle_type']?.toString().trim() ?? '',
    );
    final licenseController = TextEditingController(
      text: activeRider['license_number']?.toString().trim() ?? '',
    );
    final passwordController = TextEditingController();
    bool isSaving = false;

    if (!context.mounted) return false;

    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => Container(
          padding: EdgeInsets.fromLTRB(
            20,
            12,
            20,
            MediaQuery.of(sheetContext).viewInsets.bottom + 40,
          ),
          decoration: BoxDecoration(
            color: AppUi.surfaceOf(sheetContext),
            borderRadius: AppUi.radiusSheetTop,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppUi.borderOf(sheetContext),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  "Edit Rider Credentials",
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppUi.textPrimaryOf(sheetContext),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  "Update profile details or assign a new password for @${activeRider['username'] ?? rider['username'] ?? 'rider'}",
                  style: TextStyle(
                    color: AppUi.textSecondaryOf(sheetContext),
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: AppFormField(
                        controller: firstNameController,
                        label: "First Name",
                        icon: Icons.person_outline_rounded,
                        textCapitalization: TextCapitalization.words,
                        compact: true,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: AppFormField(
                        controller: lastNameController,
                        label: "Last Name",
                        icon: Icons.person_outline_rounded,
                        textCapitalization: TextCapitalization.words,
                        compact: true,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: AppFormField(
                        controller: miController,
                        label: "M.I.",
                        icon: Icons.text_fields_rounded,
                        textCapitalization: TextCapitalization.characters,
                        compact: true,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 3,
                      child: AppDropdownField<String>.fromStrings(
                        label: 'Suffix',
                        value: selectedSuffix,
                        icon: Icons.star_border_rounded,
                        items: const [
                          'None',
                          'Jr.',
                          'Sr.',
                          'II',
                          'III',
                          'IV',
                          'V',
                        ],
                        compact: true,
                        onChanged: (v) {
                          setSheetState(
                            () => selectedSuffix = (v == 'None' || v == null)
                                ? null
                                : v,
                          );
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                AppFormField(
                  controller: phoneController,
                  label: "Phone Number",
                  icon: Icons.phone_outlined,
                  keyboardType: TextInputType.phone,
                  compact: true,
                ),
                const SizedBox(height: 12),
                AppFormField(
                  controller: vehicleController,
                  label: "Vehicle Type",
                  icon: Icons.two_wheeler_rounded,
                  compact: true,
                ),
                const SizedBox(height: 12),
                AppFormField(
                  controller: licenseController,
                  label: "License Number",
                  icon: Icons.badge_outlined,
                  compact: true,
                ),
                const SizedBox(height: 12),
                AppFormField(
                  controller: passwordController,
                  label: "New Password (optional)",
                  icon: Icons.lock_outline_rounded,
                  isPassword: true,
                  hintText: "Leave blank to keep current password",
                  compact: true,
                ),
                const SizedBox(height: 24),
                AppFormSubmitButton(
                  label: isSaving ? "Saving changes..." : "Save Credentials",
                  icon: Icons.check_circle_outline_rounded,
                  onPressed: isSaving
                      ? () {}
                      : () async {
                          final fname = firstNameController.text.trim();
                          final lname = lastNameController.text.trim();
                          final mi = miController.text.trim();
                          final phone = phoneController.text.trim();
                          final vehicle = vehicleController.text.trim();
                          final license = licenseController.text.trim();
                          final newPass = passwordController.text.trim();

                          if (fname.isEmpty || lname.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'First name and last name are required.',
                                ),
                              ),
                            );
                            return;
                          }
                          if (newPass.isNotEmpty && newPass.length < 6) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Password must be at least 6 characters.',
                                ),
                              ),
                            );
                            return;
                          }

                          setSheetState(() => isSaving = true);
                          try {
                            final composedName = [
                              fname,
                              mi,
                              lname,
                              selectedSuffix ?? '',
                            ].where((s) => s.trim().isNotEmpty).join(' ').trim();

                            bool rpcSucceeded = false;
                            try {
                              await supabase.rpc(
                                'owner_update_rider_credentials',
                                params: {
                                  'p_rider_id': riderId,
                                  'p_first_name': fname,
                                  'p_last_name': lname,
                                  'p_mi': mi.isEmpty ? null : mi,
                                  'p_suffix': selectedSuffix,
                                  'p_phone': phone.isEmpty ? null : phone,
                                  'p_vehicle_type': vehicle.isEmpty
                                      ? null
                                      : vehicle,
                                  'p_license_number': license.isEmpty
                                      ? null
                                      : license,
                                  'p_password': newPass.isEmpty
                                      ? null
                                      : newPass,
                                },
                              );
                              rpcSucceeded = true;
                            } catch (rpcErr) {
                              debugPrint(
                                'RPC update failed, falling back to direct profiles update: $rpcErr',
                              );
                            }

                            // Always guarantee the profiles table is updated with authoritative current values
                            final updatePayload = <String, dynamic>{
                              'first_name': fname,
                              'last_name': lname,
                              'mi': mi.isEmpty ? null : mi,
                              'suffix': selectedSuffix,
                              'full_name': composedName,
                              'phone': phone.isEmpty ? null : phone,
                              'vehicle_type': vehicle.isEmpty ? null : vehicle,
                              'license_number': license.isEmpty ? null : license,
                              'updated_at': DateTime.now().toIso8601String(),
                            };

                            await supabase
                                .from('profiles')
                                .update(updatePayload)
                                .eq('id', riderId);

                            if (!rpcSucceeded && newPass.isNotEmpty) {
                              throw 'Profile details updated, but password update requires database migration or admin rights.';
                            }

                            // Immediately update local disk cache so offline & instant loads show current information
                            final ownerId = SafeSupabase.currentUserId;
                            if (ownerId != null) {
                              final cached = await LocalDataCache.instance
                                  .get<List<dynamic>>('owner_riders_$ownerId');
                              if (cached != null) {
                                final updatedList = cached.map((r) {
                                  if (r is Map && r['id']?.toString() == riderId) {
                                    return {
                                      ...r,
                                      ...updatePayload,
                                      'full_name': composedName,
                                    };
                                  }
                                  return r;
                                }).toList();
                                await LocalDataCache.instance.set(
                                  'owner_riders_$ownerId',
                                  updatedList,
                                );
                              }
                            }

                            if (sheetContext.mounted &&
                                Navigator.of(sheetContext).canPop()) {
                              Navigator.of(sheetContext).pop(true);
                            }
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Rider credentials updated successfully.',
                                  ),
                                  backgroundColor: AppUi.successFg,
                                ),
                              );
                              onUpdated?.call();
                            }
                          } catch (e) {
                            setSheetState(() => isSaving = false);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    FriendlyErrors.message(
                                      e,
                                      fallback:
                                          'Could not update rider credentials. Please try again.',
                                    ),
                                  ),
                                  backgroundColor: AppUi.error,
                                ),
                              );
                            }
                          }
                        },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showAddRiderDialog() {
    final firstNameController = TextEditingController();
    final lastNameController = TextEditingController();
    final miController = TextEditingController();
    String? selectedSuffix;

    final userController = TextEditingController();
    final emailController = TextEditingController();
    final passController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => Container(
          padding: EdgeInsets.fromLTRB(
            20,
            12,
            20,
            MediaQuery.of(sheetContext).viewInsets.bottom + 40,
          ),
          decoration: BoxDecoration(
            color: AppUi.surfaceOf(context),
            borderRadius: AppUi.radiusSheetTop,
          ),
          child: SingleChildScrollView(
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
                const SizedBox(height: 24),
                Text(
                  "Register New Rider",
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppUi.textPrimaryOf(context),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  "Create a rider account for water refill deliveries",
                  style: TextStyle(
                    color: AppUi.textSecondaryOf(context),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),

                const AppFormSectionHeader(
                  title: 'Rider Personal Info',
                  topPadding: 8,
                ),
                Row(
                  children: [
                    Expanded(
                      child: AppFormField(
                        controller: firstNameController,
                        label: "First Name",
                        icon: Icons.person_outline_rounded,
                        textCapitalization: TextCapitalization.words,
                        compact: true,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: AppFormField(
                        controller: lastNameController,
                        label: "Last Name",
                        icon: Icons.person_outline_rounded,
                        textCapitalization: TextCapitalization.words,
                        compact: true,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: AppFormField(
                        controller: miController,
                        label: "M.I.",
                        icon: Icons.text_fields_rounded,
                        textCapitalization: TextCapitalization.characters,
                        compact: true,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 3,
                      child: AppDropdownField<String>.fromStrings(
                        label: 'Suffix',
                        value: selectedSuffix,
                        icon: Icons.star_border_rounded,
                        compact: true,
                        items: const [
                          'None',
                          'Jr.',
                          'Sr.',
                          'II',
                          'III',
                          'IV',
                          'V',
                        ],
                        onChanged: (v) => setSheetState(
                          () => selectedSuffix = v == 'None' ? null : v,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                const AppFormSectionHeader(
                  title: 'Account Credentials',
                  topPadding: 4,
                ),
                AppFormField(
                  controller: userController,
                  label: "Username",
                  icon: Icons.alternate_email_rounded,
                  compact: true,
                ),
                const SizedBox(height: 12),
                AppFormField(
                  controller: emailController,
                  label: "Email Address",
                  icon: Icons.mail_outline_rounded,
                  keyboardType: TextInputType.emailAddress,
                  compact: true,
                ),
                const SizedBox(height: 12),
                AppFormField(
                  controller: passController,
                  label: "Login Password",
                  icon: Icons.lock_outline_rounded,
                  isPassword: true,
                  compact: true,
                ),
                const SizedBox(height: 24),

                AppFormSubmitButton(
                  label: "Register Rider",
                  icon: Icons.person_add_alt_1_rounded,
                  onPressed: () => _handleRiderRegistration(
                    firstNameController.text,
                    lastNameController.text,
                    miController.text,
                    selectedSuffix ?? '',
                    userController.text,
                    emailController.text,
                    passController.text,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _handleRiderRegistration(
    String fname,
    String lname,
    String mi,
    String suffix,
    String user,
    String email,
    String pass,
  ) async {
    try {
      if (fname.trim().isEmpty ||
          lname.trim().isEmpty ||
          user.trim().isEmpty ||
          email.trim().isEmpty ||
          pass.trim().isEmpty) {
        throw 'Basic details are required';
      }
      if (pass.trim().length < 6) {
        throw 'Password must be at least 6 characters';
      }

      final ownerUser = supabase.auth.currentUser;
      if (ownerUser == null) {
        throw 'You must be logged in as a station owner to register a rider.';
      }

      final composedName = "$fname $mi $lname $suffix"
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();

      final rpcResult = await supabase.rpc(
        'create_rider_account',
        params: {
          'p_email': email.trim(),
          'p_password': pass.trim(),
          'p_username': user.trim(),
          'p_full_name': composedName,
          'p_owner_id': ownerUser.id,
        },
      );

      if (rpcResult != null) {
        final resStr = rpcResult.toString().trim();
        if (resStr == 'error: email_already_exists' ||
            resStr.contains('email_already_exists')) {
          throw 'An account with this email already exists. Please use a different email.';
        } else if (resStr == 'error: username_already_exists' ||
            resStr.contains('username_already_exists')) {
          throw 'This username is already taken. Please choose a different username.';
        } else if (resStr.startsWith('error:')) {
          throw resStr.replaceFirst('error:', '').trim();
        }
      }

      // Explicitly populate profile columns so newly registered rider shows complete info
      try {
        await supabase.from('profiles').update({
          'first_name': fname.trim(),
          'last_name': lname.trim(),
          'mi': mi.trim().isEmpty ? null : mi.trim(),
          'suffix': suffix.trim().isEmpty ? null : suffix.trim(),
          'full_name': composedName,
        }).eq('username', user.trim());
      } catch (err) {
        debugPrint('Non-critical: could not backfill name fields on creation: $err');
      }

      await _fetchRidersDirect();

      if (!mounted) return;
      Navigator.pop(context);
      _showSuccessDialog(composedName, email.trim(), pass.trim());
    } catch (e) {
      if (!mounted) return;
      final msg = FriendlyErrors.message(
        e,
        fallback: 'Could not create rider account. Please try again.',
      );
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: AppColors.uiError));
    }
  }

  void _showSuccessDialog(String name, String email, String pass) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppUi.surfaceOf(context),
        shape: RoundedRectangleBorder(borderRadius: AppUi.dialogRadius),
        title: Row(
          children: [
            const Icon(
              Icons.check_circle_rounded,
              color: AppColors.uiSuccess,
              size: 28,
            ),
            const SizedBox(width: 12),
            Text(
              'Rider Registered!',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: AppUi.textPrimaryOf(context),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Account for $name is ready.',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: AppUi.textSecondaryOf(context),
              ),
            ),
            const SizedBox(height: 20),
            _credsRow('Email', email),
            _credsRow('Password', pass),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7ED),
                borderRadius: BorderRadius.circular(AppUi.radiusCard),
                border: Border.all(color: const Color(0xFFFFEDD5)),
              ),
              child: const Text(
                'Share these credentials with the rider securely. They will need them to log in.',
                style: TextStyle(
                  color: Color(0xFF9A3412),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _setupRidersListener();
            },
            child: Text(
              'Got it',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: AppUi.brandOf(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _credsRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text(
            '$label: ',
            style: TextStyle(
              color: AppUi.textSecondaryOf(context),
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: AppUi.textPrimaryOf(context),
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}
