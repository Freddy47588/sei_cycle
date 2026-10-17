import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sei_cycle/core/utils/legacy_firestore.dart';
import 'package:sei_cycle/features/dashboard/services/dashboard_service.dart';
import 'package:sei_cycle/features/reports/models/report_filter.dart';
import 'package:sei_cycle/features/reports/services/report_service.dart';
import 'phase04_operations_test.dart' show stockDoc;
import 'support/memory_firestore.dart';

void main() {
  test(
    'empty current masters yield zero recorded-stock counts while retaining orphan history',
    () async {
      final db = MemoryFirestore();
      db.documents['inventory_transactions/history'] = {
        'itemId': 'removed',
        'logbookId': 'removed',
        'createdBy': 'field',
      };
      final before = Map.of(db.documents['inventory_transactions/history']!);
      final summary = await DashboardService(
        firestore: db,
      ).load(includeFinance: false);
      expect(summary.lowStockCount, 0);
      expect(summary.outOfStockCount, 0);
      expect(summary.sectionErrors['inventory'], isNull);
      expect(db.documents['inventory_transactions/history'], before);
      final report = await ReportService(firestore: db).generateReport(
        ReportFilter(
          startDate: DateTime(2026, 10),
          endDate: DateTime(2026, 10, 17),
          reportType: ReportType.inventory,
        ),
      );
      expect(report.inventoryItems, isEmpty);
      expect(db.documents.keys, ['inventory_transactions/history']);
    },
  );
  test(
    'new operational stock stays authoritative despite unrelated retired-master ledger',
    () async {
      final db = MemoryFirestore();
      db.documents['inventory/new'] = stockDoc(stock: 3);
      db.documents['inventory_transactions/history'] = {
        'createdBy': 'field',
        'itemId': 'removed',
        'quantity': 9999,
      };
      final summary = await DashboardService(
        firestore: db,
      ).load(includeFinance: false);
      expect(summary.lowStockCount, 1);
      expect(summary.outOfStockCount, 0);
      expect(summary.sectionErrors['inventory'], isNull);
      final report = await ReportService(firestore: db).generateReport(
        ReportFilter(
          startDate: DateTime(2026, 10),
          endDate: DateTime(2026, 10, 17),
          reportType: ReportType.inventory,
        ),
      );
      expect(report.inventoryItems.single.currentStock, 3);
    },
  );
  test(
    'historical stock links can outlive their master without recreating stock',
    () async {
      final db = MemoryFirestore();
      db.documents['logbooks/log'] = {'createdBy': 'field'};
      db.documents['inventory_transactions/history'] = {
        'createdBy': 'field',
        'itemId': 'removed',
        'logbookId': 'log',
        'transactionDate': Timestamp.fromDate(DateTime(2026)),
      };
      await OperationalIntegrity(
        db,
      ).check(await completeCollection(db, 'logbooks'));
      expect(
        db.documents.keys.where((p) => p.startsWith('inventory/')),
        isEmpty,
      );
    },
  );
  test(
    'missing financial links still fail and malformed current stock is never zero',
    () async {
      final db = MemoryFirestore();
      db.documents['sales/receipt'] = {
        'createdBy': 'field',
        'financeTransactionId': 'missing',
      };
      await expectLater(
        OperationalIntegrity(db).check(await completeCollection(db, 'sales')),
        throwsStateError,
      );
      db.documents['inventory/new'] = {...stockDoc(), 'currentStock': null};
      final summary = await DashboardService(
        firestore: db,
      ).load(includeFinance: false);
      expect(summary.lowStockCount, isNull);
      expect(summary.sectionErrors['inventory'], isNotNull);
    },
  );
}
