import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:erefill/core/constants.dart';
import 'package:erefill/core/widgets/brand/hero_header.dart';
import 'package:erefill/core/widgets/brand/axo_states.dart';
import 'package:erefill/core/db_tables.dart';
import 'package:erefill/core/utils/order_product_helpers.dart';
import 'package:erefill/core/water_types.dart';
import 'package:erefill/core/widgets/refill_status_widgets.dart';
import 'package:erefill/core/widgets/app_form_fields.dart';
import 'package:erefill/core/utils/friendly_errors.dart';
import 'services/station_setup_service.dart';

class ServiceCatalogScreen extends StatefulWidget {
  final bool isPopup;

  const ServiceCatalogScreen({super.key, this.isPopup = false});

  @override
  State<ServiceCatalogScreen> createState() => _ServiceCatalogScreenState();
}

class _ServiceCatalogScreenState extends State<ServiceCatalogScreen> {
  final supabase = Supabase.instance.client;
  final _setupService = StationSetupService();
  bool _isLoading = true;
  List<Map<String, dynamic>> _services = [];
  String _searchQuery = '';
  WaterTypeInfo _ownerWaterType = WaterTypes.purified;
  int _selectedTabIndex = 0; // 0 = Water Refills, 1 = Containers & Accessories
  bool _isSeeding = false;

  @override
  void initState() {
    super.initState();
    _loadServices();
  }

  Future<void> _loadServices() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      final profile = await supabase
          .from('profiles')
          .select('primary_water_type')
          .eq('id', user.id)
          .maybeSingle();

      final services = await supabase
          .from(DbTables.waterOptions)
          .select(OrderProductHelpers.catalogSelectFields)
          .eq('owner_id', user.id)
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _ownerWaterType = WaterTypes.byName(
            profile?['primary_water_type']?.toString(),
          );
          _services = List<Map<String, dynamic>>.from(services);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading services: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  bool _isRefillProduct(Map<String, dynamic> item) {
    final cat = (item['category']?.toString() ?? '').toLowerCase();
    final name = (item['name']?.toString() ?? '').toLowerCase();
    if (cat.contains('accessories') ||
        cat.contains('products') ||
        name.contains('container') ||
        name.contains('cap')) {
      return false;
    }
    return true;
  }

  List<Map<String, dynamic>> get _filteredServices {
    return _services.where((s) {
      final matchesTab = _selectedTabIndex == 0
          ? _isRefillProduct(s)
          : !_isRefillProduct(s);

      if (!matchesTab) return false;

      if (_searchQuery.isEmpty) return true;
      final query = _searchQuery.toLowerCase();
      return (s['name']?.toString().toLowerCase().contains(query) ?? false) ||
          (s['description']?.toString().toLowerCase().contains(query) ??
              false) ||
          (s['category']?.toString().toLowerCase().contains(query) ?? false) ||
          (s['price']?.toString().contains(query) ?? false);
    }).toList();
  }

  Map<String, dynamic>? get _registeredTypeService {
    for (final service in _services) {
      final type = WaterTypes.byName(
        service['category']?.toString() ?? service['name']?.toString(),
      );
      if (type.shortName == _ownerWaterType.shortName) return service;
    }
    return null;
  }

  Future<void> _toggleServiceStatus(String serviceId, bool isActive) async {
    try {
      await supabase
          .from(DbTables.waterOptions)
          .update({'is_available': !isActive})
          .eq('id', serviceId);

      await _loadServices();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isActive ? 'Product marked unavailable' : 'Product marked available',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _seedStandardProducts() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    setState(() => _isSeeding = true);
    try {
      await _setupService.seedStandardProducts(user.id);
      await _loadServices();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Standard container and cap added to catalog.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not seed products: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSeeding = false);
    }
  }

  void _showAddDialog() {
    if (_selectedTabIndex == 0) {
      final existing = _registeredTypeService;
      if (existing != null) {
        _showEditServiceDialog(existing);
      } else {
        showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (context) => AddServiceDialog(waterType: _ownerWaterType),
        ).then((_) => _loadServices());
      }
    } else {
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => const AddCustomProductDialog(),
      ).then((_) => _loadServices());
    }
  }

  void _showEditServiceDialog(Map<String, dynamic> service) {
    if (_isRefillProduct(service)) {
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) =>
            EditServiceDialog(service: service, waterType: _ownerWaterType),
      ).then((_) => _loadServices());
    } else {
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => EditCustomProductDialog(product: service),
      ).then((_) => _loadServices());
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredServices;
    final refillCount = _services.where(_isRefillProduct).length;
    final accessoryCount = _services.where((s) => !_isRefillProduct(s)).length;

    return Scaffold(
      backgroundColor: AppUi.pageBgOf(context),
      body: Column(
        children: [
          TabScreenHeroHeader(
            title: 'Water products & catalog',
            subtitle: 'Refill options, containers, and station accessories',
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
            actions: [
              if (_selectedTabIndex == 1 && accessoryCount < 2)
                IconButton(
                  onPressed: _isSeeding ? null : _seedStandardProducts,
                  tooltip: 'Add standard container & cap',
                  icon: _isSeeding
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Container(
                          padding: const EdgeInsets.all(AppUi.spacingXs),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF3E8FF),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.auto_awesome_rounded,
                            color: Color(0xFF8B5CF6),
                            size: 20,
                          ),
                        ),
                ),
              IconButton(
                onPressed: _showAddDialog,
                tooltip: _selectedTabIndex == 0 ? 'Set refill price' : 'Add product',
                icon: Container(
                  padding: const EdgeInsets.all(AppUi.spacingXs),
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white.withValues(alpha: 0.12)
                        : AppUi.blueSoft,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.add,
                    color: AppUi.bluePrimary,
                    size: 20,
                  ),
                ),
              ),
            ],
            bottom: Column(
              children: [
                // Segmented Tab Bar
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: AppUi.surfaceOf(context),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppUi.borderOf(context)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _buildTabPill(
                          index: 0,
                          title: 'Water Refills ($refillCount)',
                          icon: Icons.water_drop_outlined,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: _buildTabPill(
                          index: 1,
                          title: 'Containers & Caps ($accessoryCount)',
                          icon: Icons.inventory_2_outlined,
                        ),
                      ),
                    ],
                  ),
                ),
                // Search Field
                TextField(
                  onChanged: (v) => setState(() => _searchQuery = v),
                  style: TextStyle(color: AppUi.textPrimaryOf(context)),
                  decoration: InputDecoration(
                    hintText: _selectedTabIndex == 0
                        ? 'Search refill pricing or notes'
                        : 'Search containers, caps, or prices',
                    hintStyle: TextStyle(
                      color: AppUi.textSecondaryOf(context),
                    ),
                    prefixIcon: Icon(
                      Icons.search,
                      color: AppUi.textSecondaryOf(context),
                    ),
                    filled: true,
                    fillColor: AppUi.surfaceOf(context),
                    border: OutlineInputBorder(
                      borderRadius: AppUi.pillRadius,
                      borderSide: BorderSide(color: AppUi.borderOf(context)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: AppUi.pillRadius,
                      borderSide: BorderSide(color: AppUi.borderOf(context)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: AppUi.pillRadius,
                      borderSide: const BorderSide(color: AppUi.bluePrimary, width: 2),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const AxoLoader(message: 'Loading product catalog...')
                : filtered.isEmpty
                    ? _buildEmptyState()
                    : ListView.builder(
                        padding: AppUi.pagePadding,
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final service = filtered[index];
                          if (_selectedTabIndex == 0) {
                            return _buildRefillCard(service);
                          } else {
                            return _buildAccessoryCard(service);
                          }
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabPill({
    required int index,
    required String title,
    required IconData icon,
  }) {
    final isSelected = _selectedTabIndex == index;
    return InkWell(
      onTap: () => setState(() => _selectedTabIndex = index),
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppUi.bluePrimary : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? Colors.white : AppUi.textSecondaryOf(context),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                title,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                  color: isSelected ? Colors.white : AppUi.textSecondaryOf(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    if (_selectedTabIndex == 0) {
      return AxoEmptyState(
        pose: AxoPose.thinking,
        compact: true,
        title: 'No refill price configured',
        message: 'Set your ${_ownerWaterType.name.toLowerCase()} refill price so customers can order refills.',
        actionLabel: 'Set Refill Price',
        onAction: _showAddDialog,
      );
    } else {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: const Color(0xFFF3E8FF),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(
                  Icons.inventory_2_outlined,
                  color: Color(0xFF8B5CF6),
                  size: 32,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'No containers or accessories yet',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: AppUi.textPrimaryOf(context),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Offer empty 5-gallon containers and non-spill replacement caps to increase order volume.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: AppUi.textSecondaryOf(context),
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  FilledButton.icon(
                    onPressed: _isSeeding ? null : _seedStandardProducts,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF8B5CF6),
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                    label: const Text('Add 5-Gal Container & Cap'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _showAddDialog,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add Custom Item'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }
  }

  Widget _buildRefillCard(Map<String, dynamic> service) {
    final isActive = service['is_available'] ?? true;
    final price = (service['price'] as num?)?.toDouble() ?? 0;
    final waterType = WaterTypes.byName(
      service['category']?.toString() ?? service['name']?.toString(),
    );
    final containerSize = service['container_size']?.toString() ?? '5 gallon';
    final preparationMinutes = (service['preparation_minutes'] as num?)?.toInt() ?? 15;

    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.only(right: 44, bottom: 12),
          child: WaterTypeCard(
            type: waterType,
            description: service['description']?.toString() ?? waterType.description,
            price: price,
            containerSize: containerSize,
            preparationMinutes: preparationMinutes,
            available: isActive,
            onTap: () => _showEditServiceDialog(service),
          ),
        ),
        Positioned(
          top: 8,
          right: 0,
          child: _buildProductMenu(service, isActive),
        ),
      ],
    );
  }

  Widget _buildAccessoryCard(Map<String, dynamic> item) {
    final isActive = item['is_available'] ?? true;
    final price = (item['price'] as num?)?.toDouble() ?? 0;
    final name = item['name']?.toString() ?? 'Accessory';
    final category = item['category']?.toString() ?? 'Accessories';
    final containerSize = item['container_size']?.toString() ?? 'Piece';
    final stockLevel = (item['stock_level'] as num?)?.toInt() ?? 100;
    final description = item['description']?.toString() ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppUi.surfaceOf(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isActive ? AppUi.borderOf(context) : AppUi.borderOf(context).withValues(alpha: 0.5),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showEditServiceDialog(item),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Product Icon
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3E8FF),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.inventory_2_outlined,
                    color: Color(0xFF8B5CF6),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),

                // Name, details, stock
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              name,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: isActive
                                    ? AppUi.textPrimaryOf(context)
                                    : AppUi.textMuted,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppUi.chipBgOf(context),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              category,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppUi.textSecondaryOf(context),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: stockLevel > 10
                                  ? const Color(0xFFECFDF5)
                                  : const Color(0xFFFEF2F2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '$stockLevel in stock ($containerSize)',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: stockLevel > 10
                                    ? const Color(0xFF047857)
                                    : const Color(0xFFB91C1C),
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (description.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: AppUi.textSecondaryOf(context),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // Price & Actions
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '₱${price.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                        color: isActive ? AppUi.bluePrimary : AppUi.textMuted,
                      ),
                    ),
                    const SizedBox(height: 4),
                    _buildProductMenu(item, isActive),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProductMenu(Map<String, dynamic> item, bool isActive) {
    return PopupMenuButton<String>(
      onSelected: (value) {
        if (value == 'edit') {
          _showEditServiceDialog(item);
        } else if (value == 'toggle') {
          _toggleServiceStatus(item['id'], isActive);
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'edit',
          child: Row(
            children: [
              Icon(Icons.edit, size: 18),
              SizedBox(width: AppUi.spacingSm),
              Text('Edit Details & Price'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'toggle',
          child: Row(
            children: [
              Icon(
                isActive ? Icons.visibility_off : Icons.visibility,
                size: 18,
              ),
              AppUi.hGapSm,
              Text(isActive ? 'Mark unavailable' : 'Mark available'),
            ],
          ),
        ),
      ],
    );
  }
}

// ── ADD / EDIT REFILL WATER DIALOGS ──────────────────────────────────────────

class AddServiceDialog extends StatefulWidget {
  final WaterTypeInfo waterType;

  const AddServiceDialog({super.key, required this.waterType});

  @override
  State<AddServiceDialog> createState() => _AddServiceDialogState();
}

class _AddServiceDialogState extends State<AddServiceDialog> {
  final _formKey = GlobalKey<FormState>();
  final _descriptionController = TextEditingController();
  final _priceController = TextEditingController();
  final _containerController = TextEditingController(text: '5 gallon');
  final _preparationController = TextEditingController(text: '15');
  bool _isActive = true;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _descriptionController.text = widget.waterType.description;
  }

  Future<void> _saveService() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;
      if (user == null) throw 'User not authenticated';

      final waterType = widget.waterType;

      await OrderProductHelpers.insertProduct(supabase, {
        'owner_id': user.id,
        'name': waterType.name,
        'description': _descriptionController.text.trim().isEmpty
            ? waterType.description
            : _descriptionController.text.trim(),
        'price': double.parse(_priceController.text),
        'category': waterType.shortName,
        'container_size': _containerController.text.trim(),
        'preparation_minutes': int.parse(_preparationController.text),
        'is_available': _isActive,
        'created_at': DateTime.now().toIso8601String(),
      });

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(FriendlyErrors.message(e))));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        decoration: BoxDecoration(
          color: AppUi.surfaceOf(context),
          borderRadius: AppUi.radiusSheetTop,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppUi.dividerOf(context),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Add Refill Pricing',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppUi.textPrimaryOf(context),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppUi.blueSoft,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppUi.bluePrimary.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.water_drop_rounded,
                              color: AppUi.bluePrimary,
                              size: 24,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.waterType.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15,
                                    ),
                                  ),
                                  Text(
                                    'Standard water refill option',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AppUi.textSecondaryOf(context),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      AppFormField(
                        controller: _descriptionController,
                        label: 'Description',
                        icon: Icons.description_outlined,
                        maxLines: 2,
                        compact: true,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: AppFormField(
                              controller: _priceController,
                              label: 'Price / Gallon (₱)',
                              icon: Icons.payments_outlined,
                              keyboardType: TextInputType.number,
                              compact: true,
                              validator: (v) {
                                final p = double.tryParse(v ?? '');
                                return (p == null || p <= 0) ? 'Enter valid price' : null;
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: AppFormField(
                              controller: _containerController,
                              label: 'Container Size',
                              icon: Icons.local_drink_outlined,
                              compact: true,
                              validator: (v) =>
                                  v?.trim().isEmpty == true ? 'Required' : null,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      AppFormField(
                        controller: _preparationController,
                        label: 'Prep Time (minutes)',
                        icon: Icons.timer_outlined,
                        keyboardType: TextInputType.number,
                        compact: true,
                      ),
                      const SizedBox(height: 12),
                      SwitchListTile(
                        title: const Text('Available for ordering'),
                        value: _isActive,
                        activeThumbColor: AppUi.bluePrimary,
                        onChanged: (v) => setState(() => _isActive = v),
                      ),
                      const SizedBox(height: 20),
                      AppFormSubmitButton(
                        text: 'Save Refill Price',
                        isLoading: _isLoading,
                        onPressed: _saveService,
                        icon: Icons.save_rounded,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _priceController.dispose();
    _containerController.dispose();
    _preparationController.dispose();
    super.dispose();
  }
}

class EditServiceDialog extends StatefulWidget {
  final Map<String, dynamic> service;
  final WaterTypeInfo waterType;

  const EditServiceDialog({
    super.key,
    required this.service,
    required this.waterType,
  });

  @override
  State<EditServiceDialog> createState() => _EditServiceDialogState();
}

class _EditServiceDialogState extends State<EditServiceDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _descriptionController;
  late final TextEditingController _priceController;
  late final TextEditingController _containerController;
  late final TextEditingController _preparationController;
  bool _isActive = true;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _descriptionController = TextEditingController(
      text: widget.service['description']?.toString() ?? '',
    );
    _priceController = TextEditingController(
      text: widget.service['price'] != null
          ? (widget.service['price'] as num).toStringAsFixed(2)
          : '',
    );
    _containerController = TextEditingController(
      text: widget.service['container_size']?.toString() ?? '5 gallon',
    );
    _preparationController = TextEditingController(
      text: (widget.service['preparation_minutes'] ?? 15).toString(),
    );
    _isActive = widget.service['is_available'] ?? true;
  }

  Future<void> _updateService() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      final supabase = Supabase.instance.client;
      await supabase
          .from(DbTables.waterOptions)
          .update({
            'price': double.parse(_priceController.text),
            'container_size': _containerController.text.trim(),
            'preparation_minutes': int.parse(_preparationController.text),
            'description': _descriptionController.text.trim(),
            'is_available': _isActive,
          })
          .eq('id', widget.service['id']);

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(FriendlyErrors.message(e))));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        decoration: BoxDecoration(
          color: AppUi.surfaceOf(context),
          borderRadius: AppUi.radiusSheetTop,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppUi.dividerOf(context),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Update Refill Pricing',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppUi.textPrimaryOf(context),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AppFormField(
                        controller: _descriptionController,
                        label: 'Description',
                        icon: Icons.description_outlined,
                        maxLines: 2,
                        compact: true,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: AppFormField(
                              controller: _priceController,
                              label: 'Price per gallon (₱)',
                              icon: Icons.payments_outlined,
                              keyboardType: TextInputType.number,
                              compact: true,
                              validator: (v) {
                                final p = double.tryParse(v ?? '');
                                return (p == null || p <= 0) ? 'Enter valid price' : null;
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: AppFormField(
                              controller: _containerController,
                              label: 'Container size',
                              icon: Icons.local_drink_outlined,
                              compact: true,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      AppFormField(
                        controller: _preparationController,
                        label: 'Prep time (minutes)',
                        icon: Icons.timer_outlined,
                        keyboardType: TextInputType.number,
                        compact: true,
                      ),
                      const SizedBox(height: 12),
                      SwitchListTile(
                        title: const Text('Available for ordering'),
                        value: _isActive,
                        activeThumbColor: AppUi.bluePrimary,
                        onChanged: (v) => setState(() => _isActive = v),
                      ),
                      const SizedBox(height: 20),
                      AppFormSubmitButton(
                        text: 'Update Refill Price',
                        icon: Icons.check_circle_rounded,
                        isLoading: _isLoading,
                        onPressed: _updateService,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _priceController.dispose();
    _containerController.dispose();
    _preparationController.dispose();
    super.dispose();
  }
}

// ── ADD / EDIT CUSTOM ACCESSORY / CONTAINER PRODUCT DIALOGS ──────────────────

class AddCustomProductDialog extends StatefulWidget {
  const AddCustomProductDialog({super.key});

  @override
  State<AddCustomProductDialog> createState() => _AddCustomProductDialogState();
}

class _AddCustomProductDialogState extends State<AddCustomProductDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _priceController = TextEditingController();
  final _containerController = TextEditingController(text: '5 Gallon');
  final _stockController = TextEditingController(text: '50');
  String _category = 'Accessories';
  bool _isActive = true;
  bool _isLoading = false;

  final List<String> _categoryOptions = ['Accessories', 'Products', 'Refill'];

  Future<void> _saveProduct() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;
      if (user == null) throw 'User not authenticated';

      final price = double.parse(_priceController.text.trim());
      final stock = int.tryParse(_stockController.text.trim()) ?? 0;

      await OrderProductHelpers.insertProduct(supabase, {
        'owner_id': user.id,
        'name': _nameController.text.trim(),
        'description': _descriptionController.text.trim(),
        'price': price,
        'category': _category,
        'container_size': _containerController.text.trim(),
        'stock_level': stock,
        'preparation_minutes': 5,
        'is_available': _isActive,
        'created_at': DateTime.now().toIso8601String(),
      });

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(FriendlyErrors.message(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.92,
        ),
        decoration: BoxDecoration(
          color: AppUi.surfaceOf(context),
          borderRadius: AppUi.radiusSheetTop,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppUi.dividerOf(context),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Add Container or Accessory',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppUi.textPrimaryOf(context),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AppFormField(
                        controller: _nameController,
                        label: 'Product Name',
                        hint: 'e.g. Empty 5 Gallon Round Water Container',
                        icon: Icons.inventory_2_outlined,
                        compact: true,
                        validator: (v) => v?.trim().isEmpty == true ? 'Product name required' : null,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: _category,
                              decoration: AppUi.fieldDecorationOf(context, 'Category'),
                              items: _categoryOptions.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                              onChanged: (v) => setState(() => _category = v ?? 'Accessories'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: AppFormField(
                              controller: _containerController,
                              label: 'Unit / Size',
                              hint: 'e.g. 5 Gallon, Cap',
                              icon: Icons.straighten_outlined,
                              compact: true,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: AppFormField(
                              controller: _priceController,
                              label: 'Price (₱)',
                              icon: Icons.payments_outlined,
                              keyboardType: TextInputType.number,
                              compact: true,
                              validator: (v) {
                                final p = double.tryParse(v ?? '');
                                return (p == null || p <= 0) ? 'Price must be > 0' : null;
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: AppFormField(
                              controller: _stockController,
                              label: 'Stock Quantity',
                              icon: Icons.numbers_outlined,
                              keyboardType: TextInputType.number,
                              compact: true,
                              validator: (v) {
                                final s = int.tryParse(v ?? '');
                                return (s == null || s < 0) ? 'Enter valid stock' : null;
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      AppFormField(
                        controller: _descriptionController,
                        label: 'Description',
                        hint: 'e.g. Empty reusable 5-gallon container for refills',
                        icon: Icons.description_outlined,
                        maxLines: 2,
                        compact: true,
                      ),
                      const SizedBox(height: 12),
                      SwitchListTile(
                        title: const Text('Available for customers to order'),
                        value: _isActive,
                        activeThumbColor: AppUi.bluePrimary,
                        onChanged: (v) => setState(() => _isActive = v),
                      ),
                      const SizedBox(height: 20),
                      AppFormSubmitButton(
                        text: 'Add Product to Catalog',
                        icon: Icons.check_circle_rounded,
                        isLoading: _isLoading,
                        onPressed: _saveProduct,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    _containerController.dispose();
    _stockController.dispose();
    super.dispose();
  }
}

class EditCustomProductDialog extends StatefulWidget {
  final Map<String, dynamic> product;

  const EditCustomProductDialog({super.key, required this.product});

  @override
  State<EditCustomProductDialog> createState() => _EditCustomProductDialogState();
}

class _EditCustomProductDialogState extends State<EditCustomProductDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _priceController;
  late final TextEditingController _containerController;
  late final TextEditingController _stockController;
  late String _category;
  bool _isActive = true;
  bool _isLoading = false;

  final List<String> _categoryOptions = ['Accessories', 'Products', 'Refill'];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.product['name']?.toString() ?? '');
    _descriptionController = TextEditingController(text: widget.product['description']?.toString() ?? '');
    _priceController = TextEditingController(
      text: widget.product['price'] != null ? (widget.product['price'] as num).toStringAsFixed(2) : '',
    );
    _containerController = TextEditingController(text: widget.product['container_size']?.toString() ?? 'Piece');
    _stockController = TextEditingController(
      text: (widget.product['stock_level'] ?? 50).toString(),
    );
    final rawCat = widget.product['category']?.toString() ?? 'Accessories';
    _category = _categoryOptions.contains(rawCat) ? rawCat : 'Accessories';
    _isActive = widget.product['is_available'] ?? true;
  }

  Future<void> _updateProduct() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      final supabase = Supabase.instance.client;
      final price = double.parse(_priceController.text.trim());
      final stock = int.tryParse(_stockController.text.trim()) ?? 0;

      await supabase
          .from(DbTables.waterOptions)
          .update({
            'name': _nameController.text.trim(),
            'description': _descriptionController.text.trim(),
            'price': price,
            'category': _category,
            'container_size': _containerController.text.trim(),
            'stock_level': stock,
            'is_available': _isActive,
          })
          .eq('id', widget.product['id']);

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(FriendlyErrors.message(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.92,
        ),
        decoration: BoxDecoration(
          color: AppUi.surfaceOf(context),
          borderRadius: AppUi.radiusSheetTop,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppUi.dividerOf(context),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Edit Product',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppUi.textPrimaryOf(context),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AppFormField(
                        controller: _nameController,
                        label: 'Product Name',
                        icon: Icons.inventory_2_outlined,
                        compact: true,
                        validator: (v) => v?.trim().isEmpty == true ? 'Required' : null,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: _category,
                              decoration: AppUi.fieldDecorationOf(context, 'Category'),
                              items: _categoryOptions.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                              onChanged: (v) => setState(() => _category = v ?? 'Accessories'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: AppFormField(
                              controller: _containerController,
                              label: 'Unit / Size',
                              icon: Icons.straighten_outlined,
                              compact: true,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: AppFormField(
                              controller: _priceController,
                              label: 'Price (₱)',
                              icon: Icons.payments_outlined,
                              keyboardType: TextInputType.number,
                              compact: true,
                              validator: (v) {
                                final p = double.tryParse(v ?? '');
                                return (p == null || p <= 0) ? 'Enter valid price' : null;
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: AppFormField(
                              controller: _stockController,
                              label: 'Stock Quantity',
                              icon: Icons.numbers_outlined,
                              keyboardType: TextInputType.number,
                              compact: true,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      AppFormField(
                        controller: _descriptionController,
                        label: 'Description',
                        icon: Icons.description_outlined,
                        maxLines: 2,
                        compact: true,
                      ),
                      const SizedBox(height: 12),
                      SwitchListTile(
                        title: const Text('Available for ordering'),
                        value: _isActive,
                        activeThumbColor: AppUi.bluePrimary,
                        onChanged: (v) => setState(() => _isActive = v),
                      ),
                      const SizedBox(height: 20),
                      AppFormSubmitButton(
                        text: 'Update Product',
                        icon: Icons.check_circle_rounded,
                        isLoading: _isLoading,
                        onPressed: _updateProduct,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    _containerController.dispose();
    _stockController.dispose();
    super.dispose();
  }
}
