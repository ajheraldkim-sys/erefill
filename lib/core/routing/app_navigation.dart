import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/chat/models/chat_room.dart';
import '../../features/account/saved_addresses_screen.dart';
import '../../features/settings/payment_account_models.dart';
import 'app_routes.dart';

/// Typed navigation helpers for go_router.
extension AppNavigation on BuildContext {
  void openStationList({String? initialFilter}) =>
      push(AppRoutes.stationList, extra: initialFilter);

  void openStationDetails(Map<String, dynamic> station) {
    push(AppRoutes.stationDetails, extra: station);
  }

  void openCart([Map<String, dynamic>? station]) {
    push(AppRoutes.cart, extra: station);
  }

  void openCheckout(Map<String, dynamic> station) {
    push(AppRoutes.checkout, extra: station);
  }

  void openOrderTracker(Map<String, dynamic> order) {
    push(AppRoutes.orderTrack, extra: order);
  }

  void openOrderList() => push(AppRoutes.orderList);

  void replaceOrderTracker(Map<String, dynamic> order) {
    pushReplacement(AppRoutes.orderTrack, extra: order);
  }

  void openOrderById(String orderId) => push(AppRoutes.orderById(orderId));

  void replaceOrderById(String orderId) {
    pushReplacement(AppRoutes.orderById(orderId));
  }

  void openOrderTrackingMap({required String orderId, String? riderId}) {
    push(
      Uri(
        path: AppRoutes.orderMap(orderId),
        queryParameters: {
          if (riderId != null && riderId.isNotEmpty) 'riderId': riderId,
        },
      ).toString(),
    );
  }

  void openChat({
    required String roomId,
    required String roomTitle,
    required ChatRoomType roomType,
  }) {
    push(
      Uri(
        path: AppRoutes.chat,
        queryParameters: {
          'roomId': roomId,
          'title': roomTitle,
          'type': roomType.value,
        },
      ).toString(),
    );
  }

  void openInbox() => push(AppRoutes.inbox);

  void openCustomerSignup() => push(AppRoutes.customerSignup);

  void openOwnerSignup() => push(AppRoutes.ownerSignup);

  void openForgotPassword() => push(AppRoutes.forgotPassword);

  void openSignup() => push(AppRoutes.signup);

  void openNotifications() => push(AppRoutes.notifications);

  void openLogin() => push(AppRoutes.login);

  void openOnboarding() => push(AppRoutes.onboarding);

  

  void openOwnerMenu() => push(AppRoutes.ownerMenu);

  void openOwnerServiceCatalog() => push(AppRoutes.ownerServiceCatalog);

  void openOwnerInventory() => push(AppRoutes.ownerInventory);

  void openPaymentAccounts(PaymentAccountScope scope) {
    push(
      Uri(
        path: AppRoutes.paymentAccounts,
        queryParameters: {'scope': scope.name},
      ).toString(),
    );
  }

  void openSettingsHub({String? role}) {
    push(
      Uri(
        path: AppRoutes.settingsHub,
        queryParameters: {if (role != null && role.isNotEmpty) 'role': role},
      ).toString(),
    );
  }

  void openCustomerSettings() => push(AppRoutes.customerSettings);

  Future<T?> openRiderPerformance<T>({
    required String riderId,
    required String riderName,
  }) {
    return push<T>(
      Uri(
        path: AppRoutes.riderPerformance,
        queryParameters: {'riderId': riderId, 'name': riderName},
      ).toString(),
    );
  }

  Future<T?> openSavedAddresses<T>(SavedAddressLaunchContext launch) {
    return push<T>(AppRoutes.savedAddresses, extra: launch.toMap());
  }

  void openRiderHistory({required String riderId}) {
    push(
      Uri(
        path: AppRoutes.riderHistory,
        queryParameters: {'riderId': riderId},
      ).toString(),
    );
  }

  void popRoute() {
    if (canPop()) {
      pop();
    } else {
      goHome();
    }
  }

  void goHome() => go(AppRoutes.home);

  void resetToAuth() => go(AppRoutes.login);
}
