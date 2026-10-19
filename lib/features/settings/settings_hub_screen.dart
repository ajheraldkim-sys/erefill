import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:erefill/core/constants.dart';
import 'package:erefill/core/routing/app_navigation.dart';
import 'package:erefill/core/providers/user_provider.dart';
import 'package:erefill/core/utils/app_roles.dart';
import 'package:erefill/features/settings/rider/rider_settings_screen.dart';
import 'package:erefill/features/settings/account_security_screen.dart';
import 'package:erefill/features/account/saved_addresses_screen.dart';
import 'package:erefill/features/settings/settings_catalog.dart';
import 'package:erefill/features/settings/payment_account_models.dart';
import 'package:erefill/features/auth/widgets/desktop_admin_only_screen.dart';

class SettingsHubScreen extends StatelessWidget {
  const SettingsHubScreen({super.key, this.role = 'customer'});

  final String role;

  @override
  Widget build(BuildContext context) {
    final profileRole = context.watch<UserProvider>().user?.role;
    if (AppRoles.isDesktopAdmin(profileRole) || AppRoles.isDesktopAdmin(role)) {
      return const DesktopAdminOnlyScreen();
    }

    final authenticatedRole = _normalizeRole(profileRole);
    final effectiveRole = authenticatedRole ?? 'customer';
    final sections = RoleSettingsCatalog.forRole(effectiveRole);

    return Scaffold(
      backgroundColor: AppUi.pageBgOf(context),
      appBar: AppBar(
        title: Text(RoleSettingsCatalog.titleForRole(effectiveRole)),
        centerTitle: true,
        backgroundColor: AppUi.pageBgOf(context),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: ListView(
        padding: AppUi.pagePadding,
        children: [
          Text(
            'These are the settings relevant to your role.',
            style: TextStyle(
              color: AppUi.textMutedOf(context),
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 18),
          ...sections.map(
            (section) => _SettingsTile(section: section, role: effectiveRole),
          ),
        ],
      ),
    );
  }

  String? _normalizeRole(String? value) {
    switch (value?.toLowerCase()) {
      case 'customer':
        return 'customer';
      case 'owner':
      case 'station_owner':
        return 'owner';
      case 'rider':
        return 'rider';
      default:
        return null;
    }
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({required this.section, required this.role});

  final SettingsSection section;
  final String role;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: AppUi.surfaceOf(context),
        borderRadius: BorderRadius.circular(AppUi.radiusSheet),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppUi.radiusSheet),
          onTap: () => _handleTap(context),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: AppUi.brandSoftOf(context),
                    borderRadius: BorderRadius.circular(AppUi.radiusCard),
                  ),
                  child: Icon(
                    section.icon,
                    color: AppUi.brandOf(context),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        section.title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        section.description,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppUi.textMutedOf(context),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: AppUi.textMutedOf(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _handleTap(BuildContext context) {
    switch (role.toLowerCase()) {
      case 'customer':
        _handleCustomerTap(context);
        return;
      case 'owner':
        _handleOwnerTap(context);
        return;
      case 'rider':
        _handleRiderTap(context);
        return;
      default:
        _handleCustomerTap(context);
    }
  }

  Future<void> _handleCustomerTap(BuildContext context) async {
    switch (section.key) {
      case 'profile':
        context.openCustomerSettings();
        return;
      case 'delivery_address':
        final user = context.read<UserProvider>().user;
        await context.openSavedAddresses(
          SavedAddressLaunchContext(
            address: user?.completeAddress ?? '',
            landmark: user?.landmark ?? '',
            town: user?.town,
            barangay: user?.barangay,
            latitude: user?.latitude ?? 0,
            longitude: user?.longitude ?? 0,
          ),
        );
        if (context.mounted) {
          await context.read<UserProvider>().refreshProfile();
        }
        return;
      case 'notifications':
        context.openCustomerSettings();
        return;
      case 'payment_methods':
        context.openPaymentAccounts(PaymentAccountScope.customerPaymentMethods);
        return;
      case 'app_preferences':
        context.openCustomerSettings();
        return;
      case 'security':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => AccountSecurityScreen(role: 'customer'),
          ),
        );
        return;
      default:
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${section.title} is managed in the existing account screens.',
            ),
          ),
        );
    }
  }

  void _handleOwnerTap(BuildContext context) {
    switch (section.key) {
      case 'station_profile':
      case 'products_pricing':
      case 'delivery':
        context.openOwnerMenu();
        return;
      case 'inventory':
        context.openOwnerInventory();
        return;
      case 'payments':
        context.openPaymentAccounts(PaymentAccountScope.ownerPayoutAccounts);
        return;
      case 'riders':
        return;
      case 'notifications':
        context.openOwnerMenu();
        return;
      case 'security':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => AccountSecurityScreen(role: 'owner'),
          ),
        );
        return;
      default:
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${section.title} is configured in the relevant operations screen.',
            ),
          ),
        );
    }
  }

  void _handleRiderTap(BuildContext context) {
    switch (section.key) {
      case 'profile':
      case 'delivery_preferences':
      case 'notifications':
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const RiderSettingsScreen()));
        return;
      case 'availability':
        return;
      case 'commission_earnings':
        return;
      case 'security':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => AccountSecurityScreen(role: 'rider'),
          ),
        );
        return;
      default:
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${section.title} is managed in the rider account and delivery flows.',
            ),
          ),
        );
    }
  }
}
