import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:erefill/core/constants.dart';
import 'package:erefill/core/widgets/brand/hero_header.dart';
import 'package:erefill/core/widgets/brand/axo_states.dart';
import 'package:erefill/core/db_tables.dart';
import 'package:erefill/core/utils/order_product_helpers.dart';
import 'package:erefill/core/water_types.dart';
import 'package:erefill/core/widgets/refill_status_widgets.dart';
import 'package:erefill/core/utils/friendly_errors.dart';
import 'package:erefill/core/utils/money.dart';

/// The station's single product: a refill of the water type picked at
/// registration. Owners set its price and availability; only an admin can
/// change the water type.
class ServiceCatalogScreen extends StatefulWidget {
  final bool isPopup;

  const ServiceCatalogScreen({super.key, this.isPopup = false});

  @override
  State<ServiceCatalogScreen> createState() => _ServiceCatalogScreenState();
}

class _ServiceCatalogScreenState extends State<ServiceCatalogScreen> {
  final supabase = Supabase.instance.client;
  final _priceController = TextEditingController();
  final _priceFocus = FocusNode();

  bool _isLoading = true;
  bool _isSaving = false;
  Object? _loadError;
  Map<String, dynamic>? _product;
  WaterTypeInfo? _waterType;

  double get _savedPrice => (_product?['price'] as num?)?.toDouble() ?? 0;
  bool get _isAvailable => _product?['is_available'] != false;

  double? get _enteredPrice =>
      double.tryParse(_priceController.text.trim().replaceAll(',', ''));

  bool get _priceChanged {
    final entered = _enteredPrice;
    return entered != null && (entered - _savedPrice).abs() >= 0.005;
  }

  @override
  void initState() {
    super.initState();
    _priceController.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _priceController.dispose();
    _priceFocus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final results = await Future.wait([
        supabase
            .from('profiles')
            .select('primary_water_type')
            .eq('id', user.id)
            .maybeSingle(),
        OrderProductHelpers.ensureStationProduct(supabase, user.id),
        WaterTypes.load(),
      ]);
      final profile = results[0] as Map<String, dynamic>?;
      final product = results[1] as Map<String, dynamic>?;
      if (!mounted) return;
      setState(() {
        _waterType = WaterTypes.byName(
          profile?['primary_water_type']?.toString() ??
              product?['water_type']?.toString(),
        );
        _product = product;
        _priceController.text = product == null
            ? ''
            : _savedPriceText((product['price'] as num?)?.toDouble() ?? 0);
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e;
        _isLoading = false;
      });
    }
  }

  String _savedPriceText(double price) =>
      price == price.roundToDouble() ? price.toStringAsFixed(0) : price.toStringAsFixed(2);

  Future<void> _update(Map<String, dynamic> changes, String doneMessage) async {
    final id = _product?['id']?.toString();
    if (id == null) return;
    setState(() => _isSaving = true);
    try {
      final updated = await supabase
          .from(DbTables.waterOptions)
          .update(changes)
          .eq('id', id)
          .select(OrderProductHelpers.catalogSelectFields)
          .single();
      if (!mounted) return;
      setState(() {
        _product = Map<String, dynamic>.from(updated);
        _isSaving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(doneMessage)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(FriendlyErrors.message(e)),
          backgroundColor: AppColors.uiError,
        ),
      );
    }
  }

  Future<void> _savePrice() async {
    final price = _enteredPrice;
    if (price == null || price <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a price greater than ₱0.')),
      );
      return;
    }
    _priceFocus.unfocus();
    await _update({'price': price}, 'Price updated to ${formatPeso(price)}');
    if (mounted) _priceController.text = _savedPriceText(_savedPrice);
  }

  Future<void> _toggleAvailability(bool available) => _update(
        {'is_available': available},
        available
            ? 'Customers can order your water again'
            : 'Paused. Customers can\'t order until you turn it back on',
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppUi.pageBgOf(context),
      body: Column(
        children: [
          TabScreenHeroHeader(
            title: 'Your water',
            subtitle: 'The one product your station sells',
            leading: widget.isPopup
                ? IconButton(
                    icon: const Icon(Icons.close_rounded),
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white
                        : AppUi.textPrimary,
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(context),
                  )
                : null,
          ),
          Expanded(child: _buildBody(context)),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_isLoading) {
      return const AxoLoader(message: 'Loading your water...');
    }
    if (_loadError != null || _product == null || _waterType == null) {
      return AxoEmptyState(
        pose: AxoPose.thinking,
        compact: true,
        title: _loadError != null
            ? "Couldn't load your water"
            : 'Your station has no water type yet',
        message: _loadError != null
            ? FriendlyErrors.message(_loadError!)
            : 'Ask an eRefill admin to set the water type for your station.',
        actionLabel: 'Try again',
        onAction: _load,
      );
    }

    final type = _waterType!;
    final stock = (_product!['stock_level'] as num?)?.toInt();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: AppUi.pagePadding,
        children: [
          WaterTypeCard(
            type: type,
            description: type.description,
            price: _savedPrice,
            available: _isAvailable,
          ),
          _SectionCard(
            title: 'Price per gallon',
            subtitle: 'Customers pay this for each refill, plus delivery.',
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _priceController,
                    focusNode: _priceFocus,
                    enabled: !_isSaving,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                    ],
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _priceChanged ? _savePrice() : null,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: AppUi.textPrimaryOf(context),
                    ),
                    decoration: AppUi.fieldDecorationOf(context, '0').copyWith(
                      prefixText: '₱ ',
                      suffixText: '/ gallon',
                    ),
                  ),
                ),
                const SizedBox(width: AppUi.spacingSm),
                SizedBox(
                  height: 56,
                  child: FilledButton(
                    onPressed: _priceChanged && !_isSaving ? _savePrice : null,
                    child: _isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Save'),
                  ),
                ),
              ],
            ),
          ),
          _SectionCard(
            title: 'Taking orders',
            subtitle: _isAvailable
                ? 'Customers can order ${type.name.toLowerCase()} now.'
                : 'Paused. Your station page shows it as unavailable.',
            trailing: Switch.adaptive(
              value: _isAvailable,
              onChanged: _isSaving ? null : _toggleAvailability,
            ),
            child: stock == null
                ? null
                : Text(
                    '$stock filled gallons in stock',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppUi.textSecondaryOf(context),
                    ),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppUi.spacingSm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 16,
                  color: AppUi.textSecondaryOf(context),
                ),
                const SizedBox(width: AppUi.spacingSm),
                Expanded(
                  child: Text(
                    'Your station sells ${type.name}, the water type you chose '
                    'at registration. To switch to a different water type, '
                    'contact an eRefill admin.',
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.4,
                      color: AppUi.textSecondaryOf(context),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.subtitle,
    this.trailing,
    this.child,
  });

  final String title;
  final String subtitle;
  final Widget? trailing;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppUi.surfaceOf(context),
        borderRadius: AppUi.cardRadius,
        border: Border.all(color: AppUi.borderOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppUi.textPrimaryOf(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        color: AppUi.textSecondaryOf(context),
                      ),
                    ),
                  ],
                ),
              ),
              ?trailing,
            ],
          ),
          if (child != null) ...[
            const SizedBox(height: 12),
            child!,
          ],
        ],
      ),
    );
  }
}
