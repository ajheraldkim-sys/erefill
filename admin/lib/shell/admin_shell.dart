import 'dart:async';

import 'package:erefill/core/constants.dart';
import 'package:erefill/core/widgets/brand/erefill_logo.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../features/dashboard/dashboard_screen.dart';
import '../features/fees/platform_fees_screen.dart';
import '../features/notifications/admin_notifications_screen.dart';
import '../features/orders/orders_screen.dart';
import '../features/stations/stations_screen.dart';
import '../features/users/users_screen.dart';
import '../providers/admin_auth_provider.dart';
import '../widgets/admin_ui.dart';

enum AdminSection {
  dashboard,
  stations,
  orders,
  users,
  notifications,
  settings,
}

class AdminShell extends StatefulWidget {
  const AdminShell({super.key, required this.displayName});

  final String displayName;

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  AdminSection _section = AdminSection.dashboard;
  final Set<AdminSection> _visitedSections = {AdminSection.dashboard};
  bool _sidebarCollapsed = false;
  final Map<AdminSection, int> _refreshKeys = {};
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  RealtimeChannel? _realtimeChannel;
  Timer? _realtimeDebounce;
  int _unreadNotifications = 0;
  final List<Map<String, dynamic>> _liveNotifications = [];

  @override
  void initState() {
    super.initState();
    _setupRealtime();
  }

  @override
  void dispose() {
    _realtimeDebounce?.cancel();
    _realtimeChannel?.unsubscribe();
    super.dispose();
  }

  void _setupRealtime() {
    try {
      final supabase = Supabase.instance.client;
      _realtimeChannel = supabase.channel('desktop_admin_realtime_events')
        ..onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'orders',
          callback: (payload) {
            final id = payload.newRecord['id']?.toString() ?? '';
            final shortId = id.length >= 8 ? id.substring(0, 8) : id;
            final status = payload.newRecord['status']?.toString() ?? 'updated';
            _onLiveEvent('Order Update', 'Order #$shortId status changed to $status');
          },
        )
        ..onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'water_refill_stations',
          callback: (payload) {
            final name = payload.newRecord['name']?.toString() ?? 'Station';
            _onLiveEvent('Station Event', 'Station "$name" updated in system');
          },
        )
        ..onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'disputes',
          callback: (_) {
            _onLiveEvent('Dispute Update', 'A customer dispute was logged or modified');
          },
        )
        ..subscribe();
    } catch (_) {}
  }

  void _onLiveEvent(String title, String desc) {
    if (!mounted) return;
    setState(() {
      _liveNotifications.insert(0, {
        'title': title,
        'description': desc,
        'time': DateTime.now(),
        'read': false,
      });
      _unreadNotifications++;
    });

    _realtimeDebounce?.cancel();
    _realtimeDebounce = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) _refreshCurrent();
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 760;
        final collapsed = _sidebarCollapsed || constraints.maxWidth < 1100;
        final sidebar = _AdminSidebar(
          collapsed: compact ? false : collapsed,
          selected: _section,
          unreadNotifications: _unreadNotifications,
          onSelect: (section) {
            setState(() {
              _section = section;
              _visitedSections.add(section);
              if (section == AdminSection.notifications) {
                _unreadNotifications = 0;
              }
            });
            if (compact) _scaffoldKey.currentState?.closeDrawer();
          },
          onToggle: () =>
              setState(() => _sidebarCollapsed = !_sidebarCollapsed),
          onSignOut: () => context.read<AdminAuthProvider>().signOut(),
        );
        final content = SafeArea(
          child: Column(
            children: [
              _AdminTopBar(
                section: _section,
                displayName: widget.displayName,
                unreadNotifications: _unreadNotifications,
                onOpenNotifications: () {
                  setState(() {
                    _section = AdminSection.notifications;
                    _visitedSections.add(AdminSection.notifications);
                    _unreadNotifications = 0;
                  });
                },
                onRefresh: _refreshCurrent,
                compact: compact,
                onMenu: compact
                    ? () => _scaffoldKey.currentState?.openDrawer()
                    : null,
              ),
              Expanded(
                child: IndexedStack(
                  index: _section.index,
                  children: [
                    for (final section in AdminSection.values)
                      if (_visitedSections.contains(section))
                        KeyedSubtree(
                          key: ValueKey(
                            '${section.name}-${_refreshKeys[section] ?? 0}',
                          ),
                          child: _bodyFor(section),
                        )
                      else
                        const SizedBox.shrink(),
                  ],
                ),
              ),
            ],
          ),
        );

        if (compact) {
          return Scaffold(
            key: _scaffoldKey,
            backgroundColor: AppUi.pageBgOf(context),
            drawer: Drawer(width: 280, child: sidebar),
            body: content,
          );
        }

        return Scaffold(
          backgroundColor: AppUi.pageBgOf(context),
          body: Row(
            children: [
              sidebar,
              Expanded(child: content),
            ],
          ),
        );
      },
    );
  }

  Future<void> _refreshCurrent() async {
    setState(() {
      _refreshKeys.update(
        _section,
        (refreshKey) => refreshKey + 1,
        ifAbsent: () => 1,
      );
    });
  }

  Widget _bodyFor(AdminSection section) {
    return switch (section) {
      AdminSection.dashboard => const DashboardScreen(),
      AdminSection.stations => const StationsScreen(),
      AdminSection.orders => const OrdersScreen(),
      AdminSection.users => const UsersScreen(),
      AdminSection.notifications => const AdminNotificationsScreen(),
      AdminSection.settings => const PlatformFeesScreen(),
    };
  }
}

class _AdminSidebar extends StatelessWidget {
  const _AdminSidebar({
    required this.collapsed,
    required this.selected,
    required this.unreadNotifications,
    required this.onSelect,
    required this.onToggle,
    required this.onSignOut,
  });

  final bool collapsed;
  final AdminSection selected;
  final int unreadNotifications;
  final ValueChanged<AdminSection> onSelect;
  final VoidCallback onToggle;
  final VoidCallback onSignOut;

  static const _items = [
    _NavItem(
      AdminSection.dashboard,
      LucideIcons.layoutDashboard,
      'Dashboard',
    ),
    _NavItem(
      AdminSection.stations,
      LucideIcons.store,
      'Water Stations',
    ),
    _NavItem(
      AdminSection.users,
      LucideIcons.users,
      'Users & Accounts',
    ),
    _NavItem(
      AdminSection.orders,
      LucideIcons.shoppingBag,
      'Refill Orders',
    ),
    _NavItem(
      AdminSection.notifications,
      LucideIcons.bell,
      'Notifications',
    ),
    _NavItem(
      AdminSection.settings,
      LucideIcons.settings,
      'System Settings',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final width = collapsed ? 76.0 : 268.0;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      width: width,
      decoration: BoxDecoration(
        color: AppUi.pageBgOf(context),
        border: Border(
          right: BorderSide(
            color: AppUi.borderOf(context),
            width: 1,
          ),
        ),
      ),
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compactLayout = constraints.maxWidth < 240;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    compactLayout ? 8 : 20,
                    16,
                    compactLayout ? 8 : 16,
                    8,
                  ),
                  child: compactLayout
                      ? Center(
                          child: IconButton(
                            tooltip: 'Expand menu',
                            onPressed: onToggle,
                            icon: const Icon(
                              LucideIcons.droplets,
                              color: AppUi.bluePrimary,
                              size: 24,
                            ),
                          ),
                        )
                      : Row(
                          children: [
                            Expanded(
                              child: ERefillLogo(
                                size: 34,
                                showMark: false,
                                showWordmark: true,
                                color: AppUi.textPrimaryOf(context),
                                markColor: AppUi.bluePrimary,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Collapse menu',
                              onPressed: onToggle,
                              icon: Icon(
                                LucideIcons.panelLeftClose,
                                color: AppUi.textSecondaryOf(context),
                                size: 18,
                              ),
                              visualDensity: VisualDensity.compact,
                            ),
                          ],
                        ),
                ),
                if (!compactLayout)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      'Admin Console',
                      style: TextStyle(
                        color: AppUi.textSecondaryOf(context),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.symmetric(
                      horizontal: compactLayout ? 8 : 12,
                      vertical: 6,
                    ),
                    children: [
                      for (final item in _items)
                        _navTile(context, item, compactLayout),
                    ],
                  ),
                ),
                Container(
                  margin: EdgeInsets.symmetric(
                    horizontal: compactLayout ? 8 : 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(color: AppUi.borderOf(context)),
                    ),
                  ),
                  padding: const EdgeInsets.only(top: 8),
                  child: compactLayout
                      ? Center(
                          child: IconButton(
                            tooltip: 'Sign out',
                            onPressed: onSignOut,
                            icon: const Icon(
                              LucideIcons.logOut,
                              color: AppUi.error,
                              size: 20,
                            ),
                          ),
                        )
                      : InkWell(
                          onTap: onSignOut,
                          borderRadius: BorderRadius.circular(10),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  LucideIcons.logOut,
                                  color: AppUi.error,
                                  size: 18,
                                ),
                                SizedBox(width: 12),
                                Text(
                                  'Sign Out',
                                  style: TextStyle(
                                    color: AppUi.error,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                ),
                const SizedBox(height: 8),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _navTile(BuildContext context, _NavItem item, bool compactLayout) {
    final active = selected == item.section;
    final isNotifications = item.section == AdminSection.notifications;
    final showBadge = isNotifications && unreadNotifications > 0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Material(
        color: active ? AppUi.bluePrimary : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: () => onSelect(item.section),
          borderRadius: BorderRadius.circular(12),
          hoverColor: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: compactLayout ? 0 : 14,
              vertical: 11,
            ),
            child: compactLayout
                ? Center(
                    child: Tooltip(
                      message: item.label,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Icon(
                            item.icon,
                            size: 20,
                            color: active
                                ? Colors.white
                                : AppUi.textSecondaryOf(context),
                          ),
                          if (showBadge)
                            Positioned(
                              top: -4,
                              right: -4,
                              child: Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  color: AppUi.error,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  )
                : Row(
                    children: [
                      Icon(
                        item.icon,
                        size: 18,
                        color: active
                            ? Colors.white
                            : AppUi.textSecondaryOf(context),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          item.label,
                          style: TextStyle(
                            color: active
                                ? Colors.white
                                : AppUi.textPrimaryOf(context),
                            fontWeight:
                                active ? FontWeight.w700 : FontWeight.w600,
                            fontSize: 13.5,
                          ),
                        ),
                      ),
                      if (showBadge)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: active ? Colors.white : AppUi.error,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            unreadNotifications > 99
                                ? '99+'
                                : '$unreadNotifications',
                            style: TextStyle(
                              color: active ? AppUi.bluePrimary : Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
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
}

class _NavItem {
  const _NavItem(this.section, this.icon, this.label);
  final AdminSection section;
  final IconData icon;
  final String label;
}

class _AdminTopBar extends StatelessWidget {
  const _AdminTopBar({
    required this.section,
    required this.displayName,
    required this.unreadNotifications,
    required this.onOpenNotifications,
    required this.onRefresh,
    required this.compact,
    this.onMenu,
  });

  final AdminSection section;
  final String displayName;
  final int unreadNotifications;
  final VoidCallback onOpenNotifications;
  final VoidCallback onRefresh;
  final bool compact;
  final VoidCallback? onMenu;

  String get _title => switch (section) {
    AdminSection.dashboard => 'Dashboard',
    AdminSection.stations => 'Water Stations',
    AdminSection.orders => 'Refill Orders',
    AdminSection.users => 'Users & Accounts',
    AdminSection.notifications => 'Live Notifications',
    AdminSection.settings => 'System Settings',
  };

  @override
  Widget build(BuildContext context) {
    final now = DateFormat('EEE, MMM d · HH:mm').format(DateTime.now());

    return Container(
      padding: EdgeInsets.fromLTRB(compact ? 8 : 28, 12, compact ? 8 : 28, 12),
      decoration: BoxDecoration(
        color: AppUi.surfaceOf(context),
        border: Border(bottom: BorderSide(color: AppUi.dividerOf(context))),
      ),
      child: Row(
        children: [
          if (onMenu != null)
            IconButton(
              tooltip: 'Open navigation menu',
              onPressed: onMenu,
              icon: const Icon(LucideIcons.menu, size: 20),
            ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!compact)
                Row(
                  children: [
                    Text('Admin', style: adminCaptionTextStyle(context)),
                    const SizedBox(width: 4),
                    Icon(
                      LucideIcons.chevronRight,
                      size: 14,
                      color: AppUi.textSecondaryOf(context),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _title,
                      style: adminCaptionTextStyle(
                        context,
                      ).copyWith(color: AppUi.bluePrimary),
                    ),
                  ],
                ),
              if (!compact) AppUi.vGapXs,
              Text(
                _title,
                style: compact
                    ? adminSectionTitleStyle(context)
                    : adminScreenTitleStyle(context),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
          const Spacer(),
          if (!compact) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppUi.accentGreen.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppUi.accentGreen.withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: AppUi.accentGreen,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'Realtime Live',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppUi.accentGreen,
                    ),
                  ),
                ],
              ),
            ),
            AppUi.hGapMd,
            Text(now, style: adminCaptionTextStyle(context)),
            AppUi.hGapMd,
          ],
          IconButton(
            tooltip: 'Notifications',
            onPressed: onOpenNotifications,
            icon: Badge(
              isLabelVisible: unreadNotifications > 0,
              label: Text(
                unreadNotifications > 99 ? '99+' : '$unreadNotifications',
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
              ),
              child: const Icon(LucideIcons.bell, size: 19),
            ),
          ),
          IconButton(
            tooltip: 'Refresh view',
            onPressed: onRefresh,
            icon: const Icon(LucideIcons.refreshCw, size: 18),
          ),
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 9 : 14,
              vertical: 8,
            ),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: AppUi.borderOf(context)),
            ),
            child: Row(
              children: [
                const Icon(
                  LucideIcons.shieldCheck,
                  size: 16,
                  color: AppUi.bluePrimary,
                ),
                if (!compact) ...[
                  AppUi.hGapSm,
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 160),
                    child: Text(
                      displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        color: AppUi.textPrimaryOf(context),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
