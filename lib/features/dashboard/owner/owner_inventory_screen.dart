import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:erefill/core/constants.dart';
import 'package:erefill/core/services/owner_inventory_service.dart';
import 'package:erefill/core/widgets/brand/hero_header.dart';
import 'package:erefill/core/widgets/brand/axo_states.dart';
import 'package:erefill/core/widgets/skeleton.dart';
import 'package:erefill/core/water_types.dart';

import 'package:erefill/core/theme/app_colors.dart';
class OwnerInventoryScreen extends StatefulWidget {
  final bool embedded;
  final VoidCallback? onSwitchToCredits;

  const OwnerInventoryScreen({
    super.key,
    this.embedded = false,
    this.onSwitchToCredits,
  });

  @override
  State<OwnerInventoryScreen> createState() => _OwnerInventoryScreenState();
}

class _OwnerInventoryScreenState extends State<OwnerInventoryScreen> {
  final _service = OwnerInventoryService();
  final _supabase = Supabase.instance.client;

  OwnerInventorySnapshot? _snapshot;
  Stream<List<Map<String, dynamic>>>? _ledgerStream;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    final ownerId = _supabase.auth.currentUser?.id;
    if (ownerId != null) {
      _ledgerStream = _service.ledgerStream(ownerId);
    }
    _load();
  }

  Future<void> _load() async {
    final ownerId = _supabase.auth.currentUser?.id;
    if (ownerId == null) {
      setState(() {
        _isLoading = false;
        _error = 'Sign in as a station owner to manage inventory.';
      });
      return;
    }

    setState(() {
      _isLoading = _snapshot == null;
      _error = null;
    });

    try {
      final snapshot = await _service.fetchSnapshot(ownerId);
      if (mounted) {
        setState(() {
          _snapshot = snapshot;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _showTxSheet({
    required String title,
    required String txType,
    required bool needsProduct,
    bool allowNegative = false,
  }) async {
    final snapshot = _snapshot;
    if (snapshot == null) return;

    final gallonsCtrl = TextEditingController(text: '1');
    final notesCtrl = TextEditingController();
    String? productId = snapshot.products.isNotEmpty
        ? snapshot.products.first['id']?.toString()
        : null;

    final submitted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppUi.surfaceOf(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppUi.radiusSheet)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(
          24,
          24,
          24,
          MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: StatefulBuilder(
          builder: (context, setSheetState) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppUi.textPrimaryOf(context),
                ),
              ),
              const SizedBox(height: 16),
              if (needsProduct && snapshot.products.isNotEmpty) ...[
                DropdownButtonFormField<String>(
                  initialValue: snapshot.products
                          .any((p) => p['id']?.toString() == productId)
                      ? productId
                      : snapshot.products.first['id']?.toString(),
                  decoration: AppUi.fieldDecorationOf(context, 'Product'),
                  items: snapshot.products
                      .map(
                        (p) => DropdownMenuItem(
                          value: p['id']?.toString(),
                          child: Text(
                            WaterTypes.byName(
                              p['category']?.toString() ??
                                  p['name']?.toString(),
                            ).shortName,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setSheetState(() => productId = v),
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: gallonsCtrl,
                keyboardType: TextInputType.number,
                decoration: AppUi.fieldDecorationOf(
                  context,
                  allowNegative ? 'Gallons (+/-)' : 'Gallons',
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [5, 10, 25, 50].map((batch) {
                  return ActionChip(
                    visualDensity: VisualDensity.compact,
                    label: Text('+$batch'),
                    labelStyle: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppUi.brandOf(context),
                    ),
                    backgroundColor: AppUi.brandSoftOf(context),
                    side: BorderSide.none,
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      final current =
                          int.tryParse(gallonsCtrl.text.trim()) ?? 0;
                      setSheetState(() {
                        gallonsCtrl.text = '${current + batch}';
                      });
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: notesCtrl,
                maxLines: 2,
                decoration: AppUi.fieldDecorationOf(context, 'Notes (optional)'),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Save'),
              ),
            ],
          ),
        ),
      ),
    );

    if (submitted != true || !mounted) return;

    final gallons = int.tryParse(gallonsCtrl.text.trim());
    if (gallons == null || gallons == 0) {
      _showSnack('Enter a valid gallon amount.');
      return;
    }

    final error = await _service.logTransaction(
      txType: txType,
      gallons: gallons,
      notes: notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
      productId: needsProduct ? productId : null,
    );

    if (!mounted) return;
    if (error != null) {
      _showSnack(error, isError: true);
      return;
    }

    _showSnack('Inventory updated.');
    await _load();
  }

  void _showSnack(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.uiError : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ownerId = _supabase.auth.currentUser?.id;

    final body = RefreshIndicator(
      onRefresh: _load,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: ClampingScrollPhysics(),
        ),
        slivers: [
          if (_isLoading)
            const SliverFillRemaining(child: SkeletonList(itemCount: 4))
          else if (_error != null)
            SliverFillRemaining(
              child: AxoEmptyState(
                pose: AxoPose.thinking,
                title: 'Could not load inventory',
                message: _error!,
                actionLabel: 'Retry',
                onAction: _load,
                compact: true,
              ),
            )
          else ...[
            SliverPadding(
              padding: AppUi.pagePaddingLoose.copyWith(top: 0),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  _buildStockCards(_snapshot!),
                  const SizedBox(height: 16),
                  _buildActions(_snapshot!),
                  if (_snapshot!.products.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Text('Product stock', style: AppUi.sectionTitle),
                    const SizedBox(height: 10),
                    ..._snapshot!.products.map(_buildProductRow),
                  ],
                  const SizedBox(height: 24),
                  Text('Recent activity', style: AppUi.sectionTitle),
                  const SizedBox(height: 10),
                ]),
              ),
            ),
            if (ownerId != null && _ledgerStream != null)
              SliverPadding(
                padding: AppUi.pagePaddingLoose.copyWith(top: 0),
                sliver: StreamBuilder<List<Map<String, dynamic>>>(
                  stream: _ledgerStream,
                  builder: (context, snapshot) {
                    final rows = snapshot.data ?? [];
                    if (rows.isEmpty) {
                      return SliverToBoxAdapter(
                        child: AxoEmptyState(
                          pose: AxoPose.empty,
                          title: 'No inventory activity yet',
                          message:
                              'Loads, adjustments, and empty returns will appear here.',
                          compact: true,
                        ),
                      );
                    }
                    return SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) =>
                            _LedgerTile(row: rows[index]),
                        childCount: rows.length.clamp(0, 20),
                      ),
                    );
                  },
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
        ],
      ),
    );

    if (widget.embedded) {
      return body;
    }

    return Scaffold(
      backgroundColor: AppUi.pageBgOf(context),
      body: Column(
        children: [
          const TabScreenHeroHeader(
            title: 'Inventory',
            subtitle: 'Filled stock, empty containers, and returns',
          ),
          Expanded(child: body),
        ],
      ),
    );
  }

  Widget _buildStockCards(OwnerInventorySnapshot snapshot) {
    return Row(
      children: [
        Expanded(
          child: _StockCard(
            label: 'Filled gallons',
            value: '${snapshot.filledGallons}',
            icon: Icons.water_drop_rounded,
            color: AppUi.bluePrimary,
            warning: snapshot.hasLowFilledStock ? 'Low stock' : null,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StockCard(
            label: 'Empty containers',
            value: '${snapshot.emptyGallons}',
            icon: Icons.inventory_2_outlined,
            color: AppColors.statusReady,
          ),
        ),
      ],
    );
  }

  Widget _buildActions(OwnerInventorySnapshot snapshot) {
    final hasProducts = snapshot.products.isNotEmpty;
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.water_drop_rounded, size: 16),
                label: const Text('Load Filled'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppUi.brandOf(context),
                  side: const BorderSide(color: AppUi.bluePrimary),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppUi.radiusControl),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 11),
                ),
                onPressed: hasProducts
                    ? () => _showTxSheet(
                        title: 'Load filled gallons',
                        txType: 'load_filled',
                        needsProduct: true,
                      )
                    : null,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.replay_rounded, size: 16),
                label: const Text('Load Empty'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.statusReady,
                  side: const BorderSide(color: AppColors.statusReady),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppUi.radiusControl),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 11),
                ),
                onPressed: () => _showTxSheet(
                  title: 'Load empty containers',
                  txType: 'load_empty',
                  needsProduct: false,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.tune_rounded, size: 16),
                label: const Text('Adjust Filled'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppUi.textSecondaryOf(context),
                  side: BorderSide(color: AppUi.borderOf(context)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppUi.radiusControl),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
                onPressed: hasProducts
                    ? () => _showTxSheet(
                        title: 'Adjust filled stock',
                        txType: 'adjust_filled',
                        needsProduct: true,
                        allowNegative: true,
                      )
                    : null,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.tune_rounded, size: 16),
                label: const Text('Adjust Empty'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppUi.textSecondaryOf(context),
                  side: BorderSide(color: AppUi.borderOf(context)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppUi.radiusControl),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
                onPressed: () => _showTxSheet(
                  title: 'Adjust empty stock',
                  txType: 'adjust_empty',
                  needsProduct: false,
                  allowNegative: true,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildProductRow(Map<String, dynamic> product) {
    final stock = (product['stock_level'] as num?)?.toInt() ?? 0;
    final threshold = (product['low_stock_threshold'] as num?)?.toInt() ?? 10;
    final label = WaterTypes.byName(
      product['category']?.toString() ?? product['name']?.toString(),
    ).shortName;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: AppUi.cardDecorationOf(context),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: AppUi.textPrimaryOf(context),
              ),
            ),
          ),
          Text(
            '$stock gal',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: stock <= threshold
                  ? AppColors.uiWarning
                  : AppUi.textPrimaryOf(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _StockCard extends StatelessWidget {
  const _StockCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.warning,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final String? warning;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppUi.cardDecorationOf(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(height: 12),
          Text(label, style: AppUi.captionText),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: AppUi.textPrimaryOf(context),
            ),
          ),
          if (warning != null) ...[
            const SizedBox(height: 6),
            Text(
              warning!,
              style: TextStyle(
                color: AppColors.uiWarning,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _LedgerTile extends StatelessWidget {
  const _LedgerTile({required this.row});

  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final txType = row['tx_type']?.toString();
    final gallons = (row['gallons'] as num?)?.toInt() ?? 0;
    final notes = row['notes']?.toString();
    final createdAt = row['created_at']?.toString() ?? '';
    final isReturn = txType == 'empty_return';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: AppUi.cardDecorationOf(context),
      child: Row(
        children: [
          Icon(
            isReturn ? Icons.recycling_rounded : Icons.swap_vert_rounded,
            color: isReturn ? AppColors.statusReady : AppUi.brandOf(context),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  OwnerInventoryService.labelForTxType(txType),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppUi.textPrimaryOf(context),
                  ),
                ),
                if (notes != null && notes.isNotEmpty)
                  Text(notes, style: AppUi.captionText),
                if (createdAt.isNotEmpty)
                  Text(createdAt.split('T').first, style: AppUi.captionText),
              ],
            ),
          ),
          Text(
            '${gallons >= 0 ? '+' : ''}$gallons',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: gallons >= 0
                  ? AppColors.statusReady
                  : AppColors.uiWarning,
            ),
          ),
        ],
      ),
    );
  }
}
