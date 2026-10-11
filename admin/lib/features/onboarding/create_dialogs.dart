import 'package:erefill/core/utils/friendly_errors.dart';
import 'package:erefill/core/water_types.dart';
import 'package:erefill/core/widgets/map_tiles.dart';
import 'package:erefill/core/constants.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../services/admin_api_service.dart';
import '../../widgets/admin_ui.dart';

Future<bool?> showCreateUserDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (_) => const _CreateUserDialog(),
  );
}

class _CreateUserDialog extends StatefulWidget {
  const _CreateUserDialog();

  @override
  State<_CreateUserDialog> createState() => _CreateUserDialogState();
}

class _CreateUserDialogState extends State<_CreateUserDialog> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _username = TextEditingController();
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _middleInitial = TextEditingController();
  final _phone = TextEditingController();
  final _stationName = TextEditingController();
  final _address = TextEditingController();
  final _landmark = TextEditingController();
  final _mapController = MapController();
  final _municipalityData = AppConstants.municipalityData;
  static const _suffixes = ['None', 'Jr.', 'Sr.', 'II', 'III', 'IV', 'V'];

  String _role = 'customer';
  String? _suffix;
  String _town = 'Cantilan';
  String? _barangay;
  String _waterType = WaterTypes.purified.name;
  Map<String, dynamic>? _assignedOwner;
  List<Map<String, dynamic>> _municipalityOwners = [];
  bool _loadingOwners = false;
  String? _ownerLoadError;
  int _ownerLoadRequest = 0;
  bool _saving = false;
  LatLng _pickedLocation = const LatLng(9.3333, 125.9833);

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _username.dispose();
    _firstName.dispose();
    _lastName.dispose();
    _middleInitial.dispose();
    _phone.dispose();
    _stationName.dispose();
    _address.dispose();
    _landmark.dispose();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _loadMunicipalityOwners(String municipality) async {
    final request = ++_ownerLoadRequest;
    setState(() {
      _town = municipality;
      _barangay = null;
      _assignedOwner = null;
      _municipalityOwners = [];
      _loadingOwners = true;
      _ownerLoadError = null;
    });

    try {
      final api = context.read<AdminApiService>();
      final owners = <Map<String, dynamic>>[];
      const pageSize = 100;
      var offset = 0;
      var total = 0;

      do {
        final page = await api.listUsers(
          role: 'owner',
          limit: pageSize,
          offset: offset,
        );
        total = page.total;
        owners.addAll(page.rows);
        offset += page.rows.length;
        if (page.rows.isEmpty) break;
      } while (offset < total);

      if (!mounted || request != _ownerLoadRequest) return;
      setState(() {
        _municipalityOwners = owners.where((owner) {
          return owner['town']?.toString().trim().toLowerCase() ==
              municipality.trim().toLowerCase();
        }).toList();
        _loadingOwners = false;
      });
    } catch (e) {
      if (!mounted || request != _ownerLoadRequest) return;
      setState(() {
        _ownerLoadError = e.toString();
        _loadingOwners = false;
      });
    }
  }

  void _selectRole(String role) {
    setState(() {
      _role = role;
      _assignedOwner = null;
      _municipalityOwners = [];
      _ownerLoadError = null;
    });
    if (role == 'rider') _loadMunicipalityOwners(_town);
  }

  String get _fullName => [
    _firstName.text.trim(),
    _middleInitial.text.trim(),
    _lastName.text.trim(),
    _suffix ?? '',
  ].where((part) => part.isNotEmpty).join(' ');

  String _ownerLabel(Map<String, dynamic> owner) {
    final stationName = owner['station_name']?.toString().trim();
    final ownerName = owner['full_name']?.toString().trim();
    if (stationName != null &&
        stationName.isNotEmpty &&
        ownerName != null &&
        ownerName.isNotEmpty) {
      return '$stationName — $ownerName';
    }
    if (stationName != null && stationName.isNotEmpty) return stationName;
    if (ownerName != null && ownerName.isNotEmpty) return ownerName;
    return owner['email']?.toString() ?? 'Station owner';
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _saving = true);
    try {
      final api = context.read<AdminApiService>();
      final fullName = _fullName;
      if (_role == 'owner') {
        await api.createSignupStation(
          email: _email.text.trim(),
          password: _password.text,
          stationName: _stationName.text.trim(),
          ownerName: fullName,
          firstName: _firstName.text.trim(),
          lastName: _lastName.text.trim(),
          username: _username.text.trim(),
          phone: _phone.text.trim(),
          town: _town,
          barangay: _barangay!,
          completeAddress: _address.text.trim(),
          primaryWaterType: _waterType,
          latitude: _pickedLocation.latitude,
          longitude: _pickedLocation.longitude,
          middleInitial: _middleInitial.text.trim(),
          suffix: _suffix,
        );
      } else {
        await api.createSignupUser(
          email: _email.text.trim(),
          password: _password.text,
          role: _role,
          fullName: fullName,
          firstName: _firstName.text.trim(),
          lastName: _lastName.text.trim(),
          username: _username.text.trim(),
          phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
          town: _town,
          barangay: _role == 'customer' ? _barangay! : '',
          waterType: _waterType,
          middleInitial: _middleInitial.text.trim(),
          suffix: _suffix,
          completeAddress: _role == 'customer' ? _address.text.trim() : null,
          landmark: _role == 'customer' ? _landmark.text.trim() : null,
          latitude: _role == 'customer' ? _pickedLocation.latitude : null,
          longitude: _role == 'customer' ? _pickedLocation.longitude : null,
          ownerId: _role == 'rider' ? _assignedOwner!['id']?.toString() : null,
        );
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: AppUi.error),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminModalDialog(
      title: 'Create new user',
      subtitle: 'Create a customer, station owner, or rider account',
      icon: LucideIcons.userPlus,
      maxWidth: 560,
      actions: [
        ShadcnOutlineButton(
          height: 40,
          text: 'Cancel',
          onPressed: () => Navigator.pop(context),
        ),
        const SizedBox(width: 8),
        ShadcnPrimaryButton(
          height: 40,
          isLoading: _saving,
          icon: LucideIcons.check,
          text: 'Create User',
          onPressed: _saving ? null : _save,
        ),
      ],
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AdminDropdownFormField<String>(
                label: 'Account Role',
                icon: LucideIcons.shield,
                value: _role,
                items: const [
                  DropdownMenuItem(value: 'customer', child: Text('Customer')),
                  DropdownMenuItem(
                    value: 'owner',
                    child: Text('Station Owner'),
                  ),
                  DropdownMenuItem(
                    value: 'rider',
                    child: Text('Station Rider'),
                  ),
                ],
                onChanged: (v) => _selectRole(v ?? 'customer'),
              ),
              AppUi.vGapMd,
              AdminTextField(
                controller: _firstName,
                label: 'First name *',
                hint: 'e.g. Juan',
                icon: LucideIcons.user,
                validator: (value) => AppValidators.name(value, 'First name'),
              ),
              AppUi.vGapMd,
              AdminTextField(
                controller: _lastName,
                label: 'Last name *',
                hint: 'e.g. Dela Cruz',
                icon: LucideIcons.user,
                validator: (value) => AppValidators.name(value, 'Last name'),
              ),
              AppUi.vGapMd,
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: AdminTextField(
                      controller: _middleInitial,
                      label: 'M.I.',
                      hint: 'Optional',
                      icon: LucideIcons.type,
                      validator: AppValidators.optionalInitial,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 3,
                    child: AdminDropdownFormField<String>(
                      label: 'Suffix',
                      icon: LucideIcons.star,
                      value: _suffix ?? 'None',
                      items: _suffixes
                          .map(
                            (suffix) => DropdownMenuItem(
                              value: suffix,
                              child: Text(suffix),
                            ),
                          )
                          .toList(),
                      onChanged: (value) => setState(
                        () => _suffix = value == 'None' ? null : value,
                      ),
                    ),
                  ),
                ],
              ),
              AppUi.vGapMd,
              AdminTextField(
                controller: _username,
                label: 'Username *',
                hint: '3-24 letters, numbers, or underscores',
                icon: LucideIcons.atSign,
                validator: AppValidators.username,
              ),
              if (_role == 'owner') ...[
                AppUi.vGapMd,
                AdminTextField(
                  controller: _stationName,
                  label: 'Water station name *',
                  hint: 'e.g. AquaPure Refill Station',
                  icon: LucideIcons.store,
                  validator: (value) =>
                      AppValidators.requiredText(value, 'Station name'),
                ),
              ],
              AppUi.vGapMd,
              AdminTextField(
                controller: _phone,
                label: _role == 'rider' ? 'Phone number' : 'Phone number *',
                hint: '09xx-xxx-xxxx',
                icon: LucideIcons.phone,
                keyboardType: TextInputType.phone,
                validator: _role == 'rider' ? null : AppValidators.phone,
              ),
              AppUi.vGapMd,
              AdminTextField(
                controller: _email,
                label: 'Email address *',
                hint: 'user@example.com',
                icon: LucideIcons.mail,
                keyboardType: TextInputType.emailAddress,
                validator: AppValidators.email,
              ),
              AppUi.vGapMd,
              AdminTextField(
                controller: _password,
                label: 'Initial password *',
                hint: '8+ characters with a letter and number',
                icon: LucideIcons.lock,
                obscureText: true,
                validator: AppValidators.password,
              ),
              AppUi.vGapMd,
              AdminDropdownFormField<String>(
                label: 'Municipality',
                icon: LucideIcons.mapPin,
                value: _town,
                items: _municipalityData.keys
                    .map(
                      (town) =>
                          DropdownMenuItem(value: town, child: Text(town)),
                    )
                    .toList(),
                onChanged: (town) {
                  if (town != null) {
                    if (_role == 'rider') {
                      _loadMunicipalityOwners(town);
                    } else {
                      setState(() {
                        _town = town;
                        _barangay = null;
                      });
                    }
                  }
                },
              ),
              if (_role != 'rider') ...[
                AppUi.vGapMd,
                AdminDropdownFormField<String>(
                  label: 'Barangay',
                  icon: LucideIcons.mapPin,
                  value: _barangay,
                  hint: 'Select barangay',
                  items: (_municipalityData[_town] ?? const <String>[])
                      .map(
                        (barangay) => DropdownMenuItem(
                          value: barangay,
                          child: Text(barangay),
                        ),
                      )
                      .toList(),
                  validator: (value) =>
                      value == null ? 'Select a barangay' : null,
                  onChanged: (value) => setState(() => _barangay = value),
                ),
                AppUi.vGapMd,
                AdminTextField(
                  controller: _address,
                  label: _role == 'owner'
                      ? 'Detailed station address *'
                      : 'Complete address *',
                  hint: 'Street or purok',
                  icon: LucideIcons.navigation,
                  validator: (value) => AppValidators.requiredText(
                    value,
                    _role == 'owner' ? 'Station address' : 'Complete address',
                  ),
                ),
              ],
              if (_role == 'customer') ...[
                AppUi.vGapMd,
                AdminTextField(
                  controller: _landmark,
                  label: 'Nearest landmark',
                  hint: 'Optional',
                  icon: LucideIcons.flag,
                ),
              ],
              if (_role == 'customer' || _role == 'owner') ...[
                AppUi.vGapMd,
                Text(
                  _role == 'owner' ? 'Primary water type' : 'Water preference',
                  style: adminSectionTitleStyle(context),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: WaterTypes.all.map((type) {
                    final selected = _waterType == type.name;
                    return ChoiceChip(
                      label: Text(type.shortName),
                      selected: selected,
                      onSelected: (_) => setState(() => _waterType = type.name),
                      selectedColor: Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: 0.16),
                      labelStyle: TextStyle(
                        color: selected
                            ? Theme.of(context).colorScheme.primary
                            : AppUi.textPrimaryOf(context),
                        fontWeight: FontWeight.w700,
                      ),
                    );
                  }).toList(),
                ),
                AppUi.vGapMd,
                SizedBox(
                  height: 180,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: FlutterMap(
                      mapController: _mapController,
                      options: MapOptions(
                        initialCenter: _pickedLocation,
                        initialZoom: 13,
                        onPositionChanged: (camera, hasGesture) {
                          if (hasGesture) {
                            setState(() => _pickedLocation = camera.center);
                          }
                        },
                      ),
                      children: [
                        AppMapTiles.layer(context: context),
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.only(bottom: 32),
                            child: Icon(
                              Icons.location_on_rounded,
                              size: 38,
                              color: Colors.red,
                              shadows: [
                                Shadow(
                                  color: Colors.black54,
                                  blurRadius: 8,
                                  offset: Offset(0, 3),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Drag the map to set the ${_role == 'owner' ? 'station' : 'delivery'} location '
                  '(${_pickedLocation.latitude.toStringAsFixed(5)}, '
                  '${_pickedLocation.longitude.toStringAsFixed(5)})',
                  style: adminCaptionTextStyle(context),
                ),
              ],
              if (_role == 'rider') ...[
                AppUi.vGapMd,
                if (_loadingOwners)
                  const LinearProgressIndicator()
                else if (_ownerLoadError != null)
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Could not load owners: $_ownerLoadError',
                          style: TextStyle(
                            color: adminSemanticErrorColor(context),
                            fontSize: 12,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () => _loadMunicipalityOwners(_town),
                        child: const Text('Retry'),
                      ),
                    ],
                  )
                else
                  _SearchableOwnerField(
                    key: ValueKey(_town),
                    owners: _municipalityOwners,
                    selectedOwner: _assignedOwner,
                    municipality: _town,
                    labelForOwner: _ownerLabel,
                    onSelected: (owner) =>
                        setState(() => _assignedOwner = owner),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchableOwnerField extends StatelessWidget {
  const _SearchableOwnerField({
    super.key,
    required this.owners,
    required this.selectedOwner,
    required this.municipality,
    required this.labelForOwner,
    required this.onSelected,
  });

  final List<Map<String, dynamic>> owners;
  final Map<String, dynamic>? selectedOwner;
  final String? municipality;
  final String Function(Map<String, dynamic>) labelForOwner;
  final ValueChanged<Map<String, dynamic>?> onSelected;

  @override
  Widget build(BuildContext context) {
    final initialOwnerId = selectedOwner?['id']?.toString();
    final initialLabel = selectedOwner == null
        ? ''
        : labelForOwner(selectedOwner!);

    return FormField<String>(
      initialValue: initialOwnerId,
      validator: (value) =>
          value == null || value.isEmpty ? 'Select an assigned owner' : null,
      builder: (field) {
        return Autocomplete<Map<String, dynamic>>(
          displayStringForOption: labelForOwner,
          initialValue: TextEditingValue(text: initialLabel),
          optionsBuilder: (textEditingValue) {
            if (municipality == null) return const [];
            final query = textEditingValue.text.trim().toLowerCase();
            return owners.where((owner) {
              if (query.isEmpty) return true;
              final searchText = [
                labelForOwner(owner),
                owner['full_name']?.toString() ?? '',
                owner['station_name']?.toString() ?? '',
                owner['email']?.toString() ?? '',
              ].join(' ').toLowerCase();
              return searchText.contains(query);
            });
          },
          onSelected: (owner) {
            field.didChange(owner['id']?.toString());
            onSelected(owner);
          },
          fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
            return TextField(
              controller: controller,
              focusNode: focusNode,
              enabled: municipality != null,
              onChanged: (_) {
                if (field.value != null) {
                  field.didChange(null);
                  onSelected(null);
                }
              },
              decoration: InputDecoration(
                labelText: 'Assigned Station / Owner',
                hintText: municipality == null
                    ? 'Select municipality first'
                    : 'Search station or owner',
                helperText: municipality != null && owners.isEmpty
                    ? 'No station owners found in $municipality.'
                    : null,
                errorText: field.errorText,
                prefixIcon: const Icon(LucideIcons.store, size: 18),
                suffixIcon: const Icon(LucideIcons.search, size: 18),
                filled: true,
                fillColor: AppUi.surfaceOf(context),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppUi.borderOf(context)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppUi.borderOf(context)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: Theme.of(context).colorScheme.primary,
                    width: 2,
                  ),
                ),
              ),
            );
          },
          optionsViewBuilder: (context, onOptionSelected, options) {
            return Align(
              alignment: Alignment.topLeft,
              child: Material(
                elevation: 8,
                color: AppUi.surfaceOf(context),
                borderRadius: BorderRadius.circular(12),
                clipBehavior: Clip.antiAlias,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxHeight: 240,
                    maxWidth: 420,
                  ),
                  child: ListView.builder(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    itemCount: options.length,
                    itemBuilder: (context, index) {
                      final owner = options.elementAt(index);
                      return ListTile(
                        dense: true,
                        title: Text(
                          labelForOwner(owner),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: owner['email'] == null
                            ? null
                            : Text(
                                owner['email'].toString(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                        onTap: () => onOptionSelected(owner),
                      );
                    },
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

Future<bool?> showCreateStationDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (_) => const _CreateStationDialog(),
  );
}

class _CreateStationDialog extends StatefulWidget {
  const _CreateStationDialog();

  @override
  State<_CreateStationDialog> createState() => _CreateStationDialogState();
}

class _CreateStationDialogState extends State<_CreateStationDialog> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _stationName = TextEditingController();
  final _ownerName = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _lat = TextEditingController();
  final _lng = TextEditingController();
  String _town = 'Cantilan';
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [
      _email,
      _password,
      _stationName,
      _ownerName,
      _phone,
      _address,
      _lat,
      _lng,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _saving = true);
    try {
      await context.read<AdminApiService>().createStation(
        email: _email.text.trim(),
        password: _password.text,
        stationName: _stationName.text.trim(),
        ownerName: _ownerName.text.trim(),
        phone: _phone.text.trim(),
        town: _town,
        completeAddress: _address.text.trim(),
        latitude: double.tryParse(_lat.text.trim()),
        longitude: double.tryParse(_lng.text.trim()),
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: AppUi.error),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminModalDialog(
      title: 'Onboard new station',
      subtitle: 'Register a water refilling station and owner credentials',
      icon: LucideIcons.store,
      maxWidth: 520,
      actions: [
        ShadcnOutlineButton(
          height: 40,
          text: 'Cancel',
          onPressed: () => Navigator.pop(context),
        ),
        const SizedBox(width: 8),
        ShadcnPrimaryButton(
          height: 40,
          isLoading: _saving,
          icon: LucideIcons.check,
          text: 'Create Station',
          onPressed: _saving ? null : _save,
        ),
      ],
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AdminTextField(
                controller: _stationName,
                label: 'Station name *',
                hint: 'e.g. AquaPure Refill Station',
                icon: LucideIcons.store,
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Station name is required'
                    : null,
              ),
              AppUi.vGapMd,
              AdminTextField(
                controller: _ownerName,
                label: 'Owner full name *',
                hint: 'e.g. Juan dela Cruz',
                icon: LucideIcons.user,
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Owner name is required'
                    : null,
              ),
              AppUi.vGapMd,
              AdminTextField(
                controller: _email,
                label: 'Login email *',
                hint: 'station@erefill.com',
                icon: LucideIcons.mail,
                keyboardType: TextInputType.emailAddress,
                validator: (v) {
                  final trimmed = v?.trim() ?? '';
                  if (trimmed.isEmpty) return 'Email is required';
                  if (!trimmed.contains('@') || !trimmed.contains('.')) {
                    return 'Enter a valid email address';
                  }
                  return null;
                },
              ),
              AppUi.vGapMd,
              AdminTextField(
                controller: _password,
                label: 'Initial password *',
                hint: '8+ characters with a letter and number',
                icon: LucideIcons.lock,
                obscureText: true,
                validator: AppValidators.password,
              ),
              AppUi.vGapMd,
              AdminTextField(
                controller: _phone,
                label: 'Contact phone',
                hint: '09xx-xxx-xxxx',
                icon: LucideIcons.phone,
                keyboardType: TextInputType.phone,
              ),
              AppUi.vGapMd,
              AdminDropdownFormField<String>(
                label: 'Municipality',
                icon: LucideIcons.mapPin,
                value: _town,
                items: AppConstants.municipalityData.keys
                    .map(
                      (town) =>
                          DropdownMenuItem(value: town, child: Text(town)),
                    )
                    .toList(),
                validator: (value) =>
                    value == null ? 'Select a municipality' : null,
                onChanged: (town) {
                  if (town != null) setState(() => _town = town);
                },
              ),
              AppUi.vGapMd,
              AdminTextField(
                controller: _address,
                label: 'Complete address',
                hint: 'Street, Barangay, Landmark',
                icon: LucideIcons.navigation,
                maxLines: 2,
              ),
              AppUi.vGapMd,
              Row(
                children: [
                  Expanded(
                    child: AdminTextField(
                      controller: _lat,
                      label: 'Latitude',
                      hint: '9.317',
                      icon: LucideIcons.crosshair,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      ),
                      validator: (v) {
                        final trimmed = v?.trim() ?? '';
                        if (trimmed.isEmpty) return null;
                        final parsed = double.tryParse(trimmed);
                        if (parsed == null || parsed < -90 || parsed > 90) {
                          return 'Valid lat (-90 to 90)';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: AdminTextField(
                      controller: _lng,
                      label: 'Longitude',
                      hint: '125.98',
                      icon: LucideIcons.crosshair,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      ),
                      validator: (v) {
                        final trimmed = v?.trim() ?? '';
                        if (trimmed.isEmpty) return null;
                        final parsed = double.tryParse(trimmed);
                        if (parsed == null || parsed < -180 || parsed > 180) {
                          return 'Valid lng (-180 to 180)';
                        }
                        return null;
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
