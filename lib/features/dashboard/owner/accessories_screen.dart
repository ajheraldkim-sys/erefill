import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/constants.dart';
import '../../../core/utils/money.dart';
import 'services/accessory_repository.dart';

/// Owner screen for accessories sold next to the station's water.
class AccessoriesScreen extends StatefulWidget {
  const AccessoriesScreen({super.key, required this.ownerId, this.repository});

  final String ownerId;
  final AccessoryRepository? repository;

  @override
  State<AccessoriesScreen> createState() => _AccessoriesScreenState();
}

class _AccessoriesScreenState extends State<AccessoriesScreen> {
  late final AccessoryRepository _repo =
      widget.repository ?? SupabaseAccessoryRepository();
  List<Accessory>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await _repo.list(widget.ownerId);
      if (mounted) {
        setState(() {
          _items = items;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Could not load accessories. Pull to retry.');
      }
    }
  }

  Future<void> _edit([Accessory? existing]) async {
    final result = await showModalBottomSheet<Accessory>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AccessoryForm(initial: existing),
    );
    if (result == null) return;
    try {
      await _repo.save(widget.ownerId, result);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Saving failed. Try again.')),
        );
      }
    }
  }

  Future<void> _delete(Accessory a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${a.name}?'),
        content: const Text('Customers will no longer see it.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _repo.delete(a.id);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return Scaffold(
      appBar: AppBar(title: const Text('Accessories')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add accessory'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: items == null && _error == null
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                children: [
                  Text(
                    'Sell empty gallons, caps, seals, dispensers and more '
                    'alongside your water. Customers add them to the same order.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 12),
                  if (_error != null) Text(_error!),
                  if (items != null && items.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 32),
                      child: Center(child: Text('No accessories yet.')),
                    ),
                  for (final a in items ?? const <Accessory>[])
                    Card(
                      child: ListTile(
                        leading: Icon(
                          Accessory.iconFor(a.category),
                          color: AppUi.brandOf(context),
                        ),
                        title: Text(a.name),
                        subtitle: Text(
                          '${formatPeso(a.price)} · '
                          '${a.inStock ? '${a.stock} in stock' : 'Out of stock'}'
                          '${a.isAvailable ? '' : ' · Hidden'}',
                        ),
                        onTap: () => _edit(a),
                        trailing: IconButton(
                          tooltip: 'Delete ${a.name}',
                          icon: const Icon(Icons.delete_outline_rounded),
                          onPressed: () => _delete(a),
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

class _AccessoryForm extends StatefulWidget {
  const _AccessoryForm({this.initial});
  final Accessory? initial;

  @override
  State<_AccessoryForm> createState() => _AccessoryFormState();
}

class _AccessoryFormState extends State<_AccessoryForm> {
  late final _name = TextEditingController(text: widget.initial?.name ?? '');
  late final _price = TextEditingController(
    text: widget.initial == null ? '' : widget.initial!.price.toStringAsFixed(0),
  );
  late final _stock = TextEditingController(
    text: widget.initial?.stock.toString() ?? '0',
  );
  late String _category = widget.initial?.category ?? 'gallon';
  late bool _available = widget.initial?.isAvailable ?? true;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _stock.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    final price = double.tryParse(_price.text.trim()) ?? 0;
    final stock = int.tryParse(_stock.text.trim()) ?? 0;
    final error = name.isEmpty
        ? 'Enter a name'
        : price <= 0
            ? 'Enter a price above ₱0'
            : stock < 0
                ? 'Stock cannot be negative'
                : null;
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.pop(
      context,
      Accessory(
        id: widget.initial?.id ?? '',
        name: name,
        category: _category,
        price: price,
        stock: stock,
        isAvailable: _available,
        description: widget.initial?.description,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.initial == null ? 'New accessory' : 'Edit accessory',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final e in Accessory.categories.entries)
                  ChoiceChip(
                    avatar: Icon(Accessory.iconFor(e.key), size: 18),
                    label: Text(e.value),
                    selected: _category == e.key,
                    onSelected: (_) => setState(() => _category = e.key),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('acc-name'),
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('acc-price'),
                    controller: _price,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Price',
                      prefixText: '₱',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    key: const Key('acc-stock'),
                    controller: _stock,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(labelText: 'In stock'),
                  ),
                ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Show to customers'),
              value: _available,
              onChanged: (v) => setState(() => _available = v),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _error!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            FilledButton(onPressed: _submit, child: const Text('Save')),
          ],
        ),
      ),
    );
  }
}
