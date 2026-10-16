import 'package:erefill/core/constants.dart';
import 'package:erefill/core/services/receipt_service.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DeliveryReceiptMessage extends StatefulWidget {
  const DeliveryReceiptMessage({super.key, required this.snapshot});

  final Map<String, dynamic> snapshot;

  @override
  State<DeliveryReceiptMessage> createState() => _DeliveryReceiptMessageState();
}

class _DeliveryReceiptMessageState extends State<DeliveryReceiptMessage> {
  late Future<_ReceiptEvidence> _evidence;

  @override
  void initState() {
    super.initState();
    _evidence = _loadEvidence();
  }

  Future<_ReceiptEvidence> _loadEvidence() async {
    final storage = Supabase.instance.client.storage.from('delivery_proofs');
    final photoPath = widget.snapshot['photo_path']?.toString();
    final signaturePath = widget.snapshot['signature_path']?.toString();
    if (photoPath == null || signaturePath == null) {
      throw StateError('Receipt evidence references are missing.');
    }
    final urls = await Future.wait([
      storage.createSignedUrl(photoPath, 600),
      storage.createSignedUrl(signaturePath, 600),
    ]);
    return _ReceiptEvidence(photoUrl: urls[0], signatureUrl: urls[1]);
  }

  void _retry() => setState(() => _evidence = _loadEvidence());

  @override
  Widget build(BuildContext context) {
    final snapshot = widget.snapshot;
    final total = _money(snapshot['total_amount']);
    final paid = _money(snapshot['amount_paid']);
    final outstanding = _money(snapshot['outstanding_balance']);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppUi.surfaceOf(context),
        border: Border.all(color: AppUi.borderOf(context)),
        borderRadius: AppUi.cardRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.verified_rounded,
                color: Color(0xFF16A34A),
                size: 22,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Delivery Completed',
                  style: TextStyle(
                    color: AppUi.textPrimaryOf(context),
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Order #${snapshot['reference_number'] ?? ''}',
            style: TextStyle(
              color: AppUi.textSecondaryOf(context),
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            _date(snapshot['delivered_at']),
            style: TextStyle(
              color: AppUi.textSecondaryOf(context),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Total $total',
            style: TextStyle(
              color: AppUi.textPrimaryOf(context),
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            outstanding <= 0
                ? 'Paid: $paid'
                : 'Paid: $paid  |  Outstanding: $outstanding',
            style: TextStyle(
              color: outstanding <= 0
                  ? const Color(0xFF15803D)
                  : AppUi.textSecondaryOf(context),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          FutureBuilder<_ReceiptEvidence>(
            future: _evidence,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Row(
                  children: [
                    const Expanded(
                      child: Text('Delivery evidence could not be loaded.'),
                    ),
                    TextButton(onPressed: _retry, child: const Text('Retry')),
                  ],
                );
              }
              if (!snapshot.hasData) {
                return const SizedBox(
                  height: 72,
                  child: Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                );
              }
              return Row(
                children: [
                  Expanded(
                    child: _thumbnail(
                      context,
                      label: 'Delivery photo',
                      url: snapshot.data!.photoUrl,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _thumbnail(
                      context,
                      label: 'Signature',
                      url: snapshot.data!.signatureUrl,
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      DeliveryReceiptScreen(snapshot: widget.snapshot),
                ),
              ),
              icon: const Icon(Icons.receipt_long_rounded),
              label: const Text('View full receipt'),
            ),
          ),
          Text(
            'Receipt ${snapshot['receipt_number'] ?? ''}  |  ${snapshot['rider_name'] ?? 'Rider'}',
            style: TextStyle(
              color: AppUi.textSecondaryOf(context),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _thumbnail(
    BuildContext context, {
    required String label,
    required String url,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: AppUi.textSecondaryOf(context),
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 5),
        GestureDetector(
          onTap: () => _showImage(context, url, label),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.network(
              url,
              height: 76,
              width: double.infinity,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(
                height: 76,
                color: AppUi.surfaceRaisedOf(context),
                alignment: Alignment.center,
                child: const Icon(Icons.broken_image_outlined),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _showImage(BuildContext context, String url, String title) {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppBar(
              title: Text(title),
              automaticallyImplyLeading: false,
              actions: [
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            Flexible(
              child: InteractiveViewer(
                child: Image.network(url, fit: BoxFit.contain),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class DeliveryReceiptScreen extends StatefulWidget {
  const DeliveryReceiptScreen({super.key, required this.snapshot});

  final Map<String, dynamic> snapshot;

  @override
  State<DeliveryReceiptScreen> createState() => _DeliveryReceiptScreenState();
}

class _DeliveryReceiptScreenState extends State<DeliveryReceiptScreen> {
  late Future<_ReceiptEvidence> _evidence;
  bool _isPrinting = false;

  @override
  void initState() {
    super.initState();
    _evidence = _loadEvidence();
  }

  Future<_ReceiptEvidence> _loadEvidence() async {
    final storage = Supabase.instance.client.storage.from('delivery_proofs');
    final photoPath = widget.snapshot['photo_path']?.toString();
    final signaturePath = widget.snapshot['signature_path']?.toString();
    if (photoPath == null || signaturePath == null) {
      throw StateError('Receipt evidence references are missing.');
    }
    final urls = await Future.wait([
      storage.createSignedUrl(photoPath, 600),
      storage.createSignedUrl(signaturePath, 600),
    ]);
    return _ReceiptEvidence(photoUrl: urls[0], signatureUrl: urls[1]);
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = widget.snapshot;
    final items = _items(snapshot['items']);
    final paid = _numeric(snapshot['amount_paid']);
    final due = _numeric(snapshot['outstanding_balance']);

    return Scaffold(
      appBar: AppBar(title: const Text('Delivery receipt')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Erefill - Delivery Receipt',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  Text('Receipt ${snapshot['receipt_number'] ?? ''}'),
                  Text('Order #${snapshot['reference_number'] ?? ''}'),
                  const SizedBox(height: 12),
                  _detail('Status', 'Delivered'),
                  _detail('Delivered at', _date(snapshot['delivered_at'])),
                  _detail('Customer', snapshot['customer_name']),
                  _detail('Recipient', snapshot['recipient_name']),
                  _detail('Station', snapshot['station_name']),
                  _detail('Rider', snapshot['rider_name']),
                  _detail('Address', snapshot['delivery_address']),
                  _detail(
                    'Payment',
                    '${snapshot['payment_method'] ?? 'Unknown'} - ${snapshot['payment_status'] ?? 'Unknown'}',
                  ),
                  _detail('Amount paid', _currency(paid)),
                  _detail('Outstanding balance', _currency(due)),
                  _detail(
                    'Subtotal',
                    _currency(_numeric(snapshot['subtotal'])),
                  ),
                  _detail(
                    'Delivery fee',
                    _currency(_numeric(snapshot['delivery_fee'])),
                  ),
                  _detail(
                    'Total',
                    _currency(_numeric(snapshot['total_amount'])),
                  ),
                ],
              ),
            ),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Delivered items',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  for (final item in items)
                    _detail(
                      '${item['product_name'] ?? item['water_type'] ?? 'Water refill'} x${item['quantity'] ?? 1}',
                      _currency(
                        _numeric(item['total_price']) != 0
                            ? item['total_price']
                            : _numeric(item['unit_price']) *
                                  _numeric(item['quantity']),
                      ),
                    ),
                ],
              ),
            ),
          ),
          FutureBuilder<_ReceiptEvidence>(
            future: _evidence,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Card(
                  child: ListTile(
                    title: const Text('Could not load private delivery proof.'),
                    trailing: IconButton(
                      tooltip: 'Retry',
                      onPressed: () => setState(() {
                        _evidence = _loadEvidence();
                      }),
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                  ),
                );
              }
              if (!snapshot.hasData) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              return Column(
                children: [
                  _evidenceCard(
                    context,
                    'Delivery photo',
                    snapshot.data!.photoUrl,
                  ),
                  _evidenceCard(
                    context,
                    'Recipient signature',
                    snapshot.data!.signatureUrl,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _isPrinting ? null : _printReceipt,
            icon: _isPrinting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.print_rounded),
            label: Text(_isPrinting ? 'Preparing PDF...' : 'Print or save PDF'),
          ),
        ],
      ),
    );
  }

  Future<void> _printReceipt() async {
    setState(() => _isPrinting = true);
    try {
      final storage = Supabase.instance.client.storage.from('delivery_proofs');
      final photo = await storage.download(widget.snapshot['photo_path']);
      final signature = await storage.download(
        widget.snapshot['signature_path'],
      );
      final snapshot = widget.snapshot;
      final orderId = snapshot['order_id']?.toString() ?? '';
      final order = <String, dynamic>{
        ...snapshot,
        'id': orderId,
        'status': 'delivered',
        'customer_address': snapshot['delivery_address'],
        'created_at': snapshot['delivered_at'],
      };
      final bytes = await ReceiptService.generateReceiptPdf(
        order: order,
        items: _items(snapshot['items']),
        deliveryReceipt: snapshot,
        deliveryPhoto: photo,
        recipientSignature: signature,
      );
      await Printing.layoutPdf(
        onLayout: (_) async => bytes,
        name: '${snapshot['receipt_number'] ?? 'eRefill_Receipt'}.pdf',
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not prepare receipt PDF: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _isPrinting = false);
    }
  }

  Widget _evidenceCard(BuildContext context, String title, String url) {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(title: Text(title)),
          GestureDetector(
            onTap: () => showDialog<void>(
              context: context,
              builder: (context) => Dialog(
                child: InteractiveViewer(
                  child: Image.network(url, fit: BoxFit.contain),
                ),
              ),
            ),
            child: Image.network(
              url,
              width: double.infinity,
              height: title == 'Delivery photo' ? 240 : 160,
              fit: BoxFit.contain,
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _detail(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 132, child: Text(label)),
          Expanded(
            child: Text(
              value?.toString() ?? 'Not available',
              textAlign: TextAlign.end,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _items(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }
}

class _ReceiptEvidence {
  const _ReceiptEvidence({required this.photoUrl, required this.signatureUrl});

  final String photoUrl;
  final String signatureUrl;
}

String _date(dynamic value) {
  final parsed = DateTime.tryParse(value?.toString() ?? '');
  if (parsed == null) return 'Time not available';
  return DateFormat('MMMM d, yyyy h:mm a').format(parsed.toLocal());
}

double _numeric(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

String _currency(dynamic value) => 'PHP ${_numeric(value).toStringAsFixed(2)}';

double _money(dynamic value) => _numeric(value);
