import 'package:erefill/core/constants.dart';
import 'package:erefill/core/utils/friendly_errors.dart';
import 'package:erefill/core/water_types.dart';
import 'package:erefill/core/widgets/water_type_thumb.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:erefill/core/sync/sync_store.dart';
import 'package:erefill/core/sync/synced_state.dart';

import '../../sync/admin_sync.dart';
import '../../sync/admin_sync_widgets.dart';
import '../../widgets/admin_ui.dart';

/// Admin catalog of water types. Each station sells exactly one product: the
/// refill of the water type chosen at registration, so this list is the whole
/// product catalog.
class WaterTypesScreen extends StatefulWidget {
  const WaterTypesScreen({super.key});

  @override
  State<WaterTypesScreen> createState() => _WaterTypesScreenState();
}

class _WaterTypesScreenState extends State<WaterTypesScreen> with SyncedState {
  SupabaseClient get _client => Supabase.instance.client;

  /// Per-type station counts; refreshing it also reloads the shared
  /// [WaterTypes] catalog, which keeps its own offline copy.
  late final SyncedResource<Map<String, int>> _counts;

  Map<String, int> get _stationCounts => _counts.data ?? const {};

  @override
  void initState() {
    super.initState();
    _counts = useSynced(AdminSync.waterTypeStationCounts());
  }

  Future<void> _load() =>
      SyncStore.instance.refreshTagged(AdminSync.tagCatalog);

  void _snack(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppUi.error : null,
      ),
    );
  }

  Future<void> _edit([WaterTypeInfo? type]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _WaterTypeDialog(
        type: type,
        nextSortOrder: (WaterTypes.catalog.value.length + 1) * 10,
      ),
    );
    if (saved == true) {
      await _load();
      if (mounted) {
        _snack(type == null ? 'Water type added' : 'Water type updated');
      }
    }
  }

  Future<void> _toggleActive(WaterTypeInfo type) async {
    try {
      await _client
          .from(WaterTypes.table)
          .update({'is_active': !type.isActive})
          .eq('id', type.id!);
      await _load();
    } catch (e) {
      if (mounted) _snack(FriendlyErrors.message(e), isError: true);
    }
  }

  Future<void> _delete(WaterTypeInfo type) async {
    final inUse = _stationCounts[type.name] ?? 0;
    if (inUse > 0) {
      _snack(
        '${type.name} is sold by $inUse station${inUse == 1 ? '' : 's'}. '
        'Hide it from registration instead, or move those stations first.',
        isError: true,
      );
      return;
    }
    final confirmed = await showAdminConfirmDialog(
      context,
      title: 'Delete ${type.name}?',
      message:
          'New stations will no longer be able to pick it. '
          'Customers who prefer it will see their default instead.',
      confirmLabel: 'Delete',
      isDestructive: true,
    );
    if (confirmed != true) return;
    try {
      await _client.from(WaterTypes.table).delete().eq('id', type.id!);
      await _load();
      if (mounted) _snack('Water type deleted');
    } catch (e) {
      if (mounted) _snack(FriendlyErrors.message(e), isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminSyncedFrame(
      resources: [_counts],
      child: AdminPageScaffold(
        onRefresh: _load,
        header: const AdminSectionHeader(
          title: 'Water Types',
          subtitle:
              'The products stations can sell. Each station sells one water '
              'type, chosen at registration, at its own price.',
        ),
        actions: [
          ShadcnPrimaryButton(
            height: 38,
            icon: LucideIcons.plus,
            text: 'Add water type',
            onPressed: () => _edit(),
          ),
        ],
        child: _buildBody(context),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (WaterTypes.catalog.value.isEmpty) {
      final placeholder = adminSyncPlaceholder([_counts]);
      if (placeholder != null) return placeholder;
    }
    final types = WaterTypes.catalog.value;
    if (types.isEmpty) {
      return const AdminEmptyState(
        message: 'No water types yet. Add one so stations can register.',
      );
    }
    return Column(
      children: [
        for (final type in types)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _WaterTypeRow(
              type: type,
              stationCount: _stationCounts[type.name] ?? 0,
              onEdit: () => _edit(type),
              onToggleActive: () => _toggleActive(type),
              onDelete: () => _delete(type),
            ),
          ),
      ],
    );
  }
}

class _WaterTypeRow extends StatelessWidget {
  const _WaterTypeRow({
    required this.type,
    required this.stationCount,
    required this.onEdit,
    required this.onToggleActive,
    required this.onDelete,
  });

  final WaterTypeInfo type;
  final int stationCount;
  final VoidCallback onEdit;
  final VoidCallback onToggleActive;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return AdminCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          WaterTypeThumb(
            type: type,
            size: 56,
            radius: AppUi.radiusControl,
            iconSize: 22,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(type.name, style: adminSectionTitleStyle(context)),
                    if (type.badge.isNotEmpty)
                      AdminBadge(label: type.badge, color: type.color),
                    if (!type.isActive)
                      AdminBadge(
                        label: 'Hidden from registration',
                        color: AppUi.textSecondaryOf(context),
                      ),
                  ],
                ),
                if (type.tagline.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(type.tagline, style: adminBodyTextStyle(context)),
                ],
                if (type.description.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(type.description, style: adminCaptionTextStyle(context)),
                ],
                const SizedBox(height: 8),
                Text(
                  stationCount == 0
                      ? 'No stations sell this yet'
                      : 'Sold by $stationCount station${stationCount == 1 ? '' : 's'}',
                  style: adminCaptionTextStyle(context),
                ),
              ],
            ),
          ),
          Wrap(
            spacing: 4,
            children: [
              IconButton(
                tooltip: 'Edit',
                onPressed: onEdit,
                icon: const Icon(LucideIcons.pencil, size: 18),
              ),
              IconButton(
                tooltip: type.isActive
                    ? 'Hide from registration'
                    : 'Show at registration',
                onPressed: onToggleActive,
                icon: Icon(
                  type.isActive ? LucideIcons.eyeOff : LucideIcons.eye,
                  size: 18,
                ),
              ),
              IconButton(
                tooltip: 'Delete',
                onPressed: onDelete,
                icon: Icon(
                  LucideIcons.trash2,
                  size: 18,
                  color: adminSemanticErrorColor(context),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WaterTypeDialog extends StatefulWidget {
  const _WaterTypeDialog({this.type, required this.nextSortOrder});

  final WaterTypeInfo? type;
  final int nextSortOrder;

  @override
  State<_WaterTypeDialog> createState() => _WaterTypeDialogState();
}

class _WaterTypeDialogState extends State<_WaterTypeDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.type?.name);
  late final _shortName = TextEditingController(text: widget.type?.shortName);
  late final _tagline = TextEditingController(text: widget.type?.tagline);
  late final _description = TextEditingController(
    text: widget.type?.description,
  );
  late final _badge = TextEditingController(text: widget.type?.badge);
  late final _benefits = TextEditingController(
    text: widget.type?.benefits.join(', '),
  );
  late String? _photoUrl = widget.type?.photoUrl;
  Uint8List? _pickedBytes;
  String? _pickedExtension;
  bool _saving = false;

  static const _photoBucket = 'product_images';
  static const _maxPhotoBytes = 5 * 1024 * 1024;
  static const _photoTypes = {
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'webp': 'image/webp',
  };

  Future<void> _pickPhoto() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      imageQuality: 85,
    );
    if (file == null || !mounted) return;
    final extension = file.name.split('.').last.toLowerCase();
    if (!_photoTypes.containsKey(extension)) {
      _showError('Choose a JPG, PNG, or WebP photo.');
      return;
    }
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    if (bytes.length > _maxPhotoBytes) {
      _showError('That photo is over 5 MB. Choose a smaller one.');
      return;
    }
    setState(() {
      _pickedBytes = bytes;
      _pickedExtension = extension;
    });
  }

  void _removePhoto() => setState(() {
    _pickedBytes = null;
    _pickedExtension = null;
    _photoUrl = null;
  });

  /// Uploads a newly picked photo and returns its public URL; otherwise the
  /// current URL (null when removed).
  Future<String?> _uploadPhotoIfPicked(String name) async {
    final bytes = _pickedBytes;
    final extension = _pickedExtension;
    if (bytes == null || extension == null) return _photoUrl;
    final slug = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
    final path =
        'water_types/$slug-${DateTime.now().millisecondsSinceEpoch}.$extension';
    final storage = Supabase.instance.client.storage.from(_photoBucket);
    await storage.uploadBinary(
      path,
      bytes,
      fileOptions: FileOptions(contentType: _photoTypes[extension]),
    );
    return storage.getPublicUrl(path);
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppUi.error),
    );
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _shortName,
      _tagline,
      _description,
      _badge,
      _benefits,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final name = _name.text.trim();
    final String? photoUrl;
    try {
      photoUrl = await _uploadPhotoIfPicked(name);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _showError("The photo couldn't upload. ${FriendlyErrors.message(e)}");
      return;
    }
    final payload = {
      'name': name,
      'short_name': _shortName.text.trim().isEmpty
          ? WaterTypes.shortNameFor(name)
          : _shortName.text.trim(),
      'tagline': _tagline.text.trim(),
      'description': _description.text.trim(),
      'badge': _badge.text.trim(),
      'benefits': _benefits.text
          .split(',')
          .map((b) => b.trim())
          .where((b) => b.isNotEmpty)
          .toList(),
      'photo_url': photoUrl,
    };
    try {
      final table = Supabase.instance.client.from(WaterTypes.table);
      if (widget.type?.id == null) {
        await table.insert({...payload, 'sort_order': widget.nextSortOrder});
      } else {
        await table.update(payload).eq('id', widget.type!.id!);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      final lower = e.toString().toLowerCase();
      _showError(
        lower.contains('duplicate') || lower.contains('unique')
            ? 'A water type named "$name" already exists.'
            : FriendlyErrors.message(e),
      );
    }
  }

  Widget _buildPhotoField(BuildContext context) {
    final pickedBytes = _pickedBytes;
    final hasPhoto = pickedBytes != null || _photoUrl != null;
    const previewSize = 96.0;
    final preview = pickedBytes != null
        ? ClipRRect(
            borderRadius: BorderRadius.circular(AppUi.radiusControl),
            child: Image.memory(
              pickedBytes,
              width: previewSize,
              height: previewSize,
              fit: BoxFit.cover,
            ),
          )
        : WaterTypeThumb(
            type: WaterTypeInfo(
              name: _name.text,
              shortName: _name.text,
              iconKey: widget.type?.iconKey ?? WaterTypes.defaultIconKey,
              photoUrl: _photoUrl,
            ),
            size: previewSize,
            radius: AppUi.radiusControl,
            iconSize: 32,
          );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        preview,
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Shown to customers on station pages and in their cart. '
                'JPG, PNG, or WebP, up to 5 MB.',
                style: adminCaptionTextStyle(context),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ShadcnOutlineButton(
                    height: 34,
                    icon: LucideIcons.imagePlus,
                    text: hasPhoto ? 'Replace photo' : 'Choose photo',
                    onPressed: _saving ? null : _pickPhoto,
                  ),
                  if (hasPhoto)
                    TextButton(
                      onPressed: _saving ? null : _removePhoto,
                      child: Text(
                        'Remove',
                        style: TextStyle(
                          color: adminSemanticErrorColor(context),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.type != null;
    return AdminModalDialog(
      title: editing ? 'Edit water type' : 'Add water type',
      subtitle: editing
          ? 'Changes show on every station selling ${widget.type!.name}.'
          : 'Stations can pick it when they register.',
      icon: LucideIcons.droplet,
      maxWidth: 520,
      actions: [
        ShadcnOutlineButton(
          height: 38,
          text: 'Cancel',
          onPressed: _saving ? null : () => Navigator.pop(context, false),
        ),
        const SizedBox(width: 8),
        ShadcnPrimaryButton(
          height: 38,
          text: editing ? 'Save changes' : 'Add water type',
          isLoading: _saving,
          onPressed: _saving ? null : _save,
        ),
      ],
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AdminTextField(
                controller: _name,
                label: 'Name',
                hint: 'e.g. Distilled Water',
                textCapitalization: TextCapitalization.words,
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? 'Enter a name' : null,
              ),
              AppUi.vGapMd,
              AdminTextField(
                controller: _shortName,
                label: 'Short name (optional)',
                hint: 'e.g. Distilled',
                textCapitalization: TextCapitalization.words,
              ),
              AppUi.vGapMd,
              AdminTextField(
                controller: _tagline,
                label: 'Tagline',
                hint: 'e.g. Steam-purified',
              ),
              AppUi.vGapMd,
              AdminTextField(
                controller: _description,
                label: 'Description',
                maxLines: 3,
              ),
              AppUi.vGapMd,
              AdminTextField(
                controller: _badge,
                label: 'Badge',
                hint: 'e.g. Lab tested',
              ),
              AppUi.vGapMd,
              AdminTextField(
                controller: _benefits,
                label: 'Benefits',
                hint: 'Comma separated, e.g. No minerals, Clean taste',
              ),
              AppUi.vGapMd,
              Text('Photo', style: adminSectionTitleStyle(context)),
              const SizedBox(height: 8),
              _buildPhotoField(context),
            ],
          ),
        ),
      ),
    );
  }
}
