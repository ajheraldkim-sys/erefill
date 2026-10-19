import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:erefill/core/constants.dart';

import 'package:erefill/core/theme/app_colors.dart';
class LocationPermissionScreen extends StatefulWidget {
  final Widget child;
  const LocationPermissionScreen({super.key, required this.child});

  @override
  State<LocationPermissionScreen> createState() =>
      _LocationPermissionScreenState();
}

class _LocationPermissionScreenState extends State<LocationPermissionScreen>
    with WidgetsBindingObserver {
  bool _isServiceEnabled = true;
  LocationPermission _permission = LocationPermission.whileInUse;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _performCheck(isInitial: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _performCheck();
    }
  }

  Future<void> _performCheck({bool isInitial = false}) async {
    // Only display full-screen loading on cold initial check.
    // Never unmount the running child hierarchy when resuming from camera or other apps!
    if (isInitial && mounted) {
      setState(() => _isLoading = true);
    }

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      var permission = await Geolocator.checkPermission();

      // If we haven't asked yet and it's initial, let's try to be proactive
      // but only if GPS is actually on.
      if (isInitial &&
          serviceEnabled &&
          permission == LocationPermission.denied) {
        // We don't request here to avoid unexpected popups,
        // but we ensure the UI is ready to ask.
      }

      if (mounted) {
        setState(() {
          _isServiceEnabled = serviceEnabled;
          _permission = permission;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _checkStatus() async => _performCheck();

  Future<void> _requestAccess() async {
    setState(() => _isLoading = true);

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        await Geolocator.openLocationSettings();
        setState(() => _isLoading = false);
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.unableToDetermine) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.deniedForever) {
        await Geolocator.openAppSettings();
      }

      await _performCheck();
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: AppUi.pageBgOf(context),
        body: Center(
          child: CircularProgressIndicator(
            color: AppUi.bluePrimary,
            strokeWidth: 2.5,
          ),
        ),
      );
    }

    bool hasPermission =
        _permission == LocationPermission.always ||
        _permission == LocationPermission.whileInUse;
    bool hasAccess = _isServiceEnabled && hasPermission;

    if (hasAccess) {
      return widget.child;
    }

    return Scaffold(
      backgroundColor: AppUi.pageBgOf(context),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppUi.chipBgOf(context),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  !_isServiceEnabled
                      ? Icons.location_off_rounded
                      : Icons.security_rounded,
                  color: OnboardingPalette.bluePrimary,
                  size: 64,
                ),
              ),
              const SizedBox(height: 32),
              Text(
                !_isServiceEnabled ? 'GPS is Off' : 'Permission Required',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: AppUi.textPrimaryOf(context),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                !_isServiceEnabled
                    ? 'Your device GPS is currently disabled. Please enable it to continue using eRefill.'
                    : 'eRefill needs your permission to access your location to find the nearest water stations and provide accurate delivery.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  color: AppUi.textSecondaryOf(context),
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 32),
              // Status Indicators
              _buildStatusIndicator('GPS Service', _isServiceEnabled),
              const SizedBox(height: 8),
              _buildStatusIndicator('App Permission', hasPermission),
              const SizedBox(height: 48),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _requestAccess,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: OnboardingPalette.bluePrimary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: AppUi.cardRadius,
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    !_isServiceEnabled
                        ? 'Open GPS Settings'
                        : 'Grant Permissions',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: _checkStatus,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text(
                  'Try Again',
                  style: TextStyle(
                    color: OnboardingPalette.bluePrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusIndicator(String label, bool isOk) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: isOk ? AppUi.successBg : AppUi.errorBg,
        borderRadius: BorderRadius.circular(AppUi.radiusCard),
        border: Border.all(
          color: isOk ? AppUi.successBg : AppUi.errorBg,
        ),
      ),
      child: Row(
        children: [
          Icon(
            isOk ? Icons.check_circle_rounded : Icons.cancel_rounded,
            color: isOk ? AppColors.uiSuccess : AppColors.uiError,
            size: 18,
          ),
          const SizedBox(width: 12),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: isOk ? AppUi.successFg : AppUi.errorFg,
            ),
          ),
          const Spacer(),
          Text(
            isOk ? 'Enabled' : 'Required',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
              color: isOk ? AppColors.uiSuccess : AppColors.uiError,
            ),
          ),
        ],
      ),
    );
  }
}
