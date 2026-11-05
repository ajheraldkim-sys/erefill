import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/utils/money.dart';

/// A customer's report about a delivered order.
class Dispute {
  const Dispute({
    required this.id,
    required this.orderId,
    required this.reason,
    required this.description,
    required this.status,
    required this.createdAt,
    this.orderTotal,
    this.ownerResponse,
    this.refundAmount = 0,
  });

  final String id;
  final String orderId;
  final String reason;
  final String description;

  /// open | investigating | resolved | dismissed
  final String status;
  final DateTime createdAt;
  final double? orderTotal;
  final String? ownerResponse;
  final double refundAmount;

  static const reasons = <String, String>{
    'missing_items': 'Missing items',
    'wrong_item': 'Wrong item',
    'quality': 'Water quality',
    'damaged': 'Damaged gallon',
    'not_delivered': 'Not delivered',
    'overcharged': 'Overcharged',
    'other': 'Something else',
  };

  static const reportWindow = Duration(hours: 48);

  static bool canReport({
    required String status,
    required DateTime? deliveredAt,
    required DateTime now,
  }) =>
      status == 'delivered' &&
      deliveredAt != null &&
      now.difference(deliveredAt) <= reportWindow;

  factory Dispute.fromRow(Map<String, dynamic> r) => Dispute(
        id: r['id'].toString(),
        orderId: r['order_id'].toString(),
        reason: (r['reason'] ?? 'other').toString(),
        description: (r['description'] ?? '').toString(),
        status: r['status'].toString(),
        createdAt: DateTime.parse(r['created_at'].toString()),
        orderTotal: ((r['order'] as Map?)?['total_amount'] as num?)?.toDouble(),
        ownerResponse: r['owner_response']?.toString(),
        refundAmount: (r['refund_amount'] as num?)?.toDouble() ?? 0,
      );
}

abstract interface class DisputeRepository {
  Future<String> uploadEvidence(List<int> bytes, String ext);
  Future<void> open(String orderId, String reason, String description, List<String> evidence);
  Future<List<Dispute>> ownerInbox();
  Future<void> respond(String disputeId, {required bool accept, required String reply, double refund});
}

class SupabaseDisputeRepository implements DisputeRepository {
  SupabaseDisputeRepository([SupabaseClient? c]) : _db = c ?? Supabase.instance.client;
  final SupabaseClient _db;

  @override
  Future<String> uploadEvidence(List<int> bytes, String ext) async {
    final path = '${_db.auth.currentUser!.id}/${DateTime.now().millisecondsSinceEpoch}.$ext';
    await _db.storage.from('dispute_evidence').uploadBinary(
          path,
          Uint8List.fromList(bytes),
          fileOptions: FileOptions(contentType: 'image/$ext'),
        );
    return path;
  }

  @override
  Future<void> open(String orderId, String reason, String description, List<String> evidence) =>
      _db.rpc('open_dispute', params: {
        'p_order_id': orderId,
        'p_reason': reason,
        'p_description': description,
        'p_evidence_paths': evidence,
      });

  @override
  Future<List<Dispute>> ownerInbox() async {
    final rows = await _db
        .from('disputes')
        .select('id, order_id, reason, description, status, created_at, owner_response, '
            'refund_amount, order:orders!inner(owner_id, total_amount)')
        .eq('order.owner_id', _db.auth.currentUser!.id)
        .order('created_at', ascending: false);
    return [for (final r in rows) Dispute.fromRow(r)];
  }

  @override
  Future<void> respond(String disputeId, {required bool accept, required String reply, double refund = 0}) =>
      _db.rpc('owner_respond_dispute', params: {
        'p_dispute_id': disputeId,
        'p_accept': accept,
        'p_response': reply,
        'p_refund_amount': refund,
      });
}

typedef PhotoPick = Future<(List<int>, String)?> Function();

Future<(List<int>, String)?> _pickPhoto() async {
  final f = await ImagePicker().pickImage(source: ImageSource.camera, maxWidth: 1600, imageQuality: 80);
  if (f == null) return null;
  return (await f.readAsBytes(), 'jpeg');
}

/// Customer bottom sheet: report a problem with a delivered order.
class ReportProblemSheet extends StatefulWidget {
  const ReportProblemSheet({super.key, required this.orderId, this.repository, this.pickPhoto});
  final String orderId;
  final DisputeRepository? repository;
  final PhotoPick? pickPhoto;

  @override
  State<ReportProblemSheet> createState() => _ReportProblemSheetState();
}

class _ReportProblemSheetState extends State<ReportProblemSheet> {
  late final DisputeRepository _repo = widget.repository ?? SupabaseDisputeRepository();
  final _text = TextEditingController();
  String _reason = 'missing_items';
  final _evidence = <String>[];
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _addPhoto() async {
    final p = await (widget.pickPhoto ?? _pickPhoto)();
    if (p == null) return;
    setState(() => _busy = true);
    try {
      final path = await _repo.uploadEvidence(p.$1, p.$2);
      if (mounted) setState(() => _evidence.add(path));
    } catch (_) {
      if (mounted) setState(() => _error = 'Photo upload failed.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _send() async {
    final text = _text.text.trim();
    if (text.isEmpty) {
      setState(() => _error = 'Tell the station what went wrong.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _repo.open(widget.orderId, _reason, text, List.of(_evidence));
      if (!mounted) return;
      Navigator.maybePop(context, true);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Report sent. The station has 24 hours to reply.')),
      );
    } on PostgrestException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Sending failed. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Report a problem', style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text('The station replies first. If you can\'t agree, eRefill steps in.',
              style: theme.textTheme.bodySmall),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final e in Dispute.reasons.entries)
                ChoiceChip(
                  label: Text(e.value),
                  selected: _reason == e.key,
                  onSelected: (_) => setState(() => _reason = e.key),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _text,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'What happened?'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy || _evidence.length >= 3 ? null : _addPhoto,
            icon: const Icon(Icons.photo_camera_outlined),
            label: Text(_evidence.isEmpty ? 'Add photo' : 'Add photo (${_evidence.length}/3)'),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ),
          const SizedBox(height: 12),
          FilledButton(onPressed: _busy ? null : _send, child: const Text('Send report')),
        ],
      ),
    );
  }
}

/// Owner inbox of customer reports.
class OwnerDisputesScreen extends StatefulWidget {
  const OwnerDisputesScreen({super.key, this.repository});
  final DisputeRepository? repository;

  @override
  State<OwnerDisputesScreen> createState() => _OwnerDisputesScreenState();
}

class _OwnerDisputesScreenState extends State<OwnerDisputesScreen> {
  late final DisputeRepository _repo = widget.repository ?? SupabaseDisputeRepository();
  List<Dispute>? _items;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await _repo.ownerInbox();
      if (mounted) setState(() => _items = d);
    } catch (_) {
      if (mounted) setState(() => _items = const []);
    }
  }

  Future<void> _respond(Dispute d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _RespondDialog(dispute: d, repo: _repo),
    );
    if (ok == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return Scaffold(
      appBar: AppBar(title: const Text('Customer reports')),
      body: items == null
          ? const Center(child: CircularProgressIndicator())
          : items.isEmpty
              ? const Center(child: Text('No reports. Keep it up!'))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    for (final d in items)
                      Card(
                        child: ListTile(
                          title: Text(
                            '${Dispute.reasons[d.reason] ?? d.reason} · '
                            '#${d.orderId.substring(0, d.orderId.length.clamp(0, 8)).toUpperCase()}',
                          ),
                          subtitle: Text(
                            '${d.description}\n${switch (d.status) {
                              'open' => 'Waiting for your reply',
                              'investigating' => 'eRefill is reviewing',
                              'resolved' => 'Resolved · refund ${formatPeso(d.refundAmount)}',
                              _ => 'Closed',
                            }}',
                          ),
                          isThreeLine: true,
                          trailing: d.status == 'open' && d.ownerResponse == null
                              ? TextButton(onPressed: () => _respond(d), child: const Text('Respond'))
                              : null,
                        ),
                      ),
                  ],
                ),
    );
  }
}

class _RespondDialog extends StatefulWidget {
  const _RespondDialog({required this.dispute, required this.repo});
  final Dispute dispute;
  final DisputeRepository repo;

  @override
  State<_RespondDialog> createState() => _RespondDialogState();
}

class _RespondDialogState extends State<_RespondDialog> {
  final _reply = TextEditingController();
  final _refund = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _reply.dispose();
    _refund.dispose();
    super.dispose();
  }

  Future<void> _send(bool accept) async {
    final reply = _reply.text.trim();
    final refund = double.tryParse(_refund.text.trim()) ?? 0;
    final max = widget.dispute.orderTotal ?? double.infinity;
    if (reply.isEmpty) return setState(() => _error = 'Write a reply to the customer.');
    if (accept && (refund <= 0 || refund > max)) {
      return setState(() => _error = 'Enter a refund up to ${formatPeso(max)}.');
    }
    try {
      await widget.repo.respond(widget.dispute.id, accept: accept, reply: reply, refund: accept ? refund : 0);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = e is PostgrestException ? e.message : 'Sending failed.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Reply to customer'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.dispute.description),
          const SizedBox(height: 12),
          TextField(
            key: const Key('dispute-reply'),
            controller: _reply,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Your reply'),
          ),
          TextField(
            key: const Key('dispute-refund'),
            controller: _refund,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Refund amount', prefixText: '₱'),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => _send(false), child: const Text('Explain, no refund')),
        FilledButton(onPressed: () => _send(true), child: const Text('Refund')),
      ],
    );
  }
}
