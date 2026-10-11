import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:erefill/core/constants.dart';
import 'package:erefill/core/widgets/app_form_fields.dart';
import 'package:erefill/widgets/app_widgets.dart';
import 'package:erefill/core/routing/app_navigation.dart';
import 'package:erefill/core/utils/safe_supabase.dart';
import 'package:erefill/core/utils/friendly_errors.dart';

class RiderManagementScreen extends StatefulWidget {
  const RiderManagementScreen({super.key});

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
    _fetchRidersDirect();
    _setupRidersListener();
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
                              onTap: () {
                                HapticFeedback.selectionClick();
                                context.openRiderPerformance(
                                  riderId: rider['id'].toString(),
                                  riderName:
                                      rider['full_name']?.toString() ??
                                          'Rider Profile',
                                );
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
                                      child: const Icon(
                                        Icons.two_wheeler_rounded,
                                        color: AppUi.bluePrimary,
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
                                              fontWeight: FontWeight.w800,
                                              fontSize: 16,
                                              color: AppUi.textPrimaryOf(context),
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
                                            color: const Color(
                                              0xFF10B981,
                                            ).withValues(alpha: 0.1),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: const Text(
                                            'Active',
                                            style: TextStyle(
                                              color: Color(0xFF10B981),
                                              fontSize: 10,
                                              fontWeight: FontWeight.w900,
                                              letterSpacing: 0.5,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        IconButton(
                                          visualDensity: VisualDensity.compact,
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(
                                            minWidth: 32,
                                            minHeight: 32,
                                          ),
                                          icon: const Icon(Icons.edit_outlined, size: 20),
                                          color: AppUi.bluePrimary,
                                          tooltip: 'Edit Credentials',
                                          onPressed: () {
                                            HapticFeedback.lightImpact();
                                            _showEditRiderDialog(rider);
                                          },
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
          style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.2),
        ),
        icon: const Icon(Icons.person_add_rounded, size: 20),
      ),
    );
  }

  void _showEditRiderDialog(Map<String, dynamic> rider) {
    final riderId = rider['id']?.toString() ?? '';
    final firstNameController = TextEditingController(
      text: rider['first_name']?.toString() ?? '',
    );
    final lastNameController = TextEditingController(
      text: rider['last_name']?.toString() ?? '',
    );
    final miController = TextEditingController(
      text: rider['mi']?.toString() ?? '',
    );
    String? selectedSuffix = rider['suffix']?.toString();
    final phoneController = TextEditingController(
      text: rider['phone']?.toString() ?? '',
    );
    final vehicleController = TextEditingController(
      text: rider['vehicle_type']?.toString() ?? '',
    );
    final licenseController = TextEditingController(
      text: rider['license_number']?.toString() ?? '',
    );
    final passwordController = TextEditingController();
    bool isSaving = false;

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
              crossAxisAlignment: CrossAxisAlignment.stretch,
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
                const SizedBox(height: 20),
                Text(
                  "Edit Rider Credentials",
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: AppUi.textPrimaryOf(context),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  "Update profile details or assign a new password for @${rider['username'] ?? 'rider'}",
                  style: TextStyle(
                    color: AppUi.textSecondaryOf(context),
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
                        items: const ['None', 'Jr.', 'Sr.', 'II', 'III', 'IV', 'V'],
                        compact: true,
                        onChanged: (v) {
                          setSheetState(() => selectedSuffix = (v == 'None' || v == null) ? null : v);
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
                  onPressed: isSaving ? () {} : () async {
                    final fname = firstNameController.text.trim();
                    final lname = lastNameController.text.trim();
                    final mi = miController.text.trim();
                    final phone = phoneController.text.trim();
                    final vehicle = vehicleController.text.trim();
                    final license = licenseController.text.trim();
                    final newPass = passwordController.text.trim();

                    if (fname.isEmpty || lname.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('First name and last name are required.')),
                      );
                      return;
                    }
                    if (newPass.isNotEmpty && newPass.length < 6) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Password must be at least 6 characters.')),
                      );
                      return;
                    }

                    setSheetState(() => isSaving = true);
                    try {
                      await supabase.rpc('owner_update_rider_credentials', params: {
                        'p_rider_id': riderId,
                        'p_first_name': fname,
                        'p_last_name': lname,
                        'p_mi': mi.isEmpty ? null : mi,
                        'p_suffix': selectedSuffix,
                        'p_phone': phone.isEmpty ? null : phone,
                        'p_vehicle_type': vehicle.isEmpty ? null : vehicle,
                        'p_license_number': license.isEmpty ? null : license,
                        'p_password': newPass.isEmpty ? null : newPass,
                      });

                      if (sheetContext.mounted && Navigator.of(sheetContext).canPop()) {
                        Navigator.of(sheetContext).pop();
                      }
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Rider credentials updated successfully.'),
                            backgroundColor: AppUi.successFg,
                          ),
                        );
                        _fetchRidersDirect();
                      }
                    } catch (e) {
                      setSheetState(() => isSaving = false);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Update failed: $e'),
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
                    fontWeight: FontWeight.w900,
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
                        items: const ['None', 'Jr.', 'Sr.', 'II', 'III', 'IV', 'V'],
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

      final rpcResult = await supabase.rpc('create_rider_account', params: {
        'p_email': email.trim(),
        'p_password': pass.trim(),
        'p_username': user.trim(),
        'p_full_name': composedName,
        'p_owner_id': ownerUser.id,
      });

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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: Colors.red,
        ),
      );
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
              color: Color(0xFF10B981),
              size: 28,
            ),
            const SizedBox(width: 12),
            Text(
              'Rider Registered!',
              style: TextStyle(
                fontWeight: FontWeight.w900,
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
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFFEDD5)),
              ),
              child: const Text(
                '⚠️ Share these credentials with the rider securely. They will need them to log in.',
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
            child: const Text(
              'Got it',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: AppUi.bluePrimary,
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
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}
