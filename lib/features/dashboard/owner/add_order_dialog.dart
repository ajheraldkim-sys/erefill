import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:erefill/core/constants.dart';
import 'package:erefill/core/widgets/app_form_fields.dart';

class AddOrderDialog extends StatefulWidget {
  final String ownerId;
  final List<Map<String, dynamic>> riders;
  final VoidCallback onOrderAdded;
  final double? initialPrice;

  const AddOrderDialog({
    super.key,
    required this.ownerId,
    required this.riders,
    required this.onOrderAdded,
    this.initialPrice,
  });

  @override
  State<AddOrderDialog> createState() => _AddOrderDialogState();
}

class _AddOrderDialogState extends State<AddOrderDialog> {
  final _formKey = GlobalKey<FormState>();
  final _customerNameController = TextEditingController();
  final _addressController = TextEditingController();
  final _gallonsController = TextEditingController();
  final _pricePerGallonController = TextEditingController();
  final _phoneController = TextEditingController();
  final _notesController = TextEditingController();

  String? _selectedRiderId;
  bool _isCredit = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    final price = widget.initialPrice ?? 25.0;
    _pricePerGallonController.text = price.toStringAsFixed(2);
    if (widget.initialPrice == null) {
      _loadStationPrice();
    }
  }

  Future<void> _loadStationPrice() async {
    try {
      final res = await Supabase.instance.client
          .from('owner_settings')
          .select('price_per_gallon')
          .eq('owner_id', widget.ownerId)
          .maybeSingle();
      if (res != null && res['price_per_gallon'] != null && mounted) {
        final p = (res['price_per_gallon'] as num).toDouble();
        if (p > 0) {
          setState(() {
            _pricePerGallonController.text = p.toStringAsFixed(2);
          });
        }
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _customerNameController.dispose();
    _addressController.dispose();
    _gallonsController.dispose();
    _pricePerGallonController.dispose();
    _phoneController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  double get _totalAmount {
    final gallons = double.tryParse(_gallonsController.text) ?? 0;
    final price = double.tryParse(_pricePerGallonController.text) ?? 0;
    return gallons * price;
  }

  Future<void> _submitOrder() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final supabase = Supabase.instance.client;

      // Create the order
      final orderData = {
        'owner_id': widget.ownerId,
        'customer_name': _customerNameController.text,
        'delivery_address': _addressController.text,
        'phone': _phoneController.text,
        'gallons': double.parse(_gallonsController.text),
        'price_per_gallon': double.parse(_pricePerGallonController.text),
        'total_amount': _totalAmount,
        'status': 'pending',
        'is_credit': _isCredit,
        'notes': _notesController.text,
        'payment_method': 'cod',
        'payment_status': _isCredit ? 'pending' : 'success',
        'rider_id': _selectedRiderId,
        'assigned_rider_id': _selectedRiderId,
        'created_at': DateTime.now().toIso8601String(),
      };

      await supabase.from('orders').insert(orderData);

      if (mounted) {
        Navigator.pop(context);
        widget.onOrderAdded();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Order created successfully! 🎉'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to create order: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: AppUi.dialogRadius),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500),
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Create New Order',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: AppUi.textPrimary,
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                const AppFormSectionHeader(
                  title: 'Customer Information',
                  topPadding: 8,
                ),
                AppFormField(
                  controller: _customerNameController,
                  label: 'Customer Name',
                  icon: Icons.person_outline_rounded,
                  textCapitalization: TextCapitalization.words,
                  compact: true,
                  validator: (v) => v?.isEmpty == true ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                AppFormField(
                  controller: _phoneController,
                  label: 'Phone Number',
                  icon: Icons.phone_android_rounded,
                  keyboardType: TextInputType.phone,
                  compact: true,
                  validator: (v) => v?.isEmpty == true ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                AppFormField(
                  controller: _addressController,
                  label: 'Delivery Address',
                  icon: Icons.location_on_outlined,
                  textCapitalization: TextCapitalization.words,
                  maxLines: 2,
                  compact: true,
                  validator: (v) => v?.isEmpty == true ? 'Required' : null,
                ),
                const SizedBox(height: 16),

                const AppFormSectionHeader(
                  title: 'Refill Quantity & Pricing',
                  topPadding: 4,
                ),
                Row(
                  children: [
                    Expanded(
                      child: AppFormField(
                        controller: _gallonsController,
                        label: 'Gallons',
                        icon: Icons.water_drop_outlined,
                        keyboardType: TextInputType.number,
                        compact: true,
                        validator: (v) => v?.isEmpty == true ? 'Required' : null,
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: AppFormField(
                        controller: _pricePerGallonController,
                        label: 'Price / Gal (₱)',
                        icon: Icons.payments_outlined,
                        keyboardType: TextInputType.number,
                        compact: true,
                        validator: (v) => v?.isEmpty == true ? 'Required' : null,
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Total Amount Display
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: AppUi.blueSoft,
                    borderRadius: AppUi.cardRadius,
                    border: Border.all(color: AppUi.bluePrimary.withValues(alpha: 0.15)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Total Amount:',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: AppUi.textPrimary,
                        ),
                      ),
                      Text(
                        '₱${_totalAmount.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: AppUi.bluePrimary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                const AppFormSectionHeader(
                  title: 'Dispatch & Settings',
                  topPadding: 4,
                ),
                if (widget.riders.isNotEmpty) ...[
                  AppDropdownField<String>(
                    label: 'Assign Rider (Optional)',
                    icon: Icons.delivery_dining_rounded,
                    value: _selectedRiderId,
                    compact: true,
                    items: widget.riders.map((rider) {
                      final name =
                          rider['full_name'] ?? rider['username'] ?? 'Unknown';
                      return DropdownMenuItem(
                        value: rider['id'] as String,
                        child: Text(
                          name,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                        ),
                      );
                    }).toList(),
                    onChanged: (v) => setState(() => _selectedRiderId = v),
                  ),
                  const SizedBox(height: 12),
                ],

                // Credit Toggle
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
                        'Credit Order',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                      ),
                      subtitle: const Text(
                        'Customer will pay at a later date',
                        style: TextStyle(fontSize: 12, color: AppUi.textMuted),
                      ),
                      value: _isCredit,
                      thumbColor: WidgetStateProperty.resolveWith((states) {
                        if (states.contains(WidgetState.selected)) {
                          return AppUi.bluePrimary;
                        }
                        return null;
                      }),
                      onChanged: (v) => setState(() => _isCredit = v),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                AppFormField(
                  controller: _notesController,
                  label: 'Special Instructions (Optional)',
                  icon: Icons.notes_rounded,
                  maxLines: 2,
                  compact: true,
                ),
                const SizedBox(height: 24),

                AppFormSubmitButton(
                  label: 'Record Refill Order',
                  isLoading: _isLoading,
                  onPressed: _submitOrder,
                  icon: Icons.add_circle_outline_rounded,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
