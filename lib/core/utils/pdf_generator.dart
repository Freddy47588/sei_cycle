import 'dart:io';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../../features/reports/models/analytics_model.dart';

class PdfGenerator {
  static Future<List<int>> buildBytes(AnalyticsModel data) async {
    final pdf = pw.Document();

    // Load logo
    pw.MemoryImage? logoImage;
    try {
      final ByteData bytes = await rootBundle.load('lib/assets/logo.png');
      logoImage = pw.MemoryImage(bytes.buffer.asUint8List());
    } catch (e) {
      // Ignored if logo not found
    }

    final dateFormat = DateFormat('dd MMM yyyy');
    final currencyFormat = NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp',
      decimalDigits: 0,
    );

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return [
            _buildHeader(logoImage, data, dateFormat),
            pw.SizedBox(height: 20),
            _buildSummary(data, currencyFormat),
            pw.SizedBox(height: 20),
            _buildLogbooksTable(data, dateFormat),
            if (data.financeIncluded) ...[
              pw.SizedBox(height: 16),
              pw.Text('Penjualan: ${currencyFormat.format(data.totalSales)}'),
              for (final e in data.salesPerProduct.entries)
                pw.Text('${e.key}: ${currencyFormat.format(e.value)}'),
              for (final e in data.salesPerModule.entries)
                pw.Text('${e.key}: ${currencyFormat.format(e.value)}'),
            ],
            pw.SizedBox(height: 16),
            pw.Text('Aliran nutrisi aktual'),
            for (final e in data.flowsPerMaterial.entries)
              pw.Text('${e.key}: ${e.value}'),
          ];
        },
        footer: (pw.Context context) {
          return pw.Container(
            alignment: pw.Alignment.centerRight,
            margin: const pw.EdgeInsets.only(top: 10),
            child: pw.Text(
              'Dicetak pada: ${dateFormat.format(DateTime.now())} - Halaman ${context.pageNumber} dari ${context.pagesCount}',
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey),
            ),
          );
        },
      ),
    );

    return pdf.save();
  }

  static Future<void> generateAndSharePdf(AnalyticsModel data) async {
    final bytes = await buildBytes(data);
    final output = await getTemporaryDirectory();
    final file = File(
      '${output.path}/Laporan_SeiCycle_${DateTime.now().millisecondsSinceEpoch}.pdf',
    );
    await file.writeAsBytes(bytes);

    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)], text: 'Laporan SeiCycle'),
    );
  }

  static pw.Widget _buildHeader(
    pw.MemoryImage? logo,
    AnalyticsModel data,
    DateFormat dateFormat,
  ) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'LAPORAN ANALITIK SEICYCLE',
              style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              'Periode: ${dateFormat.format(data.startDate)} - ${dateFormat.format(data.endDate)}',
              style: const pw.TextStyle(fontSize: 12),
            ),
          ],
        ),
        if (logo != null)
          pw.Container(width: 50, height: 50, child: pw.Image(logo)),
      ],
    );
  }

  static pw.Widget _buildSummary(
    AnalyticsModel data,
    NumberFormat currencyFormat,
  ) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Ringkasan',
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          pw.Text('Total Aktivitas: ${data.logbooks.length} catatan'),
          pw.Text('Item Stok Rendah: ${data.lowStockItems.length} item'),
          if (data.financeIncluded)
            pw.Text(
              'Total Pemasukan: ${currencyFormat.format(data.totalIncome)}',
            ),
          if (data.financeIncluded)
            pw.Text(
              'Total Pengeluaran: ${currencyFormat.format(data.totalExpense)}',
            ),
          if (data.financeIncluded)
            pw.Text(
              'Arus Kas Bersih: ${currencyFormat.format(data.profitLoss)}',
            ),
        ],
      ),
    );
  }

  static pw.Widget _buildLogbooksTable(
    AnalyticsModel data,
    DateFormat dateFormat,
  ) {
    if (data.logbooks.isEmpty) {
      return pw.Text('Tidak ada catatan operasional pada periode ini.');
    }

    final headers = ['Tanggal', 'Modul', 'Aktivitas', 'Kuantitas'];
    final rows = data.logbooks.map((log) {
      return [
        dateFormat.format(log.activityDate),
        log.moduleId,
        log.activityType,
        '${log.quantity} ${log.unit}',
      ];
    }).toList();

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'Data Operasional',
          style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 8),
        pw.TableHelper.fromTextArray(
          headers: headers,
          data: rows,
          border: pw.TableBorder.all(color: PdfColors.grey300),
          headerStyle: pw.TextStyle(
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.white,
          ),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.green700),
          cellPadding: const pw.EdgeInsets.all(6),
        ),
      ],
    );
  }
}
