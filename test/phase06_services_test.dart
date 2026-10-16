import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:excel/excel.dart';
import 'package:sei_cycle/core/utils/excel_generator.dart';
import 'package:sei_cycle/core/utils/pdf_generator.dart';
import 'package:sei_cycle/features/reports/models/analytics_model.dart';
import 'package:sei_cycle/core/constants/farm_modules.dart';
import 'package:sei_cycle/core/utils/sample_data_guard.dart';
import 'package:sei_cycle/features/circular_flow/models/circular_flow.dart';
import 'package:sei_cycle/features/circular_flow/services/circular_flow_service.dart';
import 'package:sei_cycle/features/dashboard/models/dashboard_filter.dart';
import 'package:sei_cycle/features/dashboard/services/dashboard_service.dart';
import 'package:sei_cycle/features/dashboard/services/productivity_service.dart';
import 'package:sei_cycle/features/finance/models/finance_record.dart';
import 'package:sei_cycle/features/finance/services/finance_service.dart';
import 'package:sei_cycle/features/inventory/services/inventory_service.dart';
import 'package:sei_cycle/features/profile/models/app_user.dart';
import 'package:sei_cycle/features/reports/models/report_filter.dart';
import 'package:sei_cycle/features/reports/services/report_service.dart';
import 'package:sei_cycle/features/sales/models/sale.dart';
import 'package:sei_cycle/features/sales/services/sales_service.dart';
import 'phase04_operations_test.dart' show stockDoc, seedUser;
import 'support/memory_firestore.dart';

final day = DateTime(2026, 10, 16);
AppUser user(String role, {bool active = true}) => AppUser(
  uid: 'field',
  name: 'Petugas',
  email: '',
  photoUrl: '',
  role: role,
  isActive: active,
  createdAt: day,
  updatedAt: day,
);
SaleInput saleInput({
  double quantity = 5,
  int price = 25000,
  String unit = 'kg',
}) => SaleInput(
  inventoryItemId: 'harvest',
  quantity: quantity,
  unit: unit,
  unitPrice: price,
  saleDate: day,
  paymentMethod: 'tunai',
);
CircularFlowInput flowInput({
  double quantity = 3,
  String unit = 'kg',
  String source = 'cacing_tanah',
  String? sourceBatch,
  String? log,
  String? ledger,
}) => CircularFlowInput(
  sourceModuleType: source,
  destinationModuleType: 'tanaman',
  materialName: 'Kascing',
  quantity: quantity,
  unit: unit,
  flowDate: day,
  sourceBatchId: sourceBatch,
  logbookId: log,
  inventoryTransactionId: ledger,
);
void seedHarvest(MemoryFirestore db, {double stock = 20}) {
  seedUser(db, role: 'admin');
  db.documents['inventory/harvest'] = {
    ...stockDoc(stock: stock),
    'id': 'harvest',
    'name': 'Lele Panen',
    'itemKey': 'lele_panen',
    'isSellable': true,
    'productType': 'harvest',
  };
}

Future<void> saveCash(
  FinanceService service, {
  String request = 'cash',
  String? id,
  DateTime? expected,
  double amount = 50000,
  String type = 'income',
}) => service.save(
  requestId: request,
  id: id,
  expectedUpdatedAt: expected,
  type: type,
  category: 'Operasional',
  amount: amount,
  date: day,
  note: 'Asli',
  paymentMethod: 'tunai',
  userId: 'field',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'request payloads preserve microsecond date differences for all new write paths',
    () async {
      final db = MemoryFirestore();
      seedHarvest(db);
      final different = day.add(const Duration(microseconds: 1));
      final finance = FinanceService(firestore: db);
      await saveCash(finance);
      await expectLater(
        finance.save(
          requestId: 'cash',
          type: 'income',
          category: 'Operasional',
          amount: 50000,
          date: different,
          note: 'Asli',
          paymentMethod: 'tunai',
          userId: 'field',
        ),
        throwsStateError,
      );
      final sales = SalesService(firestore: db);
      await sales.create(
        requestId: 'precise',
        userId: 'field',
        input: saleInput(),
      );
      await expectLater(
        sales.create(
          requestId: 'precise',
          userId: 'field',
          input: SaleInput(
            inventoryItemId: 'harvest',
            quantity: 5,
            unit: 'kg',
            unitPrice: 25000,
            saleDate: different,
            paymentMethod: 'tunai',
          ),
        ),
        throwsStateError,
      );
      final flows = CircularFlowService(firestore: db);
      await flows.create(
        requestId: 'precise',
        userId: 'field',
        input: flowInput(),
      );
      await expectLater(
        flows.create(
          requestId: 'precise',
          userId: 'field',
          input: CircularFlowInput(
            sourceModuleType: 'cacing_tanah',
            destinationModuleType: 'tanaman',
            materialName: 'Kascing',
            quantity: 3,
            unit: 'kg',
            flowDate: different,
          ),
        ),
        throwsStateError,
      );
    },
  );
  test(
    'sample-marked inventory cannot be sold even when classified as harvest',
    () async {
      final db = MemoryFirestore();
      seedHarvest(db);
      db.documents['inventory/harvest']!['isSampleData'] = true;
      await expectLater(
        SalesService(
          firestore: db,
        ).create(requestId: 'sample', userId: 'field', input: saleInput()),
        throwsStateError,
      );
      expect(db.documents.containsKey('sales/sample'), false);
    },
  );
  test('flow can reference existing ledger without writing it twice', () async {
    final db = MemoryFirestore();
    seedHarvest(db);
    db.documents['inventory_transactions/actual'] = {
      'quantity': 3.0,
      'unit': 'kg',
      'moduleType': 'cacing_tanah',
      'isReversed': false,
    };
    await CircularFlowService(firestore: db).create(
      requestId: 'ref',
      userId: 'field',
      input: flowInput(ledger: 'actual'),
    );
    expect(
      db.documents.keys.where((k) => k.startsWith('inventory_transactions/')),
      hasLength(1),
    );
    expect(db.documents['inventory/harvest']!['currentStock'], 20);
    db.documents['inventory_transactions/actual']!['createdBy'] = 'sample_seed';
    await expectLater(
      CircularFlowService(firestore: db).create(
        requestId: 'sample',
        userId: 'field',
        input: flowInput(ledger: 'actual'),
      ),
      throwsStateError,
    );
  });
  test('dashboard sales quantities and cash income stay separate', () async {
    final db = MemoryFirestore();
    seedHarvest(db);
    await SalesService(
      firestore: db,
    ).create(requestId: 'summary', userId: 'field', input: saleInput());
    final r =
        await DashboardService(
          firestore: db,
          profile: user('admin'),
          clock: () => day,
        ).getDashboardSummary(
          includeFinance: true,
          filter: DashboardFilter(
            start: day,
            end: day.add(const Duration(days: 1)),
          ),
        );
    expect(r.salesTotal, 125000);
    expect(r.monthlyIncome, 125000);
    expect(r.soldQuantities['Lele Panen (kg)'], 5);
    expect(
      db.documents.keys.where((k) => k.startsWith('production_results/')),
      isEmpty,
    );
  });
  test(
    'report export round-trips Excel and builds PDF; unauthorized export has no finance data',
    () async {
      final db = MemoryFirestore();
      seedHarvest(db);
      await SalesService(
        firestore: db,
      ).create(requestId: 'export', userId: 'field', input: saleInput());
      await CircularFlowService(firestore: db).create(
        requestId: 'flow',
        userId: 'field',
        input: flowInput(quantity: 3.5),
      );
      final report = await ReportService(firestore: db).generateReport(
        ReportFilter(startDate: day, endDate: day),
        includeFinance: true,
        profile: user('admin'),
      );
      final workbook = Excel.decodeBytes(ExcelGenerator.buildBytes(report));
      expect(
        workbook.tables.keys,
        containsAll(['Summary', 'Keuangan', 'Penjualan', 'Aliran Aktual']),
      );
      expect(
        workbook['Penjualan'].rows[1].last!.value,
        const IntCellValue(125000),
      );
      expect(
        workbook['Aliran Aktual'].rows[1][4]!.value,
        const DoubleCellValue(3.5),
      );
      final pdf = await PdfGenerator.buildBytes(report);
      expect(String.fromCharCodes(pdf.take(4)), '%PDF');
      final safe = AnalyticsModel(
        logbooks: [],
        inventoryItems: [],
        financeRecords: report.financeRecords,
        sales: report.sales,
        startDate: day,
        endDate: day,
      );
      final noFinance = Excel.decodeBytes(ExcelGenerator.buildBytes(safe));
      expect(noFinance.tables.containsKey('Keuangan'), false);
      expect(noFinance.tables.containsKey('Penjualan'), false);
      expect(
        noFinance['Summary'].rows
            .expand((r) => r)
            .whereType<Data>()
            .any((c) => '${c.value}'.contains('Pemasukan')),
        false,
      );
    },
  );
  test(
    'reports reject truncation and finance summaries reject over 500 rows',
    () async {
      final db = MemoryFirestore();
      for (var i = 0; i < 1001; i++) {
        db.documents['inventory/item-$i'] = {...stockDoc(), 'name': '$i'};
      }
      await expectLater(
        ReportService(firestore: db).generateReport(
          ReportFilter(
            startDate: day,
            endDate: day,
            reportType: ReportType.inventory,
          ),
        ),
        throwsStateError,
      );
      db.documents.clear();
      for (var i = 0; i < 501; i++) {
        db.documents['finance_transactions/cash-$i'] = {
          'type': 'income',
          'amount': 100,
          'category': 'Test',
          'date': Timestamp.fromDate(day),
          'isDeleted': false,
        };
      }
      await expectLater(
        FinanceService(firestore: db).loadSummaryByDateRange(
          start: day,
          end: day.add(const Duration(days: 1)),
        ),
        throwsStateError,
      );
      expect(
        db.queryLimits.values.expand((l) => l).every((l) => l != null),
        true,
      );
    },
  );
  test('runtime has no sample feature while canonical modules survive', () {
    expect(File('lib/core/dev/sample_data_service.dart').existsSync(), false);
    for (final f
        in Directory('lib')
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))) {
      final code = f.readAsStringSync();
      for (final marker in [
        'SampleDataService',
        'seedSampleData',
        'clearSampleData',
        'hasSampleData',
        'seedDefaultFlows',
        'defaultCircularFlows',
        'Seed sampel',
        'Hapus sampel',
      ]) {
        expect(code.contains(marker), false, reason: '${f.path}: $marker');
      }
    }
    expect(FarmModules.values.map((m) => m.id).toSet(), {
      'ayam_kampung',
      'maggot_bsf',
      'cacing_tanah',
      'tanaman',
      'lele',
    });
    expect(
      File(
        'lib/features/profile/screen/profile_screen.dart',
      ).readAsStringSync(),
      contains('FarmModuleService().seedDefaults'),
    );
  });
  for (final role in [
    'admin',
    'operator_lapangan',
    'operator_keuangan',
    'operator',
    'mitra',
    'peserta_edukasi',
  ]) {
    test('inactive $role has no management capabilities', () {
      final p = user(role, active: false);
      expect(
        [
          p.canManageFinance,
          p.canDeleteFinance,
          p.canManageSales,
          p.canManageCircularFlows,
          p.canManageEducation,
          p.canDeleteEducation,
          p.canManageFarmModules,
          p.canManageUsers,
          p.canDeleteUsers,
          p.canManageInventory,
          p.canManageBatches,
          p.canManageSchedules,
        ].any((v) => v),
        false,
      );
    });
  }
  test(
    'sale writes one receipt stock ledger finance; replay never changes production',
    () async {
      final db = MemoryFirestore();
      seedHarvest(db);
      final service = SalesService(firestore: db);
      await service.create(
        requestId: 'one',
        userId: 'field',
        input: saleInput(),
      );
      await service.create(
        requestId: 'one',
        userId: 'field',
        input: saleInput(),
      );
      await service.create(
        requestId: 'two',
        userId: 'field',
        input: saleInput(quantity: 8),
      );
      expect(db.documents['inventory/harvest']?['currentStock'], 7);
      expect(
        db.documents.keys.where((p) => p.startsWith('sales/')),
        hasLength(2),
      );
      expect(
        db.documents.keys.where((p) => p.startsWith('inventory_transactions/')),
        hasLength(2),
      );
      expect(
        db.documents.keys.where((p) => p.startsWith('finance_transactions/')),
        hasLength(2),
      );
      expect(
        db.documents.keys.any((p) => p.startsWith('production_results/')),
        false,
      );
      await expectLater(
        service.create(
          requestId: 'one',
          userId: 'field',
          input: saleInput(quantity: 6),
        ),
        throwsStateError,
      );
    },
  );
  test('sales round half up once using thousandths and integer Rupiah', () {
    expect(saleInput(quantity: 0.125, price: 12).totalAmount, 2);
    expect(saleInput(quantity: 0.125, price: 11).totalAmount, 1);
  });
  for (final qty in [
    0.0,
    -1.0,
    double.nan,
    double.infinity,
    0.0001,
    1000001.0,
  ]) {
    test('invalid sale quantity $qty rejected before write', () async {
      final db = MemoryFirestore();
      seedHarvest(db);
      await expectLater(
        SalesService(firestore: db).create(
          requestId: 'invalid',
          userId: 'field',
          input: saleInput(quantity: qty),
        ),
        throwsArgumentError,
      );
      expect(db.documents.containsKey('sales/invalid'), false);
    });
  }
  test(
    'sale rejects unavailable stock, nonharvest, wrong unit and inactive user',
    () async {
      final db = MemoryFirestore();
      seedHarvest(db, stock: 2);
      final service = SalesService(firestore: db);
      await expectLater(
        service.create(requestId: 'x', userId: 'field', input: saleInput()),
        throwsStateError,
      );
      seedHarvest(db);
      db.documents['inventory/harvest']!['isSellable'] = false;
      await expectLater(
        service.create(requestId: 'x', userId: 'field', input: saleInput()),
        throwsStateError,
      );
      seedHarvest(db);
      await expectLater(
        service.create(
          requestId: 'x',
          userId: 'field',
          input: saleInput(unit: 'liter'),
        ),
        throwsStateError,
      );
      seedUser(db, role: 'admin', active: false);
      await expectLater(
        service.create(requestId: 'x', userId: 'field', input: saleInput()),
        throwsStateError,
      );
    },
  );
  test('sale rollback leaves all documents untouched', () async {
    final db = MemoryFirestore();
    seedHarvest(db);
    db.failCommit = true;
    await expectLater(
      SalesService(
        firestore: db,
      ).create(requestId: 'x', userId: 'field', input: saleInput()),
      throwsStateError,
    );
    expect(db.documents.keys, hasLength(2));
    expect(db.documents['inventory/harvest']?['currentStock'], 20);
  });
  test(
    'sales retry re-reads competing balance and refuses overselling',
    () async {
      final db = MemoryFirestore();
      seedHarvest(db);
      db.retryOnce = true;
      db.beforeRetry = () =>
          db.documents['inventory/harvest']!['currentStock'] = 1;
      await expectLater(
        SalesService(
          firestore: db,
        ).create(requestId: 'race', userId: 'field', input: saleInput()),
        throwsStateError,
      );
      expect(db.documents.containsKey('sales/race'), false);
    },
  );
  test(
    'sales commit ambiguity replays receipt without second decrement',
    () async {
      final db = MemoryFirestore();
      seedHarvest(db);
      db.denyNextCommittedWrite = true;
      await SalesService(
        firestore: db,
      ).create(requestId: 'ambiguous', userId: 'field', input: saleInput());
      expect(db.documents['inventory/harvest']?['currentStock'], 15);
      expect(
        db.documents.keys.where((p) => p.startsWith('sales/')),
        hasLength(1),
      );
    },
  );
  test(
    'finance create income expense and idempotent retry; changed payload rejected',
    () async {
      final db = MemoryFirestore();
      seedUser(db, role: 'operator_keuangan');
      final service = FinanceService(firestore: db);
      await saveCash(service);
      await saveCash(service);
      await saveCash(service, request: 'expense', type: 'expense');
      expect(
        db.documents.keys.where((p) => p.startsWith('finance_transactions/')),
        hasLength(2),
      );
      await expectLater(saveCash(service, amount: 70000), throwsStateError);
    },
  );
  for (final amount in [0.0, -1.0, double.nan, double.infinity, 1e13]) {
    test('finance invalid amount $amount', () async {
      final db = MemoryFirestore();
      seedUser(db, role: 'admin');
      await expectLater(
        saveCash(FinanceService(firestore: db), amount: amount),
        throwsArgumentError,
      );
    });
  }
  test(
    'finance edits require version snapshot and permanent before/after audit',
    () async {
      final db = MemoryFirestore();
      seedUser(db, role: 'admin');
      final service = FinanceService(firestore: db);
      await saveCash(service);
      final old = FinanceRecord.fromDocument(
        await db.collection('finance_transactions').doc('cash').get(),
      );
      await expectLater(
        saveCash(
          service,
          id: 'cash',
          request: 'stale',
          expected: day,
          amount: 60000,
        ),
        throwsStateError,
      );
      await saveCash(
        service,
        id: 'cash',
        request: 'edit',
        expected: old.updatedAt,
        amount: 60000,
      );
      await saveCash(
        service,
        id: 'cash',
        request: 'edit',
        expected: old.updatedAt,
        amount: 60000,
      );
      final audit = db.documents['finance_transactions/cash/edits/edit']!;
      expect(audit['before']['amount'], 50000);
      expect(audit['after']['amount'], 60000);
      expect(db.documents['finance_transactions/cash']?['version'], 1);
    },
  );
  test(
    'sale-linked finance edit and delete cannot be invoked manually',
    () async {
      final db = MemoryFirestore();
      seedHarvest(db);
      await SalesService(
        firestore: db,
      ).create(requestId: 'x', userId: 'field', input: saleInput());
      final r = FinanceRecord.fromDocument(
        await db.collection('finance_transactions').doc('sale_x').get(),
      );
      final service = FinanceService(firestore: db);
      await expectLater(
        saveCash(service, id: r.id, request: 'edit', expected: r.updatedAt),
        throwsStateError,
      );
      await expectLater(
        service.delete(
          r.id,
          userId: 'field',
          expectedUpdatedAt: r.updatedAt,
          requestId: 'delete',
        ),
        throwsStateError,
      );
    },
  );
  test(
    'finance soft delete retained with audit; double request is a no-op',
    () async {
      final db = MemoryFirestore();
      seedUser(db, role: 'admin');
      final service = FinanceService(firestore: db);
      await saveCash(service);
      final r = FinanceRecord.fromDocument(
        await db.collection('finance_transactions').doc('cash').get(),
      );
      for (var i = 0; i < 2; i++) {
        await service.delete(
          'cash',
          userId: 'field',
          expectedUpdatedAt: r.updatedAt,
          requestId: 'delete',
        );
      }
      expect(db.documents['finance_transactions/cash']?['isDeleted'], true);
      expect(db.documents['finance_transactions/cash/edits/delete'], isNotNull);
    },
  );
  test(
    'finance summary and pagination use full period, not just first 20 records',
    () async {
      final db = MemoryFirestore();
      seedUser(db, role: 'admin');
      final service = FinanceService(firestore: db);
      for (var i = 0; i < 24; i++) {
        await saveCash(service, request: 'cash-$i', amount: 100);
      }
      final first = await service.fetchPage(
        start: day,
        end: day.add(const Duration(days: 1)),
      );
      final second = await service.fetchPage(
        start: day,
        end: day.add(const Duration(days: 1)),
        cursor: first.cursor,
      );
      expect(first.items.length, 20);
      expect(second.items.length, 4);
      final total = await service.loadSummaryByDateRange(
        start: day,
        end: day.add(const Duration(days: 1)),
      );
      expect(total.totalIncome, 2400);
    },
  );
  test('finance summary errors are not replaced with zero', () async {
    final db = MemoryFirestore();
    db.queryErrors['finance_transactions'] = StateError('offline');
    await expectLater(
      FinanceService(firestore: db).loadSummaryByDateRange(
        start: day,
        end: day.add(const Duration(days: 1)),
      ),
      throwsStateError,
    );
  });
  test(
    'actual flow is idempotent and never touches stock or production',
    () async {
      final db = MemoryFirestore();
      seedUser(db);
      db.documents['inventory/feed'] = stockDoc();
      final service = CircularFlowService(firestore: db);
      await service.create(
        requestId: 'flow',
        userId: 'field',
        input: flowInput(),
      );
      await service.create(
        requestId: 'flow',
        userId: 'field',
        input: flowInput(),
      );
      expect(db.documents['inventory/feed']?['currentStock'], 20);
      expect(
        db.documents.keys.where((p) => p.startsWith('inventory_transactions/')),
        isEmpty,
      );
      expect(
        CircularFlow.fromDocument(
          await db.collection('circular_flows').doc('flow').get(),
        ).isActual,
        true,
      );
      await expectLater(
        service.create(
          requestId: 'flow',
          userId: 'field',
          input: flowInput(quantity: 4),
        ),
        throwsStateError,
      );
    },
  );
  for (final qty in [0.0, -1.0, double.nan, double.infinity]) {
    test('flow invalid quantity $qty', () async {
      final db = MemoryFirestore();
      seedUser(db);
      await expectLater(
        CircularFlowService(firestore: db).create(
          requestId: 'x',
          userId: 'field',
          input: flowInput(quantity: qty),
        ),
        throwsArgumentError,
      );
    });
  }
  test('flow invalid unit modules and references rejected', () async {
    final db = MemoryFirestore();
    seedUser(db);
    final service = CircularFlowService(firestore: db);
    for (final input in [
      flowInput(unit: 'invalid'),
      flowInput(source: 'tanaman'),
    ]) {
      await expectLater(
        service.create(requestId: 'x', userId: 'field', input: input),
        throwsArgumentError,
      );
    }
    for (final input in [
      flowInput(sourceBatch: 'missing'),
      flowInput(log: 'missing'),
      flowInput(ledger: 'missing'),
    ]) {
      await expectLater(
        service.create(requestId: 'x', userId: 'field', input: input),
        throwsStateError,
      );
    }
  });
  test(
    'legacy circular parser remains readable but not treated as actual',
    () async {
      final db = MemoryFirestore();
      db.documents['circular_flows/legacy'] = {'materialName': 'Lama'};
      final flow = CircularFlow.fromDocument(
        await db.collection('circular_flows').doc('legacy').get(),
      );
      expect(flow.materialName, 'Lama');
      expect(flow.isActual, false);
      for (final marker in [
        {'createdBy': 'sample_seed'},
        {'sampleVersion': 'v2'},
      ]) {
        db.documents['circular_flows/legacy'] = {
          'materialName': 'Lama',
          'sourceType': 'manual',
          'createdBy': 'field',
          ...marker,
        };
        expect(
          CircularFlow.fromDocument(
            await db.collection('circular_flows').doc('legacy').get(),
          ).isActual,
          false,
        );
      }
    },
  );
  test(
    'report never queries finance or sales for field role even if requested',
    () async {
      final db = MemoryFirestore();
      final r = await ReportService(firestore: db).generateReport(
        ReportFilter(startDate: day, endDate: day),
        includeFinance: true,
        profile: user('operator_lapangan'),
      );
      expect(db.queries, isNot(contains('finance_transactions')));
      expect(db.queries, isNot(contains('sales')));
      expect(r.financeIncluded, false);
    },
  );
  test(
    'report sales totals are separate from cash income, quantities grouped by unit',
    () async {
      final db = MemoryFirestore();
      seedHarvest(db);
      await SalesService(
        firestore: db,
      ).create(requestId: 'x', userId: 'field', input: saleInput());
      await CircularFlowService(
        firestore: db,
      ).create(requestId: 'f', userId: 'field', input: flowInput());
      final r = await ReportService(firestore: db).generateReport(
        ReportFilter(startDate: day, endDate: day),
        includeFinance: true,
        profile: user('admin'),
      );
      expect(r.totalIncome, 125000);
      expect(r.totalSales, 125000);
      expect(r.profitLoss, 125000);
      expect(r.salesPerProduct['Lele Panen'], 125000);
      expect(r.salesPerModule['lele'], 125000);
      expect(r.flowsPerMaterial['Kascing (kg)'], 3);
    },
  );
  test(
    'dashboard and productivity reject sample-marked data instead of publishing demo stats',
    () async {
      final db = MemoryFirestore();
      db.documents['logbooks/demo'] = {'isSampleData': true};
      await expectLater(
        DashboardService(
          firestore: db,
        ).getDashboardSummary(includeFinance: false),
        throwsStateError,
      );
      await expectLater(
        ProductivityService(
          firestore: db,
        ).load(DashboardFilter.days(7), 'lele', null),
        throwsStateError,
      );
      expect(hasSampleMarker({'createdBy': 'sample_seed'}), true);
    },
  );
  test('field cannot classify inventory as harvest product', () async {
    final db = MemoryFirestore();
    seedUser(db);
    await expectLater(
      InventoryService(firestore: db).createItem(
        requestId: 'master',
        isSellable: true,
        name: 'Pakan',
        itemKey: 'pakan',
        moduleType: 'lele',
        category: 'pakan',
        unit: 'kg',
        minStock: 0,
        location: '',
        userId: 'field',
      ),
      throwsStateError,
    );
  });
}
