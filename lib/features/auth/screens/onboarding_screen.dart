import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import '../../../core/constants.dart';
import '../../../core/providers/user_provider.dart';
import '../../../core/widgets/app_header.dart';
import '../../../core/routing/app_navigation.dart';
import '../../../core/widgets/map_tiles.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/app_form_fields.dart';
import '../../../core/utils/profile_query_helpers.dart';

import 'package:erefill/core/theme/app_colors.dart';
import 'package:erefill/core/utils/friendly_errors.dart';
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pageController = PageController();
  final _mapController = MapController();
  int _currentStep = 0;
  bool _isLoading = false;

  // Data to collect
  String? _selectedRole;
  String? _selectedTown;
  String? _selectedBarangay;
  LatLng _pickedLocation = const LatLng(9.3333, 125.9833);
  final _stationNameController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _miController = TextEditingController();
  final _suffixController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _landmarkController = TextEditingController();

  final Map<String, List<String>> _municipalityData =
      AppConstants.municipalityData;

  @override
  void initState() {
    super.initState();
    _prefillFromProfile();
  }

  void _prefillFromProfile() {
    final user = context.read<UserProvider>().user;
    if (user != null) {
      _selectedRole = user.role;
      _firstNameController.text =
          user.firstName ?? user.fullName?.split(' ').first ?? '';
      _lastNameController.text =
          user.lastName ??
          ((user.fullName?.split(' ').length ?? 0) > 1
              ? user.fullName?.split(' ').last
              : '') ??
          '';
      _miController.text = user.mi ?? '';
      _suffixController.text = user.suffix ?? '';
      _phoneController.text = user.phone ?? '';
      _addressController.text = user.completeAddress ?? '';
      _landmarkController.text = user.landmark ?? '';
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _mapController.dispose();
    _stationNameController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _miController.dispose();
    _suffixController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _landmarkController.dispose();
    super.dispose();
  }

  void _nextStep() {
    if (_currentStep == 0 && _selectedRole == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select your role.')),
      );
      return;
    }
    if (_currentStep == 1 &&
        (_selectedTown == null || _selectedBarangay == null)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select your municipality and barangay.'),
        ),
      );
      return;
    }
    if (_currentStep < 2) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOutCubic,
      );
      setState(() => _currentStep++);
    } else {
      _completeOnboarding();
    }
  }

  Future<void> _completeOnboarding() async {
    if (_selectedRole == null ||
        _selectedTown == null ||
        _selectedBarangay == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please complete municipality and barangay.'),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      final Map<String, dynamic> updates = {
        'role': _selectedRole,
        'first_name': _firstNameController.text.trim(),
        'last_name': _lastNameController.text.trim(),
        'mi': _miController.text.trim(),
        'suffix': _suffixController.text.trim(),
        'full_name':
            "${_firstNameController.text.trim()} ${_miController.text.trim()} ${_lastNameController.text.trim()} ${_suffixController.text.trim()}"
                .replaceAll(RegExp(r'\s+'), ' '),
        'town': _selectedTown,
        'barangay': _selectedBarangay,
        'complete_address': _addressController.text.trim(),
        'landmark': _landmarkController.text.trim(),
        'phone': _phoneController.text.trim(),
        'latitude': _pickedLocation.latitude,
        'longitude': _pickedLocation.longitude,
      };

      if (_selectedRole == 'owner') {
        updates['station_name'] = _stationNameController.text.trim();
      }

      await ProfileQueryHelpers.updateProfile(
        Supabase.instance.client,
        updates,
        userId: user.id,
      );

      // Refresh user provider
      if (!mounted) return;
      await context.read<UserProvider>().refreshProfile();

      if (!mounted) return;
      context.resetToAuth();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Update failed: ${FriendlyErrors.message(e)}'),
          backgroundColor: AppColors.uiError,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _locateMe() async {
    try {
      final position = await Geolocator.getCurrentPosition();
      if (!mounted) return;
      final newLoc = LatLng(position.latitude, position.longitude);
      setState(() => _pickedLocation = newLoc);
      _mapController.move(newLoc, 16);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not determine location')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppUi.surface,
      appBar: AppTopBar(
        title: 'Complete Profile',
        subtitle: 'Step ${_currentStep + 1} of 3',
        automaticallyImplyLeading: false,
      ),
      body: _isLoading
         ? const SkeletonList(itemCount: 5)
          : Column(
              children: [
                _buildProgress(),
                Expanded(
                  child: PageView(
                    controller: _pageController,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      _buildRoleStep(),
                      _buildLocationStep(),
                      _buildDetailsStep(),
                    ],
                  ),
                ),
                _buildFooter(),
              ],
            ),
    );
  }

  Widget _buildProgress() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      child: ClipRRect(
        borderRadius: AppUi.controlRadius,
        child: LinearProgressIndicator(
          value: (_currentStep + 1) / 3,
          backgroundColor: OnboardingPalette.bluePale,
          color: OnboardingPalette.bluePrimary,
          minHeight: 8,
        ),
      ),
    );
  }

  Widget _buildRoleStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Who are you?',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppUi.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Choose the role that best describes how you will use eRefill.',
            style: TextStyle(fontSize: 14, color: OnboardingPalette.textSecondary),
          ),
          const SizedBox(height: 32),
          _roleCard(
            'customer',
            'Customer',
            'Order water delivery to your home or office.',
            Icons.shopping_basket_rounded,
          ),
          const SizedBox(height: 16),
          _roleCard(
            'owner',
            'Station Owner',
            'Manage your water station and fulfill orders.',
            Icons.store_rounded,
          ),
        ],
      ),
    );
  }

  Widget _roleCard(String role, String title, String desc, IconData icon) {
    bool isSelected = _selectedRole == role;
    return InkWell(
      onTap: () => setState(() => _selectedRole = role),
      borderRadius: AppUi.pillRadius,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isSelected
              ? OnboardingPalette.bluePrimary.withValues(alpha: 0.05)
              : Colors.white,
          borderRadius: AppUi.pillRadius,
          border: Border.all(
            color: isSelected ? OnboardingPalette.bluePrimary : AppUi.borderColor,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isSelected ? OnboardingPalette.bluePrimary : OnboardingPalette.bluePale,
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: isSelected ? Colors.white : OnboardingPalette.textSecondary,
                size: 28,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: OnboardingPalette.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    desc,
                    style: const TextStyle(
                      fontSize: 13,
                      color: OnboardingPalette.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              const Icon(
                Icons.check_circle_rounded,
                color: OnboardingPalette.bluePrimary,
                size: 24,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Where are you located?',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppUi.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Select your local area to connect with nearby services.',
            style: TextStyle(fontSize: 14, color: OnboardingPalette.textSecondary),
          ),
          const SizedBox(height: 32),
          _dropdownField(
            label: 'Municipality',
            value: _selectedTown,
            items: _municipalityData.keys.toList(),
            icon: Icons.location_city_rounded,
            onChanged: (val) {
              setState(() {
                _selectedTown = val;
                _selectedBarangay = null;
              });
            },
          ),
          const SizedBox(height: 16),
          _dropdownField(
            label: 'Barangay',
            value: _selectedBarangay,
            items: _selectedTown != null
                ? _municipalityData[_selectedTown]!
                : [],
            icon: Icons.map_rounded,
            onChanged: (val) => setState(() => _selectedBarangay = val),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailsStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Precise Details',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppUi.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _selectedRole == 'owner'
                ? 'Tell us more about your water station.'
                : 'Complete your contact information.',
            style: const TextStyle(fontSize: 14, color: OnboardingPalette.textSecondary),
          ),
          const SizedBox(height: 32),
          if (_selectedRole == 'owner') ...[
            _textField(
              controller: _stationNameController,
              label: 'Station Name',
              icon: Icons.store_rounded,
              hint: 'e.g. Blue Spring Water',
            ),
            const SizedBox(height: 16),
          ],
          _textField(
            controller: _firstNameController,
            label: 'First Name',
            icon: Icons.person_outline,
            hint: 'Required',
          ),
          const SizedBox(height: 16),
          _textField(
            controller: _lastNameController,
            label: 'Last Name',
            icon: Icons.person_outline,
            hint: 'Required',
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                flex: 1,
                child: _textField(
                  controller: _miController,
                  label: 'M.I.',
                  icon: Icons.text_fields_rounded,
                  hint: 'Optional',
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 1,
                child: _textField(
                  controller: _suffixController,
                  label: 'Suffix',
                  icon: Icons.star_border_rounded,
                  hint: 'Optional',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _textField(
            controller: _phoneController,
            label: 'Phone Number',
            icon: Icons.phone_android_rounded,
            hint: '09XX XXX XXXX',
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 16),
          _textField(
            controller: _addressController,
            label: 'Street / Purok / House Number',
            icon: Icons.home_rounded,
            hint: 'Specific address',
          ),
          const SizedBox(height: 16),
          _textField(
            controller: _landmarkController,
            label: 'Nearby Landmark',
            icon: Icons.near_me_rounded,
            hint: 'e.g. Near St. Paul Hospital',
          ),
          const SizedBox(height: 32),
          const Text(
            'Pin Precise Location',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: OnboardingPalette.textMuted,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            height: 200,
            decoration: BoxDecoration(
              borderRadius: AppUi.pillRadius,
              border: Border.all(color: AppUi.borderColor),
            ),
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: AppUi.pillRadius,
                  child: FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: _pickedLocation,
                      initialZoom: 14,
                      onPositionChanged: (camera, hasGesture) {
                        if (hasGesture) {
                          setState(() => _pickedLocation = camera.center);
                        }
                      },
                    ),
                    children: [
                      AppMapTiles.layer(context: context),
                    ],
                  ),
                ),
                const Center(
                  child: Padding(
                    padding: EdgeInsets.only(bottom: 35),
                    child: Icon(
                      Icons.location_on_rounded,
                      color: OnboardingPalette.bluePrimary,
                      size: 44,
                      shadows: [
                        Shadow(
                          color: Colors.black54,
                          blurRadius: 8,
                          offset: Offset(0, 3),
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  right: 12,
                  bottom: 12,
                  child: FloatingActionButton.small(
                    onPressed: _locateMe,
                    backgroundColor: AppUi.surface,
                    foregroundColor: OnboardingPalette.bluePrimary,
                    child: const Icon(Icons.my_location_rounded),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _dropdownField({
    required String label,
    required String? value,
    required List<String> items,
    required IconData icon,
    required void Function(String?) onChanged,
  }) {
    final effectiveValue =
        (value != null && items.contains(value)) ? value : null;
    return DropdownButtonFormField<String>(
      initialValue: effectiveValue,
      items: items
          .map((t) => DropdownMenuItem(value: t, child: Text(t)))
          .toList(),
      onChanged: onChanged,
      decoration: _inputDecoration(label, icon),
      style: const TextStyle(
        fontWeight: FontWeight.w700,
        fontSize: 15,
        color: OnboardingPalette.textPrimary,
      ),
      icon: const Icon(Icons.keyboard_arrow_down_rounded),
    );
  }

  Widget _textField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? hint,
    TextInputType? keyboardType,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: _inputDecoration(label, icon).copyWith(hintText: hint),
      style: const TextStyle(
        fontWeight: FontWeight.w700,
        fontSize: 15,
        color: OnboardingPalette.textPrimary,
      ),
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return AppFormDecoration.inputDecoration(
      context,
      label: label,
      prefixIcon: icon,
    );
  }

  Widget _buildFooter() {
    bool canProceed = true;
    if (_currentStep == 0 && _selectedRole == null) {
      canProceed = false;
    }
    if (_currentStep == 1 &&
        (_selectedTown == null || _selectedBarangay == null)) {
      canProceed = false;
    }

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        children: [
          if (_currentStep > 0)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: OutlinedButton(
                onPressed: () {
                  _pageController.previousPage(
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeInOut,
                  );
                  setState(() => _currentStep--);
                },
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.all(18),
                  shape: RoundedRectangleBorder(borderRadius: AppUi.cardRadius),
                  side: const BorderSide(color: AppUi.borderColor),
                ),
                child: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  size: 18,
                  color: OnboardingPalette.textSecondary,
                ),
              ),
            ),
          Expanded(
            child: SizedBox(
              height: 58,
              child: ElevatedButton(
                onPressed: canProceed ? _nextStep : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: OnboardingPalette.bluePrimary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: AppUi.cardRadius),
                  elevation: 0,
                ),
                child: Text(
                  _currentStep == 2 ? 'Let\'s Get Started' : 'Next Step',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
