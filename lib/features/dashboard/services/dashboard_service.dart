import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/utils/sample_data_guard.dart';
import '../../sales/services/sales_service.dart';
import '../../sales/models/sale.dart';

import '../../../core/constants/firestore_collections.dart';
import '../../../theme/app_theme.dart';
import '../../profile/models/app_user.dart';
import '../models/dashboard_filter.dart';
import '../models/dashboard_numbers.dart';
export '../models/dashboard_numbers.dart';
import '../models/dashboard_summary.dart';

class DashboardService {
  DashboardService({
    FirebaseFirestore? firestore,
    this.profile,
    DateTime Function()? clock,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _clock = clock ?? DateTime.now;
  final FirebaseFirestore _firestore;
  final AppUser? profile;
  final DateTime Function() _clock;

  Future<DashboardSummary> load({required bool includeFinance}) =>
      getDashboardSummary(includeFinance: includeFinance);

  Future<DashboardSummary> getDashboardSummary({
    required bool includeFinance,
    DashboardFilter? filter,
  }) async {
    await requireNoSampleData(_firestore, [
      'farm_modules',
      'logbooks',
      'schedules',
      'batches',
      'inventory',
    ]);
    final now = _clock();
    final today = DashboardFilter.days(1, now: now);
    final period = filter ?? DashboardFilter.days(30, now: now);
    final financeAllowed =
        includeFinance && (profile?.canViewFinanceDashboard ?? false);
    // A finance failure remains an explicit section error; operational data survives.
    Object? financeError;
    final financeFuture = financeAllowed
        ? getMonthlyFinanceSummary(
            startOfMonth: period.start,
            endOfMonth: period.end,
          ).then<FinanceDashboardSummary?>(
            (value) => value,
            onError: (Object error) {
              financeError = error;
              return null;
            },
          )
        : Future<FinanceDashboardSummary?>.value(null);
    Object? salesError;
    final salesFuture = financeAllowed
        ? SalesService(firestore: _firestore)
              .summary(period.start, period.end)
              .then<List<Sale>?>(
                (v) => v,
                onError: (Object e) {
                  salesError = e;
                  return null;
                },
              )
        : Future<List<Sale>?>.value(null);
    final results = await Future.wait<Object?>([
      _count(
        _firestore
            .collection(FirestoreCollections.farmModules)
            .where('isActive', isEqualTo: true),
      ),
      _count(_range(FirestoreCollections.logbooks, 'activityDate', today)),
      _count(_range(FirestoreCollections.schedules, 'date', today)),
      _count(
        _range(
          FirestoreCollections.schedules,
          'date',
          today,
        ).where('status', isEqualTo: 'pending'),
      ),
      _count(
        _range(
          FirestoreCollections.schedules,
          'date',
          today,
        ).where('status', isEqualTo: 'done'),
      ),
      _count(
        _range(
          FirestoreCollections.schedules,
          'date',
          today,
        ).where('status', isEqualTo: 'skipped'),
      ),
      _count(_batches.where('status', isEqualTo: 'active')),
      _count(_batches.where('status', isEqualTo: 'completed')),
      _firestore
          .collection(FirestoreCollections.inventory)
          .where('isDeleted', isEqualTo: false)
          .orderBy(FieldPath.documentId)
          .limit(201)
          .get(),
      _firestore
          .collection(FirestoreCollections.logbooks)
          .where('isDeleted', isEqualTo: false)
          .orderBy('activityDate', descending: true)
          .limit(10)
          .get(),
      _range(
        FirestoreCollections.schedules,
        'date',
        today,
      ).orderBy('date', descending: true).limit(10).get(),
      // Completion time, rather than the planned date, determines recent checklist events.
      _firestore
          .collection(FirestoreCollections.schedules)
          .where('isDeleted', isEqualTo: false)
          .where('status', isEqualTo: 'done')
          .orderBy('completedAt', descending: true)
          .limit(10)
          .get(),
      getRecentCircularFlows(filter: period),
      financeFuture,
      salesFuture,
    ]);
    final stockDocs = (results[8] as QuerySnapshot<Map<String, dynamic>>).docs;
    final inventory = stockDocs.take(200).map((doc) {
      final d = doc.data();
      final stock = finiteNumber(d['currentStock']);
      final minimum = finiteNumber(d['minStock']);
      if (stock == null || minimum == null) {
        throw const FormatException(
          'Saldo stok tidak valid; ringkasan tidak dihitung sebagai nol.',
        );
      }
      return LowStockDashboardItem(
        id: doc.id,
        name: '${d['name'] ?? 'Item tanpa nama'}',
        currentStock: stock,
        minStock: minimum,
        unit: '${d['unit'] ?? ''}',
      );
    }).toList();
    final low = inventory
        .where(
          (item) => item.currentStock > 0 && item.currentStock <= item.minStock,
        )
        .toList();
    final empty = inventory.where((item) => item.currentStock <= 0).toList();
    final finance = results[13] as FinanceDashboardSummary?;
    return DashboardSummary(
      salesTotal: (results[14] as List<Sale>?)?.fold<int>(
        0,
        (total, s) => total + s.totalAmount,
      ),
      soldQuantities: {
        for (final sale in (results[14] as List<Sale>? ?? []))
          '${sale.productName} (${sale.unit})': (results[14] as List<Sale>)
              .where(
                (s) => s.productName == sale.productName && s.unit == sale.unit,
              )
              .fold<double>(0, (total, s) => total + s.quantity),
      },
      salesError: salesError,
      activeModuleCount: results[0] as int,
      todayLogCount: results[1] as int,
      todayScheduleCount: results[2] as int,
      pendingScheduleCount: results[3] as int,
      doneScheduleCount: results[4] as int,
      skippedScheduleCount: results[5] as int,
      activeBatchCount: results[6] as int,
      completedBatchCount: results[7] as int,
      lowStockCount: low.length,
      outOfStockCount: empty.length,
      inventoryLoaded: inventory.length,
      inventoryTruncated: stockDocs.length > 200,
      lowStockPreview: [...empty, ...low].take(5).toList(),
      recentActivities: mergeDashboardActivities(
        (results[9] as QuerySnapshot<Map<String, dynamic>>).docs,
        [
          ...(results[10] as QuerySnapshot<Map<String, dynamic>>).docs,
          ...(results[11] as QuerySnapshot<Map<String, dynamic>>).docs,
        ],
      ),
      circularFlows: results[12] as List<DashboardCircularFlow>,
      monthlyIncome: finance?.income ?? 0,
      monthlyExpense: finance?.expense ?? 0,
      monthlyProfit: (finance?.income ?? 0) - (finance?.expense ?? 0),
      revenueItems: const [],
      financeVisible: financeAllowed,
      financeError: financeError,
      updatedAt: _clock(),
    );
  }

  Query<Map<String, dynamic>> get _batches => _firestore
      .collection(FirestoreCollections.batches)
      .where('isDeleted', isEqualTo: false);

  Query<Map<String, dynamic>> _range(
    String collection,
    String date,
    DashboardFilter filter,
  ) => _firestore
      .collection(collection)
      .where('isDeleted', isEqualTo: false)
      .where(date, isGreaterThanOrEqualTo: Timestamp.fromDate(filter.start))
      .where(date, isLessThan: Timestamp.fromDate(filter.end));

  Future<int> _count(Query<Map<String, dynamic>> query) async {
    final count = (await query.count().get()).count;
    if (count == null) throw StateError('Agregasi jumlah tidak tersedia.');
    return count;
  }

  Future<List<DashboardCircularFlow>> getRecentCircularFlows({
    int limit = 5,
    DashboardFilter? filter,
  }) async {
    Query<Map<String, dynamic>> query = _firestore.collection(
      FirestoreCollections.circularFlows,
    );
    if (filter != null) {
      query = query
          .where(
            'flowDate',
            isGreaterThanOrEqualTo: Timestamp.fromDate(filter.start),
          )
          .where('flowDate', isLessThan: Timestamp.fromDate(filter.end));
    }
    final snapshot = await query
        .orderBy('flowDate', descending: true)
        .limit(limit)
        .get();
    return [
      for (final doc in snapshot.docs)
        if (doc.data()['sourceType'] == 'manual' &&
            '${doc.data()['createdBy'] ?? ''}'.isNotEmpty &&
            !hasSampleMarker(doc.data()) &&
            doc.data()['isDeleted'] != true)
          if (finiteNumber(doc.data()['quantity']) case final double quantity
              when quantity > 0)
            if (doc.data()['flowDate'] is Timestamp &&
                '${doc.data()['unit'] ?? ''}'.isNotEmpty)
              DashboardCircularFlow(
                sourceModuleType: '${doc.data()['sourceModuleType'] ?? ''}',
                destinationModuleType:
                    '${doc.data()['destinationModuleType'] ?? ''}',
                materialName: '${doc.data()['materialName'] ?? ''}',
                quantity: quantity,
                unit: '${doc.data()['unit']}',
                notes: '${doc.data()['notes'] ?? ''}',
                flowDate: (doc.data()['flowDate'] as Timestamp).toDate(),
              ),
    ];
  }

  Future<FinanceDashboardSummary> getMonthlyFinanceSummary({
    DateTime? startOfMonth,
    DateTime? endOfMonth,
  }) async {
    if (!(profile?.canViewFinanceDashboard ?? false)) {
      throw StateError('Tidak memiliki akses ringkasan keuangan.');
    }
    final now = _clock();
    final period = DashboardFilter(
      start: startOfMonth ?? DateTime(now.year, now.month),
      end: endOfMonth ?? DateTime(now.year, now.month + 1),
    );
    await requireNoSampleData(_firestore, [
      FirestoreCollections.financeTransactions,
    ]);
    final snapshot = await _range(
      FirestoreCollections.financeTransactions,
      'date',
      period,
    ).orderBy('date', descending: true).limit(501).get();
    if (snapshot.docs.length > 500) {
      throw StateError(
        'Lebih dari 500 transaksi. Persempit periode untuk ringkasan akurat.',
      );
    }
    var income = 0.0, expense = 0.0;
    for (final doc in snapshot.docs) {
      final d = doc.data();
      final amount = finiteNumber(d['amount']);
      if (amount == null ||
          amount < 0 ||
          !['income', 'expense'].contains(d['type'])) {
        throw const FormatException('Transaksi keuangan tidak valid.');
      }
      if (d['type'] == 'income') income += amount;
      if (d['type'] == 'expense') expense += amount;
    }
    if (!income.isFinite || !expense.isFinite || !(income - expense).isFinite) {
      throw const FormatException('Nilai keuangan melebihi batas.');
    }
    return FinanceDashboardSummary(income: income, expense: expense);
  }
}

class FinanceDashboardSummary {
  const FinanceDashboardSummary({required this.income, required this.expense});
  final double income, expense;
}

List<DashboardActivity> mergeDashboardActivities(
  List<QueryDocumentSnapshot<Map<String, dynamic>>> logs,
  List<QueryDocumentSnapshot<Map<String, dynamic>>> schedules,
) {
  final result = <DashboardActivity>[];
  final seen = <String>{};
  for (final source in [(logs, 'logbook'), (schedules, 'schedule')]) {
    for (final doc in source.$1) {
      if (!seen.add('${source.$2}/${doc.id}')) continue;
      final d = doc.data();
      final status = source.$2 == 'logbook'
          ? 'recorded'
          : '${d['status'] ?? 'unknown'}';
      final rawDate = source.$2 == 'logbook'
          ? d['activityDate']
          : status == 'done'
          ? d['completedAt'] ?? d['date']
          : status == 'skipped'
          ? d['skippedAt'] ?? d['date']
          : d['date'];
      if (rawDate is! Timestamp) continue;
      final date = rawDate.toDate().toLocal();
      final module = '${d['moduleType'] ?? ''}';
      result.add(
        DashboardActivity(
          id: doc.id,
          source: source.$2,
          moduleType: module,
          status: status,
          batchId: d['batchId'] as String?,
          occurredAt: date,
          time: DateFormat('d/M HH:mm').format(date),
          title:
              '${d['title'] ?? d['activityType'] ?? 'Aktivitas operasional'}',
          icon: moduleIcon(module),
          color: moduleColor(module),
          done: status == 'done',
        ),
      );
    }
  }
  result.sort((a, b) => b.occurredAt!.compareTo(a.occurredAt!));
  return result.take(10).toList();
}

Color moduleColor(String module) => switch (module) {
  'ayam_kampung' => AppColors.warning,
  'maggot_bsf' => AppColors.accentBrown,
  'cacing_tanah' => AppColors.primaryGreen,
  'lele' => AppColors.info,
  'tanaman' => AppColors.success,
  _ => AppColors.primaryGreen,
};
IconData moduleIcon(String module) => switch (module) {
  'ayam_kampung' => Icons.egg_alt_outlined,
  'maggot_bsf' => Icons.bug_report_outlined,
  'cacing_tanah' => Icons.grass_outlined,
  'lele' => Icons.water_drop_outlined,
  'tanaman' => Icons.eco_outlined,
  _ => Icons.edit_note_outlined,
};
