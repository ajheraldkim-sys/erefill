import 'package:flutter/material.dart';
import 'package:erefill/core/constants.dart';
import 'package:erefill/core/widgets/brand/hero_header.dart';
import 'rider_logistics_map.dart';
import 'rider_management_screen.dart';
import '../../payouts/widgets/owner_payout_requests_tab.dart';

class RidersScreen extends StatefulWidget {
  final String ownerId;
  const RidersScreen({super.key, required this.ownerId});

  @override
  State<RidersScreen> createState() => _RidersScreenState();
}

class _RidersScreenState extends State<RidersScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppUi.pageBgOf(context),
      body: Column(
        children: [
          TabScreenHeroHeader(
            title: 'Riders',
            subtitle: 'Live map, assignments, and delivery workload',
          ),
          Material(
            color: AppUi.surfaceOf(context),
            child: TabBar(
              controller: _tabController,
              indicatorSize: TabBarIndicatorSize.label,
              indicator: const UnderlineTabIndicator(
                borderSide: BorderSide(width: 3, color: AppUi.bluePrimary),
              ),
              labelColor: AppUi.bluePrimary,
              unselectedLabelColor: AppUi.textMuted,
              labelStyle: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
              unselectedLabelStyle: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
              tabs: const [
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.map_rounded, size: 18),
                      SizedBox(width: 8),
                      Text('Live map'),
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.people_alt_rounded, size: 18),
                      SizedBox(width: 8),
                      Text('Riders'),
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.payments_rounded, size: 18),
                      SizedBox(width: 8),
                      Text('Payouts'),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                RiderLogisticsMap(ownerId: widget.ownerId),
                const RiderManagementScreen(),
                OwnerPayoutRequestsTab(ownerId: widget.ownerId),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
