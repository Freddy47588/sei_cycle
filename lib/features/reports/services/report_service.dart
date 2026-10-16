import 'package:cloud_firestore/cloud_firestore.dart';

import '../../finance/models/finance_record.dart';
import '../../inventory/models/inventory_item.dart';
import '../../logbook/models/logbook_entry.dart';
import '../models/analytics_model.dart';
import '../models/report_filter.dart';

class ReportService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<AnalyticsModel> generateReport(
    ReportFilter filter, {
    bool includeFinance = true,
  }) async {
    final startDate = Timestamp.fromDate(filter.startDate);
    final endDate = Timestamp.fromDate(filter.endDate);

    List<LogbookEntry> logbooks = [];
    List<InventoryItem> inventoryItems = [];
    List<FinanceRecord> financeRecords = [];

    // Fetch Logbooks
    if (filter.reportType == ReportType.fullSummary ||
        filter.reportType == ReportType.operational) {
      Query<Map<String, dynamic>> logbookQuery = _firestore
          .collection('logbooks')
          .where('isDeleted', isEqualTo: false)
          .where('activityDate', isGreaterThanOrEqualTo: startDate)
          .where('activityDate', isLessThanOrEqualTo: endDate);

      if (filter.moduleType != null && filter.moduleType!.isNotEmpty) {
        logbookQuery = logbookQuery.where(
          'moduleType',
          isEqualTo: filter.moduleType,
        );
      }

      final logbookSnapshot = await logbookQuery.get();
      logbooks = logbookSnapshot.docs
          .map((doc) => LogbookEntry.fromDocument(doc))
          .toList();
    }

    // Fetch Inventory
    if (filter.reportType == ReportType.fullSummary ||
        filter.reportType == ReportType.inventory) {
      final inventorySnapshot = await _firestore
          .collection('inventory')
          .where('isDeleted', isEqualTo: false)
          .get();
      inventoryItems = inventorySnapshot.docs
          .map((doc) => InventoryItem.fromDocument(doc))
          .toList();
    }

    // Fetch Finance
    if (includeFinance &&
        (filter.reportType == ReportType.fullSummary ||
            filter.reportType == ReportType.finance)) {
      final financeSnapshot = await _firestore
          .collection('finance_transactions')
          .where('isDeleted', isEqualTo: false)
          .where('date', isGreaterThanOrEqualTo: startDate)
          .where('date', isLessThanOrEqualTo: endDate)
          .get();
      financeRecords = financeSnapshot.docs
          .map((doc) => FinanceRecord.fromDocument(doc))
          .toList();
    }

    return AnalyticsModel(
      logbooks: logbooks,
      inventoryItems: inventoryItems,
      financeRecords: financeRecords,
      startDate: filter.startDate,
      endDate: filter.endDate,
    );
  }
}
