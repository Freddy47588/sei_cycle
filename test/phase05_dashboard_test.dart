import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sei_cycle/features/dashboard/models/dashboard_filter.dart';
import 'package:sei_cycle/features/dashboard/models/productivity_point.dart';
import 'package:sei_cycle/features/dashboard/services/dashboard_service.dart';
import 'package:sei_cycle/features/dashboard/services/productivity_service.dart';
import 'package:sei_cycle/features/profile/models/app_user.dart';
import 'support/memory_firestore.dart';

final now = DateTime(2026, 1, 2, 12);
final period = DashboardFilter.days(7, now: now);
AppUser user(String role, {bool active = true}) => AppUser(
  uid: role,
  name: role,
  email: '',
  photoUrl: '',
  role: role,
  isActive: active,
  createdAt: now,
  updatedAt: now,
);
Map<String, dynamic> logData(
  String module,
  Map<String, dynamic> details, {
  String? batch = 'B1',
  DateTime? date,
}) => {
  'moduleType': module,
  'batchId': batch,
  'details': details,
  'activityDate': Timestamp.fromDate(date ?? now),
  'isDeleted': false,
};
AnalyticsDocument log(
  String module,
  Map<String, dynamic> details, {
  String id = 'log',
  String? batch = 'B1',
  DateTime? date,
}) => AnalyticsDocument(id, logData(module, details, batch: batch, date: date));
AnalyticsDocument production(
  String module,
  String product,
  String unit,
  double quantity, {
  String id = 'result',
  String parent = 'log',
  String? batch = 'B1',
}) => AnalyticsDocument(id, {
  'moduleType': module,
  'productName': product,
  'unit': unit,
  'quantity': quantity,
  'logbookId': parent,
  'batchId': batch,
  'harvestDate': Timestamp.fromDate(now),
});
ProductivityReport report(
  String module,
  List<AnalyticsDocument> logs, {
  List<AnalyticsDocument> products = const [],
  String? batch,
  bool truncated = false,
}) => calculateProductivity(
  filter: period,
  module: module,
  batchId: batch,
  logs: logs,
  production: products,
  parents: {for (final log in logs) log.id: log.data},
  productionTruncated: truncated,
);

void main() {
  test('calendar range crosses years and uses exclusive end', () {
    expect(period.start, DateTime(2025, 12, 27));
    expect(period.end, DateTime(2026, 1, 3));
    expect(period.contains(period.start), isTrue);
    expect(period.contains(period.end), isFalse);
    expect(
      DashboardFilter.days(7, now: DateTime(2024, 3, 2)).start,
      DateTime(2024, 2, 25),
    );
    expect(() => DashboardFilter(start: now, end: now), throwsArgumentError);
  });
  test('eggs are butir and population is latest per batch, never a sum', () {
    final result = report('ayam_kampung', [
      log('ayam_kampung', {
        'produksi_telur_hari_ini': 8,
        'populasi_aktif': 50,
      }, date: DateTime(2026, 1, 1)),
      log('ayam_kampung', {
        'produksi_telur_hari_ini': 10,
        'populasi_aktif': 48,
      }, id: 'second'),
    ]);
    expect(result.series.first.unit, 'butir');
    expect(result.series.first.summary, 18);
    expect(result.series[1].summary, 48);
  });
  test('maggot target and estimate never become actual harvest', () {
    final result = report('maggot_bsf', [
      log('maggot_bsf', {
        'estimasi_panen_kg': 200,
        'target_panen_larva_kg': 300,
      }),
    ]);
    expect(result.production, isEmpty);
    expect(result.series.every((s) => !s.additive), isTrue);
  });
  test('solid kascing kg and liquid liters stay separate', () {
    final logs = [
      log('cacing_tanah', {'panen_kascing_kg': 20, 'kascing_cair_liter': 5}),
    ];
    final result = report(
      'cacing_tanah',
      logs,
      products: [
        production('cacing_tanah', 'Kascing', 'kg', 20),
        production('cacing_tanah', 'Kascing Cair', 'liter', 5, id: 'liquid'),
      ],
    );
    expect(result.production, {'Kascing (kg)': 20, 'Kascing Cair (liter)': 5});
  });
  test('plant growth groups batch commodity block and planting date', () {
    final result = report('tanaman', [
      log('tanaman', {
        'jenis_tanaman': 'Talas',
        'blok_lokasi': 'A',
        'tanggal_tanam': '1/12/25',
        'tinggi_tanaman_cm': 10,
      }),
      log('tanaman', {
        'jenis_tanaman': 'Pepaya',
        'blok_lokasi': 'A',
        'tanggal_tanam': '1/12/25',
        'tinggi_tanaman_cm': 50,
      }, id: 'other'),
      log(
        'tanaman',
        {
          'jenis_tanaman': 'Talas',
          'blok_lokasi': 'A',
          'tanggal_tanam': '1/12/25',
          'tinggi_tanaman_cm': 12,
        },
        id: 'another',
        batch: 'B2',
      ),
    ]);
    expect(result.series, hasLength(3));
    expect(result.series.every((s) => s.points.length == 1), isTrue);
  });
  test(
    'lele legacy keys keep audited business meaning and reject textual survival',
    () {
      final result = report('lele', [
        log('lele', {
          'mortalitas_ikan': 125,
          'kondisi_air': 'jernih',
          'ph_air': 7.2,
          'suhu_air': 28,
          'pakan_lele_kg': 2,
        }),
      ]);
      expect(
        result.series.any(
          (s) => s.label.startsWith('Bobot rata-rata') && s.unit == 'g/ekor',
        ),
        isTrue,
      );
      expect(
        result.series.any((s) => s.label.startsWith('Pakan maggot sore')),
        isTrue,
      );
      expect(result.series.any((s) => s.unit == '%'), isFalse);
    },
  );
  test(
    'non finite and invalid measurements are excluded without fabricated zeros',
    () {
      final result = report('lele', [
        log('lele', {
          'ph_air': double.nan,
          'suhu_air': double.infinity,
          'kondisi_air': 101,
          'pakan_lele_kg': -1,
        }),
      ]);
      expect(result.series, isEmpty);
      expect(finiteNumber('Infinity'), isNull);
      expect(finiteNumber('3,5'), 3.5);
    },
  );
  test('missing days stay missing and zero observations remain valid', () {
    final result = report('lele', [
      log('lele', {'ph_air': 0}, date: DateTime(2025, 12, 27)),
      log('lele', {'ph_air': 7}, id: 'last'),
    ]);
    expect(result.series.single.points.length, 2);
    expect(result.series.single.points.first.value, 0);
  });
  test(
    'one harvest represented by logbook production and inventory counts once',
    () async {
      final db = MemoryFirestore();
      db.documents['logbooks/log'] = logData('lele', {'panen_lele_kg': 20});
      db.documents['production_results/result'] = production(
        'lele',
        'Lele Panen',
        'kg',
        20,
      ).data;
      db.documents['batches/B1'] = {'isDeleted': false};
      db.documents['inventory_transactions/movement'] = {
        'quantity': 20,
        'logbookId': 'log',
      };
      db.documents['inventory/lele'] = {'currentStock': 20};
      final result = await ProductivityService(
        firestore: db,
      ).load(period, 'lele', 'B1');
      expect(result.production, {'Lele Panen (kg)': 20});
      expect(db.queries, contains('inventory_transactions'));
      expect(db.queries, isNot(contains('inventory')));
    },
  );
  test('duplicate production identity fails closed instead of doubling', () {
    final result = report(
      'lele',
      [
        log('lele', {'panen_lele_kg': 20}),
      ],
      products: [
        production('lele', 'Lele', 'kg', 20),
        production('lele', 'Lele', 'kg', 20, id: 'duplicate'),
      ],
    );
    expect(result.productionUncertain, isTrue);
    expect(result.production, isEmpty);
  });
  test(
    'missing or deleted parent and truncated production cannot become totals',
    () {
      final product = production('lele', 'Lele', 'kg', 20);
      expect(
        report('lele', [], products: [product]).productionUncertain,
        isTrue,
      );
      final deleted = AnalyticsDocument('log', {
        ...logData('lele', {}),
        'isDeleted': true,
      });
      expect(
        report('lele', [deleted], products: [product]).productionUncertain,
        isTrue,
      );
      expect(
        report(
          'lele',
          [log('lele', {})],
          products: [product],
          truncated: true,
        ).production,
        isEmpty,
      );
    },
  );
  test('legacy harvest without canonical result remains uncertain', () {
    expect(
      report('lele', [
        log('lele', {'panen_lele_kg': 20}, batch: null),
      ]).productionUncertain,
      isTrue,
    );
  });
  test(
    'batch filter isolates completed history without assigning legacy records',
    () {
      final logs = [
        log('lele', {'ph_air': 7}, batch: 'completed'),
        log('lele', {'ph_air': 8}, id: 'legacy', batch: null),
      ];
      expect(report('lele', logs, batch: 'completed').logCount, 1);
      expect(report('lele', logs).logCount, 2);
      expect(report('ayam_kampung', logs).logCount, 0);
    },
  );
  test('empty successful data is distinct from failure', () async {
    final db = MemoryFirestore();
    final summary = await DashboardService(
      firestore: db,
      clock: () => now,
    ).load(includeFinance: false);
    expect(summary.activeModuleCount, 0);
    expect(summary.todayLogCount, 0);
    expect(summary.recentActivities, isEmpty);
    db.queryErrors['logbooks'] = FirebaseException(
      plugin: 'cloud_firestore',
      code: 'failed-precondition',
    );
    final failed = await DashboardService(
      firestore: db,
    ).load(includeFinance: false);
    expect(failed.todayLogCount, isNull);
    expect(failed.sectionErrors['logs'], isA<FirebaseException>());
    expect(failed.activeModuleCount, 0);
  });
  test(
    'oversize source is unavailable while independent stock and schedule totals remain accurate',
    () async {
      final db = MemoryFirestore();
      db.documents['farm_modules/active'] = {'isActive': true};
      db.documents['farm_modules/inactive'] = {'isActive': false};
      db.documents['batches/active'] = {'status': 'active', 'isDeleted': false};
      db.documents['batches/completed'] = {
        'status': 'completed',
        'isDeleted': false,
      };
      for (var i = 0; i < 610; i++) {
        db.documents['logbooks/l$i'] = logData('lele', {});
      }
      for (final status in ['pending', 'done', 'skipped', 'unknown']) {
        db.documents['schedules/$status'] = {
          'isDeleted': false,
          'date': Timestamp.fromDate(now),
          'status': status,
        };
      }
      db.documents['inventory/low'] = {
        'name': 'Low',
        'currentStock': 2,
        'minStock': 3,
        'isLowStock': false,
        'isDeleted': false,
      };
      db.documents['inventory/empty'] = {
        'name': 'Empty',
        'currentStock': -1,
        'minStock': 3,
        'isLowStock': false,
        'isDeleted': false,
      };
      db.documents['inventory/safe'] = {
        'name': 'Safe',
        'currentStock': 10,
        'minStock': 3,
        'isLowStock': true,
        'isDeleted': false,
      };
      final summary = await DashboardService(
        firestore: db,
        clock: () => now,
      ).load(includeFinance: false);
      expect(summary.activeModuleCount, 1);
      expect(summary.activeBatchCount, 1);
      expect(summary.completedBatchCount, 1);
      expect(summary.todayLogCount, isNull);
      expect(summary.sectionErrors['logs'], isA<StateError>());
      expect(summary.recentActivities, isEmpty);
      expect(summary.todayScheduleCount, 4);
      expect(
        [
          summary.pendingScheduleCount,
          summary.doneScheduleCount,
          summary.skippedScheduleCount,
        ],
        [1, 1, 1],
      );
      expect(summary.lowStockCount, 1);
      expect(summary.outOfStockCount, 1);
      expect(db.aggregateQueries, isEmpty);
      expect(
        db.queryLimits.values.expand((v) => v).every((limit) => limit != null),
        isTrue,
      );
    },
  );
  test('complete ID pagination counts stock beyond 200 accurately', () async {
    final db = MemoryFirestore();
    for (var i = 0; i < 205; i++) {
      db.documents['inventory/$i'] = {
        'name': '$i',
        'currentStock': 0,
        'minStock': 0,
        'isDeleted': false,
      };
    }
    final summary = await DashboardService(
      firestore: db,
      clock: () => now,
    ).load(includeFinance: false);
    expect(summary.inventoryTruncated, isFalse);
    expect(summary.inventoryLoaded, 205);
    expect(summary.outOfStockCount, 205);
    expect(summary.lowStockCount, 0);
  });
  for (final profile in [
    user('operator_lapangan'),
    user('mitra'),
    user('admin', active: false),
  ]) {
    test(
      'finance is never requested for ${profile.role} active=${profile.isActive}',
      () async {
        final db = MemoryFirestore();
        final summary = await DashboardService(
          firestore: db,
          profile: profile,
          clock: () => now,
        ).load(includeFinance: true);
        expect(db.queries, isNot(contains('finance_transactions')));
        expect(summary.financeVisible, isFalse);
      },
    );
  }
  for (final role in ['admin', 'operator_keuangan']) {
    test(
      'finance $role computes net cash and exposes permission failures',
      () async {
        final db = MemoryFirestore();
        db.documents['finance_transactions/in'] = {
          'isDeleted': false,
          'date': Timestamp.fromDate(now),
          'type': 'income',
          'amount': 100,
        };
        db.documents['finance_transactions/out'] = {
          'isDeleted': false,
          'date': Timestamp.fromDate(now),
          'type': 'expense',
          'amount': 150,
        };
        final service = DashboardService(
          firestore: db,
          profile: user(role),
          clock: () => now,
        );
        final summary = await service.load(includeFinance: true);
        expect(
          [
            summary.monthlyIncome,
            summary.monthlyExpense,
            summary.monthlyProfit,
          ],
          [100, 150, -50],
        );
        db.queryErrors['finance_transactions'] = FirebaseException(
          plugin: 'cloud_firestore',
          code: 'permission-denied',
        );
        final denied = await service.load(includeFinance: true);
        expect(denied.financeError, isA<FirebaseException>());
        expect(denied.financeVisible, isTrue);
      },
    );
  }
  test('timeline merges sources deduplicates sorts and preserves status', () {
    final db = MemoryFirestore();
    QueryDocumentSnapshot<Map<String, dynamic>> doc(
      String id,
      Map<String, dynamic> data,
    ) => MemorySnapshot(MemoryDocument(db, id), data);
    final logDoc = doc('logbooks/log', logData('lele', {}));
    final schedule = doc('schedules/s', {
      'date': Timestamp.fromDate(now),
      'status': 'done',
      'completedAt': Timestamp.fromDate(now.add(const Duration(hours: 1))),
    });
    final result = mergeDashboardActivities([logDoc], [schedule, schedule]);
    expect(result, hasLength(2));
    expect(result.first.source, 'schedule');
    expect(result.first.done, isTrue);
    expect(result.last.status, 'recorded');
    expect(result.last.done, isFalse);
  });
  test(
    'finance over 500 rows is an explicit error, never a partial total',
    () async {
      final db = MemoryFirestore();
      for (var i = 0; i < 501; i++) {
        db.documents['finance_transactions/$i'] = {
          'isDeleted': false,
          'date': Timestamp.fromDate(now),
          'type': 'income',
          'amount': 1,
        };
      }
      final value = await DashboardService(
        firestore: db,
        profile: user('admin'),
        clock: () => now,
      ).load(includeFinance: true);
      expect(value.financeError, isA<StateError>());
      expect(value.revenueItems, isEmpty);
    },
  );
  test(
    'malformed inventory cannot silently produce a zero stock KPI',
    () async {
      final db = MemoryFirestore();
      db.documents['inventory/bad'] = {
        'isDeleted': false,
        'currentStock': double.nan,
        'minStock': 0,
      };
      final summary = await DashboardService(
        firestore: db,
        clock: () => now,
      ).load(includeFinance: false);
      expect(summary.lowStockCount, isNull);
      expect(summary.outOfStockCount, isNull);
      expect(summary.sectionErrors['inventory'], isA<FormatException>());
      expect(summary.todayLogCount, 0);
    },
  );
}
