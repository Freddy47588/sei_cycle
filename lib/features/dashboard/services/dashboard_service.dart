import '../../../core/utils/debug_diagnostics.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/utils/sample_data_guard.dart';
import '../../sales/services/sales_service.dart';
import '../../sales/models/sale.dart';
import '../../finance/services/finance_service.dart';
import '../../../core/utils/legacy_firestore.dart';
import '../../../core/utils/firestore_fields.dart';

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
    final today = DashboardFilter.days(1, now: _clock());
    final period = filter ?? DashboardFilter.days(30, now: _clock());
    final errors = <String, Object>{};
    final cache =
        <String, Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>>{};
    var samplesExcluded = false;
    Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> read(String c) =>
        cache.putIfAbsent(c, () async {
          final all = await completeCollection(_firestore, c);
          samplesExcluded |= all.any(
            (d) => isSeedOrigin(legacyFields(d.data())),
          );
          final real = all.where((d) => isOperationalRecord(d.data())).toList();
          for (final doc in real) {
            requireReviewedProvenance(doc.data());
          }
          return real;
        });
    Future<T?> section<T>(String name, Future<T> Function() body) async {
      try {
        return await diagnoseLoad('DashboardService', name, body);
      } catch (error) {
        errors[name] = error;
        return null;
      }
    }

    bool inPeriod(Map<String, dynamic> d, String key, DashboardFilter f) {
      if (d[key] is! Timestamp) {
        throw const FormatException('Tanggal aktivitas tidak valid.');
      }
      return f.contains((d[key] as Timestamp).toDate());
    }

    final financeAllowed =
        includeFinance && (profile?.canViewFinanceDashboard ?? false);
    final result = await Future.wait<Object?>([
      section('modules', () async {
        final docs = await read('farm_modules');
        // Production contains two ID conventions for each of the five modules.
        return docs
            .where((d) => legacyFields(d.data())['isActive'] == true)
            .map(
              (d) => canonicalModuleId(
                stringField(d.data(), ['module_id'], fallback: d.id),
              ),
            )
            .toSet()
            .length;
      }),
      section('logs', () async {
        final docs = (await read('logbooks'))
            .where(
              (d) => inPeriod(legacyFields(d.data()), 'activityDate', today),
            )
            .toList();
        await OperationalIntegrity(_firestore).check(docs);
        return docs
            .where(
              (d) => inPeriod(legacyFields(d.data()), 'activityDate', today),
            )
            .length;
      }),
      section('schedules', () async {
        final docs = (await read('schedules'))
            .where((d) => inPeriod(legacyFields(d.data()), 'date', today))
            .toList();
        await OperationalIntegrity(_firestore).check(docs);
        return [
          docs.length,
          for (final status in ['pending', 'done', 'skipped'])
            docs.where((d) => d.data()['status'] == status).length,
        ];
      }),
      section('batches', () async {
        final docs = await read('batches');
        await OperationalIntegrity(_firestore).check(docs);
        return [
          for (final status in ['active', 'completed'])
            docs.where((d) => d.data()['status'] == status).length,
        ];
      }),
      section('inventory', () async {
        final docs = await read('inventory');
        // Non-seed ledger activity against seed masters must block stock KPIs.
        final ledger = await read('inventory_transactions');
        await OperationalIntegrity(_firestore).check(ledger);
        final legacy = await read('inventory_items');
        final all = [...docs, ...legacy];
        final ids = <String>{};
        return [
          for (final doc in all)
            () {
              if (!ids.add(doc.id)) {
                throw StateError(
                  'Belum dapat dihitung: identitas inventory legacy ambigu.',
                );
              }
              final d = legacyFields(doc.data());
              final stock = finiteNumber(d['currentStock']),
                  minimum = finiteNumber(d['minStock']);
              if (stock == null || minimum == null || minimum < 0) {
                throw const FormatException(
                  'Saldo atau minimum stok tidak valid.',
                );
              }
              return LowStockDashboardItem(
                id: doc.id,
                name: stringField(d, ['name']),
                currentStock: stock,
                minStock: minimum,
                unit: stringField(d, ['unit']),
              );
            }(),
        ];
      }),
      section(
        'activities',
        () async => mergeDashboardActivities(
          await read('logbooks'),
          await read('schedules'),
        ),
      ),
      section('flows', () => getRecentCircularFlows(filter: period)),
      financeAllowed
          ? section(
              'finance',
              () => getMonthlyFinanceSummary(
                startOfMonth: period.start,
                endOfMonth: period.end,
              ),
            )
          : Future.value(null),
      financeAllowed
          ? section(
              'sales',
              () => SalesService(
                firestore: _firestore,
              ).summary(period.start, period.end),
            )
          : Future.value(null),
    ]);
    final schedules = result[2] as List<int>?;
    final batches = result[3] as List<int>?;
    final stock = result[4] as List<LowStockDashboardItem>?;
    final low = stock
        ?.where((i) => i.currentStock > 0 && i.currentStock <= i.minStock)
        .toList();
    final empty = stock?.where((i) => i.currentStock <= 0).toList();
    final finance = result[7] as FinanceDashboardSummary?;
    final sales = result[8] as List<Sale>?;
    final quantities = <String, double>{};
    for (final sale in sales ?? <Sale>[]) {
      final key = '${sale.productName} (${sale.unit})';
      quantities[key] = (quantities[key] ?? 0) + sale.quantity;
    }
    return DashboardSummary(
      sectionErrors: errors,
      samplesExcluded: samplesExcluded,
      activeModuleCount: result[0] as int?,
      todayLogCount: result[1] as int?,
      todayScheduleCount: schedules?[0],
      pendingScheduleCount: schedules?[1],
      doneScheduleCount: schedules?[2],
      skippedScheduleCount: schedules?[3],
      activeBatchCount: batches?[0],
      completedBatchCount: batches?[1],
      lowStockCount: low?.length,
      outOfStockCount: empty?.length,
      inventoryLoaded: stock?.length ?? 0,
      lowStockPreview: [...?empty, ...?low].take(5).toList(),
      monthlyIncome: finance?.income,
      monthlyExpense: finance?.expense,
      monthlyProfit: finance == null ? null : finance.income - finance.expense,
      financeVisible: financeAllowed,
      financeError: errors['finance'],
      revenueItems: const [],
      recentActivities: result[5] as List<DashboardActivity>? ?? [],
      circularFlows: result[6] as List<DashboardCircularFlow>? ?? [],
      salesTotal: sales?.fold<int>(0, (v, s) => v + s.totalAmount),
      soldQuantities: quantities,
      salesError: errors['sales'],
      updatedAt: _clock(),
    );
  }

  Future<List<DashboardCircularFlow>> getRecentCircularFlows({
    int limit = 5,
    DashboardFilter? filter,
  }) async {
    if (limit < 1 || limit > 500) throw ArgumentError.value(limit, 'limit');
    final docs =
        (await operationalCollection(_firestore, 'circular_flows')).where((
          doc,
        ) {
          final d = doc.data();
          return d['sourceType'] == 'manual' &&
              d['flowDate'] is Timestamp &&
              (filter == null ||
                  filter.contains((d['flowDate'] as Timestamp).toDate()));
        }).toList()..sort(
          (a, b) => (b.data()['flowDate'] as Timestamp).compareTo(
            a.data()['flowDate'] as Timestamp,
          ),
        );
    await OperationalIntegrity(_firestore).check(docs);
    return docs.take(limit).map((doc) {
      final d = doc.data();
      final quantity = finiteNumber(d['quantity']);
      if (quantity == null ||
          quantity <= 0 ||
          stringField(d, ['unit']).isEmpty) {
        throw const FormatException('Aliran operasional tidak valid.');
      }
      return DashboardCircularFlow(
        sourceModuleType: stringField(d, ['sourceModuleType']),
        destinationModuleType: stringField(d, ['destinationModuleType']),
        materialName: stringField(d, ['materialName']),
        quantity: quantity,
        unit: stringField(d, ['unit']),
        notes: stringField(d, ['notes']),
        flowDate: (d['flowDate'] as Timestamp).toDate(),
      );
    }).toList();
  }

  Future<FinanceDashboardSummary> getMonthlyFinanceSummary({
    DateTime? startOfMonth,
    DateTime? endOfMonth,
  }) async {
    if (!(profile?.canViewFinanceDashboard ?? false)) {
      throw StateError('Tidak memiliki akses ringkasan keuangan.');
    }
    final now = _clock();
    final summary = await FinanceService(firestore: _firestore)
        .loadSummaryByDateRange(
          start: startOfMonth ?? DateTime(now.year, now.month),
          end: endOfMonth ?? DateTime(now.year, now.month + 1),
        );
    return FinanceDashboardSummary(
      income: summary.totalIncome,
      expense: summary.totalExpense,
    );
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
      final d = legacyFields(doc.data());
      if (!isOperationalRecord(d)) continue;
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
          batchId: d['batchId'] is String ? d['batchId'] as String : null,
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
