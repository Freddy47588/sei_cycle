import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../core/constants/firestore_collections.dart';
import '../../../theme/app_theme.dart';
import '../../circular_flow/services/circular_flow_service.dart';
import '../models/dashboard_summary.dart';

class DashboardService {
  DashboardService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  Future<DashboardSummary> load({required bool includeFinance}) =>
      getDashboardSummary(includeFinance: includeFinance);

  Future<DashboardSummary> getDashboardSummary({
    required bool includeFinance,
  }) async {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));
    final startOfMonth = DateTime(now.year, now.month);
    final endOfMonth = DateTime(now.year, now.month + 1);

    final results = await Future.wait<Object?>([
      getActiveFarmModules(),
      getTodayLogbooks(startOfDay: startOfDay, endOfDay: endOfDay),
      getTodaySchedules(startOfDay: startOfDay, endOfDay: endOfDay),
      getLowStockInventory(),
      getRecentCircularFlows(),
      includeFinance
          ? getMonthlyFinanceSummary(
              startOfMonth: startOfMonth,
              endOfMonth: endOfMonth,
            )
          : Future.value(null),
    ]);

    final activeModules =
        results[0] as List<QueryDocumentSnapshot<Map<String, dynamic>>>;
    final todayLogbooks =
        results[1] as List<QueryDocumentSnapshot<Map<String, dynamic>>>;
    final todaySchedules =
        results[2] as List<QueryDocumentSnapshot<Map<String, dynamic>>>;
    final lowStockDocs =
        results[3] as List<QueryDocumentSnapshot<Map<String, dynamic>>>;
    final circularFlows = results[4] as List<DashboardCircularFlow>;
    final financeSummary = results[5] as FinanceDashboardSummary?;

    final activities = _activitiesFromFirestore(todayLogbooks, todaySchedules);
    final revenueItems = _revenueItemsFromFinance(financeSummary);

    return DashboardSummary(
      activeModuleCount: activeModules.length,
      todayLogCount: todayLogbooks.length,
      todayScheduleCount: todaySchedules.length,
      lowStockCount: lowStockDocs.length,
      monthlyIncome: financeSummary?.income ?? 0,
      monthlyExpense: financeSummary?.expense ?? 0,
      monthlyProfit:
          (financeSummary?.income ?? 0) - (financeSummary?.expense ?? 0),
      recentActivities: activities,
      revenueItems: revenueItems,
      circularFlows: circularFlows,
      lowStockPreview: [
        for (final document in lowStockDocs.take(5))
          _lowStockItemFromDocument(document),
      ],
      financeVisible: includeFinance && financeSummary != null,
    );
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
  getActiveFarmModules() async {
    try {
      final snapshot = await _firestore
          .collection(FirestoreCollections.farmModules)
          .where('isActive', isEqualTo: true)
          .orderBy('order')
          .get();
      return snapshot.docs;
    } on FirebaseException catch (error) {
      if (!_canFallback(error)) rethrow;
      final snapshot = await _firestore
          .collection(FirestoreCollections.farmModules)
          .where('isActive', isEqualTo: true)
          .get();
      final docs = snapshot.docs;
      docs.sort((a, b) {
        final left = a.data()['order'];
        final right = b.data()['order'];
        return (left is num ? left : 0).compareTo(right is num ? right : 0);
      });
      return docs;
    }
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> getTodayLogbooks({
    DateTime? startOfDay,
    DateTime? endOfDay,
  }) {
    final now = DateTime.now();
    final start = startOfDay ?? DateTime(now.year, now.month, now.day);
    final end = endOfDay ?? start.add(const Duration(days: 1));
    return _dateRangeDocs(
      collection: FirestoreCollections.logbooks,
      field: 'activityDate',
      start: start,
      end: end,
      descending: true,
    );
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> getTodaySchedules({
    DateTime? startOfDay,
    DateTime? endOfDay,
  }) {
    final now = DateTime.now();
    final start = startOfDay ?? DateTime(now.year, now.month, now.day);
    final end = endOfDay ?? start.add(const Duration(days: 1));
    return _dateRangeDocs(
      collection: FirestoreCollections.schedules,
      field: 'date',
      start: start,
      end: end,
    );
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
  getLowStockInventory() async {
    try {
      final snapshot = await _firestore
          .collection(FirestoreCollections.inventory)
          .where('isDeleted', isEqualTo: false)
          .where('isLowStock', isEqualTo: true)
          .orderBy('name')
          .get();
      return snapshot.docs;
    } on FirebaseException catch (error) {
      if (!_canFallback(error)) rethrow;
      final docs = await _activeDocs(FirestoreCollections.inventory);
      final lowStock = docs
          .where((document) => document.data()['isLowStock'] == true)
          .toList();
      lowStock.sort(_compareString('name'));
      return lowStock;
    }
  }

  Future<List<DashboardCircularFlow>> getRecentCircularFlows({
    int limit = 5,
  }) async {
    final flows = await CircularFlowService(
      firestore: _firestore,
    ).getRecentFlows(limit: limit);
    return [
      for (final flow in flows)
        DashboardCircularFlow(
          sourceModuleType: flow.sourceModuleType,
          destinationModuleType: flow.destinationModuleType,
          materialName: flow.materialName,
          quantity: flow.quantity,
          unit: flow.unit,
          notes: flow.notes,
        ),
    ];
  }

  Future<FinanceDashboardSummary?> getMonthlyFinanceSummary({
    DateTime? startOfMonth,
    DateTime? endOfMonth,
  }) async {
    final now = DateTime.now();
    final start = startOfMonth ?? DateTime(now.year, now.month);
    final end = endOfMonth ?? DateTime(now.year, now.month + 1);
    try {
      final snapshot = await _firestore
          .collection(FirestoreCollections.financeTransactions)
          .where('isDeleted', isEqualTo: false)
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
          .where('date', isLessThan: Timestamp.fromDate(end))
          .orderBy('date', descending: true)
          .get();
      return _financeFromDocs(snapshot.docs);
    } on FirebaseException catch (error) {
      if (error.code == 'permission-denied') return null;
      if (!_canFallback(error)) rethrow;
      final docs = await _activeDocs(FirestoreCollections.financeTransactions);
      return _financeFromDocs(
        docs.where((document) {
          final value = document.data()['date'];
          if (value is! Timestamp) return false;
          final date = value.toDate();
          return !date.isBefore(start) && date.isBefore(end);
        }).toList(),
      );
    }
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _dateRangeDocs({
    required String collection,
    required String field,
    required DateTime start,
    required DateTime end,
    bool descending = false,
  }) async {
    try {
      final snapshot = await _firestore
          .collection(collection)
          .where('isDeleted', isEqualTo: false)
          .where(field, isGreaterThanOrEqualTo: Timestamp.fromDate(start))
          .where(field, isLessThan: Timestamp.fromDate(end))
          .orderBy(field, descending: descending)
          .get();
      return snapshot.docs;
    } on FirebaseException catch (error) {
      if (!_canFallback(error)) rethrow;
      final docs = await _activeDocs(collection);
      final filtered = docs.where((document) {
        final value = document.data()[field];
        if (value is! Timestamp) return false;
        final date = value.toDate();
        return !date.isBefore(start) && date.isBefore(end);
      }).toList();
      filtered.sort(_compareTimestamp(field, descending: descending));
      return filtered;
    }
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _activeDocs(
    String collection,
  ) async {
    final snapshot = await _firestore.collection(collection).get();
    return snapshot.docs
        .where((document) => document.data()['isDeleted'] != true)
        .toList();
  }

  List<DashboardActivity> _activitiesFromFirestore(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> logbooks,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> schedules,
  ) {
    final activities = <DashboardActivity>[];
    for (final document in logbooks.take(7)) {
      final data = document.data();
      final date = data['activityDate'];
      activities.add(
        DashboardActivity(
          time: _timeLabel(date),
          title:
              _string(data['title']) ??
              _string(data['activityType']) ??
              'Catatan logbook harian',
          icon: _moduleIcon(_string(data['moduleType'])),
          color: _moduleColor(_string(data['moduleType'])),
          done: true,
        ),
      );
    }
    if (activities.isNotEmpty) return activities;
    for (final document in schedules.take(7)) {
      final data = document.data();
      activities.add(
        DashboardActivity(
          time: _timeLabel(data['date']),
          title: _string(data['title']) ?? 'Jadwal operasional hari ini',
          icon: Icons.event_note_outlined,
          color: AppColors.info,
          done: data['status'] == 'completed',
        ),
      );
    }
    return activities;
  }

  List<RevenueBreakdownItem> _revenueItemsFromFinance(
    FinanceDashboardSummary? summary,
  ) {
    if (summary == null || (summary.income == 0 && summary.expense == 0)) {
      return const [];
    }
    final total = summary.income + summary.expense;
    return [
      RevenueBreakdownItem(
        label: 'Pemasukan',
        amount: summary.income,
        portion: total == 0 ? 0 : summary.income / total,
        color: AppColors.success,
      ),
      RevenueBreakdownItem(
        label: 'Pengeluaran',
        amount: summary.expense,
        portion: total == 0 ? 0 : summary.expense / total,
        color: AppColors.error,
      ),
      RevenueBreakdownItem(
        label: 'Laba Bersih',
        amount: summary.income - summary.expense,
        portion: summary.income == 0
            ? 0
            : ((summary.income - summary.expense).abs() / summary.income).clamp(
                0,
                1,
              ),
        color: summary.income >= summary.expense
            ? AppColors.primaryGreen
            : AppColors.warning,
      ),
    ];
  }

  FinanceDashboardSummary _financeFromDocs(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    var income = 0.0;
    var expense = 0.0;
    for (final document in docs) {
      final data = document.data();
      final amount = (data['amount'] as num?)?.toDouble() ?? 0;
      if (data['type'] == 'income') income += amount;
      if (data['type'] == 'expense') expense += amount;
    }
    return FinanceDashboardSummary(income: income, expense: expense);
  }

  LowStockDashboardItem _lowStockItemFromDocument(
    QueryDocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    return LowStockDashboardItem(
      id: _string(data['id']) ?? document.id,
      name: _string(data['name']) ?? 'Item tanpa nama',
      currentStock: (data['currentStock'] as num?)?.toDouble() ?? 0,
      minStock: (data['minStock'] as num?)?.toDouble() ?? 0,
      unit: _string(data['unit']) ?? '',
    );
  }
}

class FinanceDashboardSummary {
  const FinanceDashboardSummary({required this.income, required this.expense});

  final double income;
  final double expense;
}

bool _canFallback(FirebaseException error) =>
    error.code == 'failed-precondition' ||
    error.code == 'unavailable' ||
    error.code == 'permission-denied';

String? _string(Object? value) =>
    value is String && value.trim().isNotEmpty ? value.trim() : null;

String _timeLabel(Object? value) {
  if (value is! Timestamp) return '--:--';
  final date = value.toDate();
  return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}

int Function(
  QueryDocumentSnapshot<Map<String, dynamic>>,
  QueryDocumentSnapshot<Map<String, dynamic>>,
)
_compareString(String field) {
  return (left, right) {
    final leftValue = _string(left.data()[field]) ?? '';
    final rightValue = _string(right.data()[field]) ?? '';
    return leftValue.compareTo(rightValue);
  };
}

int Function(
  QueryDocumentSnapshot<Map<String, dynamic>>,
  QueryDocumentSnapshot<Map<String, dynamic>>,
)
_compareTimestamp(String field, {bool descending = false}) {
  return (left, right) {
    final leftValue = left.data()[field];
    final rightValue = right.data()[field];
    final leftDate = leftValue is Timestamp
        ? leftValue.toDate()
        : DateTime.fromMillisecondsSinceEpoch(0);
    final rightDate = rightValue is Timestamp
        ? rightValue.toDate()
        : DateTime.fromMillisecondsSinceEpoch(0);
    final comparison = leftDate.compareTo(rightDate);
    return descending ? -comparison : comparison;
  };
}

Color _moduleColor(String? moduleType) => switch (moduleType) {
  'ayam_kampung' => AppColors.warning,
  'maggot_bsf' => AppColors.accentLightGreen,
  'cacing_tanah' => AppColors.primaryGreen,
  'lele' => AppColors.info,
  'tanaman' => AppColors.success,
  _ => AppColors.primaryGreen,
};

IconData _moduleIcon(String? moduleType) => switch (moduleType) {
  'ayam_kampung' => Icons.egg_alt_outlined,
  'maggot_bsf' => Icons.bug_report_outlined,
  'cacing_tanah' => Icons.grass_outlined,
  'lele' => Icons.water_drop_outlined,
  'tanaman' => Icons.eco_outlined,
  _ => Icons.edit_note_outlined,
};
