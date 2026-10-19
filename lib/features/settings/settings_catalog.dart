import 'package:flutter/material.dart';

class SettingsSection {
  const SettingsSection({
    required this.key,
    required this.title,
    required this.description,
    required this.icon,
  });

  final String key;
  final String title;
  final String description;
  final IconData icon;
}

class RoleSettingsCatalog {
  const RoleSettingsCatalog._();

  static const Map<String, String> _roleTitles = {
    'customer': 'Customer settings',
    'owner': 'Station owner settings',
    'rider': 'Rider settings',
  };

  static const List<SettingsSection> _customerSections = [
    SettingsSection(
      key: 'profile',
      title: 'Profile',
      description: 'Name, contact details, username, and account basics.',
      icon: Icons.person_outline_rounded,
    ),
    SettingsSection(
      key: 'delivery_address',
      title: 'Delivery address',
      description: 'Saved addresses, defaults, and delivery notes.',
      icon: Icons.location_on_outlined,
    ),
    SettingsSection(
      key: 'notifications',
      title: 'Notifications',
      description: 'Order and status alerts you actually receive.',
      icon: Icons.notifications_outlined,
    ),
    SettingsSection(
      key: 'payment_methods',
      title: 'Payment methods',
      description: 'Supported payment options for checkout and orders.',
      icon: Icons.payments_outlined,
    ),
    SettingsSection(
      key: 'order_preferences',
      title: 'Order preferences',
      description: 'Helpful defaults without overriding the order itself.',
      icon: Icons.receipt_long_outlined,
    ),
    SettingsSection(
      key: 'app_preferences',
      title: 'App preferences',
      description: 'Theme, language, and the rest of your app experience.',
      icon: Icons.tune_rounded,
    ),
    SettingsSection(
      key: 'account',
      title: 'Account',
      description: 'Email, username, and password settings.',
      icon: Icons.manage_accounts_outlined,
    ),
  ];

  static const List<SettingsSection> _ownerSections = [
    SettingsSection(
      key: 'station_profile',
      title: 'Station profile',
      description: 'Name, address, contact details, and station information.',
      icon: Icons.storefront_outlined,
    ),
    SettingsSection(
      key: 'products_pricing',
      title: 'Products & pricing',
      description: 'Water catalog, available products, and price rules.',
      icon: Icons.water_drop_outlined,
    ),
    SettingsSection(
      key: 'inventory',
      title: 'Inventory',
      description: 'Low stock, stock alerts, and filled/empty gallon tracking.',
      icon: Icons.inventory_2_outlined,
    ),
    SettingsSection(
      key: 'delivery',
      title: 'Delivery',
      description: 'Fees, rider rules, and scheduling.',
      icon: Icons.local_shipping_outlined,
    ),
    SettingsSection(
      key: 'riders',
      title: 'Riders',
      description: 'Assignments, rider activity, and station-level access.',
      icon: Icons.people_alt_outlined,
    ),
    SettingsSection(
      key: 'payments',
      title: 'Payment accounts',
      description:
          'Station payout and collection methods supported by the app.',
      icon: Icons.account_balance_wallet_outlined,
    ),
    SettingsSection(
      key: 'notifications',
      title: 'Notifications',
      description: 'Operational alerts for orders, riders, and inventory.',
      icon: Icons.notifications_active_outlined,
    ),
    SettingsSection(
      key: 'account',
      title: 'Account',
      description: 'Email, username, and password settings.',
      icon: Icons.manage_accounts_outlined,
    ),
  ];

  static const List<SettingsSection> _riderSections = [
    SettingsSection(
      key: 'profile',
      title: 'Profile',
      description: 'Contact details, vehicle info, and rider identity.',
      icon: Icons.person_outline_rounded,
    ),
    SettingsSection(
      key: 'availability',
      title: 'Availability',
      description: 'Your online/offline state and delivery readiness.',
      icon: Icons.online_prediction_rounded,
    ),
    SettingsSection(
      key: 'delivery_preferences',
      title: 'Delivery preferences',
      description: 'Delivery routing, notifications, and order handling.',
      icon: Icons.route_rounded,
    ),
    SettingsSection(
      key: 'commission_earnings',
      title: 'Commission & earnings',
      description: 'Your delivered orders, payout summary, and reporting.',
      icon: Icons.account_balance_wallet_outlined,
    ),
    SettingsSection(
      key: 'notifications',
      title: 'Notifications',
      description: 'Alerts relevant to assignments and order updates.',
      icon: Icons.notifications_outlined,
    ),
    SettingsSection(
      key: 'account',
      title: 'Account',
      description: 'Email, username, and password settings.',
      icon: Icons.manage_accounts_outlined,
    ),
  ];

  static String titleForRole(String? role) {
    final normalized = (role ?? 'customer').toLowerCase();
    return _roleTitles[normalized] ?? _roleTitles['customer']!;
  }

  static List<SettingsSection> forRole(String? role) {
    switch ((role ?? 'customer').toLowerCase()) {
      case 'owner':
        return _ownerSections;
      case 'rider':
        return _riderSections;
      case 'admin':
      case 'super_admin':
      case 'administrator':
        return const [];
      case 'customer':
      default:
        return _customerSections;
    }
  }
}
