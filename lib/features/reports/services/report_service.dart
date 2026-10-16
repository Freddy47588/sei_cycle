import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/utils/sample_data_guard.dart';
import '../../circular_flow/models/circular_flow.dart';
import '../../finance/models/finance_record.dart';
import '../../profile/models/app_user.dart';
import '../../inventory/models/inventory_item.dart';
import '../../logbook/models/logbook_entry.dart';
import '../../sales/models/sale.dart';
import '../models/analytics_model.dart';
import '../models/report_filter.dart';

class ReportService {
  ReportService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;
  final FirebaseFirestore _firestore;
  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _complete(
    Query<Map<String, dynamic>> q,
  ) async {
    final r = await q.limit(1001).get();
    if (r.docs.length > 1000) {
      throw StateError(
        'Laporan melebihi batas 1.000 dokumen per sumber. Persempit periode/modul. Ekspor parsial tidak dibuat.',
      );
    }
    requireOperationalData(r.docs);
    return r.docs;
  }

  Future<AnalyticsModel> generateReport(
    ReportFilter filter, {
    bool includeFinance = false,
    AppUser? profile,
  }) async {
    if (profile != null && !profile.canViewReports) {
      throw StateError('Tidak memiliki akses laporan.');
    }
    if (!filter.endDate.isAfter(filter.startDate) &&
        filter.endDate != filter.startDate) {
      throw ArgumentError('Rentang tanggal tidak valid.');
    }
    final end = DateTime(
      filter.endDate.year,
      filter.endDate.month,
      filter.endDate.day + 1,
    );
    final startDate = Timestamp.fromDate(filter.startDate),
        endDate = Timestamp.fromDate(end);
    Query<Map<String, dynamic>> period(
      String collection,
      String date, {
      bool activeOnly = false,
    }) {
      Query<Map<String, dynamic>> q = _firestore
          .collection(collection)
          .where(date, isGreaterThanOrEqualTo: startDate)
          .where(date, isLessThan: endDate);
      if (activeOnly) q = q.where('isDeleted', isEqualTo: false);
      if (filter.moduleType != null && filter.moduleType!.isNotEmpty) {
        q = q.where(
          collection == 'circular_flows' ? 'sourceModuleType' : 'moduleType',
          isEqualTo: filter.moduleType,
        );
      }
      return q.orderBy(date, descending: true);
    }

    final full = filter.reportType == ReportType.fullSummary;
    final operational = full || filter.reportType == ReportType.operational;
    final inventory = full || filter.reportType == ReportType.inventory;
    final finance =
        includeFinance &&
        (profile?.canViewFinance ?? false) &&
        (full || filter.reportType == ReportType.finance);
    List<LogbookEntry> logs = [];
    List<InventoryItem> stock = [];
    List<FinanceRecord> cash = [];
    List<Sale> sales = [];
    List<CircularFlow> flows = [];
    if (operational) {
      logs = (await _complete(
        period('logbooks', 'activityDate', activeOnly: true),
      )).map(LogbookEntry.fromDocument).toList();
      flows = (await _complete(
        period(
          'circular_flows',
          'flowDate',
        ).where('sourceType', isEqualTo: 'manual'),
      )).map(CircularFlow.fromDocument).where((f) => f.isActual).toList();
    }
    if (inventory) {
      Query<Map<String, dynamic>> q = _firestore
          .collection('inventory')
          .where('isDeleted', isEqualTo: false);
      if (filter.moduleType != null && filter.moduleType!.isNotEmpty) {
        q = q.where('moduleType', isEqualTo: filter.moduleType);
      }
      stock = (await _complete(
        q.orderBy('name'),
      )).map(InventoryItem.fromDocument).toList();
    }
    if (finance) {
      final docs = await _complete(
        period('finance_transactions', 'date', activeOnly: true),
      );
      for (final doc in docs) {
        final d = doc.data();
        if (d['amount'] is! num ||
            !(d['amount'] as num).isFinite ||
            (d['amount'] as num) <= 0 ||
            !['income', 'expense'].contains(d['type'])) {
          throw StateError(
            'Transaksi keuangan tidak valid. Laporan tidak dihitung sebagai nol.',
          );
        }
      }
      cash = docs.map(FinanceRecord.fromDocument).toList();
      sales = (await _complete(
        period('sales', 'saleDate'),
      )).map(Sale.fromDocument).toList();
    }
    return AnalyticsModel(
      logbooks: logs,
      inventoryItems: stock,
      financeRecords: cash,
      sales: sales,
      circularFlows: flows,
      financeIncluded: finance,
      startDate: filter.startDate,
      endDate: filter.endDate,
    );
  }
}
