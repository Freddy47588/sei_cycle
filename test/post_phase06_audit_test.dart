import 'package:sei_cycle/features/finance/services/finance_service.dart';
import 'package:sei_cycle/features/inventory/services/inventory_service.dart';
import 'package:sei_cycle/features/inventory/services/inventory_adjustment_service.dart';
import 'phase04_operations_test.dart' show seedUser, stockDoc;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sei_cycle/features/dashboard/services/dashboard_service.dart';
import 'package:sei_cycle/features/dashboard/services/productivity_service.dart';
import 'package:sei_cycle/features/dashboard/models/dashboard_filter.dart';
import 'support/memory_firestore.dart';

void main() {
  final now = DateTime(2026, 10, 17, 12);
  test('finance summary and page exclude samples and keep real cash', () async {
    final db = MemoryFirestore();
    for (final id in ['real', 'sample']) {
      db.documents['finance_transactions/$id'] = {
        'id': id,
        'isDeleted': false,
        'date': Timestamp.fromDate(now),
        'type': 'income',
        'amount': id == 'real' ? 100 : 9999,
        if (id == 'sample') 'sampleVersion': 'v2',
        if (id == 'sample') 'createdBy': 'sample_seed',
      };
    }
    final service = FinanceService(firestore: db);
    final summary = await service.loadSummaryByDateRange(
      start: DateTime(2026, 10, 1),
      end: DateTime(2026, 11, 1),
    );
    expect(summary.totalIncome, 100);
    final page = await service.fetchPage(
      start: DateTime(2026, 10, 1),
      end: DateTime(2026, 11, 1),
    );
    expect(page.items.map((r) => r.id), ['real']);
  });
  test(
    'inventory listing excludes samples without modifying production documents',
    () async {
      final db = MemoryFirestore();
      db.documents['inventory/real'] = stockDoc();
      db.documents['inventory/sample'] = {
        ...stockDoc(),
        'isSampleData': true,
        'createdBy': 'sample_seed',
      };
      final page = await InventoryService(firestore: db).fetchPage();
      expect(page.items.map((r) => r.id), ['real']);
      expect(db.documents['inventory/sample']!['currentStock'], 20);
    },
  );
  test('sample inventory adjustment is refused atomically', () async {
    final db = MemoryFirestore();
    seedUser(db);
    db.documents['inventory/sample'] = {
      ...stockDoc(),
      'createdBy': 'sample_seed',
    };
    await expectLater(
      InventoryAdjustmentService(firestore: db).mutate(
        requestId: 'blocked',
        itemId: 'sample',
        type: 'in',
        value: 1,
        unit: 'kg',
        notes: 'Audit',
        userId: 'field',
      ),
      throwsStateError,
    );
    expect(db.documents['inventory/sample']!['currentStock'], 20);
    expect(db.documents.containsKey('inventory_transactions/blocked'), isFalse);
  });
  test('mixed sample data does not hide real Dashboard activity', () async {
    final db = MemoryFirestore();
    db.documents['farm_modules/lele'] = {'isActive': true};
    for (final id in ['real', 'sample']) {
      db.documents['logbooks/$id'] = {
        'isDeleted': false,
        'activityDate': Timestamp.fromDate(now),
        'moduleType': 'lele',
        if (id == 'sample') 'isSampleData': true,
        if (id == 'sample') 'createdBy': 'sample_seed',
      };
    }
    final result = await DashboardService(
      firestore: db,
      clock: () => now,
    ).load(includeFinance: false);
    expect(result.todayLogCount, 1);
    expect(result.activeModuleCount, 1);
    expect(result.recentActivities.map((a) => a.id), ['real']);
  });
  test('invalid inventory leaves independent real KPI available', () async {
    final db = MemoryFirestore();
    db.documents['farm_modules/lele'] = {'isActive': true};
    db.documents['inventory/bad'] = {
      'isDeleted': false,
      'currentStock': 'bad',
      'minStock': 0,
    };
    final result = await DashboardService(
      firestore: db,
      clock: () => now,
    ).load(includeFinance: false);
    expect(result.activeModuleCount, 1);
    expect(result.lowStockCount, isNull);
  });
  test(
    'productivity ignores samples and preserves real legacy unmarked rows',
    () async {
      final db = MemoryFirestore();
      for (final id in ['real', 'sample']) {
        db.documents['logbooks/$id'] = {
          'isDeleted': false,
          'moduleType': 'lele',
          'activityDate': Timestamp.fromDate(now),
          'details': {'ph_air': id == 'real' ? 7 : 12},
          if (id == 'sample') 'createdBy': 'sample_seed',
        };
      }
      final report = await ProductivityService(
        firestore: db,
      ).load(DashboardFilter.days(7, now: now), 'lele', null);
      expect(report.logCount, 1);
      expect(report.series.single.points.single.value, 7);
    },
  );
  test(
    'valid actual circular flow is found behind newer non actual rows',
    () async {
      final db = MemoryFirestore();
      for (var i = 0; i < 12; i++) {
        db.documents['circular_flows/$i'] = {
          'sourceType': 'manual',
          'createdBy': i > 0 ? 'sample_seed' : 'admin',
          'isDeleted': false,
          'flowDate': Timestamp.fromDate(now.add(Duration(minutes: i))),
          'quantity': 2,
          'unit': 'kg',
          'materialName': '$i',
          if (i > 0) 'sampleVersion': 'v2',
        };
      }
      final flows = await DashboardService(
        firestore: db,
      ).getRecentCircularFlows();
      expect(flows.map((f) => f.materialName), ['0']);
    },
  );
}
