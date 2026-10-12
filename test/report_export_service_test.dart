import 'package:flutter_test/flutter_test.dart';
import 'package:erefill/core/services/report_export_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ReportExportService tests', () {
    test('generateReportPdf creates non-empty PDF bytes', () async {
      final pdfBytes = await ReportExportService.generateReportPdf(
        stationName: 'Cantilan Pure Springs',
        stationAddress: 'Barangay Linintian, Cantilan, Surigao del Sur',
        stationPhone: '09123456789',
        rangeLabel: 'This Month - October 2026',
        totalDeliveries: 45,
        totalGallons: 250.0,
        totalIncome: 6250.0,
        totalExpenses: 750.0,
        totalCommission: 1250.0,
        netProfit: 4250.0,
        taxRate: 0.03,
        dailyBreakdown: [
          {
            'date': DateTime(2026, 10, 1),
            'gallons': 20.0,
            'income': 500.0,
          },
          {
            'date': DateTime(2026, 10, 2),
            'gallons': 30.0,
            'income': 750.0,
          },
        ],
        riderStats: [
          {
            'name': 'Pedro Penduko',
            'count': 25,
            'gallons': 150.0,
            'commission': 750.0,
          },
          {
            'name': 'Juan Rider',
            'count': 20,
            'gallons': 100.0,
            'commission': 500.0,
          },
        ],
      );

      expect(pdfBytes, isNotEmpty);
      expect(pdfBytes.length, greaterThan(1000));
      // PDF documents start with '%PDF-'
      final header = String.fromCharCodes(pdfBytes.sublist(0, 5));
      expect(header, equals('%PDF-'));
    });

    test('generateReportPdf handles empty breakdowns gracefully', () async {
      final pdfBytes = await ReportExportService.generateReportPdf(
        stationName: 'Madrid Aqua Hub',
        rangeLabel: 'Today',
        totalDeliveries: 0,
        totalGallons: 0.0,
        totalIncome: 0.0,
        totalExpenses: 0.0,
        totalCommission: 0.0,
        netProfit: 0.0,
      );

      expect(pdfBytes, isNotEmpty);
      expect(pdfBytes.length, greaterThan(500));
      final header = String.fromCharCodes(pdfBytes.sublist(0, 5));
      expect(header, equals('%PDF-'));
    });
  });
}

