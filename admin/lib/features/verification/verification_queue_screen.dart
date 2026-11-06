import 'package:erefill/features/account/verification/id_checks.dart';
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
  List<Map<String, dynamic>> _certs = const [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final api = context.read<AdminApiService>();
      final rows = await api.listPendingVerifications();
      List<Map<String, dynamic>> certs = const [];
      try {
        certs = await api.listPendingCertificates();
      } catch (_) {}
      if (mounted) {
        setState(() {
          _rows = rows;
          _certs = certs;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not load verifications: $e');
    }
  }

  static const _idDocs = {
    'front_path': 'ID front',
    'back_path': 'ID back',
    'selfie_path': 'Selfie with ID',
    'business_permit_path': 'Business / sanitary permit',
  };

  Future<void> _open(Map<String, dynamic> row) async {
    final api = context.read<AdminApiService>();
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _ReviewDialog(
        title: 'Review ID',
        checks: _checksOf(row),
        idType: row['id_type']?.toString(),
        docs: {
          for (final e in _idDocs.entries)
            if (row[e.key] != null) e.value: row[e.key].toString(),
        },
        decide: (approve, reason) => api.reviewVerification(
          row['id'].toString(),
          approve: approve,
          reason: reason,
        ),
      ),
    );
    if (changed == true) _load();
  }

  static IdCheckReport? _checksOf(Map<String, dynamic> row) {
    final c = row['auto_checks'];
    if (c is! Map || c['checked_on_device'] != true) return null;
    try {
      return IdCheckReport.fromJson(Map<String, dynamic>.from(c));
    } catch (_) {
      return null;
    }
  }

  Future<void> _openCert(Map<String, dynamic> row) async {
    final api = context.read<AdminApiService>();
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _ReviewDialog(
        title: 'Review certificate',
        docs: {row['cert_type'].toString(): row['file_path'].toString()},
        decide: (approve, reason) => api.reviewCertificate(
          row['id'].toString(),
          approve: approve,
          reason: reason,
        ),
      ),
    );
    if (changed == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    if (_error != null) return Center(child: Text(_error!));
    if (rows == null) return const Center(child: CircularProgressIndicator());
    if (rows.isEmpty && _certs.isEmpty) {
      return const Center(child: Text('Nothing waiting for review.'));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(24),
        itemCount: rows.length + _certs.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          if (i >= rows.length) {
            final c = _certs[i - rows.length];
            final p = (c['profile'] as Map?) ?? const {};
            return Card(
              child: ListTile(
                leading: const Icon(Icons.science_outlined),
                title: Text(
                  '${p['station_name'] ?? 'Station'} · water quality',
                ),
                subtitle: Text(
                  '${c['cert_type']} · issued ${c['issued_on']} · expires ${c['expires_on']}',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _openCert(c),
              ),
            );
          }
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
              trailing: _ChecksBadge(report: _checksOf(r)),
              onTap: () => _open(r),
            ),
          );
        },
      ),
    );
  }
}

class _ReviewDialog extends StatefulWidget {
  const _ReviewDialog({
    required this.title,
    required this.docs,
    required this.decide,
    this.checks,
    this.idType,
  });

  final String title;

  /// On-device screening from the user's phone, if the app sent it.
  final IdCheckReport? checks;
  final String? idType;

  /// Label -> storage path in verification_docs.
  final Map<String, String> docs;
  final Future<void> Function(bool approve, String? reason) decide;

  @override
  State<_ReviewDialog> createState() => _ReviewDialogState();
}

class _ReviewDialogState extends State<_ReviewDialog> {
  final _reason = TextEditingController();
  Map<String, String?> _urls = const {};
  bool _busy = false;
  String? _error;

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
    for (final e in widget.docs.entries) {
      try {
        urls[e.key] = await api.verificationDocUrl(e.value);
      } catch (_) {
        urls[e.key] = null;
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
      await widget.decide(approve, approve ? null : _reason.text.trim());
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
      title: Text(widget.title),
      content: SizedBox(
        width: 760,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.title == 'Review ID')
                _ChecksPanel(report: widget.checks, idType: widget.idType),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final e in {
                    for (final l in widget.docs.keys) l: l,
                  }.entries)
                    SizedBox(
                      width: 360,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            e.value,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
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

/// Small summary on each queue row: how many things to look at.
class _ChecksBadge extends StatelessWidget {
  const _ChecksBadge({required this.report});
  final IdCheckReport? report;

  @override
  Widget build(BuildContext context) {
    final r = report;
    if (r == null) return const Icon(Icons.chevron_right);
    final n = r.flags.length;
    final color = n == 0 ? Colors.green : Colors.orange;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Chip(
          avatar: Icon(
            n == 0 ? Icons.check_circle : Icons.flag_outlined,
            size: 18,
            color: color,
          ),
          label: Text(n == 0 ? 'Checks passed' : '$n to check'),
          visualDensity: VisualDensity.compact,
        ),
        const Icon(Icons.chevron_right),
      ],
    );
  }
}

/// Results of the free on-device checks, shown above the photos.
class _ChecksPanel extends StatelessWidget {
  const _ChecksPanel({required this.report, required this.idType});
  final IdCheckReport? report;
  final String? idType;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = report;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Phone checks', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            'Run on the user\'s phone (Google ML Kit). Use them to focus your '
            'review; they can be faked by a modified app, so always look at '
            'the photos yourself.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          if (r == null)
            const Text(
              'No phone checks: sent from an older app or the checks failed.',
            )
          else ...[
            for (final f in r.flags)
              _line(Icons.flag_outlined, Colors.orange, f),
            for (final p in r.passes)
              _line(Icons.check_circle_outline, Colors.green, p),
            _line(
              Icons.percent,
              theme.colorScheme.onSurfaceVariant,
              'Name parts found on the ID: ${(r.nameMatch * 100).round()}%',
            ),
            if (r.qrFound && r.qrSigned == true)
              _line(
                Icons.info_outline,
                theme.colorScheme.onSurfaceVariant,
                'National ID QR is signed by the PSA, but the app cannot check '
                'the signature itself.',
              ),
          ],
          if (idType == 'philsys')
            _line(
              Icons.open_in_new,
              theme.colorScheme.primary,
              'To confirm the card is genuine, scan its QR on the government\'s '
              'eVerify site (National ID Check).',
            ),
        ],
      ),
    );
  }

  Widget _line(IconData icon, Color color, String text) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(child: Text(text)),
      ],
    ),
  );
}
