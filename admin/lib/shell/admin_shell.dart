import 'package:erefill/core/constants.dart';
import 'package:erefill/core/widgets/brand/erefill_logo.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../features/dashboard/dashboard_screen.dart';
import '../features/fees/platform_fees_screen.dart';
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

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 760;
        final collapsed = _sidebarCollapsed || constraints.maxWidth < 1100;
        final sidebar = _AdminSidebar(
          collapsed: compact ? false : collapsed,
          selected: _section,
          onSelect: (section) {
            setState(() {
              _section = section;
              _visitedSections.add(section);
            });
            if (compact) _scaffoldKey.currentState?.closeDrawer();
          },
          onToggle: () => setState(() => _sidebarCollapsed = !_sidebarCollapsed),
          onSignOut: () => context.read<AdminAuthProvider>().signOut(),
        );
        final content = Column(
          children: [
            _AdminTopBar(
              section: _section,
              displayName: widget.displayName,
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
      AdminSection.settings => const PlatformFeesScreen(),
    };
  }
}

class _AdminSidebar extends StatelessWidget {
  const _AdminSidebar({
    required this.collapsed,
    required this.selected,
    required this.onSelect,
    required this.onToggle,
    required this.onSignOut,
  });

  final bool collapsed;
  final AdminSection selected;
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
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF065A60), Color(0xFF0F172A)],
        ),
        boxShadow: [
          BoxShadow(color: Color(0x22000000), blurRadius: 24, offset: Offset(4, 0)),
        ],
      ),
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Keep the icon-only layout during the width tween so labels never
            // enter a sidebar that's still too narrow to display them.
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
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                        )
                      : Row(
                          children: [
                            const Expanded(
                              child: ERefillLogo(
                                size: 34,
                                showMark: false,
                                showWordmark: true,
                                color: Colors.white,
                                markColor: Colors.white,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Collapse menu',
                              onPressed: onToggle,
                              icon: const Icon(
                                LucideIcons.panelLeftClose,
                                color: Colors.white70,
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
                        color: Colors.white.withValues(alpha: 0.65),
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
                        _navTile(item, compactLayout),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Sign out',
                  onPressed: onSignOut,
                  icon: Icon(
                    LucideIcons.logOut,
                    color: Colors.white.withValues(alpha: 0.75),
                    size: 20,
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

  Widget _navTile(_NavItem item, bool compactLayout) {
    final active = selected == item.section;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Material(
        color: active ? AppUi.bluePrimary : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: () => onSelect(item.section),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: compactLayout ? 0 : 14,
              vertical: 11,
            ),
            child: compactLayout
                ? Center(
                    child: Tooltip(
                      message: item.label,
                      child: Icon(item.icon, size: 20, color: active ? Colors.white : Colors.white60),
                    ),
                  )
                : Row(
                    children: [
                      Icon(item.icon, size: 18, color: active ? Colors.white : Colors.white70),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          item.label,
                          style: TextStyle(
                            color: active ? Colors.white : Colors.white70,
                            fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                            fontSize: 13.5,
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
    required this.onRefresh,
    required this.compact,
    this.onMenu,
  });

  final AdminSection section;
  final String displayName;
  final VoidCallback onRefresh;
  final bool compact;
  final VoidCallback? onMenu;

  String get _title => switch (section) {
        AdminSection.dashboard => 'Dashboard',
        AdminSection.stations => 'Water Stations',
        AdminSection.orders => 'Refill Orders',
        AdminSection.users => 'Users & Accounts',
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
                    Icon(LucideIcons.chevronRight, size: 14, color: AppUi.textSecondaryOf(context)),
                    const SizedBox(width: 4),
                    Text(_title, style: adminCaptionTextStyle(context).copyWith(color: AppUi.bluePrimary)),
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
                border: Border.all(color: AppUi.accentGreen.withValues(alpha: 0.4)),
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
                    'Telemetry Active',
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
                const Icon(LucideIcons.shieldCheck, size: 16, color: AppUi.bluePrimary),
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
