import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/account/saved_addresses_screen.dart';
import '../../features/auth/screens/customer_signup_screen.dart';
import '../../features/auth/screens/forgot_password_screen.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/owner_signup_screen.dart';
import '../../features/auth/screens/reset_password_screen.dart';
import '../../features/auth/screens/signup_role_screen.dart';
import '../../features/auth/widgets/auth_wrapper.dart';
import '../../features/onboarding/screens/welcome_onboarding_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../features/chat/chat_screen.dart';
import '../../features/chat/inbox_screen.dart';
import '../../features/chat/models/chat_room.dart';
import '../../features/dashboard/customer/checkout_screen.dart';
import '../../features/dashboard/customer/order_detail_screen.dart';
import '../../features/dashboard/customer/customer_orders_list.dart';
import '../../features/dashboard/customer/payment_return_screen.dart';
import '../../features/dashboard/customer/station_details.dart';
import '../../features/dashboard/customer/station_list_screen.dart';
import '../../features/dashboard/owner/notifications_screen.dart';
import '../../features/dashboard/owner/order_tracking_map.dart';
import '../../features/dashboard/owner/owner_inventory_screen.dart';
import '../../features/dashboard/owner/owner_menu_screen.dart';
import '../../features/dashboard/owner/rider_performance_screen.dart';
import '../../features/dashboard/owner/service_catalog_screen.dart';
import '../../features/dashboard/rider/rider_dashboard.dart';
import '../../features/dashboard/admin/admin_dashboard_screen.dart';
import '../../features/delivery_mgmt/screens/delivery_management_screen.dart';

import '../../features/settings/customer/customer_settings_screen.dart';
import '../../features/settings/payment_account_models.dart';
import '../../features/settings/payment_accounts_screen.dart';
import '../../features/settings/settings_hub_screen.dart';
import '../providers/user_provider.dart';
import '../widgets/brand/axo_states.dart';
import 'app_page_transitions.dart';
import 'app_routes.dart';

/// Application router configuration.
class AppRouter {
  AppRouter._();

  static GlobalKey<NavigatorState> rootNavigatorKey =
      GlobalKey<NavigatorState>();

  static GoRouter createRouter({GlobalKey<NavigatorState>? navigatorKey}) {
    final navKey = navigatorKey ?? GlobalKey<NavigatorState>();
    rootNavigatorKey = navKey;
    return GoRouter(
      navigatorKey: navKey,
      initialLocation: AppRoutes.home,
      redirect: (context, state) {
        try {
          final session = Supabase.instance.client.auth.currentSession;
          final isAuth = session != null;
          final path = state.uri.path;

          final isAuthRoute =
              path == AppRoutes.login ||
              path == AppRoutes.signup ||
              path == AppRoutes.customerSignup ||
              path == AppRoutes.ownerSignup ||
              path == AppRoutes.forgotPassword;

          if (isAuth && isAuthRoute) {
            return AppRoutes.home;
          }

          final isOwnerRoute =
              path == AppRoutes.ownerMenu ||
              path == AppRoutes.ownerServiceCatalog ||
              path == AppRoutes.ownerInventory ||
              path == AppRoutes.riderPerformance;

          if (isOwnerRoute) {
            if (!isAuth) return AppRoutes.login;
            final role = session.user.userMetadata?['role']
                ?.toString()
                .toLowerCase();
            if (role != null && role != 'owner' && role != 'admin') {
              return AppRoutes.home;
            }
          }
          if (state.uri.host == 'payment-callback' &&
              path != AppRoutes.paymentCallback) {
            final query = state.uri.hasQuery ? '?${state.uri.query}' : '';
            return '${AppRoutes.paymentCallback}$query';
          }
          if ((state.uri.host == 'reset-password' ||
                  state.uri.path.contains('reset-password')) &&
              path != AppRoutes.resetPassword) {
            return AppRoutes.resetPassword;
          }
          if (state.uri.host == 'login-callback') {
            return AppRoutes.home;
          }
        } catch (_) {
          // Fallback if Supabase instance is uninitialized in standalone tests
        }
        return null;
      },
      routes: [
        GoRoute(
          path: AppRoutes.home,
          builder: (context, state) => const AuthWrapper(),
        ),
        _pushed(
          AppRoutes.onboarding,
          (context, _) => WelcomeOnboardingScreen(
            onFinish: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool('onboarding_complete', true);
              if (context.mounted) {
                if (context.canPop()) {
                  context.pop();
                } else {
                  context.go(AppRoutes.home);
                }
              }
            },
          ),
        ),
        _pushed(AppRoutes.login, (_, _) => const LoginScreen()),
        _pushed(AppRoutes.signup, (_, _) => const SignupRoleScreen()),
        _pushed(
          AppRoutes.customerSignup,
          (_, _) => const CustomerSignupScreen(),
        ),
        _pushed(AppRoutes.ownerSignup, (_, _) => const OwnerSignupScreen()),
        _pushed(
          AppRoutes.forgotPassword,
          (_, _) => const ForgotPasswordScreen(),
        ),
        _pushed(
          AppRoutes.resetPassword,
          (_, _) => const ResetPasswordScreen(),
        ),
        _pushed(
          AppRoutes.paymentSuccess,
          (_, state) => PaymentReturnScreen(
            isSuccess: true,
            orderId: state.uri.queryParameters['order_id'],
          ),
        ),
        _pushed(
          AppRoutes.paymentCancel,
          (_, state) => PaymentReturnScreen(
            isSuccess: false,
            orderId: state.uri.queryParameters['order_id'],
          ),
        ),
        _pushed(
          AppRoutes.paymentCallback,
          (_, state) => PaymentReturnScreen(
            isSuccess:
                state.uri.queryParameters['status'] != 'cancel' &&
                state.uri.queryParameters['status'] != 'failed',
            orderId: state.uri.queryParameters['order_id'],
          ),
        ),

        _pushed(AppRoutes.stationList, (context, state) {
          final filter = state.extra as String?;
          return StationListScreen(initialFilter: filter);
        }),
        _pushed(AppRoutes.stationDetails, (context, state) {
          final station = state.extra as Map<String, dynamic>?;
          if (station == null) return _missingRoute('Station not found');
          return StationDetailsScreen(station: station);
        }),
        _pushed(AppRoutes.checkout, (context, state) {
          final station = state.extra as Map<String, dynamic>?;
          if (station == null) return _missingRoute('Checkout unavailable');
          return CheckoutScreen(station: station);
        }),
        _pushed(AppRoutes.orderTrack, (context, state) {
          final order = state.extra as Map<String, dynamic>?;
          if (order == null) return _missingRoute('Order not found');
          return OrderDetailScreen(order: order);
        }),
        _pushed(AppRoutes.orderList, (_, _) => const CustomerOrdersList()),
        _pushed('/orders/:orderId/map', (context, state) {
          final orderId = state.pathParameters['orderId'];
          if (orderId == null || orderId.isEmpty) {
            return _missingRoute('Order map unavailable');
          }
          return OrderTrackingMap(
            orderId: orderId,
            riderId: state.uri.queryParameters['riderId'],
          );
        }),
        _pushed('/orders/:orderId', (context, state) {
          final orderId = state.pathParameters['orderId'];
          if (orderId == null || orderId.isEmpty) {
            return _missingRoute('Order not found');
          }
          return OrderDetailScreen(orderId: orderId);
        }),
        _pushed(AppRoutes.chat, (context, state) {
          final roomId = state.uri.queryParameters['roomId'];
          final roomTitle = state.uri.queryParameters['title'];
          final roomTypeRaw = state.uri.queryParameters['type'];
          if (roomId == null || roomId.isEmpty) {
            return _missingRoute('Chat room not found');
          }
          return ChatScreen(
            roomId: roomId,
            roomTitle: roomTitle,
            roomType: roomTypeRaw != null
                ? ChatRoomType.fromString(roomTypeRaw)
                : ChatRoomType.customerSupport,
          );
        }),
        _pushed(AppRoutes.inbox, (_, _) => const InboxScreen()),
        _pushed(AppRoutes.notifications, (_, _) => const NotificationsScreen()),
        _pushed(AppRoutes.ownerMenu, (_, _) => const OwnerMenuScreen()),
        _pushed(
          AppRoutes.ownerServiceCatalog,
          (_, _) => const ServiceCatalogScreen(),
        ),
        _pushed(
          AppRoutes.ownerInventory,
          (_, _) => const OwnerInventoryScreen(),
        ),
        _pushed(
          AppRoutes.deliveryManagement,
          (_, _) => const DeliveryManagementScreen(),
        ),
        _pushed(AppRoutes.paymentAccounts, (context, state) {
          final role = context.read<UserProvider>().user?.role.toLowerCase();
          final scope = role == 'owner' || role == 'station_owner'
              ? PaymentAccountScope.ownerPayoutAccounts
              : PaymentAccountScope.customerPaymentMethods;
          return PaymentAccountsScreen(scope: scope);
        }),
        _pushed(AppRoutes.settingsHub, (context, state) {
          final role = state.uri.queryParameters['role'] ?? 'customer';
          return SettingsHubScreen(role: role);
        }),
        _pushed(
          AppRoutes.customerSettings,
          (_, _) => const CustomerSettingsScreen(),
        ),
        _pushed(AppRoutes.riderPerformance, (context, state) {
          final riderId = state.uri.queryParameters['riderId'];
          final riderName = state.uri.queryParameters['name'] ?? 'Rider';
          if (riderId == null || riderId.isEmpty) {
            return _missingRoute('Rider not found');
          }
          return RiderPerformanceScreen(riderId: riderId, riderName: riderName);
        }),
        _pushed(AppRoutes.savedAddresses, (context, state) {
          final extra = state.extra;
          if (extra is! Map<String, dynamic>) {
            return _missingRoute('Address context missing');
          }
          return SavedAddressesScreen(
            launch: SavedAddressLaunchContext.fromMap(extra),
          );
        }),
        _pushed(AppRoutes.riderHistory, (context, state) {
          final riderId = state.uri.queryParameters['riderId'];
          if (riderId == null || riderId.isEmpty) {
            return _missingRoute('Rider not found');
          }
          return RiderHistoryScreen(riderId: riderId);
        }),
        _pushed(
          AppRoutes.adminDashboard,
          (_, _) => const AdminDashboardScreen(),
        ),
      ],
    );
  }

  static GoRoute _pushed(
    String path,
    Widget Function(BuildContext, GoRouterState) build,
  ) {
    return GoRoute(
      path: path,
      pageBuilder: (context, state) =>
          fadeSlidePage(key: state.pageKey, child: build(context, state)),
    );
  }

  static Widget _missingRoute(String message) {
    return Scaffold(
      body: Center(
        child: AxoEmptyState(title: message, message: 'Go back and try again.'),
      ),
    );
  }
}
