import 'package:sei_cycle/features/education/models/education_content.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sei_cycle/core/utils/legacy_firestore.dart';
import 'package:sei_cycle/core/utils/sample_data_guard.dart';
import 'package:sei_cycle/features/dashboard/services/dashboard_service.dart';
import 'package:sei_cycle/features/finance/services/finance_service.dart';
import 'package:sei_cycle/features/inventory/services/inventory_service.dart';
import 'package:sei_cycle/features/logbook/models/logbook_page.dart';
import 'package:sei_cycle/features/logbook/services/logbook_service.dart';
import 'package:sei_cycle/features/profile/models/app_user.dart';
import 'package:sei_cycle/features/sales/services/sales_service.dart';
import 'package:sei_cycle/features/schedule/models/schedule_filter.dart';
import 'package:sei_cycle/features/schedule/services/schedule_service.dart';
import 'package:sei_cycle/features/reports/models/report_filter.dart';
import 'package:sei_cycle/features/reports/services/report_service.dart';
import 'phase04_operations_test.dart' show seedUser, stockDoc;
import 'support/memory_firestore.dart';

// Shapes observed in production; IDs, descriptions and money are synthetic.
final date = DateTime(2026, 10, 15, 12);
final timestamp = Timestamp.fromDate(date);
Map<String, dynamic> cash() => {
  'type': 'income',
  'category': 'Operasional',
  'amount': 1200.0,
  'date': timestamp,
  'created_at': timestamp,
  'updated_at': timestamp,
  'created_by': 'redacted-actor',
  'note': 'Redacted',
};

void main() {
  test(
    'seed-origin note updates are refused without inheriting provenance',
    () async {
      final db = MemoryFirestore();
      db.documents['logbooks/seed'] = {
        'createdBy': 'sample_seed',
        'notes': 'Original',
        'updatedAt': timestamp,
      };
      await expectLater(
        LogbookService(firestore: db).updateNotes(
          'seed',
          notes: 'New',
          userId: 'field',
          expectedUpdatedAt: date,
        ),
        throwsStateError,
      );
      expect(db.documents['logbooks/seed']!['notes'], 'Original');
      expect(
        db.documents.keys.where((p) => p.contains('/note_edits/')),
        isEmpty,
      );
    },
  );

  test(
    'a second-page query failure cannot publish the first page as a total',
    () async {
      final db = MemoryFirestore();
      for (var i = 0; i < 101; i++) {
        db.documents['finance_transactions/$i'] = cash();
      }
      db.queryErrors['finance_transactions'] = FirebaseException(
        plugin: 'cloud_firestore',
        code: 'unavailable',
      );
      db.queryFailureAfter['finance_transactions'] = 1;
      await expectLater(
        FinanceService(firestore: db).loadSummaryByDateRange(
          start: DateTime(2026, 10),
          end: DateTime(2026, 11),
        ),
        throwsA(isA<FirebaseException>()),
      );
    },
  );

  test(
    'real UID with simulation flag stays reviewable while totals are blocked',
    () async {
      final db = MemoryFirestore();
      db.documents['finance_transactions/review'] = {
        ...cash(),
        'createdBy': 'real',
        'sampleVersion': 'v2',
      };
      final service = FinanceService(firestore: db);
      final page = await service.fetchPage(
        start: DateTime(2026, 10),
        end: DateTime(2026, 11),
      );
      expect(page.items.single.requiresProvenanceReview, true);
      await expectLater(
        service.loadSummaryByDateRange(
          start: DateTime(2026, 10),
          end: DateTime(2026, 11),
        ),
        throwsStateError,
      );
    },
  );

  test(
    'education labels simulations without writing the label into the title',
    () async {
      final db = MemoryFirestore();
      db.documents['education_contents/example'] = {
        'title': 'Learning example',
        'createdBy': 'sample_seed',
      };
      final content = EducationContent.fromDocument(
        await db.collection('education_contents').doc('example').get(),
      );
      expect(content.title, 'Learning example');
      expect(content.displayTitle, 'Contoh / Simulasi - Learning example');
      expect(content.toFirestore()['title'], 'Learning example');
    },
  );

  test(
    'provenance flags on a real UID require review, not automatic exclusion',
    () {
      final data = {'createdBy': 'real-uid', 'isSampleData': true};
      expect(isSeedOrigin(data), false);
      expect(isOperationalRecord(data), true);
      expect(() => requireReviewedProvenance(data), throwsStateError);
      expect(isOperationalRecord({'createdBy': 'sample_seed'}), false);
      expect(isOperationalRecord({}), true);
    },
  );

  test(
    'observed module ID conventions count one module instead of two',
    () async {
      final db = MemoryFirestore();
      db.documents['farm_modules/ayam_kampung'] = {
        'module_id': 'ayam_kampung',
        'isActive': true,
      };
      db.documents['farm_modules/module_ayam'] = {
        'module_id': 'module_ayam',
        'is_active': true,
      };
      final summary = await DashboardService(
        firestore: db,
        clock: () => date,
      ).load(includeFinance: false);
      expect(summary.activeModuleCount, 1);
    },
  );

  test('canonical fields win over legacy aliases without modifying input', () {
    final d = {'currentStock': 7, 'current_stock': 3, 'created_by': 'real'};
    expect(legacyFields(d)['currentStock'], 7);
    expect(legacyFields(d)['createdBy'], 'real');
    expect(d.containsKey('createdBy'), false);
  });

  test('missing soft delete is active, invalid type is an error', () {
    expect(isOperationalRecord({'created_by': 'real'}), true);
    expect(isOperationalRecord({'is_deleted': true}), false);
    expect(
      () => isOperationalRecord({'isDeleted': 'false'}),
      throwsFormatException,
    );
  });

  test('actual snake_case logbook and schedule remain accessible', () async {
    final db = MemoryFirestore();
    db.documents['logbooks/legacy'] = {
      'module_id': 'lele',
      'activity_date': timestamp,
      'activity_type': 'pakan',
      'quantity': 2.0,
      'unit': 'kg',
      'is_deleted': false,
      'created_by': 'real',
      'note': 'Redacted',
    };
    db.documents['schedules/legacy'] = {
      'module_id': 'lele',
      'scheduled_at': timestamp,
      'schedule_type': 'pakan',
      'status': 'pending',
      'title': 'Redacted',
      'created_by': 'real',
    };
    final logs = await LogbookService(firestore: db).getPage(
      filter: LogbookFilter(
        moduleId: 'lele',
        start: DateTime(2026, 10, 15),
        endExclusive: DateTime(2026, 10, 16),
      ),
    );
    expect(logs.entries.single.activityDate, date);
    expect(logs.entries.single.createdBy, 'real');
    final schedules = await ScheduleService(
      firestore: db,
    ).fetchPage(filter: const ScheduleFilter(view: ScheduleView.all));
    expect(schedules.items.single.scheduledAt, date);
    expect(schedules.items.single.isDeleted, false);
    final dashboard = await DashboardService(
      firestore: db,
      clock: () => date,
    ).load(includeFinance: false);
    expect(dashboard.todayLogCount, 1);
    expect(dashboard.todayScheduleCount, 1);
  });

  test(
    'finance merges observed legacy collection without inventing metadata',
    () async {
      final db = MemoryFirestore();
      db.documents['finance_records/old'] = cash();
      db.documents['finance_transactions/new'] = {
        ...cash(),
        'createdBy': 'real',
      };
      db.documents['finance_transactions/seed'] = {
        ...cash(),
        'createdBy': 'sample_seed',
      };
      final service = FinanceService(firestore: db);
      final result = await service.loadSummaryByDateRange(
        start: DateTime(2026, 10),
        end: DateTime(2026, 11),
      );
      expect(result.totalIncome, 2400);
      expect(
        result.transactions.where((r) => r.legacyReadOnly).single.id,
        'old',
      );
      expect(result.transactions.every((r) => !r.isDeleted), true);
    },
  );

  test('denied legacy source cannot produce a partial finance total', () async {
    final db = MemoryFirestore();
    db.documents['finance_transactions/real'] = cash();
    db.queryErrors['finance_records'] = FirebaseException(
      plugin: 'cloud_firestore',
      code: 'permission-denied',
    );
    await expectLater(
      FinanceService(firestore: db).loadSummaryByDateRange(
        start: DateTime(2026, 10),
        end: DateTime(2026, 11),
      ),
      throwsA(isA<FirebaseException>()),
    );
  });

  for (final wrong in ['1200', null, double.nan, double.infinity, -1]) {
    test('invalid finance amount $wrong never becomes zero', () async {
      final db = MemoryFirestore();
      db.documents['finance_records/legacy'] = {...cash(), 'amount': wrong};
      await expectLater(
        FinanceService(firestore: db).loadSummaryByDateRange(
          start: DateTime(2026, 10),
          end: DateTime(2026, 11),
        ),
        throwsFormatException,
      );
    });
  }

  test(
    'ambiguous same ID across legacy and canonical finance is blocked',
    () async {
      final db = MemoryFirestore();
      db.documents['finance_records/same'] = cash();
      db.documents['finance_transactions/same'] = cash();
      await expectLater(
        FinanceService(firestore: db).compatibleDocuments(),
        throwsStateError,
      );
    },
  );

  test(
    'inventory reads observed current_stock and min_stock with no creator',
    () async {
      final db = MemoryFirestore();
      db.documents['inventory_items/legacy'] = {
        'name': 'Redacted',
        'current_stock': 4.0,
        'min_stock': 5.0,
        'unit': 'kg',
      };
      db.documents['inventory/seed'] = {
        ...stockDoc(),
        'createdBy': 'sample_seed',
      };
      final page = await InventoryService(firestore: db).fetchPage();
      expect(page.items.single.currentStock, 4);
      expect(page.items.single.isLowStock, true);
      expect(page.items.single.legacyReadOnly, true);
      final result = await DashboardService(
        firestore: db,
        clock: () => date,
      ).load(includeFinance: false);
      expect(result.lowStockCount, 1);
      expect(result.sectionErrors['inventory'], isNull);
    },
  );

  test(
    'pagination crosses 100 seed documents and retains all real rows',
    () async {
      final db = MemoryFirestore();
      for (var i = 0; i < 130; i++) {
        db.documents['finance_transactions/a${i.toString().padLeft(3, '0')}'] =
            {...cash(), 'createdBy': 'sample_seed'};
      }
      for (var i = 0; i < 23; i++) {
        db.documents['finance_transactions/z$i'] = cash();
      }
      final service = FinanceService(firestore: db);
      final first = await service.fetchPage(
        start: DateTime(2026, 10),
        end: DateTime(2026, 11),
      );
      final second = await service.fetchPage(
        start: DateTime(2026, 10),
        end: DateTime(2026, 11),
        cursor: first.cursor,
      );
      expect(first.items.length, 20);
      expect(first.hasMore, true);
      expect(second.items.length, 3);
      expect(second.hasMore, false);
      expect({
        ...first.items.map((r) => r.id),
        ...second.items.map((r) => r.id),
      }, hasLength(23));
      expect(
        (await service.loadSummaryByDateRange(
          start: DateTime(2026, 10),
          end: DateTime(2026, 11),
        )).totalIncome,
        27600,
      );
      expect(
        db.queryLimits.values
            .expand((v) => v)
            .every((v) => v != null && v <= 100),
        true,
      );
    },
  );

  test(
    '500 sentinel rejects oversize sources without a partial total',
    () async {
      final db = MemoryFirestore();
      for (var i = 0; i < 501; i++) {
        db.documents['finance_transactions/$i'] = cash();
      }
      await expectLater(
        FinanceService(firestore: db).compatibleDocuments(),
        throwsStateError,
      );
    },
  );

  test(
    'real ledger referencing a seed master blocks stock KPI, keeps evidence',
    () async {
      final db = MemoryFirestore();
      db.documents['farm_modules/lele'] = {
        'is_active': true,
        'module_id': 'lele',
      };
      db.documents['inventory/seed'] = {
        ...stockDoc(),
        'createdBy': 'sample_seed',
      };
      db.documents['inventory_transactions/real'] = {
        'createdBy': 'real',
        'itemId': 'seed',
        'transactionDate': timestamp,
      };
      final before = Map.of(db.documents['inventory/seed']!);
      final result = await DashboardService(
        firestore: db,
        clock: () => date,
      ).load(includeFinance: false);
      expect(result.activeModuleCount, 1);
      expect(result.lowStockCount, isNull);
      expect(result.sectionErrors['inventory'], isA<StateError>());
      expect(db.documents['inventory/seed'], before);
    },
  );

  test(
    'real sale referencing seed inventory blocks summary, preserves receipt',
    () async {
      final db = MemoryFirestore();
      db.documents['inventory/seed'] = {
        ...stockDoc(),
        'createdBy': 'sample_seed',
      };
      db.documents['sales/receipt'] = {
        'inventoryItemId': 'seed',
        'saleDate': timestamp,
        'createdBy': 'real',
      };
      await expectLater(
        SalesService(
          firestore: db,
        ).summary(DateTime(2026, 10), DateTime(2026, 11)),
        throwsStateError,
      );
      expect(db.documents.containsKey('sales/receipt'), true);
    },
  );

  test(
    'new finance writes use actor UID and never inherit seed fields',
    () async {
      final db = MemoryFirestore();
      seedUser(db, role: 'operator_keuangan');
      await FinanceService(firestore: db).save(
        requestId: 'new',
        type: 'income',
        category: 'Operasional',
        amount: 1200,
        date: date,
        note: 'Redacted',
        userId: 'field',
      );
      final d = db.documents['finance_transactions/new']!;
      expect(d['createdBy'], 'field');
      expect(d['updatedBy'], 'field');
      expect(d['source'], 'manual');
      expect(d.containsKey('isSampleData'), false);
      expect(d.containsKey('sampleVersion'), false);
      expect(d['createdAt'], isA<Timestamp>());
    },
  );

  test(
    'UID is bound to profile document identity, not a stale legacy id',
    () async {
      final db = MemoryFirestore();
      db.documents['users/real-auth-uid'] = {
        'id': 'legacy-id',
        'uid': 'wrong-uid',
        'role': 'operator',
        'is_active': true,
      };
      final profile = AppUser.fromDocument(
        await db.collection('users').doc('real-auth-uid').get(),
      );
      expect(profile.uid, 'real-auth-uid');
      expect(profile.canManageLogbooks, true);
      expect(profile.canViewFinance, false);
    },
  );

  test(
    'reports exclude seed finance and preserve legitimate missing creator',
    () async {
      final db = MemoryFirestore();
      db.documents['users/admin'] = {'role': 'admin', 'isActive': true};
      final profile = AppUser.fromDocument(
        await db.collection('users').doc('admin').get(),
      );
      db.documents['finance_records/old'] = cash()..remove('created_by');
      db.documents['finance_transactions/seed'] = {
        ...cash(),
        'createdBy': 'sample_seed',
      };
      final report = await ReportService(firestore: db).generateReport(
        ReportFilter(
          startDate: date,
          endDate: date,
          reportType: ReportType.finance,
        ),
        includeFinance: true,
        profile: profile,
      );
      expect(report.totalIncome, 1200);
    },
  );
}
