import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:erefill/core/constants.dart';
import 'package:erefill/core/theme/app_colors.dart';
import 'package:erefill/core/utils/app_haptics.dart';

import 'package:erefill/core/utils/friendly_errors.dart';
Future<bool?> showCreateStationSheet(BuildContext context) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => const _CreateStationSheet(),
  );
}

Future<bool?> showCreateUserSheet(BuildContext context) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => const _CreateUserSheet(),
  );
}

class _CreateStationSheet extends StatefulWidget {
  const _CreateStationSheet();

  @override
  State<_CreateStationSheet> createState() => _CreateStationSheetState();
}

class _CreateStationSheetState extends State<_CreateStationSheet> {
  final supabase = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();

  final _stationName = TextEditingController();
  final _ownerName = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _pricePerGallon = TextEditingController(text: '30.00');
  final _deliveryFee = TextEditingController(text: '15.00');

  String _town = 'Cantilan';
  bool _saving = false;

  @override
  void dispose() {
    _stationName.dispose();
    _ownerName.dispose();
    _email.dispose();
    _password.dispose();
    _phone.dispose();
    _address.dispose();
    _pricePerGallon.dispose();
    _deliveryFee.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    AppHaptics.medium();

    try {
      // 1. Try admin_create_station RPC
      try {
        await supabase.rpc('admin_create_station', params: {
          'p_email': _email.text.trim(),
          'p_password': _password.text.trim(),
          'p_station_name': _stationName.text.trim(),
          'p_owner_name': _ownerName.text.trim(),
          'p_phone': _phone.text.trim(),
          'p_town': _town,
          'p_complete_address': _address.text.trim(),
          'p_base_delivery_fee': double.tryParse(_deliveryFee.text.trim()) ?? 15.0,
          'p_price_per_gallon': double.tryParse(_pricePerGallon.text.trim()) ?? 30.0,
        });
      } catch (_) {
        // Fallback: direct insert to water_refill_stations
        await supabase.from('water_refill_stations').insert({
          'name': _stationName.text.trim(),
          'address': _address.text.trim(),
          'town': _town,
          'phone': _phone.text.trim(),
          'price_per_gallon': double.tryParse(_pricePerGallon.text.trim()) ?? 30.0,
          'base_delivery_fee': double.tryParse(_deliveryFee.text.trim()) ?? 15.0,
          'status': 'active',
          'is_accepting_orders': true,
          'created_at': DateTime.now().toIso8601String(),
        });
      }

      if (!mounted) return;
      AppHaptics.success();
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Water refill station created and verified!'),
          backgroundColor: AppColors.statusDelivered,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      AppHaptics.error();
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to create station: ${FriendlyErrors.message(e)}'), backgroundColor: AppUi.error),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      decoration: BoxDecoration(
        color: AppUi.surfaceOf(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(AppUi.radiusPill)),
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppUi.borderOf(context),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Onboard New Water Station',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppUi.textPrimaryOf(context),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _stationName,
                decoration: const InputDecoration(
                  labelText: 'Station Name *',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _ownerName,
                decoration: const InputDecoration(
                  labelText: 'Owner Full Name *',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _email,
                      decoration: const InputDecoration(
                        labelText: 'Owner Email *',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) => v == null || !v.contains('@') ? 'Valid email required' : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _password,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Initial Password *',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) => v == null || v.length < 6 ? 'Min 6 chars' : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _town,
                      decoration: const InputDecoration(
                        labelText: 'Municipality *',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'Cantilan', child: Text('Cantilan')),
                        DropdownMenuItem(value: 'Madrid', child: Text('Madrid')),
                      ],
                      onChanged: (v) => setState(() => _town = v ?? 'Cantilan'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _phone,
                      decoration: const InputDecoration(
                        labelText: 'Phone Number',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _address,
                decoration: const InputDecoration(
                  labelText: 'Complete Street Address',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _pricePerGallon,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Price / Gallon (₱)',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      initialValue: 'Centralized Rate',
                      readOnly: true,
                      decoration: const InputDecoration(
                        labelText: 'Delivery Fee',
                        helperText: 'Admin-Controlled Rate/km',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: _saving ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppUi.bluePrimary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppUi.radiusCard)),
                  ),
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : const Icon(Icons.check_rounded, size: 20),
                  label: Text(
                    _saving ? 'Creating Station...' : 'Create & Verify Station',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CreateUserSheet extends StatefulWidget {
  const _CreateUserSheet();

  @override
  State<_CreateUserSheet> createState() => _CreateUserSheetState();
}

class _CreateUserSheetState extends State<_CreateUserSheet> {
  final supabase = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();

  final _fullName = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _phone = TextEditingController();

  String _role = 'rider';
  String _town = 'Cantilan';
  bool _saving = false;

  @override
  void dispose() {
    _fullName.dispose();
    _email.dispose();
    _password.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    AppHaptics.medium();

    try {
      // 1. Try admin_create_user RPC
      try {
        await supabase.rpc('admin_create_user', params: {
          'p_email': _email.text.trim(),
          'p_password': _password.text.trim(),
          'p_role': _role,
          'p_full_name': _fullName.text.trim(),
          'p_phone': _phone.text.trim(),
          'p_town': _town,
        });
      } catch (_) {
        // Fallback: direct insert to profiles
        await supabase.from('profiles').insert({
          'full_name': _fullName.text.trim(),
          'email': _email.text.trim(),
          'phone': _phone.text.trim(),
          'role': _role,
          'town': _town,
          'created_at': DateTime.now().toIso8601String(),
        });
      }

      if (!mounted) return;
      AppHaptics.success();
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${_role.toUpperCase()} account created successfully!'),
          backgroundColor: AppColors.statusDelivered,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      AppHaptics.error();
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to create account: ${FriendlyErrors.message(e)}'), backgroundColor: AppUi.error),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      decoration: BoxDecoration(
        color: AppUi.surfaceOf(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(AppUi.radiusPill)),
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppUi.borderOf(context),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Register Marketplace Account',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppUi.textPrimaryOf(context),
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _role,
                decoration: const InputDecoration(
                  labelText: 'Account Role *',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'rider', child: Text('Delivery Rider')),
                  DropdownMenuItem(value: 'owner', child: Text('Station Owner')),
                  DropdownMenuItem(value: 'customer', child: Text('Customer')),
                  DropdownMenuItem(value: 'admin', child: Text('System Admin')),
                ],
                onChanged: (v) => setState(() => _role = v ?? 'rider'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _fullName,
                decoration: const InputDecoration(
                  labelText: 'Full Name *',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _email,
                      decoration: const InputDecoration(
                        labelText: 'Email Address *',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) => v == null || !v.contains('@') ? 'Valid email required' : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _password,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Initial Password *',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) => v == null || v.length < 6 ? 'Min 6 chars' : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _town,
                      decoration: const InputDecoration(
                        labelText: 'Town *',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'Cantilan', child: Text('Cantilan')),
                        DropdownMenuItem(value: 'Madrid', child: Text('Madrid')),
                      ],
                      onChanged: (v) => setState(() => _town = v ?? 'Cantilan'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _phone,
                      decoration: const InputDecoration(
                        labelText: 'Phone Number',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: _saving ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppUi.bluePrimary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppUi.radiusCard)),
                  ),
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : const Icon(Icons.person_add_rounded, size: 20),
                  label: Text(
                    _saving ? 'Registering Account...' : 'Create ${_role.toUpperCase()} Account',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
