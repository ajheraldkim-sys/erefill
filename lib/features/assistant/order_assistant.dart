import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/constants.dart';
import '../../core/models/cart_model.dart';
import '../../core/utils/money.dart';

class AssistantMessage {
  const AssistantMessage({required this.fromUser, required this.text});
  final bool fromUser;
  final String text;

  Map<String, String> toJson() =>
      {'role': fromUser ? 'user' : 'assistant', 'text': text};
}

/// A cart suggested by the assistant. The customer reviews it in checkout;
/// the assistant never places orders.
class AssistantProposal {
  const AssistantProposal({
    required this.stationId,
    required this.stationName,
    required this.items,
    required this.subtotal,
    this.deliveryLabel,
    this.deliveryNote = '',
  });

  final String stationId;
  final String stationName;
  final List<({String id, String name, String kind, double price, int quantity})> items;
  final double subtotal;
  final String? deliveryLabel;
  final String deliveryNote;

  int get gallons => items
      .where((i) => i.kind != 'accessory')
      .fold(0, (s, i) => s + i.quantity);

  factory AssistantProposal.fromJson(Map<String, dynamic> j) => AssistantProposal(
        stationId: j['station_id'].toString(),
        stationName: (j['station_name'] ?? 'Station').toString(),
        items: [
          for (final i in (j['items'] as List? ?? const []))
            if (i is Map)
              (
                id: i['product_id'].toString(),
                name: (i['name'] ?? '').toString(),
                kind: (i['kind'] ?? 'water').toString(),
                price: (i['price'] as num?)?.toDouble() ?? 0,
                quantity: (i['quantity'] as num?)?.toInt() ?? 1,
              ),
        ],
        subtotal: (j['subtotal'] as num?)?.toDouble() ?? 0,
        deliveryLabel: j['delivery_label']?.toString(),
        deliveryNote: (j['delivery_note'] ?? '').toString(),
      );

  /// Replaces the cart with this proposal.
  void applyTo(CartProvider cart) {
    for (final id in cart.items.keys.toList()) {
      cart.removeItem(id);
    }
    cart.setStation(stationId, stationName);
    for (final i in items) {
      cart.addItem(i.id, i.name, i.price, kind: i.kind);
      cart.updateQuantity(i.id, i.quantity);
    }
  }
}

class AssistantReply {
  const AssistantReply({required this.text, this.proposal, this.remaining});
  final String text;
  final AssistantProposal? proposal;
  final int? remaining;
}

abstract interface class AssistantService {
  Future<AssistantReply> send(List<AssistantMessage> history);
}

/// Calls the `order-assistant` Edge Function (Claude runs server-side).
class SupabaseAssistantService implements AssistantService {
  @override
  Future<AssistantReply> send(List<AssistantMessage> history) async {
    try {
      final res = await Supabase.instance.client.functions.invoke(
        'order-assistant',
        body: {'messages': [for (final m in history) m.toJson()]},
      );
      final data = Map<String, dynamic>.from(res.data as Map);
      final p = data['proposal'];
      return AssistantReply(
        text: (data['reply'] ?? '').toString(),
        proposal: p is Map ? AssistantProposal.fromJson(Map<String, dynamic>.from(p)) : null,
        remaining: (data['remaining'] as num?)?.toInt(),
      );
    } on FunctionException catch (e) {
      final details = e.details;
      final msg = details is Map ? details['error']?.toString() : null;
      return AssistantReply(text: msg ?? 'The assistant is unavailable right now.');
    }
  }
}

/// "Ask eRefill" chat sheet.
class AskErefillSheet extends StatefulWidget {
  const AskErefillSheet({super.key, this.service, required this.onCheckout});

  final AssistantService? service;

  /// Called after the proposal is put in the cart, with its station id.
  final void Function(String stationId) onCheckout;

  @override
  State<AskErefillSheet> createState() => _AskErefillSheetState();
}

class _AskErefillSheetState extends State<AskErefillSheet> {
  late final AssistantService _svc = widget.service ?? SupabaseAssistantService();
  final _input = TextEditingController();
  final _messages = <AssistantMessage>[];
  AssistantProposal? _proposal;
  bool _busy = false;
  int? _remaining;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _busy) return;
    setState(() {
      _messages.add(AssistantMessage(fromUser: true, text: text));
      _input.clear();
      _busy = true;
    });
    final reply = await _svc.send(List.of(_messages));
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (reply.text.isNotEmpty) {
        _messages.add(AssistantMessage(fromUser: false, text: reply.text));
      }
      _proposal = reply.proposal ?? _proposal;
      _remaining = reply.remaining ?? _remaining;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = _proposal;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  Icon(Icons.auto_awesome_rounded, color: AppUi.brandOf(context)),
                  const SizedBox(width: 8),
                  Expanded(child: Text('Ask eRefill', style: theme.textTheme.titleMedium)),
                  if (_remaining != null)
                    Text('$_remaining left today', style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  if (_messages.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'Try: "3 gallons from my usual station tomorrow morning" '
                        'or "Order 2 gallons at seals sa suki ko."',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  for (final m in _messages)
                    Align(
                      alignment: m.fromUser ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        constraints: const BoxConstraints(maxWidth: 300),
                        decoration: BoxDecoration(
                          color: m.fromUser
                              ? AppUi.brandOf(context).withValues(alpha: 0.12)
                              : AppUi.surfaceRaisedOf(context),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(m.text, style: theme.textTheme.bodyMedium),
                      ),
                    ),
                  if (_busy)
                    const Padding(
                      padding: EdgeInsets.all(8),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  if (p != null) _proposalCard(context, p),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 8, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: const InputDecoration(hintText: 'What would you like to order?'),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Send',
                    onPressed: _busy ? null : _send,
                    icon: Icon(Icons.send_rounded, color: AppUi.brandOf(context)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _proposalCard(BuildContext context, AssistantProposal p) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(p.stationName, style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            for (final i in p.items)
              Text('${i.quantity} × ${i.name} · ${formatPeso(i.price * i.quantity)}'),
            if (p.deliveryLabel != null) Text(p.deliveryLabel!),
            if (p.deliveryNote.isNotEmpty) Text('Note: ${p.deliveryNote}'),
            const SizedBox(height: 4),
            Text('Subtotal ${formatPeso(p.subtotal)}', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () {
                p.applyTo(context.read<CartProvider>());
                widget.onCheckout(p.stationId);
              },
              child: const Text('Review & checkout'),
            ),
          ],
        ),
      ),
    );
  }
}
