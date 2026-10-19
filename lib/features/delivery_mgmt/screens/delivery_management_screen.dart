import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/constants.dart';
import '../../../core/services/owner_inventory_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/providers/user_provider.dart';
import '../../../core/services/report_export_service.dart';
import '../../../core/widgets/app_form_fields.dart';
import '../../../core/widgets/brand/axo_states.dart';
import '../models/credit_model.dart';
import '../models/delivery_model.dart';
import '../providers/credit_provider.dart';
import '../providers/delivery_provider.dart';
import '../providers/report_provider.dart';
import '../widgets/bar_chart_widget.dart';
import '../widgets/dm_offline_banner.dart';
import '../widgets/dm_screen_header.dart';

import 'package:erefill/core/utils/money.dart';
/// Complete Offline Delivery & Credit Management screen for station owners.
class DeliveryManagementScreen extends StatefulWidget {
  const DeliveryManagementScreen({super.key});

  @override
  State<DeliveryManagementScreen> createState() =>
      _DeliveryManagementScreenState();
}

class _DeliveryManagementScreenState extends State<DeliveryManagementScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _uuid = const Uuid();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _initProviders());
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _initProviders() {
    if (!mounted) return;
    final ownerId = Supabase.instance.client.auth.currentUser?.id ??
        context.read<UserProvider>().user?.id;
    if (ownerId == null || ownerId.isEmpty) return;

    context.read<DeliveryProvider>().initialize(ownerId);
    context.read<CreditProvider>().initialize(ownerId);
    context.read<ReportProvider>().initialize(ownerId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppUi.pageBgOf(context),
      body: SafeArea(
        bottom: false,
        child: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) => [
            SliverToBoxAdapter(
              child: Column(
                children: [
                  const DmOfflineBanner(),
                  const DmScreenHeader(
                    title: 'Delivery & Credit Ledger',
                    subtitle: 'Offline deliveries, customer credit & sales reports',
                  ),
                  Container(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: AppUi.surfaceOf(context),
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
                        borderRadius: BorderRadius.circular(
                          AppUi.radiusControl - 2,
                        ),
                      ),
                      dividerColor: Colors.transparent,
                      tabs: const [
                        Tab(text: 'Credit Ledger'),
                        Tab(text: 'Delivery Logs'),
                        Tab(text: 'Analytics'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          body: TabBarView(
            controller: _tabController,
            children: [
              DmCreditLedgerTab(uuid: _uuid),
              DmDeliveryLogsTab(uuid: _uuid),
              const DmReportsAnalyticsTab(),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TAB 1: CREDIT & UTANG LEDGER
// ─────────────────────────────────────────────────────────────────────────────
class DmCreditLedgerTab extends StatefulWidget {
  final Uuid uuid;
  const DmCreditLedgerTab({super.key, required this.uuid});

  @override
  State<DmCreditLedgerTab> createState() => _DmCreditLedgerTabState();
}

class _DmCreditLedgerTabState extends State<DmCreditLedgerTab> {
  int _filterIndex = 0; // 0 = All, 1 = Customer, 2 = Rider

  @override
  Widget build(BuildContext context) {
    final creditProv = context.watch<CreditProvider>();
    final allCredits = creditProv.credits;
    final filteredCredits = _filterIndex == 0
        ? allCredits
        : _filterIndex == 1
        ? creditProv.customerCredits
        : creditProv.riderCredits;

    final totalOutstanding = filteredCredits.fold<double>(
      0.0,
      (sum, c) => sum + c.remaining,
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppUi.bluePrimary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('New Credit'),
        onPressed: () => _showAddCreditDialog(context),
      ),
      body: RefreshIndicator(
        onRefresh: () => creditProv.loadCredits(),
        child: ListView(
          padding: AppUi.pagePaddingLoose,
          children: [
            // Outstanding Summary Banner
            Container(
              padding: AppUi.cardPadding,
              decoration: BoxDecoration(
                color: AppUi.brandSoftOf(context),
                borderRadius: AppUi.radiusLg,
                border: Border.all(
                  color: AppUi.bluePrimary.withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Total Outstanding Credit',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppUi.textSecondaryOf(context),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        formatPeso(totalOutstanding),
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: AppUi.brandOf(context),
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppUi.surfaceOf(context),
                      borderRadius: BorderRadius.circular(AppUi.radiusSheet),
                      border: Border.all(
                        color: AppUi.bluePrimary.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Text(
                      '${filteredCredits.where((c) => !c.isPaid).length} unpaid',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppUi.brandOf(context),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Segment Filter Chips
            Row(
              children: [
                _buildFilterChip('All (${allCredits.length})', 0),
                const SizedBox(width: 8),
                _buildFilterChip(
                  'Customers (${creditProv.customerCredits.length})',
                  1,
                ),
                const SizedBox(width: 8),
                _buildFilterChip(
                  'Riders (${creditProv.riderCredits.length})',
                  2,
                ),
              ],
            ),
            const SizedBox(height: 14),

            if (creditProv.isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (filteredCredits.isEmpty)
              const Padding(
                padding: EdgeInsets.all(40),
                child: AxoEmptyState(
                  title: 'No credits recorded',
                  message:
                      'Track water credits, customer balances, and rider advances here.',
                ),
              )
            else
              ...filteredCredits.map((credit) => _buildCreditCard(context, credit)),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, int index) {
    final selected = _filterIndex == index;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() => _filterIndex = index),
      selectedColor: AppUi.bluePrimary,
      labelStyle: TextStyle(
        color: selected ? Colors.white : AppUi.textSecondaryOf(context),
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppUi.radiusSheet)),
    );
  }

  Widget _buildCreditCard(BuildContext context, DmCredit credit) {
    final isPaid = credit.isPaid;
    final isPartial = !isPaid && credit.paidAmount > 0;

    final badgeColor = isPaid
        ? AppColors.uiSuccess
        : isPartial
        ? AppColors.uiWarning
        : AppColors.uiError;

    final badgeText = isPaid
        ? 'PAID'
        : isPartial
        ? 'PARTIAL (${formatPeso(credit.remaining, whole: true)} left)'
        : 'UNPAID';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: AppUi.cardPadding,
      decoration: AppUi.cardDecorationOf(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Icon(
                      credit.creditType == CreditType.customer
                          ? Icons.person_outline_rounded
                          : Icons.delivery_dining_outlined,
                      size: 18,
                      color: AppUi.textSecondaryOf(context),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        credit.debtorName.isNotEmpty
                            ? credit.debtorName
                            : (credit.creditType == CreditType.customer
                                ? 'Customer'
                                : 'Rider Advance'),
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                credit.isSynced
                    ? Icons.cloud_done_rounded
                    : Icons.cloud_off_rounded,
                size: 16,
                color: credit.isSynced ? AppColors.uiSuccess : AppColors.uiWarning,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Original: ${formatPeso(credit.amount)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppUi.textSecondaryOf(context),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (credit.paidAmount > 0)
                    Text(
                      'Paid: ${formatPeso(credit.paidAmount)}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppUi.successFg,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppUi.radiusControl),
                ),
                child: Text(
                  badgeText,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: badgeColor,
                  ),
                ),
              ),
            ],
          ),
          if (credit.notes != null && credit.notes!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              credit.notes!,
              style: TextStyle(
                fontSize: 12,
                fontStyle: FontStyle.italic,
                color: AppUi.textSecondaryOf(context),
              ),
            ),
          ],
          if (!isPaid) ...[
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.payments_outlined, size: 16),
                  label: const Text('Record Payment'),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: AppUi.brandOf(context),
                    side: const BorderSide(color: AppUi.bluePrimary),
                  ),
                  onPressed: () => _showRecordPaymentDialog(context, credit),
                ),
                const SizedBox(width: 8),
                FilledButton.tonal(
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    backgroundColor: AppUi.successBg,
                    foregroundColor: AppUi.successFg,
                  ),
                  onPressed: () async {
                    HapticFeedback.lightImpact();
                    await context.read<CreditProvider>().markPaid(credit.id);
                  },
                  child: const Text('Mark Paid'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  void _showRecordPaymentDialog(BuildContext context, DmCredit credit) {
    final amountCtrl = TextEditingController(
      text: credit.remaining.toStringAsFixed(2),
    );
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: AppUi.surfaceOf(dialogCtx),
        title: const Text('Record Payment'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Remaining balance: ${formatPeso(credit.remaining)}'),
            const SizedBox(height: 12),
            AppFormField(
              controller: amountCtrl,
              label: 'Payment Amount (₱)',
              prefixIcon: Icons.payments_rounded,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppUi.bluePrimary,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              final paid = double.tryParse(amountCtrl.text.trim()) ?? 0;
              if (paid > 0) {
                final cappedPaid = paid > credit.remaining ? credit.remaining : paid;
                Navigator.pop(dialogCtx);
                await context.read<CreditProvider>().applyPartialPayment(
                      credit.id,
                      cappedPaid,
                    );
              }
            },
            child: const Text('Confirm'),
          ),
        ],
      ),
    ).whenComplete(() => amountCtrl.dispose());
  }

  void _showAddCreditDialog(BuildContext context) {
    final nameCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    CreditType type = CreditType.customer;

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: AppUi.surfaceOf(dialogCtx),
          title: const Text('Record New Credit / Utang'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: ChoiceChip(
                        label: const Text('Customer'),
                        selected: type == CreditType.customer,
                        onSelected: (_) =>
                            setDialogState(() => type = CreditType.customer),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ChoiceChip(
                        label: const Text('Rider Advance'),
                        selected: type == CreditType.rider,
                        onSelected: (_) =>
                            setDialogState(() => type = CreditType.rider),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                AppFormField(
                  controller: nameCtrl,
                  label: type == CreditType.customer
                      ? 'Customer Name'
                      : 'Rider Name',
                  prefixIcon: Icons.person_outline_rounded,
                ),
                const SizedBox(height: 12),
                AppFormField(
                  controller: amountCtrl,
                  label: 'Credit Amount (₱)',
                  prefixIcon: Icons.payments_outlined,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                ),
                const SizedBox(height: 12),
                AppFormField(
                  controller: notesCtrl,
                  label: 'Notes (optional)',
                  prefixIcon: Icons.notes_rounded,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppUi.bluePrimary,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                final amt = double.tryParse(amountCtrl.text.trim()) ?? 0;
                final name = nameCtrl.text.trim();
                if (amt > 0 && name.isNotEmpty) {
                  final ownerId =
                      Supabase.instance.client.auth.currentUser?.id ??
                      context.read<UserProvider>().user?.id ??
                      '';
                  final newCredit = DmCredit(
                    id: widget.uuid.v4(),
                    ownerId: ownerId,
                    creditType: type,
                    debtorName: name,
                    amount: amt,
                    notes: notesCtrl.text.trim(),
                    createdAt: DateTime.now(),
                    updatedAt: DateTime.now(),
                  );
                  Navigator.pop(dialogCtx);
                  await context.read<CreditProvider>().addCredit(newCredit);
                }
              },
              child: const Text('Save Credit'),
            ),
          ],
        ),
      ),
    ).whenComplete(() {
      nameCtrl.dispose();
      amountCtrl.dispose();
      notesCtrl.dispose();
    });
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TAB 2: OFFLINE DELIVERY LOGS
// ─────────────────────────────────────────────────────────────────────────────
class DmDeliveryLogsTab extends StatelessWidget {
  final Uuid uuid;
  const DmDeliveryLogsTab({super.key, required this.uuid});

  @override
  Widget build(BuildContext context) {
    final delivProv = context.watch<DeliveryProvider>();
    final deliveries = delivProv.deliveries;

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppUi.bluePrimary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_task_rounded),
        label: const Text('Log Delivery'),
        onPressed: () => _showAddDeliveryDialog(context),
      ),
      body: RefreshIndicator(
        onRefresh: () => delivProv.loadDeliveries(),
        child: ListView(
          padding: AppUi.pagePaddingLoose,
          children: [
            if (delivProv.isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (deliveries.isEmpty)
              const Padding(
                padding: EdgeInsets.all(40),
                child: AxoEmptyState(
                  title: 'No manual deliveries logged',
                  message:
                      'Tap Log Delivery to record manual or offline walk-in refills.',
                ),
              )
            else
              ...deliveries.map(
                (d) => Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: AppUi.cardPadding,
                  decoration: AppUi.cardDecorationOf(context),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              d.riderName ?? 'Station Refill',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${d.gallons.toStringAsFixed(0)} gal · ${formatPeso(d.pricePerGallon, whole: true)}/gal',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppUi.textSecondaryOf(context),
                              ),
                            ),
                            if (d.emptyGallonsReturned > 0)
                              Text(
                                'Empties returned: ${d.emptyGallonsReturned.toStringAsFixed(0)}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppUi.brandOf(context),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            formatPeso(d.income),
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: AppUi.brandOf(context),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Icon(
                            d.isSynced
                                ? Icons.cloud_done_rounded
                                : Icons.cloud_off_rounded,
                            size: 16,
                            color: d.isSynced
                                ? AppColors.uiSuccess
                                : AppColors.uiWarning,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  void _showAddDeliveryDialog(BuildContext context) {
    final noteCtrl = TextEditingController();
    final gallonsCtrl = TextEditingController(text: '1');
    final priceCtrl = TextEditingController(text: '25');
    final emptyReturnedCtrl = TextEditingController(text: '1');

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: AppUi.surfaceOf(dialogCtx),
          title: const Text('Log Walk-in / Offline Delivery'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppFormField(
                  controller: noteCtrl,
                  label: 'Customer / Note (optional)',
                  prefixIcon: Icons.notes_rounded,
                ),
                const SizedBox(height: 12),
                AppFormField(
                  controller: gallonsCtrl,
                  label: 'Gallons Delivered',
                  prefixIcon: Icons.water_drop_outlined,
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),
                AppFormField(
                  controller: priceCtrl,
                  label: 'Price per Gallon (₱)',
                  prefixIcon: Icons.payments_outlined,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                ),
                const SizedBox(height: 12),
                AppFormField(
                  controller: emptyReturnedCtrl,
                  label: 'Empty Bottles Returned',
                  prefixIcon: Icons.replay_rounded,
                  keyboardType: TextInputType.number,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppUi.bluePrimary,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                final gallons = double.tryParse(gallonsCtrl.text.trim()) ?? 1;
                final price = double.tryParse(priceCtrl.text.trim()) ?? 25;
                final empties =
                    double.tryParse(emptyReturnedCtrl.text.trim()) ?? 0;
                final ownerId =
                    Supabase.instance.client.auth.currentUser?.id ??
                    context.read<UserProvider>().user?.id ??
                    '';

                final delivery = DmDelivery(
                  id: uuid.v4(),
                  ownerId: ownerId,
                  deliveryDate: DateTime.now(),
                  gallons: gallons,
                  pricePerGallon: price,
                  emptyGallonsReturned: empties,
                  commission: 0,
                  notes: noteCtrl.text.trim(),
                  createdAt: DateTime.now(),
                  updatedAt: DateTime.now(),
                );

                Navigator.pop(dialogCtx);
                await context.read<DeliveryProvider>().addDelivery(
                      delivery: delivery,
                      commissionPerGallon: 0,
                    );
                if (ownerId.isNotEmpty) {
                  unawaited(OwnerInventoryService().recordDeliveryCompletion(
                    ownerId: ownerId,
                    orderId: delivery.id,
                    gallons: gallons.round(),
                    emptyGallonsReturned: empties.round(),
                  ));
                }
              },
              child: const Text('Record Delivery'),
            ),
          ],
        ),
      ),
    ).whenComplete(() {
      noteCtrl.dispose();
      gallonsCtrl.dispose();
      priceCtrl.dispose();
      emptyReturnedCtrl.dispose();
    });
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TAB 3: REPORTS & ANALYTICS
// ─────────────────────────────────────────────────────────────────────────────
class DmReportsAnalyticsTab extends StatelessWidget {
  const DmReportsAnalyticsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final reportProv = context.watch<ReportProvider>();

    return RefreshIndicator(
      onRefresh: () => reportProv.loadReport(),
      child: ListView(
        padding: AppUi.pagePaddingLoose,
        children: [
          // Range Switcher
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildRangeChip(context, reportProv, 'Today', ReportRange.today),
                const SizedBox(width: 8),
                _buildRangeChip(
                  context,
                  reportProv,
                  'This Week',
                  ReportRange.thisWeek,
                ),
                const SizedBox(width: 8),
                _buildRangeChip(
                  context,
                  reportProv,
                  'This Month',
                  ReportRange.thisMonth,
                ),
                const SizedBox(width: 8),
                _buildRangeChip(
                  context,
                  reportProv,
                  'All Time',
                  ReportRange.allTime,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Export PDF Report Banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppUi.brandSoftOf(context),
              borderRadius: BorderRadius.circular(AppUi.radiusControl),
              border: Border.all(color: AppUi.blueBorder),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isNarrow = constraints.maxWidth < 420;
                final actions = Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ElevatedButton.icon(
                      onPressed: () => _exportPdf(context, reportProv, share: false),
                      icon: const Icon(Icons.print_rounded, size: 15),
                      label: const Text('Print/Save'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppUi.bluePrimary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      onPressed: () => _exportPdf(context, reportProv, share: true),
                      icon: const Icon(Icons.share_rounded, size: 18),
                      tooltip: 'Share PDF',
                      color: AppUi.brandOf(context),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                );

                if (isNarrow) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.picture_as_pdf_rounded,
                            color: AppUi.brandOf(context),
                            size: 22,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${_getRangeLabel(reportProv.range)} PDF Report',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: AppUi.brandOf(context),
                                  ),
                                ),
                                Text(
                                  'Official sales, deliveries & tax statement',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AppUi.textMutedOf(context),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      actions,
                    ],
                  );
                }

                return Row(
                  children: [
                    Icon(
                      Icons.picture_as_pdf_rounded,
                      color: AppUi.brandOf(context),
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${_getRangeLabel(reportProv.range)} PDF Report',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppUi.brandOf(context),
                            ),
                          ),
                          Text(
                            'Official sales, deliveries & tax statement',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppUi.textMutedOf(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                    actions,
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 16),

          // Summary Metrics Grid
          Row(
            children: [
              Expanded(
                child: _buildMetricCard(
                  context,
                  title: 'Total Gallons',
                  value: reportProv.totalGallons.toStringAsFixed(0),
                  color: AppUi.bluePrimary,
                  icon: Icons.water_drop_rounded,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMetricCard(
                  context,
                  title: 'Gross Income',
                  value: formatPeso(reportProv.totalIncome, whole: true),
                  color: AppUi.successFg,
                  icon: Icons.payments_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildMetricCard(
                  context,
                  title: 'Deliveries',
                  value: '${reportProv.totalDeliveries}',
                  color: OrderStatusColors.outForDelivery,
                  icon: Icons.local_shipping_rounded,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMetricCard(
                  context,
                  title: 'Net Profit',
                  value: formatPeso(reportProv.netProfit, whole: true),
                  color: AppColors.statusCompleted,
                  icon: Icons.trending_up_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Daily Volume / Income Chart
          Container(
            padding: AppUi.cardPadding,
            decoration: AppUi.cardDecorationOf(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Daily Income Trend',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 16),
                DmBarChart(points: reportProv.dailySeries),
              ],
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildRangeChip(
    BuildContext context,
    ReportProvider prov,
    String label,
    ReportRange range,
  ) {
    final selected = prov.range == range;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => prov.setRange(range),
      selectedColor: AppUi.bluePrimary,
      labelStyle: TextStyle(
        color: selected ? Colors.white : AppUi.textSecondaryOf(context),
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  Widget _buildMetricCard(
    BuildContext context, {
    required String title,
    required String value,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: AppUi.cardPadding,
      decoration: AppUi.cardDecorationOf(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppUi.textSecondaryOf(context),
                ),
              ),
              Icon(icon, size: 18, color: color),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  String _getRangeLabel(ReportRange range) {
    switch (range) {
      case ReportRange.today:
        return 'Today';
      case ReportRange.thisWeek:
        return 'This Week';
      case ReportRange.thisMonth:
        return 'This Month';
      case ReportRange.thisYear:
        return 'This Year';
      case ReportRange.allTime:
        return 'All Time';
      case ReportRange.custom:
        return 'Custom Range';
    }
  }

  Future<void> _exportPdf(
    BuildContext context,
    ReportProvider reportProv, {
    required bool share,
  }) async {
    final user = context.read<UserProvider>().user;
    final stationName = user?.stationName ?? 'eRefill Water Station';
    final stationAddress = user?.completeAddress ??
        '${user?.barangay ?? ''}, ${user?.town ?? 'Surigao del Sur'}';
    final stationPhone = user?.phone;
    final rangeLabel = _getRangeLabel(reportProv.range);

    final dailyBreakdown = reportProv.dailySeries
        .map((d) => {
              'date': d.date,
              'gallons': d.gallons,
              'income': d.income,
            })
        .toList();

    final riderStats = reportProv.leaderboard
        .map((r) => {
              'name': r.rider.fullName,
              'count': r.deliveryCount,
              'gallons': r.totalGallons,
              'commission': r.totalCommission,
            })
        .toList();

    if (share) {
      await ReportExportService.shareReport(
        context: context,
        stationName: stationName,
        stationAddress: stationAddress,
        stationPhone: stationPhone,
        rangeLabel: rangeLabel,
        totalDeliveries: reportProv.totalDeliveries,
        totalGallons: reportProv.totalGallons,
        totalIncome: reportProv.totalIncome,
        totalExpenses: reportProv.totalExpenses,
        totalCommission: reportProv.totalCommission,
        netProfit: reportProv.netProfit,
        dailyBreakdown: dailyBreakdown,
        riderStats: riderStats,
      );
    } else {
      await ReportExportService.printReport(
        context: context,
        stationName: stationName,
        stationAddress: stationAddress,
        stationPhone: stationPhone,
        rangeLabel: rangeLabel,
        totalDeliveries: reportProv.totalDeliveries,
        totalGallons: reportProv.totalGallons,
        totalIncome: reportProv.totalIncome,
        totalExpenses: reportProv.totalExpenses,
        totalCommission: reportProv.totalCommission,
        netProfit: reportProv.netProfit,
        dailyBreakdown: dailyBreakdown,
        riderStats: riderStats,
      );
    }
  }
}
