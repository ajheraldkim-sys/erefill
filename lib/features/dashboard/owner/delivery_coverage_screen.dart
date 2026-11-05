import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants.dart';

/// Where a station delivers for free. Outside this zone customers pay the
/// platform's per-km rate (set by the admin).
class DeliveryCoverage {
  const DeliveryCoverage({
    required this.radiusKm,
    required this.barangays,
    required this.minGallons,
  });

  final double radiusKm;
  final List<String> barangays;
  final int? minGallons;
}

abstract interface class DeliveryCoverageRepository {
  Future<DeliveryCoverage> load(String ownerId);
  Future<void> save(String ownerId, DeliveryCoverage coverage);
}

class SupabaseDeliveryCoverageRepository implements DeliveryCoverageRepository {
  SupabaseDeliveryCoverageRepository([SupabaseClient? client])
    : _client = client ?? Supabase.instance.client;
  final SupabaseClient _client;

  @override
  Future<DeliveryCoverage> load(String ownerId) async {
    final row = await _client
        .from('owner_settings')
        .select(
          'free_delivery_radius_km, free_delivery_barangays, free_delivery_min_gallons',
        )
        .eq('owner_id', ownerId)
        .maybeSingle();
    return DeliveryCoverage(
      radiusKm: (row?['free_delivery_radius_km'] as num?)?.toDouble() ?? 1.0,
      barangays: [
        for (final b in (row?['free_delivery_barangays'] as List? ?? []))
          b.toString(),
      ],
      minGallons: (row?['free_delivery_min_gallons'] as num?)?.toInt(),
    );
  }

  @override
  Future<void> save(String ownerId, DeliveryCoverage c) async {
    await _client.from('owner_settings').upsert({
      'owner_id': ownerId,
      'free_delivery_radius_km': c.radiusKm,
      'free_delivery_barangays': c.barangays,
      'free_delivery_min_gallons': c.minGallons,
    }, onConflict: 'owner_id');
  }
}

class DeliveryCoverageScreen extends StatefulWidget {
  const DeliveryCoverageScreen({
    super.key,
    required this.ownerId,
    required this.town,
    this.repository,
  });

  final String ownerId;
  final String? town;
  final DeliveryCoverageRepository? repository;

  @override
  State<DeliveryCoverageScreen> createState() => _DeliveryCoverageScreenState();
}

class _DeliveryCoverageScreenState extends State<DeliveryCoverageScreen> {
  late final DeliveryCoverageRepository _repo =
      widget.repository ?? SupabaseDeliveryCoverageRepository();
  final _minGallons = TextEditingController();
  double _radius = 1.0;
  final Set<String> _barangays = {};
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _minGallons.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final c = await _repo.load(widget.ownerId);
      if (!mounted) return;
      setState(() {
        _radius = c.radiusKm.clamp(0, 10).toDouble();
        _barangays
          ..clear()
          ..addAll(c.barangays);
        _minGallons.text = c.minGallons?.toString() ?? '';
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load your delivery coverage. Pull to retry.';
      });
    }
  }

  Future<void> _save() async {
    final raw = _minGallons.text.trim();
    final min = raw.isEmpty ? null : int.tryParse(raw);
    if (raw.isNotEmpty && (min == null || min < 1 || min > 100)) {
      setState(() => _error = 'Minimum gallons must be between 1 and 100.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _repo.save(
        widget.ownerId,
        DeliveryCoverage(
          radiusKm: (_radius * 10).roundToDouble() / 10,
          barangays: _barangays.toList()..sort(),
          minGallons: min,
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Delivery coverage saved')));
    } catch (e) {
      if (mounted) setState(() => _error = 'Saving failed. Try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final barangayOptions =
        AppConstants.municipalityData[widget.town] ?? const <String>[];

    return Scaffold(
      appBar: AppBar(title: const Text('Delivery coverage')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Customers inside your free zone pay no delivery fee. '
                    'Everyone else pays the platform per-km rate.',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Free delivery radius',
                    style: theme.textTheme.titleSmall,
                  ),
                  Text(
                    'Free within ${_radius.toStringAsFixed(1)} km',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: AppUi.brandOf(context),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Slider(
                    value: _radius,
                    min: 0,
                    max: 10,
                    divisions: 20,
                    label: '${_radius.toStringAsFixed(1)} km',
                    semanticFormatterCallback: (v) =>
                        'Free within ${v.toStringAsFixed(1)} kilometers',
                    onChanged: (v) => setState(() => _radius = v),
                  ),
                  const SizedBox(height: 12),
                  Text('Free barangays', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Text(
                    barangayOptions.isEmpty
                        ? 'Set your station town in Station details to pick barangays.'
                        : 'Always free to these barangays, whatever the distance.',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final b in barangayOptions)
                        FilterChip(
                          label: Text(b),
                          selected: _barangays.contains(b),
                          onSelected: (on) => setState(
                            () => on ? _barangays.add(b) : _barangays.remove(b),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Free for bigger orders',
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    key: const Key('min-gallons'),
                    controller: _minGallons,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Minimum gallons for free delivery',
                      hintText: 'Leave empty for no rule',
                      suffixText: 'gallons',
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: Text(_saving ? 'Saving…' : 'Save coverage'),
                  ),
                ],
              ),
            ),
    );
  }
}
