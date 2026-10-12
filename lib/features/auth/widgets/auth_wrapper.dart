import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:erefill/core/constants.dart';
import 'package:erefill/core/providers/user_provider.dart';
import 'package:erefill/features/auth/screens/auth_entry_screen.dart';
import 'package:erefill/features/dashboard/owner/owner_dashboard.dart';
import 'package:erefill/features/dashboard/customer/customer_home.dart';
import 'package:erefill/features/dashboard/rider/rider_dashboard.dart';
import 'package:erefill/features/dashboard/admin/admin_dashboard_screen.dart';
import 'package:erefill/features/auth/screens/onboarding_screen.dart';
import 'package:erefill/features/auth/widgets/location_permission_screen.dart';
import 'package:erefill/features/onboarding/screens/welcome_onboarding_screen.dart';

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  bool? _isFirstInstall;
  bool _splashComplete = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _returnToLogin() async {
    try {
      await Supabase.instance.client.auth.signOut(scope: SignOutScope.local);
    } catch (e) {
      debugPrint('Local sign-out failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not sign out right now. Please try again.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted) {
        setState(() {
          _isFirstInstall = !(prefs.getBool('onboarding_complete') ?? false);
          _splashComplete = true;
        });
      }
    } catch (e) {
      debugPrint('Error during auth wrapper initialization: $e');
      if (mounted) {
        setState(() {
          _isFirstInstall = false;
          _splashComplete = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // 1. Initial Loading Splash Screen (guaranteed minimum display time on launch/refresh)
    if (!_splashComplete || _isFirstInstall == null) {
      return const _SplashScreen();
    }

    // 2. Fresh Install Onboarding Flow
    if (_isFirstInstall!) {
      return WelcomeOnboardingScreen(
        onFinish: () {
          setState(() => _isFirstInstall = false);
        },
      );
    }

    // 3. Auth & Role Resolution
    final userProvider = context.watch<UserProvider>();

    if (userProvider.isLoading && userProvider.user == null) {
      return const _SplashScreen();
    }

    if (!userProvider.isAuthenticated) {
      return AuthEntryScreen(
        onBackToOnboarding: () async {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('onboarding_complete', false);
          if (mounted) {
            setState(() => _isFirstInstall = true);
          }
        },
      );
    }

    // 4. Location Guard (Required for authenticated users accessing station/delivery features)
    // Administrators do not require client GPS location tracking.
    final role = userProvider.user?.role;
    if (role == 'admin' || role == 'super_admin' || role == 'administrator') {
      return _buildAuthenticatedContent(context, userProvider);
    }

    return LocationPermissionScreen(
      key: const ValueKey('location_permission_guard'),
      child: _buildAuthenticatedContent(context, userProvider),
    );
  }

  Widget _buildAuthenticatedContent(BuildContext context, UserProvider userProvider) {
    final user = userProvider.user;
    if (user == null) {
      return Scaffold(
        backgroundColor: AppUi.pageBgOf(context),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: const BoxDecoration(
                      color: Color(0xFFFEF3C7),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.cloud_off_rounded,
                      color: Color(0xFFD97706),
                      size: 38,
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Unable to Load Profile',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'We could not connect to sync your profile. Please check your internet connection and tap Retry, or return to login.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 13,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 28),
                  Wrap(
                    spacing: 12,
                    runSpacing: 10,
                    alignment: WrapAlignment.center,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => userProvider.refreshProfile(),
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: const Text('Retry'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: _returnToLogin,
                        icon: const Icon(Icons.login_rounded, size: 18),
                        label: const Text('Return to Login'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppUi.bluePrimary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // --- ADMINISTRATIVE SUSPENSION GUARD ---
    if (user.isSuspended) {
      return Scaffold(
        backgroundColor: AppUi.pageBgOf(context),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: const BoxDecoration(
                      color: Color(0xFFFEE2E2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.lock_person_rounded,
                      color: Color(0xFFDC2626),
                      size: 44,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Account Suspended',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: AppUi.textPrimaryOf(context),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    user.suspendedReason?.isNotEmpty == true
                        ? user.suspendedReason!
                        : 'Your account has been temporarily suspended by administrative review.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: AppUi.textSecondaryOf(context),
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _returnToLogin,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppUi.bluePrimary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.logout_rounded, size: 20),
                      label: const Text(
                        'Sign Out',
                        style: TextStyle(fontWeight: FontWeight.w700),
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

    // --- SMART PROFILE ONBOARDING GUARD ---
    // Riders and Admins bypass customer location onboarding.
    final isAdmin = user.role == 'admin' || user.role == 'super_admin' || user.role == 'administrator';
    if (user.role != 'rider' && !isAdmin && (user.town == null || user.town!.isEmpty)) {
      return const OnboardingScreen();
    }

    if (user.role == 'owner') return OwnerDashboard(key: ValueKey('owner_${user.id}'));
    if (user.role == 'customer') return CustomerHome(key: ValueKey('customer_${user.id}'));
    if (user.role == 'rider') return RiderDashboard(key: ValueKey('rider_${user.id}'));
    if (isAdmin) return AdminDashboardScreen(key: ValueKey('admin_${user.id}'));

    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 16),
            const Text(
              'Unexpected role',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Role: ${user.role}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _returnToLogin,
              child: const Text('Return to Login'),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── In-App Splash Screen ───────────────────────────────────────────────────

class _SplashScreen extends StatefulWidget {
  const _SplashScreen();

  @override
  State<_SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<_SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..forward();

    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeIn);
    _scale = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFF0A0F1A),
        body: Stack(
          fit: StackFit.expand,
          children: [
            // Background image
            Image.asset(
              'assets/images/onboarding_bg.png',
              fit: BoxFit.cover,
              alignment: Alignment.center,
              errorBuilder: (context, error, stackTrace) =>
                  const SizedBox.shrink(),
            ),
            // Gradient overlay — darker than onboarding for a more dramatic splash
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    const Color(0xFF0A0F1A).withValues(alpha: 0.75),
                    const Color(0xFF0A0F1A).withValues(alpha: 0.55),
                    const Color(0xFF0A0F1A).withValues(alpha: 0.85),
                  ],
                  stops: const [0.0, 0.5, 1.0],
                ),
              ),
            ),
            // Centered branding with Glassmorphism
            Center(
              child: FadeTransition(
                opacity: _fade,
                child: ScaleTransition(
                  scale: _scale,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 40,
                          vertical: 32,
                        ),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Colors.white.withValues(alpha: 0.16),
                              const Color(0xFF0A0F1A).withValues(alpha: 0.55),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.22),
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF38BDF8).withValues(alpha: 0.12),
                              blurRadius: 32,
                              spreadRadius: 2,
                            ),
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.4),
                              blurRadius: 24,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Wordmark
                            const Text(
                              'eRefill',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 42,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -1.5,
                              ),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Smart Water Delivery',
                              style: TextStyle(
                                color: Color(0xFFCBD5E1),
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 28),
                            // Loading indicator
                            const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Color(0xFF38BDF8),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
