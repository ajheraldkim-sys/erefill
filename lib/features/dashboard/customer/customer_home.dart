import 'package:flutter/material.dart';
import 'package:erefill/core/constants.dart';
import 'package:erefill/core/widgets/role_bottom_nav_bar.dart';
import 'package:erefill/core/widgets/lazy_indexed_stack.dart';
import 'package:erefill/features/dashboard/customer/customer_orders_list.dart';
import 'package:erefill/features/dashboard/customer/station_list_screen.dart';
import 'package:erefill/features/dashboard/customer/customer_profile_screen.dart';
import 'package:erefill/features/dashboard/customer/customer_home_tab.dart';
import 'package:erefill/features/chat/inbox_screen.dart';

class CustomerHome extends StatefulWidget {
  const CustomerHome({super.key});

  @override
  State<CustomerHome> createState() => _CustomerHomeState();
}

class _CustomerHomeState extends State<CustomerHome> {
  int _selectedIndex = 0;

  void _changeTab(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _pages = [
      CustomerHomeTab(onOpenStations: () => _changeTab(1)),
      const StationListScreen(),
      const InboxScreen(),
      CustomerOrdersList(onNavigateToStations: () => _changeTab(1)),
      const CustomerProfileScreen(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _selectedIndex == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_selectedIndex != 0) {
          setState(() {
            _selectedIndex = 0;
          });
        }
      },
      child: Scaffold(
        backgroundColor: AppUi.pageBgOf(context),
        body: SafeArea(
          bottom: false,
          child: LazyIndexedStack(index: _selectedIndex, children: _pages),
        ),
        bottomNavigationBar: RoleBottomNavBar(
          currentIndex: _selectedIndex,
          onTap: (index) => _changeTab(index),
          items: const [
            RoleBottomNavItem(
              icon: Icons.home_outlined,
              activeIcon: Icons.home_rounded,
              label: 'Home',
            ),
            RoleBottomNavItem(
              icon: Icons.map_outlined,
              activeIcon: Icons.map_rounded,
              label: 'Stations',
            ),
            RoleBottomNavItem(
              icon: Icons.chat_bubble_outline_rounded,
              activeIcon: Icons.chat_bubble_rounded,
              label: 'Chat',
            ),
            RoleBottomNavItem(
              icon: Icons.receipt_long_outlined,
              activeIcon: Icons.receipt_long_rounded,
              label: 'Orders',
            ),
            RoleBottomNavItem(
              icon: Icons.person_outline_rounded,
              activeIcon: Icons.person_rounded,
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }
}
