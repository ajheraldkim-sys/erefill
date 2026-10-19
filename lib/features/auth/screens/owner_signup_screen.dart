import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:erefill/core/constants.dart';
import 'package:erefill/core/widgets/brand/hero_header.dart';
import 'package:erefill/core/widgets/checkout_step_indicator.dart';
import 'package:erefill/core/widgets/brand/axo_states.dart';
import 'package:erefill/core/utils/friendly_errors.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:erefill/core/routing/app_navigation.dart';
import 'package:erefill/core/widgets/map_tiles.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:erefill/core/providers/user_provider.dart';

import 'package:erefill/core/theme/app_colors.dart';
class OwnerSignupScreen extends StatefulWidget {
  const OwnerSignupScreen({super.key});

  @override
  State<OwnerSignupScreen> createState() => _OwnerSignupScreenState();
}

class _OwnerSignupScreenState extends State<OwnerSignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _pageController = PageController();
  final _mapController = MapController();
  int _currentStep = 0;

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _usernameController = TextEditingController();
  final _stationNameController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _miController = TextEditingController();
  final _suffixController = TextEditingController();
  final _addressController = TextEditingController();
  final _phoneController = TextEditingController();

  String _selectedTown = 'Cantilan';
  String? _selectedBarangay;
  String _selectedWaterType = 'Purified Water';
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _selectedSuffix;

  LatLng _pickedLocation = const LatLng(9.3333, 125.9833);

  final Map<String, List<String>> _municipalityData =
      AppConstants.municipalityData;

  void _nextStep() {
    if (_currentStep < 2) {
      if (_formKey.currentState!.validate()) {
        _pageController.nextPage(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
        setState(() => _currentStep++);
      }
    } else {
      _handleSignup();
    }
  }

  void _prevStep() {
    if (_currentStep > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      setState(() => _currentStep--);
    }
  }

  void _handleBack() {
    if (_currentStep > 0) {
      _prevStep();
    } else {
      if (context.canPop()) {
        context.pop();
      } else {
        context.openSignup();
      }
    }
  }

  final List<Map<String, String>> _waterOptions = const [
    {
      'name': 'Purified Water',
      'desc':
          'The most common type, treated to remove nearly all contaminants.',
    },
    {
      'name': 'Mineral Water',
      'desc': 'Often treated to contain specific levels of minerals.',
    },
    {'name': 'Alkaline Water', 'desc': 'Water with a higher pH level.'},
  ];

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.uiError : null,
      ),
    );
  }

  void _showAlreadyRegisteredDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: AppUi.cardRadius),
        backgroundColor: AppUi.surfaceOf(ctx),
        title: Text(
          'Account Already Exists',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: AppUi.textPrimaryOf(ctx),
          ),
        ),
        content: Text(
          'An account with ${_emailController.text.trim()} is already registered. Would you like to sign in instead?',
          style: TextStyle(color: AppUi.textSecondaryOf(ctx)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.openLogin();
            },
            style: FilledButton.styleFrom(backgroundColor: AppUi.bluePrimary),
            child: const Text('Sign In'),
          ),
        ],
      ),
    );
  }

  Future<void> _handleSignup() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      await Supabase.instance.client.auth.signUp(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
        data: {
          'role': 'owner',
          'username': _usernameController.text.trim(),
          'phone': _phoneController.text.trim(),
          'first_name': _firstNameController.text.trim(),
          'last_name': _lastNameController.text.trim(),
          'mi': _miController.text.trim(),
          'suffix': _selectedSuffix ?? '',
          'full_name':
              "${_firstNameController.text.trim()} ${_miController.text.trim()} ${_lastNameController.text.trim()} ${_selectedSuffix ?? ''}"
                  .replaceAll(RegExp(r'\s+'), ' '),
          'station_name': _stationNameController.text.trim(),
          'town': _selectedTown,
          'barangay': _selectedBarangay,
          'complete_address': _addressController.text.trim(),
          'primary_water_type': _selectedWaterType,
          'latitude': _pickedLocation.latitude,
          'longitude': _pickedLocation.longitude,
        },
      );
      if (!mounted) return;
      _showMessage("Station account created. Welcome to eRefill.");
      if (mounted) {
        await context.read<UserProvider>().refreshProfile();
      }
      if (!mounted) return;
      context.goHome();
    } catch (e) {
      if (!mounted) return;
      final rawError = e.toString().toLowerCase();
      if (rawError.contains('already registered') ||
          rawError.contains('user_already_exists') ||
          rawError.contains('already exists')) {
        _showAlreadyRegisteredDialog();
        return;
      }
      _showMessage(
        FriendlyErrors.message(
          e,
          fallback: 'Could not create your station account. Please try again.',
        ),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _usernameController.dispose();
    _stationNameController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _miController.dispose();
    _suffixController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _pageController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _locateMe() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Locating you...'),
        duration: Duration(seconds: 1),
      ),
    );

    final position = await Geolocator.getCurrentPosition();
    if (!mounted) return;
    final newLoc = LatLng(position.latitude, position.longitude);

    setState(() => _pickedLocation = newLoc);
    _mapController.move(newLoc, 16);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _currentStep == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_currentStep > 0) {
          _prevStep();
        }
      },
      child: Scaffold(
        backgroundColor: AppUi.pageBgOf(context),
        body: _isLoading
            ? const AxoLoader(message: 'Registering your station...')
            : Column(
                children: [
                  TabScreenHeroHeader(
                    leading: IconButton(
                      onPressed: _handleBack,
                      icon: Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: AppUi.textPrimaryOf(context),
                        size: 20,
                      ),
                      tooltip: _currentStep == 0 ? 'Back' : 'Previous step',
                    ),
                    title: 'Register water station',
                    subtitle: 'Step ${_currentStep + 1} of 3',
                    bottom: CheckoutStepIndicator(
                      activeStep: _currentStep,
                      steps: const ['Station', 'Location', 'Security'],
                    ),
                  ),
                  Expanded(
                    child: PageView(
                      controller: _pageController,
                      physics: const NeverScrollableScrollPhysics(),
                      children: [
                        _buildBioStep(),
                        _buildBusinessStep(),
                        _buildSecurityStep(),
                      ],
                    ),
                  ),
                  _buildActionButtons(),
                ],
              ),
      ),
    );
  }

  Widget _buildBioStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _currentStep == 0 ? _formKey : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionHeader('Owner Information'),
            const SizedBox(height: 16),
            _buildSignupField(
              controller: _firstNameController,
              label: 'First Name',
              icon: Icons.person_outline_rounded,
              textCapitalization: TextCapitalization.words,
              validator: (val) => AppValidators.name(val, 'First name'),
            ),
            const SizedBox(height: 12),
            _buildSignupField(
              controller: _lastNameController,
              label: 'Last Name',
              icon: Icons.person_outline_rounded,
              textCapitalization: TextCapitalization.words,
              validator: (val) => AppValidators.name(val, 'Last name'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: _buildSignupField(
                    controller: _miController,
                    label: 'M.I.',
                    icon: Icons.text_fields_rounded,
                    textCapitalization: TextCapitalization.characters,
                    validator: AppValidators.optionalInitial,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 3,
                  child: _buildDropdownField(
                    label: 'Suffix',
                    initialValue: _selectedSuffix,
                    items: ['None', 'Jr.', 'Sr.', 'II', 'III', 'IV', 'V'],
                    icon: Icons.star_border_rounded,
                    onChanged: (val) => setState(
                      () => _selectedSuffix = val == 'None' ? null : val,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildSignupField(
              controller: _phoneController,
              label: 'Phone Number',
              icon: Icons.phone_android_rounded,
              keyboardType: TextInputType.phone,
              validator: AppValidators.phone,
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildBusinessStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _currentStep == 1 ? _formKey : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionHeader('Business Identity'),
            const SizedBox(height: 16),
            _buildSignupField(
              controller: _stationNameController,
              label: 'Water Station Name',
              icon: Icons.store_rounded,
              textCapitalization: TextCapitalization.words,
              validator: (val) =>
                  AppValidators.requiredText(val, 'Water station name'),
            ),
            const SizedBox(height: 32),
            _sectionHeader('Location Details'),
            const SizedBox(height: 16),
            _buildDropdownField(
              label: 'Municipality',
              initialValue: _selectedTown,
              items: _municipalityData.keys.toList(),
              icon: Icons.location_city_rounded,
              onChanged: (val) {
                setState(() {
                  _selectedTown = val!;
                  _selectedBarangay = null;
                });
              },
            ),
            const SizedBox(height: 12),
            _buildDropdownField(
              label: 'Barangay',
              initialValue: _selectedBarangay,
              items: _municipalityData[_selectedTown]!,
              icon: Icons.map_outlined,
              validator: (val) =>
                  val == null ? "Please select your barangay." : null,
              onChanged: (val) => setState(() => _selectedBarangay = val),
            ),
            const SizedBox(height: 12),
            _buildSignupField(
              controller: _addressController,
              label: 'Detailed Address',
              icon: Icons.home_work_outlined,
              textCapitalization: TextCapitalization.words,
              validator: (val) =>
                  AppValidators.requiredText(val, 'Detailed address'),
            ),
            const SizedBox(height: 32),
            _sectionHeader('Precise Station Coordinates'),
            const SizedBox(height: 16),
            Container(
              height: 180,
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
                        initialZoom: 13,
                        onPositionChanged: (camera, hasGesture) {
                          if (hasGesture) {
                            setState(() => _pickedLocation = camera.center);
                          }
                        },
                      ),
                      children: [AppMapTiles.layer(context: context)],
                    ),
                  ),
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 35),
                      child: Icon(
                        Icons.location_on_rounded,
                        color: AppUi.brandOf(context),
                        size: 42,
                        shadows: const [
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
                      backgroundColor: AppUi.surfaceOf(context),
                      foregroundColor: AppUi.brandOf(context),
                      child: const Icon(Icons.my_location_rounded),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                "Slide map to point the exact station location",
                style: TextStyle(
                  fontSize: 11,
                  color: AppUi.textSecondaryOf(context),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 32),
            _sectionHeader('Operation Details'),
            const SizedBox(height: 16),
            _buildDropdownField(
              label: 'Primary Water Type',
              initialValue: _selectedWaterType,
              items: _waterOptions.map((e) => e['name']!).toList(),
              icon: Icons.water_drop_outlined,
              onChanged: (val) => setState(() => _selectedWaterType = val!),
            ),
            const SizedBox(height: 8),
            Text(
              _waterOptions.firstWhere(
                (opt) => opt['name'] == _selectedWaterType,
              )['desc']!,
              style: TextStyle(
                color: AppUi.textSecondaryOf(context),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildSecurityStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _currentStep == 2 ? _formKey : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionHeader('Account Security'),
            const SizedBox(height: 16),
            _buildSignupField(
              controller: _usernameController,
              label: 'Pick a unique Business Username',
              icon: Icons.alternate_email_rounded,
              validator: AppValidators.username,
            ),
            const SizedBox(height: 12),
            _buildSignupField(
              controller: _emailController,
              label: 'Business Email',
              icon: Icons.email_outlined,
              keyboardType: TextInputType.emailAddress,
              validator: AppValidators.email,
            ),
            const SizedBox(height: 12),
            _buildSignupField(
              controller: _passwordController,
              label: 'Access Password',
              icon: Icons.lock_outline_rounded,
              isPassword: true,
              obscure: _obscurePassword,
              onToggleObscure: () =>
                  setState(() => _obscurePassword = !_obscurePassword),
              validator: AppValidators.password,
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: AppUi.surfaceOf(context),
        border: Border(
          top: BorderSide(color: AppUi.borderOf(context)),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            offset: const Offset(0, -4),
            blurRadius: 10,
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                if (_currentStep > 0) ...[
                  Expanded(
                    flex: 1,
                    child: SizedBox(
                      height: 56,
                      child: OutlinedButton.icon(
                        onPressed: _prevStep,
                        icon: const Icon(Icons.arrow_back_rounded, size: 18),
                        label: const Text(
                          'Back',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppUi.textPrimaryOf(context),
                          side: BorderSide(color: AppUi.borderOf(context)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppUi.radiusControl),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  flex: _currentStep > 0 ? 2 : 1,
                  child: SizedBox(
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _nextStep,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppUi.bluePrimary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppUi.radiusControl),
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        _currentStep == 2
                            ? "Launch My Station"
                            : "Continue to Next Step",
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
            if (_currentStep == 0) ...[
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    "Already have an account? ",
                    style: TextStyle(
                      fontSize: 13,
                      color: AppUi.textSecondaryOf(context),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      if (context.canPop()) {
                        context.pop();
                      } else {
                        context.openLogin();
                      }
                    },
                    child: Text(
                      "Sign In",
                      style: TextStyle(
                        fontSize: 13,
                        color: AppUi.brandOf(context),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: AppUi.textSecondaryOf(context),
        letterSpacing: 0,
      ),
    );
  }

  Widget _buildSignupField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool isPassword = false,
    bool obscure = false,
    VoidCallback? onToggleObscure,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    TextCapitalization textCapitalization = TextCapitalization.none,
  }) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final text = value.text;
        final isValid = text.isNotEmpty && validator != null && validator(text) == null;

        Widget? suffix;
        if (isPassword) {
          suffix = IconButton(
            tooltip: obscure ? 'Show password' : 'Hide password',
            onPressed: onToggleObscure,
            icon: Icon(
              obscure
                  ? Icons.visibility_off_rounded
                  : Icons.visibility_rounded,
              size: 20,
              color: AppUi.textSecondaryOf(context),
            ),
          );
        } else if (isValid) {
          suffix = const Padding(
            padding: EdgeInsets.only(right: 14),
            child: Icon(
              Icons.check_circle_rounded,
              color: AppUi.accentGreen,
              size: 20,
            ),
          );
        }

        return TextFormField(
          controller: controller,
          obscureText: obscure,
          keyboardType: keyboardType,
          textCapitalization: textCapitalization,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 15,
            color: AppUi.textPrimaryOf(context),
          ),
          decoration: InputDecoration(
            labelText: label,
            floatingLabelBehavior: FloatingLabelBehavior.auto,
            floatingLabelStyle: TextStyle(
              color: AppUi.brandOf(context),
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
            labelStyle: TextStyle(
              color: AppUi.textSecondaryOf(context),
              fontSize: 14,
              fontWeight: FontWeight.w500,
              letterSpacing: 0,
            ),
            prefixIcon: Icon(
              icon,
              size: 20,
              color: AppUi.textSecondaryOf(context),
            ),
            suffixIcon: suffix,
            suffixIconConstraints: const BoxConstraints(
              minWidth: 44,
              minHeight: 44,
            ),
            filled: true,
            fillColor: AppUi.surfaceOf(context),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 18,
            ),
            border: OutlineInputBorder(
              borderRadius: AppUi.cardRadius,
              borderSide: BorderSide(color: AppUi.borderOf(context)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: AppUi.cardRadius,
              borderSide: BorderSide(
                color: isValid
                    ? AppUi.accentGreen.withValues(alpha: 0.5)
                    : AppUi.borderOf(context),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: AppUi.cardRadius,
              borderSide: BorderSide(
                color: Theme.of(context).brightness == Brightness.dark
                    ? AppUi.accentCyan
                    : AppUi.bluePrimary,
                width: 2,
              ),
            ),
          ),
          validator: validator,
        );
      },
    );
  }

  Widget _buildDropdownField({
    required String label,
    required String? initialValue,
    required List<String> items,
    required IconData icon,
    required void Function(String?) onChanged,
    String? Function(String?)? validator,
  }) {
    final effectiveValue =
        (initialValue != null && items.contains(initialValue))
            ? initialValue
            : null;
    return DropdownButtonFormField<String>(
      initialValue: effectiveValue,
      style: TextStyle(
        fontWeight: FontWeight.w700,
        fontSize: 15,
        color: AppUi.textPrimaryOf(context),
      ),
      items: items
          .map(
            (t) => DropdownMenuItem(
              value: t,
              child: Text(
                t,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: AppUi.textPrimaryOf(context),
                ),
              ),
            ),
          )
          .toList(),
      onChanged: onChanged,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(
          color: AppUi.textSecondaryOf(context),
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
        ),
        prefixIcon: Icon(
          icon,
          size: 20,
          color: AppUi.textSecondaryOf(context),
        ),
        filled: true,
        fillColor: AppUi.surfaceOf(context),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 20,
        ),
        border: OutlineInputBorder(
          borderRadius: AppUi.cardRadius,
          borderSide: BorderSide(color: AppUi.borderOf(context)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppUi.cardRadius,
          borderSide: BorderSide(color: AppUi.borderOf(context)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppUi.cardRadius,
          borderSide: BorderSide(
            color: Theme.of(context).brightness == Brightness.dark
                ? AppUi.accentCyan
                : AppUi.bluePrimary,
            width: 2,
          ),
        ),
      ),
    );
  }
}
