import 'dart:typed_data';
import 'package:erefill/core/constants.dart';
import 'package:erefill/core/services/receipt_service.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:erefill/core/theme/app_colors.dart';
import 'package:erefill/core/utils/friendly_errors.dart';
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

  Future<_ReceiptEvidence> _loadEvidence() =>
      _resolveReceiptEvidence(widget.snapshot);

  void _retry() => setState(() => _evidence = _loadEvidence());

  @override
  Widget build(BuildContext context) {
    final snapshot = widget.snapshot;
    final total = _money(snapshot['total_amount']);
    final paid = _money(snapshot['amount_paid']);
    final outstanding = _money(snapshot['outstanding_balance']);
    final paymentStatus = snapshot['payment_status']?.toString() ?? 'pending';
    final paymentVerified =
        paymentStatus.toLowerCase() == 'success' ||
        paymentStatus.toLowerCase() == 'paid';

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
                color: AppColors.uiSuccess,
                size: 22,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Delivery Completed',
                  style: TextStyle(
                    color: AppUi.textPrimaryOf(context),
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
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
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            'Payment: $paymentStatus  |  Paid: $paid  |  Outstanding: $outstanding',
            style: TextStyle(
              color: paymentVerified
                  ? AppColors.uiSuccess
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
    if (url.isEmpty) {
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
          Container(
            height: 76,
            width: double.infinity,
            decoration: BoxDecoration(
              color: AppUi.surfaceRaisedOf(context),
              borderRadius: BorderRadius.circular(AppUi.radiusControl),
            ),
            alignment: Alignment.center,
            child: Icon(
              label.contains('Signature')
                  ? Icons.draw_outlined
                  : Icons.image_not_supported_outlined,
              color: AppUi.textSecondaryOf(context),
            ),
          ),
        ],
      );
    }
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
            borderRadius: BorderRadius.circular(AppUi.radiusControl),
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
                  tooltip: 'Close',
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

  Future<_ReceiptEvidence> _loadEvidence() =>
      _resolveReceiptEvidence(widget.snapshot);

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
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
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
                    style: TextStyle(fontWeight: FontWeight.w700),
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
      final snapshot = widget.snapshot;
      final rawPhoto =
          snapshot['photo_path']?.toString() ??
          snapshot['photo_url']?.toString() ??
          snapshot['delivery_photo_url']?.toString();
      final rawSignature =
          snapshot['signature_path']?.toString() ??
          snapshot['signature_url']?.toString();

      final evidence = await _evidence;

      Future<Uint8List?> fetchEvidenceBytes(
        String? raw,
        String resolvedUrl,
      ) async {
        if (raw != null &&
            raw.trim().isNotEmpty &&
            !raw.trim().startsWith('http')) {
          try {
            final bytes = await storage.download(raw.trim());
            if (bytes.isNotEmpty) return bytes;
          } catch (_) {}
        }
        final urlToFetch = resolvedUrl.isNotEmpty
            ? resolvedUrl
            : ((raw != null && raw.trim().startsWith('http')) ? raw.trim() : '');
        if (urlToFetch.isNotEmpty) {
          try {
            final res = await http.get(Uri.parse(urlToFetch));
            if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
              return res.bodyBytes;
            }
          } catch (_) {}
        }
        return null;
      }

      final photo = await fetchEvidenceBytes(rawPhoto, evidence.photoUrl);
      final signature =
          await fetchEvidenceBytes(rawSignature, evidence.signatureUrl);

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
          SnackBar(content: Text('Could not prepare receipt PDF: ${FriendlyErrors.message(error)}')),
        );
      }
    } finally {
      if (mounted) setState(() => _isPrinting = false);
    }
  }

  Widget _evidenceCard(BuildContext context, String title, String url) {
    if (url.isEmpty) {
      return Card(
        child: ListTile(
          leading: Icon(
            title.contains('Signature')
                ? Icons.draw_outlined
                : Icons.image_not_supported_outlined,
            color: AppUi.textSecondaryOf(context),
          ),
          title: Text(title),
          subtitle: const Text('No digital evidence recorded for this order.'),
        ),
      );
    }
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
              errorBuilder: (_, _, _) => Container(
                height: 120,
                color: AppUi.surfaceRaisedOf(context),
                alignment: Alignment.center,
                child: const Icon(Icons.broken_image_outlined),
              ),
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

Future<_ReceiptEvidence> _resolveReceiptEvidence(
  Map<String, dynamic> snapshot,
) async {
  final storage = Supabase.instance.client.storage.from('delivery_proofs');
  final rawPhoto =
      snapshot['photo_path']?.toString() ??
      snapshot['photo_url']?.toString() ??
      snapshot['delivery_photo_url']?.toString();
  final rawSignature =
      snapshot['signature_path']?.toString() ??
      snapshot['signature_url']?.toString();

  String photoUrl = '';
  String signatureUrl = '';

  if (rawPhoto != null && rawPhoto.trim().isNotEmpty) {
    final trimmed = rawPhoto.trim();
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      photoUrl = trimmed;
    } else {
      try {
        photoUrl = await storage.createSignedUrl(trimmed, 3600);
      } catch (_) {
        try {
          photoUrl = storage.getPublicUrl(trimmed);
        } catch (_) {}
      }
    }
  }

  if (rawSignature != null && rawSignature.trim().isNotEmpty) {
    final trimmed = rawSignature.trim();
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      signatureUrl = trimmed;
    } else {
      try {
        signatureUrl = await storage.createSignedUrl(trimmed, 3600);
      } catch (_) {
        try {
          signatureUrl = storage.getPublicUrl(trimmed);
        } catch (_) {}
      }
    }
  }

  return _ReceiptEvidence(photoUrl: photoUrl, signatureUrl: signatureUrl);
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
