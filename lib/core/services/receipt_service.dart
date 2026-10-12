import 'dart:convert' show utf8;
import 'dart:typed_data';
import 'package:flutter/material.dart' show BuildContext, debugPrint;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class ReceiptService {
  ReceiptService._();

  /// Formats date string to readable format without requiring external packages
  static String _formatDate(dynamic dateValue) {
    if (dateValue == null) return 'N/A';
    try {
      final dt = DateTime.parse(dateValue.toString()).toLocal();
      final months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
      ];
      final month = months[dt.month - 1];
      final day = dt.day.toString().padLeft(2, '0');
      final year = dt.year;
      final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
      final minute = dt.minute.toString().padLeft(2, '0');
      final period = dt.hour >= 12 ? 'PM' : 'AM';
      return '$month $day, $year - $hour:$minute $period';
    } catch (_) {
      return dateValue.toString();
    }
  }

  /// Generates receipt PDF byte array
  static Future<Uint8List> generateReceiptPdf({
    required Map<String, dynamic> order,
    List<Map<String, dynamic>> items = const [],
    Map<String, dynamic>? station,
  }) async {
    final pdf = pw.Document();

    final orderId = (order['id'] ?? '').toString();
    final shortId = orderId.length > 8 ? orderId.substring(0, 8).toUpperCase() : orderId.toUpperCase();
    final createdAt = _formatDate(order['created_at']);
    final status = (order['status'] ?? 'pending').toString().toUpperCase();

    // Customer snapshot
    final customerName = (order['customer_name'] ?? order['customer']?['full_name'] ?? 'Customer').toString();
    final customerAddress = (order['customer_address'] ?? order['address'] ?? 'Delivery Address').toString();
    final customerPhone = (order['customer_phone'] ?? order['phone'] ?? '').toString();
    final barangay = (order['customer_barangay'] ?? '').toString();

    // Station details
    final stationName = (station?['name'] ?? order['station_name'] ?? order['station']?['name'] ?? 'eRefill Water Station').toString();
    final stationAddress =
        (station?['address'] ??
                order['station_address'] ??
                'Cantilan & Madrid, Surigao del Sur')
            .toString();
    final stationPhone = (station?['phone'] ?? '').toString();

    // Financials
    final subtotal = (order['subtotal'] as num?)?.toDouble() ??
        ((order['total_amount'] as num?)?.toDouble() ?? 0) - ((order['delivery_fee'] as num?)?.toDouble() ?? 0);
    final deliveryFee = (order['delivery_fee'] as num?)?.toDouble() ?? 0.0;
    final totalAmount = (order['total_amount'] as num?)?.toDouble() ?? (subtotal + deliveryFee);
    final explicitFee = (order['platform_fee'] as num?)?.toDouble();
    final serviceFee = explicitFee ??
        ((totalAmount - (subtotal + deliveryFee)) > 0.01
            ? (totalAmount - (subtotal + deliveryFee))
            : 0.0);
    final paymentMethod = (order['payment_method'] ?? 'COD').toString().toUpperCase();
    final paymentStatus = (order['payment_status'] ?? 'pending').toString().toUpperCase();

    // Prepare line items
    final List<Map<String, dynamic>> resolvedItems = [];
    if (items.isNotEmpty) {
      resolvedItems.addAll(items);
    } else if (order['order_items'] is List && (order['order_items'] as List).isNotEmpty) {
      resolvedItems.addAll(List<Map<String, dynamic>>.from(order['order_items']));
    } else {
      resolvedItems.add({
        'product_name': order['water_type'] ?? 'Water Refill',
        'quantity': order['quantity'] ?? 1,
        'unit_price': (order['price_per_gallon'] as num?)?.toDouble() ?? (subtotal > 0 ? subtotal : totalAmount),
        'total_price': subtotal > 0 ? subtotal : totalAmount,
      });
    }

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Header Banner
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'eRefill',
                        style: pw.TextStyle(
                          fontSize: 28,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColor.fromHex('#2563EB'),
                        ),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        'Water Refilling & Delivery Service',
                        style: const pw.TextStyle(
                          fontSize: 10,
                          color: PdfColors.grey700,
                        ),
                      ),
                    ],
                  ),
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: pw.BoxDecoration(
                      color: PdfColor.fromHex('#EFF6FF'),
                      borderRadius: pw.BorderRadius.circular(6),
                      border: pw.Border.all(color: PdfColor.fromHex('#BFDBFE')),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text(
                          'RECEIPT',
                          style: pw.TextStyle(
                            fontSize: 14,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColor.fromHex('#1E3A8A'),
                          ),
                        ),
                        pw.Text(
                          '#$shortId',
                          style: pw.TextStyle(
                            fontSize: 11,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColor.fromHex('#2563EB'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 20),
              pw.Divider(color: PdfColors.grey300, thickness: 1),
              pw.SizedBox(height: 12),

              // Station & Customer Details
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  // Station Details
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'WATER REFILL STATION',
                          style: pw.TextStyle(
                            fontSize: 9,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.grey600,
                          ),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          stationName,
                          style: pw.TextStyle(
                            fontSize: 12,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          stationAddress,
                          style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                        ),
                        if (stationPhone.isNotEmpty) ...[
                          pw.SizedBox(height: 2),
                          pw.Text(
                            'Phone: $stationPhone',
                            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                          ),
                        ],
                      ],
                    ),
                  ),
                  pw.SizedBox(width: 24),
                  // Customer Details
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'DELIVERY DETAILS',
                          style: pw.TextStyle(
                            fontSize: 9,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.grey600,
                          ),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          customerName,
                          style: pw.TextStyle(
                            fontSize: 12,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          barangay.isNotEmpty ? '$customerAddress, Brgy. $barangay' : customerAddress,
                          style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                        ),
                        if (customerPhone.isNotEmpty) ...[
                          pw.SizedBox(height: 2),
                          pw.Text(
                            'Phone: $customerPhone',
                            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 16),

              // Order Metadata Box
              pw.Container(
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey100,
                  borderRadius: pw.BorderRadius.circular(6),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('Date & Time', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
                        pw.SizedBox(height: 2),
                        pw.Text(createdAt, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                      ],
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('Order Status', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
                        pw.SizedBox(height: 2),
                        pw.Text(status, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColor.fromHex('#2563EB'))),
                      ],
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('Payment Method', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
                        pw.SizedBox(height: 2),
                        pw.Text(paymentMethod, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                      ],
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('Payment Status', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
                        pw.SizedBox(height: 2),
                        pw.Text(paymentStatus, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: paymentStatus == 'SUCCESS' || paymentStatus == 'PAID' ? PdfColors.green700 : PdfColors.amber800)),
                      ],
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 20),

              // Items Table Header
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                decoration: pw.BoxDecoration(
                  color: PdfColor.fromHex('#2563EB'),
                  borderRadius: const pw.BorderRadius.vertical(top: pw.Radius.circular(4)),
                ),
                child: pw.Row(
                  children: [
                    pw.Expanded(
                      flex: 4,
                      child: pw.Text('Item Description', style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 10)),
                    ),
                    pw.Expanded(
                      flex: 2,
                      child: pw.Text('Qty', textAlign: pw.TextAlign.center, style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 10)),
                    ),
                    pw.Expanded(
                      flex: 2,
                      child: pw.Text('Unit Price', textAlign: pw.TextAlign.right, style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 10)),
                    ),
                    pw.Expanded(
                      flex: 2,
                      child: pw.Text('Total', textAlign: pw.TextAlign.right, style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 10)),
                    ),
                  ],
                ),
              ),

              // Line Items Rows
              pw.ListView.builder(
                itemCount: resolvedItems.length,
                itemBuilder: (context, index) {
                  final item = resolvedItems[index];
                  final name = (item['product_name'] ?? item['water_type'] ?? 'Water refill').toString();
                  final qty = item['quantity'] ?? 1;
                  final unitPrice = (item['unit_price'] as num?)?.toDouble() ?? 0.0;
                  final lineTotal = (item['total_price'] as num?)?.toDouble() ?? (unitPrice * (qty is num ? qty : 1));

                  return pw.Container(
                    padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                    decoration: pw.BoxDecoration(
                      color: index % 2 == 1 ? PdfColors.grey50 : PdfColors.white,
                      border: const pw.Border(
                        bottom: pw.BorderSide(color: PdfColors.grey200, width: 0.5),
                        left: pw.BorderSide(color: PdfColors.grey200, width: 0.5),
                        right: pw.BorderSide(color: PdfColors.grey200, width: 0.5),
                      ),
                    ),
                    child: pw.Row(
                      children: [
                        pw.Expanded(
                          flex: 4,
                          child: pw.Text(name, style: const pw.TextStyle(fontSize: 10)),
                        ),
                        pw.Expanded(
                          flex: 2,
                          child: pw.Text('$qty', textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 10)),
                        ),
                        pw.Expanded(
                          flex: 2,
                          child: pw.Text('PHP ${unitPrice.toStringAsFixed(2)}', textAlign: pw.TextAlign.right, style: const pw.TextStyle(fontSize: 10)),
                        ),
                        pw.Expanded(
                          flex: 2,
                          child: pw.Text('PHP ${lineTotal.toStringAsFixed(2)}', textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                        ),
                      ],
                    ),
                  );
                },
              ),
              pw.SizedBox(height: 16),

              // Totals Section
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.end,
                children: [
                  pw.Container(
                    width: 220,
                    child: pw.Column(
                      children: [
                        pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                          children: [
                            pw.Text('Subtotal:', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                            pw.Text('PHP ${subtotal.toStringAsFixed(2)}', style: const pw.TextStyle(fontSize: 10)),
                          ],
                        ),
                        pw.SizedBox(height: 4),
                        pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                          children: [
                            pw.Text('Delivery Fee:', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                            pw.Text('PHP ${deliveryFee.toStringAsFixed(2)}', style: const pw.TextStyle(fontSize: 10)),
                          ],
                        ),
                        if (serviceFee > 0) ...[
                          pw.SizedBox(height: 4),
                          pw.Row(
                            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                            children: [
                              pw.Text('Service Fee:', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                              pw.Text('PHP ${serviceFee.toStringAsFixed(2)}', style: const pw.TextStyle(fontSize: 10)),
                            ],
                          ),
                        ],
                        pw.SizedBox(height: 6),
                        pw.Divider(color: PdfColors.grey400, thickness: 0.5),
                        pw.SizedBox(height: 4),
                        pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                          children: [
                            pw.Text('Grand Total:', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: PdfColor.fromHex('#1E3A8A'))),
                            pw.Text(
                              'PHP ${totalAmount.toStringAsFixed(2)}',
                              style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: PdfColor.fromHex('#2563EB')),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              pw.Spacer(),

              // Footer & Water Safety Assurance
              pw.Divider(color: PdfColors.grey300, thickness: 1),
              pw.SizedBox(height: 8),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'Thank you for ordering with eRefill!',
                        style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColor.fromHex('#2563EB')),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        'Clean, safe water delivered to your doorstep across Cantilan and Madrid.',
                        style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
                      ),
                    ],
                  ),
                  pw.Container(
                    height: 42,
                    width: 42,
                    child: pw.BarcodeWidget(
                      barcode: pw.Barcode.qrCode(),
                      data: 'erefill://$orderId',
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  /// Opens the print / preview dialog
  static Future<void> printReceipt({
    BuildContext? context,
    required Map<String, dynamic> order,
    List<Map<String, dynamic>> items = const [],
    Map<String, dynamic>? station,
  }) async {
    try {
      final pdfBytes = await generateReceiptPdf(
        order: order,
        items: items,
        station: station,
      );

      final orderId = (order['id'] ?? '').toString();
      final shortId = orderId.length > 8 ? orderId.substring(0, 8).toUpperCase() : orderId.toUpperCase();

      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdfBytes,
        name: 'eRefill_Receipt_$shortId.pdf',
      );
    } catch (e) {
      debugPrint('Error printing receipt: $e');
    }
  }

  /// Shares the receipt PDF file
  static Future<void> shareReceipt({
    BuildContext? context,
    required Map<String, dynamic> order,
    List<Map<String, dynamic>> items = const [],
    Map<String, dynamic>? station,
  }) async {
    try {
      final pdfBytes = await generateReceiptPdf(
        order: order,
        items: items,
        station: station,
      );

      final orderId = (order['id'] ?? '').toString();
      final shortId = orderId.length > 8 ? orderId.substring(0, 8).toUpperCase() : orderId.toUpperCase();

      await Printing.sharePdf(
        bytes: pdfBytes,
        filename: 'eRefill_Receipt_$shortId.pdf',
      );
    } catch (e) {
      debugPrint('Error sharing receipt: $e');
    }
  }

  /// Generates a roll PDF tailored specifically for 58mm or 80mm mobile thermal printers
  static Future<Uint8List> generateThermalReceiptPdf({
    required Map<String, dynamic> order,
    List<Map<String, dynamic>> items = const [],
    Map<String, dynamic>? station,
    bool is58mm = true,
  }) async {
    final pdf = pw.Document();
    final pageFormat = is58mm ? PdfPageFormat.roll57 : PdfPageFormat.roll80;

    final orderId = (order['id'] ?? '').toString();
    final shortId = orderId.length > 8 ? orderId.substring(0, 8).toUpperCase() : orderId.toUpperCase();
    final createdAt = _formatDate(order['created_at']);
    final stationName = (station?['name'] ?? order['station_name'] ?? 'eRefill Station').toString();
    final customerName = (order['customer_name'] ?? order['customer']?['full_name'] ?? 'Customer').toString();
    final customerAddress = (order['customer_address'] ?? order['address'] ?? 'Delivery Address').toString();

    final subtotal = (order['subtotal'] as num?)?.toDouble() ??
        ((order['total_amount'] as num?)?.toDouble() ?? 0) - ((order['delivery_fee'] as num?)?.toDouble() ?? 0);
    final deliveryFee = (order['delivery_fee'] as num?)?.toDouble() ?? 0.0;
    final totalAmount = (order['total_amount'] as num?)?.toDouble() ?? (subtotal + deliveryFee);
    final paymentMethod = (order['payment_method'] ?? 'COD').toString().toUpperCase();

    final List<Map<String, dynamic>> resolvedItems = [];
    if (items.isNotEmpty) {
      resolvedItems.addAll(items);
    } else if (order['order_items'] is List && (order['order_items'] as List).isNotEmpty) {
      resolvedItems.addAll(List<Map<String, dynamic>>.from(order['order_items']));
    } else {
      resolvedItems.add({
        'product_name': order['water_type'] ?? 'Water Refill',
        'quantity': order['quantity'] ?? 1,
        'total_price': subtotal > 0 ? subtotal : totalAmount,
      });
    }

    pdf.addPage(
      pw.Page(
        pageFormat: pageFormat,
        margin: const pw.EdgeInsets.all(6),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Text(
                stationName.toUpperCase(),
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11),
                textAlign: pw.TextAlign.center,
              ),
              pw.SizedBox(height: 2),
              pw.Text('OFFICIAL WATER REFILL RECEIPT', style: const pw.TextStyle(fontSize: 8)),
              pw.Text('Order: #$shortId', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8)),
              pw.Text(createdAt, style: const pw.TextStyle(fontSize: 7)),
              pw.Text('--------------------------------', style: const pw.TextStyle(fontSize: 8)),
              pw.Align(
                alignment: pw.Alignment.centerLeft,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('Cust: $customerName', style: const pw.TextStyle(fontSize: 8)),
                    pw.Text('Addr: $customerAddress', style: const pw.TextStyle(fontSize: 7), maxLines: 2),
                  ],
                ),
              ),
              pw.Text('--------------------------------', style: const pw.TextStyle(fontSize: 8)),
              // Line items
              ...resolvedItems.map((it) {
                final qty = it['quantity'] ?? 1;
                final name = (it['product_name'] ?? 'Water').toString();
                final price = ((it['total_price'] ?? it['price'] ?? 0) as num).toDouble();
                return pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Expanded(
                      child: pw.Text('$qty x $name', style: const pw.TextStyle(fontSize: 8)),
                    ),
                    pw.Text('P${price.toStringAsFixed(2)}', style: const pw.TextStyle(fontSize: 8)),
                  ],
                );
              }),
              pw.Text('--------------------------------', style: const pw.TextStyle(fontSize: 8)),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Subtotal:', style: const pw.TextStyle(fontSize: 8)),
                  pw.Text('P${subtotal.toStringAsFixed(2)}', style: const pw.TextStyle(fontSize: 8)),
                ],
              ),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Delivery Fee:', style: const pw.TextStyle(fontSize: 8)),
                  pw.Text('P${deliveryFee.toStringAsFixed(2)}', style: const pw.TextStyle(fontSize: 8)),
                ],
              ),
              pw.SizedBox(height: 2),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('TOTAL DUE:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                  pw.Text('P${totalAmount.toStringAsFixed(2)}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                ],
              ),
              pw.SizedBox(height: 2),
              pw.Text('Paid via: $paymentMethod', style: const pw.TextStyle(fontSize: 8)),
              pw.Text('--------------------------------', style: const pw.TextStyle(fontSize: 8)),
              pw.Text('Thank you for choosing eRefill!', style: const pw.TextStyle(fontSize: 8)),
              pw.SizedBox(height: 10),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  /// Sends a thermal-formatted receipt directly to a connected thermal roll printer
  static Future<void> printThermalReceipt({
    BuildContext? context,
    required Map<String, dynamic> order,
    List<Map<String, dynamic>> items = const [],
    Map<String, dynamic>? station,
    bool is58mm = true,
  }) async {
    try {
      final pdfBytes = await generateThermalReceiptPdf(
        order: order,
        items: items,
        station: station,
        is58mm: is58mm,
      );

      final orderId = (order['id'] ?? '').toString();
      final shortId = orderId.length > 8 ? orderId.substring(0, 8).toUpperCase() : orderId.toUpperCase();

      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdfBytes,
        name: 'eRefill_Thermal_$shortId.pdf',
        format: is58mm ? PdfPageFormat.roll57 : PdfPageFormat.roll80,
      );
    } catch (e) {
      debugPrint('Error printing thermal receipt: $e');
    }
  }

  /// Generates raw ESC/POS byte sequence for Bluetooth / USB POS thermal printers
  static Uint8List generateEscPosBytes({
    required Map<String, dynamic> order,
    List<Map<String, dynamic>> items = const [],
    Map<String, dynamic>? station,
    bool is58mm = true,
  }) {
    final buffer = <int>[];
    final widthChars = is58mm ? 32 : 48;
    final divider = '-' * widthChars;

    // Helper closures
    void writeBytes(List<int> bytes) => buffer.addAll(bytes);
    void writeLine(String line) => buffer.addAll(utf8.encode('$line\n'));

    // ESC @ (Initialize printer)
    writeBytes([0x1B, 0x40]);

    // ESC a 1 (Align Center)
    writeBytes([0x1B, 0x61, 0x01]);

    // ESC E 1 (Bold ON)
    writeBytes([0x1B, 0x45, 0x01]);
    final stationName = (station?['name'] ?? order['station_name'] ?? 'eRefill Station').toString();
    writeLine(stationName.toUpperCase());

    // ESC E 0 (Bold OFF)
    writeBytes([0x1B, 0x45, 0x00]);
    writeLine('OFFICIAL WATER REFILL RECEIPT');

    final orderId = (order['id'] ?? '').toString();
    final shortId = orderId.length > 8 ? orderId.substring(0, 8).toUpperCase() : orderId.toUpperCase();
    writeLine('Order #$shortId');
    writeLine(_formatDate(order['created_at']));
    writeLine(divider);

    // ESC a 0 (Align Left)
    writeBytes([0x1B, 0x61, 0x00]);
    final customerName = (order['customer_name'] ?? order['customer']?['full_name'] ?? 'Customer').toString();
    final customerAddress = (order['customer_address'] ?? order['address'] ?? 'Delivery Address').toString();
    writeLine('Customer: $customerName');
    writeLine('Address: $customerAddress');
    writeLine(divider);

    // Line items
    final subtotal = (order['subtotal'] as num?)?.toDouble() ??
        ((order['total_amount'] as num?)?.toDouble() ?? 0) - ((order['delivery_fee'] as num?)?.toDouble() ?? 0);
    final deliveryFee = (order['delivery_fee'] as num?)?.toDouble() ?? 0.0;
    final totalAmount = (order['total_amount'] as num?)?.toDouble() ?? (subtotal + deliveryFee);

    final List<Map<String, dynamic>> resolvedItems = [];
    if (items.isNotEmpty) {
      resolvedItems.addAll(items);
    } else if (order['order_items'] is List && (order['order_items'] as List).isNotEmpty) {
      resolvedItems.addAll(List<Map<String, dynamic>>.from(order['order_items']));
    } else {
      resolvedItems.add({
        'product_name': order['water_type'] ?? 'Water Refill',
        'quantity': order['quantity'] ?? 1,
        'total_price': subtotal > 0 ? subtotal : totalAmount,
      });
    }

    for (final it in resolvedItems) {
      final qty = it['quantity'] ?? 1;
      final name = (it['product_name'] ?? 'Refill').toString();
      final price = ((it['total_price'] ?? 0) as num).toDouble();
      final itemDesc = '$qty x $name';
      final priceStr = 'P${price.toStringAsFixed(2)}';
      final spaces = widthChars - itemDesc.length - priceStr.length;
      if (spaces > 0) {
        writeLine('$itemDesc${' ' * spaces}$priceStr');
      } else {
        writeLine(itemDesc);
        writeLine('${' ' * (widthChars - priceStr.length)}$priceStr');
      }
    }

    writeLine(divider);
    // Subtotal & Delivery
    final subStr = 'P${subtotal.toStringAsFixed(2)}';
    writeLine('Subtotal:${' ' * (widthChars - 9 - subStr.length)}$subStr');

    final delStr = 'P${deliveryFee.toStringAsFixed(2)}';
    writeLine('Delivery:${' ' * (widthChars - 9 - delStr.length)}$delStr');

    writeLine(divider);

    // ESC E 1 (Bold ON)
    writeBytes([0x1B, 0x45, 0x01]);
    final totalStr = 'P${totalAmount.toStringAsFixed(2)}';
    writeLine('TOTAL:${' ' * (widthChars - 6 - totalStr.length)}$totalStr');
    writeBytes([0x1B, 0x45, 0x00]);

    writeLine(divider);

    // ESC a 1 (Align Center)
    writeBytes([0x1B, 0x61, 0x01]);
    writeLine('Thank you for choosing eRefill!');
    writeLine('Stay Hydrated!');

    // Line feeds
    writeBytes([0x0A, 0x0A, 0x0A]);

    // GS V 66 0 (Paper cut)
    writeBytes([0x1D, 0x56, 0x42, 0x00]);

    return Uint8List.fromList(buffer);
  }
}
