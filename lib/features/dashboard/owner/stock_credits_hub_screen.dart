import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/constants.dart';
import '../../../core/widgets/brand/hero_header.dart';
import '../../delivery_mgmt/providers/credit_provider.dart';
import '../../delivery_mgmt/providers/delivery_provider.dart';
import '../../delivery_mgmt/providers/report_provider.dart';
import '../../delivery_mgmt/screens/delivery_management_screen.dart';
import '../../delivery_mgmt/widgets/dm_offline_banner.dart';
import 'owner_inventory_screen.dart';

/// Unified Hub for Station Owners:
/// Tab 0: Inventory Stock (filled stock, empty bottles, product stock, activity stream)
/// Tab 1: Customer Credits / Utang Ledger (balances, partial payments, debtor tracking)
/// Tab 2: Delivery Logs & Sales Reports (offline delivery logging & analytics statement)
class StockCreditsHubScreen extends StatefulWidget {
  final int initialTab;
  const StockCreditsHubScreen({super.key, this.initialTab = 0});

  @override
  State<StockCreditsHubScreen> createState() => _StockCreditsHubScreenState();
}

class _StockCreditsHubScreenState extends State<StockCreditsHubScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _uuid = const Uuid();
  int _logSubTab = 0; // 0 = Delivery Logs, 1 = Sales Analytics

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, 2),
    );
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging && mounted) {
        setState(() {});
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _initProviders());
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _initProviders() {
    final ownerId = Supabase.instance.client.auth.currentUser?.id;
    if (ownerId == null || ownerId.isEmpty) return;

    context.read<DeliveryProvider>().initialize(ownerId);
    context.read<CreditProvider>().initialize(ownerId);
    context.read<ReportProvider>().initialize(ownerId);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: AppUi.pageBgOf(context),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const DmOfflineBanner(),
            const TabScreenHeroHeader(
              title: 'Stock & Credits',
              subtitle: 'Container inventory, customer utang ledger & offline sales',
            ),
            // Custom Segmented Pill Tab Bar
            Container(
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: isDark
                    ? AppUi.darkSurfaceRaised
                    : AppUi.lightSurfaceRaised,
                borderRadius: BorderRadius.circular(AppUi.radiusControl),
                border: Border.all(color: AppUi.borderOf(context)),
              ),
              child: TabBar(
                controller: _tabController,
                labelColor: Colors.white,
                unselectedLabelColor: AppUi.textSecondaryOf(context),
                indicatorSize: TabBarIndicatorSize.tab,
                indicator: BoxDecoration(
                  color: AppUi.bluePrimary,
                  borderRadius: BorderRadius.circular(AppUi.radiusControl - 3),
                  boxShadow: [
                    BoxShadow(
                      color: AppUi.bluePrimary.withValues(alpha: 0.25),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                dividerColor: Colors.transparent,
                labelPadding: EdgeInsets.zero,
                labelStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
                unselectedLabelStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                tabs: const [
                  Tab(
                    height: 38,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.inventory_2_rounded, size: 14),
                        SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            'Stock',
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Tab(
                    height: 38,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.receipt_long_rounded, size: 14),
                        SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            'Credits',
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Tab(
                    height: 38,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.insights_rounded, size: 14),
                        SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            'Logs',
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Tab Views
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  // Tab 0: Inventory Stock
                  const OwnerInventoryScreen(embedded: true),

                  // Tab 1: Credit & Utang Ledger
                  DmCreditLedgerTab(uuid: _uuid),

                  // Tab 2: Delivery Logs & Sales Reports
                  Column(
                    children: [
                      // Sub-toggle between Delivery Logs and Sales Analytics
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        child: Row(
                          children: [
                            ChoiceChip(
                              label: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.list_alt_rounded, size: 14),
                                  SizedBox(width: 5),
                                  Text('Delivery Logs'),
                                ],
                              ),
                              selected: _logSubTab == 0,
                              onSelected: (_) => setState(() => _logSubTab = 0),
                              selectedColor: AppUi.bluePrimary,
                              labelStyle: TextStyle(
                                color: _logSubTab == 0
                                    ? Colors.white
                                    : AppUi.textSecondaryOf(context),
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(AppUi.radiusSheet),
                              ),
                            ),
                            const SizedBox(width: 8),
                            ChoiceChip(
                              label: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.bar_chart_rounded, size: 14),
                                  SizedBox(width: 5),
                                  Text('Sales Analytics'),
                                ],
                              ),
                              selected: _logSubTab == 1,
                              onSelected: (_) => setState(() => _logSubTab = 1),
                              selectedColor: AppUi.bluePrimary,
                              labelStyle: TextStyle(
                                color: _logSubTab == 1
                                    ? Colors.white
                                    : AppUi.textSecondaryOf(context),
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(AppUi.radiusSheet),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: _logSubTab == 0
                            ? DmDeliveryLogsTab(uuid: _uuid)
                            : const DmReportsAnalyticsTab(),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

