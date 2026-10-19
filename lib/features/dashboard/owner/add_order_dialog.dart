import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/constants.dart';
import '../../../../core/widgets/app_form_fields.dart';
import '../../../../core/utils/app_haptics.dart';

import 'package:erefill/core/theme/app_colors.dart';
import 'package:erefill/core/utils/money.dart';
import 'package:erefill/core/utils/friendly_errors.dart';
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
  final _customerNameController = TextEditingController(text: 'Walk-in Customer');
  final _addressController = TextEditingController(text: 'Station Counter');
  final _gallonsController = TextEditingController(text: '1');
  final _pricePerGallonController = TextEditingController();
  final _phoneController = TextEditingController();
  final _notesController = TextEditingController();

  String? _selectedRiderId;
  bool _isCredit = false;
  bool _isLoading = false;
  bool _isWalkIn = true;
  List<String> _recentCustomers = [];

  @override
  void initState() {
    super.initState();
    final price = widget.initialPrice ?? 25.0;
    _pricePerGallonController.text = price.toStringAsFixed(2);
    if (widget.initialPrice == null) {
      _loadStationPrice();
    }
    _loadRecentCustomers();
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

  Future<void> _loadRecentCustomers() async {
    try {
      final res = await Supabase.instance.client
          .from('orders')
          .select('customer_name')
          .eq('owner_id', widget.ownerId)
          .order('created_at', ascending: false)
          .limit(25);
      if (mounted) {
        final names = res
            .map((r) => r['customer_name']?.toString().trim())
            .whereType<String>()
            .where((name) =>
                name.isNotEmpty &&
                name.toLowerCase() != 'walk-in customer' &&
                name.toLowerCase() != 'walk-in')
            .toSet()
            .take(5)
            .toList();
        setState(() => _recentCustomers = names);
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

  void _adjustGallons(int delta) {
    AppHaptics.light();
    final current = int.tryParse(_gallonsController.text.trim()) ?? 1;
    final next = (current + delta).clamp(1, 999);
    setState(() {
      _gallonsController.text = next.toString();
    });
  }

  void _selectCustomer(String name) {
    AppHaptics.selection();
    setState(() {
      _customerNameController.text = name;
      if (name != 'Walk-in Customer') {
        _isWalkIn = false;
        if (_addressController.text == 'Station Counter') {
          _addressController.text = '';
        }
      }
    });
  }

  Future<void> _submitOrder() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final supabase = Supabase.instance.client;
      final custName = _customerNameController.text.trim().isEmpty
          ? 'Walk-in Customer'
          : _customerNameController.text.trim();
      final addr = _addressController.text.trim().isEmpty
          ? 'Station Counter'
          : _addressController.text.trim();
      final phone = _phoneController.text.trim().isEmpty
          ? 'N/A'
          : _phoneController.text.trim();

      // Create the order
      final orderData = {
        'owner_id': widget.ownerId,
        'customer_name': custName,
        'customer_address': addr,
        'customer_phone': phone,
        'quantity': int.parse(_gallonsController.text),
        'water_type': 'Refill',
        'container_type': 'Slim',
        'total_price': _totalAmount,
        'total_amount': _totalAmount,
        'status': _isWalkIn ? 'accepted' : 'pending',
        'delivery_type': _isWalkIn ? 'pickup' : 'delivery',
        'notes': [
          if (_isCredit) 'Credit order',
          if (_notesController.text.trim().isNotEmpty)
            _notesController.text.trim(),
        ].join('\n'),
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
            content: Text('Refill recorded'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to record order: ${FriendlyErrors.message(e)}')));
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
        constraints: const BoxConstraints(maxWidth: 520),
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Quick Walk-in / Order',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppUi.textPrimaryOf(context),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Order Type Selector
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () {
                          AppHaptics.selection();
                          setState(() {
                            _isWalkIn = true;
                            _customerNameController.text = 'Walk-in Customer';
                            _addressController.text = 'Station Counter';
                          });
                        },
                        borderRadius: BorderRadius.circular(AppUi.radiusCard),
                        child: AnimatedContainer(
                          duration: Duration(milliseconds: 150),
                          padding: EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: _isWalkIn
                                ? AppUi.bluePrimary
                                : AppUi.surfaceRaisedOf(context),
                            borderRadius: BorderRadius.circular(AppUi.radiusCard),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            'Walk-in refill',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: _isWalkIn
                                  ? Colors.white
                                  : AppUi.textSecondaryOf(context),
                            ),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: InkWell(
                        onTap: () {
                          AppHaptics.selection();
                          setState(() {
                            _isWalkIn = false;
                            if (_customerNameController.text == 'Walk-in Customer') {
                              _customerNameController.text = '';
                            }
                            if (_addressController.text == 'Station Counter') {
                              _addressController.text = '';
                            }
                          });
                        },
                        borderRadius: BorderRadius.circular(AppUi.radiusCard),
                        child: AnimatedContainer(
                          duration: Duration(milliseconds: 150),
                          padding: EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: !_isWalkIn
                                ? AppUi.bluePrimary
                                : AppUi.surfaceRaisedOf(context),
                            borderRadius: BorderRadius.circular(AppUi.radiusCard),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            'Delivery request',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: !_isWalkIn
                                  ? Colors.white
                                  : AppUi.textSecondaryOf(context),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 14),

                // Recent customer chips
                if (_recentCustomers.isNotEmpty) ...[
                  Text(
                    'Recent Customers:',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppUi.textSecondaryOf(context),
                    ),
                  ),
                  const SizedBox(height: 6),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        ActionChip(
                          label: const Text('Walk-in'),
                          avatar: const Icon(Icons.person, size: 14),
                          onPressed: () => _selectCustomer('Walk-in Customer'),
                        ),
                        const SizedBox(width: 6),
                        ..._recentCustomers.map(
                          (name) => Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: ActionChip(
                              label: Text(name),
                              onPressed: () => _selectCustomer(name),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                // Customer Name
                AppFormField(
                  controller: _customerNameController,
                  label: 'Customer Name',
                  icon: Icons.person_outline_rounded,
                  textCapitalization: TextCapitalization.words,
                  compact: true,
                  validator: (v) => v?.trim().isEmpty == true ? 'Required' : null,
                ),
                if (!_isWalkIn) ...[
                  const SizedBox(height: 10),
                  AppFormField(
                    controller: _phoneController,
                    label: 'Phone Number',
                    icon: Icons.phone_android_rounded,
                    keyboardType: TextInputType.phone,
                    compact: true,
                  ),
                  const SizedBox(height: 10),
                  AppFormField(
                    controller: _addressController,
                    label: 'Delivery Address',
                    icon: Icons.location_on_outlined,
                    textCapitalization: TextCapitalization.words,
                    compact: true,
                    validator: (v) => v?.trim().isEmpty == true ? 'Required' : null,
                  ),
                ],
                const SizedBox(height: 14),

                // Gallons Quantity Steppers
                Text(
                  'Quantity (Gallons)',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
                SizedBox(height: 6),
                Row(
                  children: [
                    SizedBox(
                      width: 48,
                      height: 48,
                      child: OutlinedButton(
                        onPressed: () => _adjustGallons(-1),
                        style: OutlinedButton.styleFrom(
                          padding: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppUi.radiusCard),
                          ),
                        ),
                        child: Text('-1', style: TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ),
                    SizedBox(width: 8),
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
                    SizedBox(width: 8),
                    SizedBox(
                      width: 48,
                      height: 48,
                      child: OutlinedButton(
                        onPressed: () => _adjustGallons(1),
                        style: OutlinedButton.styleFrom(
                          padding: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppUi.radiusCard),
                          ),
                        ),
                        child: Text('+1', style: TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ),
                    SizedBox(width: 8),
                    SizedBox(
                      width: 52,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: () => _adjustGallons(5),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppUi.bluePrimary,
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.zero,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppUi.radiusCard),
                          ),
                        ),
                        child: Text('+5', style: TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 12),

                // Price per gallon
                AppFormField(
                  controller: _pricePerGallonController,
                  label: 'Price per Gallon (₱)',
                  icon: Icons.payments_outlined,
                  keyboardType: TextInputType.numberWithOptions(decimal: true),
                  compact: true,
                  validator: (v) => v?.isEmpty == true ? 'Required' : null,
                  onChanged: (_) => setState(() {}),
                ),
                SizedBox(height: 14),

                // Cash vs Credit Toggle
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () {
                          AppHaptics.selection();
                          setState(() => _isCredit = false);
                        },
                        borderRadius: BorderRadius.circular(AppUi.radiusCard),
                        child: Container(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: !_isCredit
                                ? AppUi.successBg
                                : AppUi.surfaceRaisedOf(context),
                            borderRadius: BorderRadius.circular(AppUi.radiusCard),
                            border: Border.all(
                              color: !_isCredit
                                  ? AppColors.uiSuccess
                                  : Colors.transparent,
                              width: 1.5,
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.payments_rounded,
                                size: 18,
                                color: !_isCredit
                                    ? AppUi.successFg
                                    : AppUi.textSecondaryOf(context),
                              ),
                              SizedBox(width: 6),
                              Text(
                                'Cash (paid)',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: !_isCredit
                                      ? AppUi.successFg
                                      : AppUi.textSecondaryOf(context),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: InkWell(
                        onTap: () {
                          AppHaptics.selection();
                          setState(() => _isCredit = true);
                        },
                        borderRadius: BorderRadius.circular(AppUi.radiusCard),
                        child: Container(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: _isCredit
                                ? AppUi.warningBg
                                : AppUi.surfaceRaisedOf(context),
                            borderRadius: BorderRadius.circular(AppUi.radiusCard),
                            border: Border.all(
                              color: _isCredit
                                  ? AppColors.uiWarning
                                  : Colors.transparent,
                              width: 1.5,
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.receipt_long_rounded,
                                size: 18,
                                color: _isCredit
                                    ? AppUi.warningFg
                                    : AppUi.textSecondaryOf(context),
                              ),
                              SizedBox(width: 6),
                              Text(
                                'Credit (utang)',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: _isCredit
                                      ? AppUi.warningFg
                                      : AppUi.textSecondaryOf(context),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 16),

                // Total Summary Bar
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppUi.brandSoftOf(context),
                    borderRadius: BorderRadius.circular(AppUi.radiusCard),
                    border: Border.all(
                      color: AppUi.bluePrimary.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Total Payable:',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppUi.textPrimaryOf(context),
                        ),
                      ),
                      Text(
                        formatPeso(_totalAmount),
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: AppUi.brandOf(context),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 18),

                // Single Tap Save Button
                SizedBox(
                  width: double.infinity,
                  height: AppUi.kRiderTouchTarget,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _submitOrder,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.uiSuccess,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppUi.radiusCard),
                      ),
                    ),
                    child: _isLoading
                        ? SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            'Save Refill (${formatPeso(_totalAmount)})',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
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
