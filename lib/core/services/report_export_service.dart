import 'dart:typed_data';
import 'package:flutter/material.dart' show BuildContext, debugPrint;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class ReportExportService {
  ReportExportService._();

  static String _formatDate(DateTime dt) {
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final month = months[dt.month - 1];
    final day = dt.day.toString().padLeft(2, '0');
    final year = dt.year;
    return '$month $day, $year';
  }

  /// Generates the Sales, Deliveries & Tax PDF report byte array
  static Future<Uint8List> generateReportPdf({
    required String stationName,
    String? stationAddress,
    String? stationPhone,
    required String rangeLabel,
    required int totalDeliveries,
    required double totalGallons,
    required double totalIncome,
    required double totalExpenses,
    required double totalCommission,
    required double netProfit,
    double taxRate = 0.03, // Default 3% business percentage tax
    List<Map<String, dynamic>> dailyBreakdown = const [],
    List<Map<String, dynamic>> riderStats = const [],
  }) async {
    final pdf = pw.Document();

    final generatedAt = DateTime.now();
    final generatedAtStr =
        '${_formatDate(generatedAt)} ${generatedAt.hour.toString().padLeft(2, '0')}:${generatedAt.minute.toString().padLeft(2, '0')}';
    final estimatedTax = totalIncome * taxRate;
    final netAfterTax = netProfit - estimatedTax;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) => [
          // ─── Header ──────────────────────────────────────────────────────────
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    stationName.toUpperCase(),
                    style: pw.TextStyle(
                      fontSize: 18,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.blue800,
                    ),
                  ),
                  if (stationAddress != null && stationAddress.isNotEmpty)
                    pw.Text(
                      stationAddress,
                      style: const pw.TextStyle(
                        fontSize: 9,
                        color: PdfColors.grey700,
                      ),
                    ),
                  if (stationPhone != null && stationPhone.isNotEmpty)
                    pw.Text(
                      'Tel: $stationPhone',
                      style: const pw.TextStyle(
                        fontSize: 9,
                        color: PdfColors.grey700,
                      ),
                    ),
                  pw.SizedBox(height: 4),
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.blue50,
                      borderRadius: pw.BorderRadius.circular(4),
                      border: pw.Border.all(
                        color: PdfColors.blue200,
                        width: 0.5,
                      ),
                    ),
                    child: pw.Text(
                      'OFFICIAL PERFORMANCE & SALES REPORT',
                      style: pw.TextStyle(
                        fontSize: 8,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.blue900,
                      ),
                    ),
                  ),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(
                    'Period: $rangeLabel',
                    style: pw.TextStyle(
                      fontSize: 11,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.grey900,
                    ),
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    'Generated: $generatedAtStr',
                    style: const pw.TextStyle(
                      fontSize: 8,
                      color: PdfColors.grey600,
                    ),
                  ),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 16),
          pw.Divider(color: PdfColors.grey300, thickness: 1),
          pw.SizedBox(height: 12),

          // ─── Executive KPI Cards ─────────────────────────────────────────────
          pw.Row(
            children: [
              pw.Expanded(
                child: _buildKpiBox(
                  'Total Volume',
                  '${totalGallons.toStringAsFixed(0)} Gal',
                  PdfColors.blue700,
                ),
              ),
              pw.SizedBox(width: 8),
              pw.Expanded(
                child: _buildKpiBox(
                  'Total Deliveries',
                  '$totalDeliveries',
                  PdfColors.orange700,
                ),
              ),
              pw.SizedBox(width: 8),
              pw.Expanded(
                child: _buildKpiBox(
                  'Gross Revenue',
                  'PHP ${totalIncome.toStringAsFixed(2)}',
                  PdfColors.green700,
                ),
              ),
              pw.SizedBox(width: 8),
              pw.Expanded(
                child: _buildKpiBox(
                  'Net Profit',
                  'PHP ${netProfit.toStringAsFixed(2)}',
                  PdfColors.teal700,
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 18),

          // ─── Financial & Tax Summary Table ───────────────────────────────────
          pw.Text(
            'FINANCIAL & TAX SUMMARY',
            style: pw.TextStyle(
              fontSize: 10,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.grey800,
            ),
          ),
          pw.SizedBox(height: 6),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey100),
                children: [
                  _cell('Item / Description', bold: true),
                  _cell('Rate / Base', alignRight: true, bold: true),
                  _cell('Amount (PHP)', alignRight: true, bold: true),
                ],
              ),
              pw.TableRow(
                children: [
                  _cell('Gross Sales Revenue'),
                  _cell('${totalGallons.toStringAsFixed(0)} gal refilled', alignRight: true),
                  _cell(totalIncome.toStringAsFixed(2), alignRight: true),
                ],
              ),
              pw.TableRow(
                children: [
                  _cell('Rider Commissions Paid / Accrued'),
                  _cell('Fleet delivery payout', alignRight: true),
                  _cell('(${totalCommission.toStringAsFixed(2)})', alignRight: true),
                ],
              ),
              pw.TableRow(
                children: [
                  _cell('Operating Expenses'),
                  _cell('Direct station supplies', alignRight: true),
                  _cell('(${totalExpenses.toStringAsFixed(2)})', alignRight: true),
                ],
              ),
              pw.TableRow(
                children: [
                  _cell('Estimated Percentage Tax (BIR Form 2551Q)', bold: true),
                  _cell('${(taxRate * 100).toStringAsFixed(1)}% of Gross Sales', alignRight: true),
                  _cell('(${estimatedTax.toStringAsFixed(2)})', alignRight: true, bold: true),
                ],
              ),
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.blue50),
                children: [
                  _cell('Net Earnings After Tax', bold: true),
                  _cell('Retained Earnings', alignRight: true, bold: true),
                  _cell(
                    'PHP ${netAfterTax.toStringAsFixed(2)}',
                    alignRight: true,
                    bold: true,
                  ),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 20),

          // ─── Rider Performance Table ─────────────────────────────────────────
          if (riderStats.isNotEmpty) ...[
            pw.Text(
              'RIDER DISPATCH & COMMISSION BREAKDOWN',
              style: pw.TextStyle(
                fontSize: 10,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.grey800,
              ),
            ),
            pw.SizedBox(height: 6),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey100),
                  children: [
                    _cell('Rider Name', bold: true),
                    _cell('Deliveries Completed', alignCenter: true, bold: true),
                    _cell('Volume (Gal)', alignCenter: true, bold: true),
                    _cell('Earned Commission (PHP)', alignRight: true, bold: true),
                  ],
                ),
                ...riderStats.map(
                  (stat) => pw.TableRow(
                    children: [
                      _cell((stat['name'] ?? 'Rider').toString()),
                      _cell(
                        (stat['count'] ?? 0).toString(),
                        alignCenter: true,
                      ),
                      _cell(
                        (stat['gallons'] is num
                                ? (stat['gallons'] as num).toStringAsFixed(0)
                                : '0'),
                        alignCenter: true,
                      ),
                      _cell(
                        (stat['commission'] is num
                                ? (stat['commission'] as num).toStringAsFixed(2)
                                : '0.00'),
                        alignRight: true,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 20),
          ],

          // ─── Daily Sales & Deliveries Trend ──────────────────────────────────
          if (dailyBreakdown.isNotEmpty) ...[
            pw.Text(
              'DAILY DELIVERY & REVENUE LOG',
              style: pw.TextStyle(
                fontSize: 10,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.grey800,
              ),
            ),
            pw.SizedBox(height: 6),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey100),
                  children: [
                    _cell('Date', bold: true),
                    _cell('Volume (Gal)', alignCenter: true, bold: true),
                    _cell('Gross Sales (PHP)', alignRight: true, bold: true),
                  ],
                ),
                ...dailyBreakdown.map((row) {
                  final dt = row['date'] is DateTime
                      ? row['date'] as DateTime
                      : DateTime.tryParse(row['date'].toString()) ?? DateTime.now();
                  final gal = (row['gallons'] as num?)?.toDouble() ?? 0.0;
                  final inc = (row['income'] as num?)?.toDouble() ?? 0.0;
                  return pw.TableRow(
                    children: [
                      _cell(_formatDate(dt)),
                      _cell(gal.toStringAsFixed(0), alignCenter: true),
                      _cell(inc.toStringAsFixed(2), alignRight: true),
                    ],
                  );
                }),
              ],
            ),
            pw.SizedBox(height: 24),
          ],

          // ─── Verification & Signature Footer ─────────────────────────────────
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'Prepared & Verified by:',
                    style: const pw.TextStyle(
                      fontSize: 8,
                      color: PdfColors.grey700,
                    ),
                  ),
                  pw.SizedBox(height: 28),
                  pw.Container(
                    width: 160,
                    decoration: const pw.BoxDecoration(
                      border: pw.Border(
                        top: pw.BorderSide(color: PdfColors.grey600, width: 0.8),
                      ),
                    ),
                    padding: const pw.EdgeInsets.only(top: 4),
                    child: pw.Text(
                      'Station Owner / Manager',
                      textAlign: pw.TextAlign.center,
                      style: pw.TextStyle(
                        fontSize: 8,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(
                    'eRefill Management Platform',
                    style: pw.TextStyle(
                      fontSize: 8,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.grey600,
                    ),
                  ),
                  pw.Text(
                    'Cantilan & Madrid, Surigao del Sur',
                    style: const pw.TextStyle(
                      fontSize: 7,
                      color: PdfColors.grey500,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );

    return pdf.save();
  }

  static pw.Widget _buildKpiBox(String label, String value, PdfColor color) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 10),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey50,
        borderRadius: pw.BorderRadius.circular(6),
        border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            label,
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
          ),
          pw.SizedBox(height: 3),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: 11,
              fontWeight: pw.FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _cell(
    String text, {
    bool bold = false,
    bool alignRight = false,
    bool alignCenter = false,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 6),
      child: pw.Text(
        text,
        textAlign: alignRight
            ? pw.TextAlign.right
            : (alignCenter ? pw.TextAlign.center : pw.TextAlign.left),
        style: pw.TextStyle(
          fontSize: 8,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
  }

  /// Print or open print dialog for the report
  static Future<void> printReport({
    required BuildContext context,
    required String stationName,
    String? stationAddress,
    String? stationPhone,
    required String rangeLabel,
    required int totalDeliveries,
    required double totalGallons,
    required double totalIncome,
    required double totalExpenses,
    required double totalCommission,
    required double netProfit,
    double taxRate = 0.03,
    List<Map<String, dynamic>> dailyBreakdown = const [],
    List<Map<String, dynamic>> riderStats = const [],
  }) async {
    try {
      final pdfBytes = await generateReportPdf(
        stationName: stationName,
        stationAddress: stationAddress,
        stationPhone: stationPhone,
        rangeLabel: rangeLabel,
        totalDeliveries: totalDeliveries,
        totalGallons: totalGallons,
        totalIncome: totalIncome,
        totalExpenses: totalExpenses,
        totalCommission: totalCommission,
        netProfit: netProfit,
        taxRate: taxRate,
        dailyBreakdown: dailyBreakdown,
        riderStats: riderStats,
      );

      await Printing.layoutPdf(
        onLayout: (_) async => pdfBytes,
        name: 'eRefill_Report_${rangeLabel.replaceAll(' ', '_')}.pdf',
      );
    } catch (e) {
      debugPrint('Print report failed: $e');
    }
  }

  /// Share PDF report
  static Future<void> shareReport({
    required BuildContext context,
    required String stationName,
    String? stationAddress,
    String? stationPhone,
    required String rangeLabel,
    required int totalDeliveries,
    required double totalGallons,
    required double totalIncome,
    required double totalExpenses,
    required double totalCommission,
    required double netProfit,
    double taxRate = 0.03,
    List<Map<String, dynamic>> dailyBreakdown = const [],
    List<Map<String, dynamic>> riderStats = const [],
  }) async {
    try {
      final pdfBytes = await generateReportPdf(
        stationName: stationName,
        stationAddress: stationAddress,
        stationPhone: stationPhone,
        rangeLabel: rangeLabel,
        totalDeliveries: totalDeliveries,
        totalGallons: totalGallons,
        totalIncome: totalIncome,
        totalExpenses: totalExpenses,
        totalCommission: totalCommission,
        netProfit: netProfit,
        taxRate: taxRate,
        dailyBreakdown: dailyBreakdown,
        riderStats: riderStats,
      );

      await Printing.sharePdf(
        bytes: pdfBytes,
        filename: 'eRefill_Report_${rangeLabel.replaceAll(' ', '_')}.pdf',
      );
    } catch (e) {
      debugPrint('Share report failed: $e');
    }
  }
}

