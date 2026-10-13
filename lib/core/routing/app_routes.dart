/// Central route paths for go_router navigation.
abstract final class AppRoutes {
  static const home = '/';
  static const onboarding = '/onboarding';
  static const login = '/login';
  static const signup = '/signup';
  static const customerSignup = '/signup/customer';
  static const ownerSignup = '/signup/owner';
  static const forgotPassword = '/forgot-password';
  static const resetPassword = '/reset-password';
  static const paymentSuccess = '/payment/success';
  static const paymentCancel = '/payment/cancel';
  static const paymentCallback = '/payment-callback';
  static const stationList = '/stations';
  static const stationDetails = '/stations/details';
  static const checkout = '/checkout';
  static const orderTrack = '/orders/track';
  static const orderList = '/orders';
  static const chat = '/chat';
  static const inbox = '/inbox';
  static const notifications = '/notifications';
  static const ownerMenu = '/owner/menu';
  static const ownerServiceCatalog = '/owner/service-catalog';
  static const ownerInventory = '/owner/inventory';
  static const deliveryManagement = '/owner/delivery-mgmt';
  static const paymentAccounts = '/settings/payment-accounts';
  static const settingsHub = '/settings';
  static const customerSettings = '/settings/customer';
  static const riderPerformance = '/owner/rider-performance';
  static const savedAddresses = '/account/saved-addresses';
  static const riderHistory = '/rider/history';
  static const adminDashboard = '/admin';
  static String orderById(String orderId) => '/orders/$orderId';
  static String orderMap(String orderId) => '/orders/$orderId/map';
}
