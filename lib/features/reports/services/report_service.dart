import '../../../core/utils/legacy_firestore.dart';
import '../../finance/services/finance_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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
    Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> period(
      String collection,
      String date, {
      bool activeOnly = false,
    }) async {
      final docs = (await operationalCollection(_firestore, collection)).where((
        doc,
      ) {
        final d = legacyFields(doc.data());
        final value = d[date];
        if (value is! Timestamp) {
          throw const FormatException('Tanggal laporan tidak valid.');
        }
        return !value.toDate().isBefore(filter.startDate) &&
            value.toDate().isBefore(end) &&
            (filter.moduleType == null ||
                filter.moduleType!.isEmpty ||
                d[collection == 'circular_flows'
                        ? 'sourceModuleType'
                        : 'moduleType'] ==
                    filter.moduleType);
      }).toList();
      await OperationalIntegrity(_firestore).check(docs);
      return docs;
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
      logs = (await period(
        'logbooks',
        'activityDate',
      )).map(LogbookEntry.fromDocument).toList();
      flows = (await period('circular_flows', 'flowDate'))
          .where((d) => d.data()['sourceType'] == 'manual')
          .map(CircularFlow.fromDocument)
          .where((f) => f.isActual)
          .toList();
    }
    if (inventory) {
      final sources = await Future.wait([
        operationalCollection(_firestore, 'inventory'),
        operationalCollection(_firestore, 'inventory_items'),
      ]);
      // This section reports the current recorded masters, independently of
      // historic ledger links to masters removed during administrative cleanup.
      final docs = sources.expand((s) => s).toList();
      final ids = <String>{};
      for (final doc in docs) {
        requireReviewedProvenance(doc.data());
        if (!ids.add(doc.id)) {
          throw StateError('Identitas inventory legacy ambigu.');
        }
      }
      stock = docs
          .map(InventoryItem.fromDocument)
          .where(
            (i) =>
                filter.moduleType == null ||
                filter.moduleType!.isEmpty ||
                i.moduleType == filter.moduleType,
          )
          .toList();
    }
    if (finance) {
      cash = (await FinanceService(firestore: _firestore).compatibleDocuments(
        start: filter.startDate,
        end: end,
        moduleType: filter.moduleType == '' ? null : filter.moduleType,
        verifyIntegrity: true,
      )).map(FinanceRecord.fromDocument).toList();
      sales = (await period(
        'sales',
        'saleDate',
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
