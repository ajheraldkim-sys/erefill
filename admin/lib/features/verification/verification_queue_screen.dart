import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/admin_api_service.dart';

/// Admin queue of pending seller and customer ID verifications.
class VerificationQueueScreen extends StatefulWidget {
  const VerificationQueueScreen({super.key});

  @override
  State<VerificationQueueScreen> createState() =>
      _VerificationQueueScreenState();
}

class _VerificationQueueScreenState extends State<VerificationQueueScreen> {
  List<Map<String, dynamic>>? _rows;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows =
          await context.read<AdminApiService>().listPendingVerifications();
      if (mounted) {
        setState(() {
          _rows = rows;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not load verifications: $e');
    }
  }

  Future<void> _open(Map<String, dynamic> row) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _ReviewDialog(row: row),
    );
    if (changed == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    if (_error != null) return Center(child: Text(_error!));
    if (rows == null) return const Center(child: CircularProgressIndicator());
    if (rows.isEmpty) {
      return const Center(child: Text('No IDs waiting for review.'));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(24),
        itemCount: rows.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final r = rows[i];
          final p = (r['profile'] as Map?) ?? const {};
          final isOwner = r['role'] == 'owner';
          return Card(
            child: ListTile(
              leading: Icon(isOwner ? Icons.storefront : Icons.person),
              title: Text(
                isOwner
                    ? '${p['station_name'] ?? 'Station'} · ${p['full_name'] ?? ''}'
                    : (p['full_name'] ?? 'Customer').toString(),
              ),
              subtitle: Text(
                '${isOwner ? 'Station owner' : 'Customer'} · '
                '${r['id_type']} ···${r['id_number_last4'] ?? '????'} · '
                '${[p['barangay'], p['town']].whereType<String>().join(', ')} · '
                'submitted ${r['created_at'].toString().substring(0, 16).replaceFirst('T', ' ')}',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _open(r),
            ),
          );
        },
      ),
    );
  }
}

class _ReviewDialog extends StatefulWidget {
  const _ReviewDialog({required this.row});
  final Map<String, dynamic> row;

  @override
  State<_ReviewDialog> createState() => _ReviewDialogState();
}

class _ReviewDialogState extends State<_ReviewDialog> {
  final _reason = TextEditingController();
  Map<String, String?> _urls = const {};
  bool _busy = false;
  String? _error;

  static const _docs = {
    'front_path': 'ID front',
    'back_path': 'ID back',
    'selfie_path': 'Selfie with ID',
    'business_permit_path': 'Business / sanitary permit',
  };

  @override
  void initState() {
    super.initState();
    _loadUrls();
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _loadUrls() async {
    final api = context.read<AdminApiService>();
    final urls = <String, String?>{};
    for (final key in _docs.keys) {
      try {
        urls[key] = await api.verificationDocUrl(widget.row[key]?.toString());
      } catch (_) {
        urls[key] = null;
      }
    }
    if (mounted) setState(() => _urls = urls);
  }

  Future<void> _decide(bool approve) async {
    if (!approve && _reason.text.trim().isEmpty) {
      setState(() => _error = 'Write a reason the user will see.');
      return;
    }
    setState(() => _busy = true);
    try {
      await context.read<AdminApiService>().reviewVerification(
            widget.row['id'].toString(),
            approve: approve,
            reason: approve ? null : _reason.text.trim(),
          );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Review ID'),
      content: SizedBox(
        width: 760,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final e in _docs.entries)
                    if (widget.row[e.key] != null)
                      SizedBox(
                        width: 360,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(e.value,
                                style: Theme.of(context).textTheme.titleSmall),
                            const SizedBox(height: 4),
                            AspectRatio(
                              aspectRatio: 4 / 3,
                              child: _urls[e.key] == null
                                  ? const ColoredBox(
                                      color: Colors.black12,
                                      child: Center(
                                        child: Text('Loading or not an image'),
                                      ),
                                    )
                                  : Image.network(
                                      _urls[e.key]!,
                                      fit: BoxFit.contain,
                                      errorBuilder: (_, _, _) => const Center(
                                        child: Text('PDF or unreadable file'),
                                      ),
                                    ),
                            ),
                          ],
                        ),
                      ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _reason,
                decoration: const InputDecoration(
                  labelText: 'Reason (required to reject)',
                  hintText: 'e.g. Selfie does not match the ID photo',
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: const Text('Close'),
        ),
        OutlinedButton(
          onPressed: _busy ? null : () => _decide(false),
          child: const Text('Reject'),
        ),
        FilledButton(
          onPressed: _busy ? null : () => _decide(true),
          child: const Text('Approve'),
        ),
      ],
    );
  }
}
