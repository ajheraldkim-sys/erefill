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

class ServiceCatalogScreen extends StatefulWidget {
  final bool isPopup;

  const ServiceCatalogScreen({super.key, this.isPopup = false});

  @override
  State<ServiceCatalogScreen> createState() => _ServiceCatalogScreenState();
}

class _ServiceCatalogScreenState extends State<ServiceCatalogScreen> {
  final supabase = Supabase.instance.client;
  bool _isLoading = true;
  List<Map<String, dynamic>> _services = [];
  String _searchQuery = '';
  WaterTypeInfo _ownerWaterType = WaterTypes.purified;

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

  List<Map<String, dynamic>> get _filteredServices {
    return _services.where((s) {
      if (_searchQuery.isEmpty) return true;
      final query = _searchQuery.toLowerCase();
      return (s['name']?.toString().toLowerCase().contains(query) ?? false) ||
          (s['description']?.toString().toLowerCase().contains(query) ??
              false) ||
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
              isActive ? 'Water option unavailable' : 'Water option available',
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

  void _showAddServiceDialog() {
    final existing = _registeredTypeService;
    if (existing != null) {
      _showEditServiceDialog(existing);
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => AddServiceDialog(waterType: _ownerWaterType),
    ).then((_) => _loadServices());
  }

  void _showEditServiceDialog(Map<String, dynamic> service) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) =>
          EditServiceDialog(service: service, waterType: _ownerWaterType),
    ).then((_) => _loadServices());
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredServices;
    final registeredService = _registeredTypeService;

    return Scaffold(
      backgroundColor: AppUi.pageBgOf(context),
      body: Column(
        children: [
          TabScreenHeroHeader(
            title: 'Refill pricing',
            subtitle:
                '${_ownerWaterType.name} · set during station registration',
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
              IconButton(
                onPressed: _showAddServiceDialog,
                icon: Container(
                  padding: const EdgeInsets.all(AppUi.spacingXs),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    registeredService == null ? Icons.add : Icons.edit,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ],
            bottom: TextField(
              onChanged: (v) => setState(() => _searchQuery = v),
              style: const TextStyle(color: AppUi.textPrimary),
              decoration: InputDecoration(
                hintText: 'Search price or notes',
                hintStyle: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                ),
                prefixIcon: Icon(
                  Icons.search,
                  color: Colors.white.withValues(alpha: 0.85),
                ),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.15),
                border: OutlineInputBorder(
                  borderRadius: AppUi.pillRadius,
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const AxoLoader(message: 'Loading refill pricing...')
                : filtered.isEmpty
                ? AxoEmptyState(
                    pose: AxoPose.thinking,
                    compact: true,
                    title: 'No refill price yet',
                    message:
                        'Set your ${_ownerWaterType.name.toLowerCase()} refill price so customers can order.',
                    actionLabel: 'Set refill price',
                    onAction: _showAddServiceDialog,
                  )
                : ListView.builder(
                    padding: AppUi.pagePadding,
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final service = filtered[index];
                      final isActive = service['is_available'] ?? true;
                      final price = (service['price'] as num?)?.toDouble() ?? 0;
                      final waterType = WaterTypes.byName(
                        service['category']?.toString() ??
                            service['name']?.toString(),
                      );
                      final containerSize =
                          service['container_size']?.toString() ?? '5 gallon';
                      final preparationMinutes =
                          (service['preparation_minutes'] as num?)?.toInt() ??
                          15;

                      return Stack(
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(right: 44),
                            child: WaterTypeCard(
                              type: waterType,
                              description:
                                  service['description']?.toString() ??
                                  waterType.description,
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
                            child: PopupMenuButton<String>(
                              onSelected: (value) {
                                if (value == 'edit') {
                                  _showEditServiceDialog(service);
                                } else if (value == 'toggle') {
                                  _toggleServiceStatus(service['id'], isActive);
                                }
                              },
                              itemBuilder: (context) => [
                                const PopupMenuItem(
                                  value: 'edit',
                                  child: Row(
                                    children: [
                                      Icon(Icons.edit, size: 18),
                                      SizedBox(width: AppUi.spacingSm),
                                      Text('Update refill price'),
                                    ],
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 'toggle',
                                  child: Row(
                                    children: [
                                      Icon(
                                        isActive
                                            ? Icons.visibility_off
                                            : Icons.visibility,
                                        size: 18,
                                      ),
                                      AppUi.hGapSm,
                                      Text(
                                        isActive
                                            ? 'Mark unavailable'
                                            : 'Mark available',
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

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

      if (user == null) {
        throw 'User not authenticated';
      }

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
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Set ${widget.waterType.name} price',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppUi.textPrimaryOf(context),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: AppUi.borderOf(context)),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: AppUi.bluePrimary.withValues(alpha: 0.08),
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
                                    'Water type from your station registration',
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
                      const AppFormSectionHeader(
                        title: 'SERVICE & CONTAINER DETAILS',
                        subtitle: 'Define pricing and preparation duration',
                        topPadding: 0,
                        bottomPadding: 8,
                      ),
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
                              validator: (v) =>
                                  double.tryParse(v ?? '') == null
                                      ? 'Enter a price'
                                      : null,
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
                        validator: (v) {
                          final minutes = int.tryParse(v ?? '');
                          return minutes == null || minutes < 0 || minutes > 240
                              ? 'Enter 0 to 240 mins'
                              : null;
                        },
                      ),
                      const SizedBox(height: 12),
                      Material(
                        color: AppUi.surfaceOf(context),
                        shape: RoundedRectangleBorder(
                          borderRadius: AppUi.cardRadius,
                          side: BorderSide(color: AppUi.borderOf(context)),
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: SwitchListTile(
                            title: const Text(
                              'Available for ordering',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                            value: _isActive,
                            thumbColor:
                                WidgetStateProperty.resolveWith((states) {
                              if (states.contains(WidgetState.selected)) {
                                return AppUi.bluePrimary;
                              }
                              return null;
                            }),
                            onChanged: (v) => setState(() => _isActive = v),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
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
  late TextEditingController _descriptionController;
  late TextEditingController _priceController;
  late TextEditingController _containerController;
  late TextEditingController _preparationController;
  late bool _isActive;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _descriptionController = TextEditingController(
      text: widget.service['description'],
    );
    _priceController = TextEditingController(
      text: widget.service['price']?.toString(),
    );
    _containerController = TextEditingController(
      text: widget.service['container_size']?.toString() ?? '5 gallon',
    );
    _preparationController = TextEditingController(
      text: widget.service['preparation_minutes']?.toString() ?? '15',
    );
    _isActive = widget.service['is_available'] ?? true;
  }

  Future<void> _updateService() async {
    setState(() => _isLoading = true);

    try {
      final supabase = Supabase.instance.client;
      final waterType = widget.waterType;

      await OrderProductHelpers.updateProduct(
        supabase,
        widget.service['id'].toString(),
        {
          'name': waterType.name,
          'description': _descriptionController.text,
          'price': double.parse(_priceController.text),
          'category': waterType.shortName,
          'container_size': _containerController.text.trim(),
          'preparation_minutes': int.parse(_preparationController.text),
          'is_available': _isActive,
        },
      );

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
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Update ${widget.waterType.name} price',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppUi.textPrimaryOf(context),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: AppUi.borderOf(context)),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: AppUi.bluePrimary.withValues(alpha: 0.08),
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
                                  'Primary station water type',
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
                    const AppFormSectionHeader(
                      title: 'SERVICE & CONTAINER DETAILS',
                      subtitle: 'Update pricing and availability',
                      topPadding: 0,
                      bottomPadding: 8,
                    ),
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
                            label: 'Price per gallon/container (₱)',
                            icon: Icons.payments_outlined,
                            keyboardType: TextInputType.number,
                            compact: true,
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
                      label: 'Preparation time (minutes)',
                      icon: Icons.timer_outlined,
                      keyboardType: TextInputType.number,
                      compact: true,
                    ),
                    const SizedBox(height: 12),
                    Material(
                      color: AppUi.surfaceOf(context),
                      shape: RoundedRectangleBorder(
                        borderRadius: AppUi.cardRadius,
                        side: BorderSide(color: AppUi.borderOf(context)),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: SwitchListTile(
                          title: const Text(
                            'Available for ordering',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                          value: _isActive,
                          thumbColor: WidgetStateProperty.resolveWith((states) {
                            if (states.contains(WidgetState.selected)) {
                              return AppUi.bluePrimary;
                            }
                            return null;
                          }),
                          onChanged: (v) => setState(() => _isActive = v),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
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
