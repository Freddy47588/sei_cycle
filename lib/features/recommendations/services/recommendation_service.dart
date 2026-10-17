import '../../../core/constants/firestore_collections.dart';
import '../../../core/utils/legacy_firestore.dart';
import '../../finance/services/finance_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/farm_modules.dart';
import '../../finance/models/finance_record.dart';
import '../../inventory/models/inventory_item.dart';
import '../../logbook/models/logbook_entry.dart';
import '../../schedule/models/schedule_item.dart';
import '../models/recommendation_model.dart';

class RecommendationService {
  RecommendationService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  Future<List<RecommendationModel>> generate({
    required bool includeFinance,
    DateTime? now,
  }) async {
    final anchor = now ?? DateTime.now();
    final today = DateTime(anchor.year, anchor.month, anchor.day);
    final logbookStart = today.subtract(const Duration(days: 45));
    final monthStart = DateTime(today.year, today.month);
    final nextMonth = DateTime(today.year, today.month + 1);

    final sources = await Future.wait([
      operationalCollection(_firestore, 'logbooks'),
      operationalCollection(_firestore, 'inventory'),
      operationalCollection(_firestore, 'inventory_items'),
      operationalCollection(_firestore, 'schedules'),
      operationalCollection(_firestore, 'inventory_transactions'),
    ]);
    await OperationalIntegrity(
      _firestore,
    ).check([...sources[0], ...sources[4]]);
    final cash = includeFinance
        ? (await FinanceService(firestore: _firestore).loadSummaryByDateRange(
            start: monthStart,
            end: nextMonth,
          )).transactions
        : <FinanceRecord>[];
    return generateFromData(
      logbooks: sources[0]
          .map(LogbookEntry.fromDocument)
          .where(
            (e) =>
                !e.activityDate.isBefore(logbookStart) &&
                !e.activityDate.isAfter(anchor),
          )
          .toList(),
      lowStockItems: [
        ...sources[1],
        ...sources[2],
      ].map(InventoryItem.fromDocument).where((i) => i.isLowStock).toList(),
      overdueSchedules: sources[3]
          .map(ScheduleItem.fromDocument)
          .where((s) => s.status == 'pending' && s.scheduledAt.isBefore(today))
          .toList(),
      financeRecords: cash,
      includeFinance: includeFinance,
      now: anchor,
    );
  }

  static List<RecommendationModel> generateFromData({
    required List<LogbookEntry> logbooks,
    required List<InventoryItem> lowStockItems,
    required List<ScheduleItem> overdueSchedules,
    required List<FinanceRecord> financeRecords,
    required bool includeFinance,
    DateTime? now,
  }) {
    final anchor = now ?? DateTime.now();
    final recommendations = <RecommendationModel>[
      ..._stockRecommendations(lowStockItems, anchor),
      ..._scheduleRecommendations(overdueSchedules, anchor),
      ..._moduleRecommendations(logbooks, anchor),
      if (includeFinance) ..._financeRecommendations(financeRecords, anchor),
    ];

    if (recommendations.isEmpty) {
      recommendations.add(
        _recommendation(
          id: 'rec_overview_normal_${_dayKey(anchor)}',
          title: 'Operasional terlihat stabil',
          description:
              'Belum ada sinyal stok rendah, jadwal terlambat, atau arus kas negatif dari data terbaru.',
          type: 'productivity',
          priority: 'low',
          createdAt: anchor,
        ),
      );
    }

    recommendations.sort(_compareRecommendation);
    return List.unmodifiable(recommendations.take(12));
  }

  static List<RecommendationModel> _stockRecommendations(
    List<InventoryItem> items,
    DateTime now,
  ) {
    return [
      for (final item in items)
        _recommendation(
          id: 'rec_stock_${item.id}',
          title: 'Restock ${item.name}',
          description:
              'Stok ${_number(item.currentStock)} ${item.unit} sudah berada di bawah minimum ${_number(item.minStock)} ${item.unit}. Prioritaskan pembelian atau pemindahan stok.',
          type: 'inventory',
          priority: 'high',
          sourceCollection: FirestoreCollections.inventory,
          sourceId: item.id,
          createdAt: now,
          validUntil: now.add(const Duration(days: 7)),
        ),
    ];
  }

  static List<RecommendationModel> _scheduleRecommendations(
    List<ScheduleItem> schedules,
    DateTime now,
  ) {
    return [
      for (final schedule in schedules)
        _recommendation(
          id: 'rec_schedule_${schedule.id}',
          title: 'Selesaikan jadwal terlambat',
          description:
              '${schedule.title} untuk ${FarmModules.nameOf(schedule.moduleId)} melewati tanggal rencana. Tandai selesai atau jadwalkan ulang setelah pekerjaan dilakukan.',
          type: 'schedule',
          priority: 'high',
          moduleType: schedule.moduleId,
          sourceCollection: FirestoreCollections.schedules,
          sourceId: schedule.id,
          createdAt: now,
          validUntil: now.add(const Duration(days: 3)),
        ),
    ];
  }

  static List<RecommendationModel> _moduleRecommendations(
    List<LogbookEntry> logbooks,
    DateTime now,
  ) {
    final byModule = <String, List<LogbookEntry>>{
      for (final module in FarmModules.values) module.id: [],
    };
    for (final logbook in logbooks) {
      byModule.putIfAbsent(logbook.moduleId, () => []).add(logbook);
    }

    final recommendations = <RecommendationModel>[];
    for (final module in FarmModules.values) {
      final moduleLogs = [...(byModule[module.id] ?? const <LogbookEntry>[])]
        ..sort((a, b) => b.activityDate.compareTo(a.activityDate));

      recommendations.add(
        _productivityRecommendation(module.id, moduleLogs, now),
      );
      recommendations.add(_harvestRecommendation(module.id, moduleLogs, now));

      if (moduleLogs.isEmpty) continue;
      final lastLog = moduleLogs.first;
      if (now.difference(lastLog.activityDate).inDays >= 4) {
        recommendations.add(
          _recommendation(
            id: 'rec_logbook_gap_${module.id}',
            title: 'Update logbook ${module.name}',
            description:
                'Belum ada catatan ${module.name} selama ${now.difference(lastLog.activityDate).inDays} hari. Tambahkan logbook terbaru agar rekomendasi lebih akurat.',
            type: 'logbook',
            priority: 'normal',
            moduleType: module.id,
            sourceCollection: FirestoreCollections.logbooks,
            sourceId: lastLog.id,
            createdAt: now,
            validUntil: now.add(const Duration(days: 2)),
          ),
        );
      }
    }
    return recommendations;
  }

  static RecommendationModel _productivityRecommendation(
    String moduleType,
    List<LogbookEntry> logs,
    DateTime now,
  ) {
    final recentLogs = logs
        .where((log) => now.difference(log.activityDate).inDays <= 14)
        .toList();
    if (recentLogs.length < 3) {
      return _recommendation(
        id: 'rec_productivity_data_${moduleType}_${_dayKey(now)}',
        title:
            'Data produktivitas ${FarmModules.nameOf(moduleType)} belum cukup',
        description:
            'Butuh minimal 3 catatan logbook dalam 14 hari untuk menilai aktivitas, panen, pakan, mortalitas, atau pertumbuhan.',
        type: 'productivity',
        priority: 'low',
        moduleType: moduleType,
        createdAt: now,
        validUntil: now.add(const Duration(days: 7)),
      );
    }

    final harvest = _sumByKeywords(recentLogs, _harvestKeywords);
    final mortality = _sumByKeywords(recentLogs, _mortalityKeywords);
    final feeding = _sumByKeywords(recentLogs, _feedKeywords);
    final growth = _sumByKeywords(recentLogs, _growthKeywords);

    var score = 45 + (recentLogs.length * 4);
    if (harvest > 0) score += 18;
    if (feeding > 0) score += 10;
    if (growth > 0) score += 10;
    if (mortality > 0) score -= mortality >= 5 ? 25 : 12;
    score = score.clamp(0, 100);

    final category = score >= 75
        ? 'baik'
        : score >= 50
        ? 'normal'
        : 'rendah';
    final priority = score < 50 || mortality > 0 ? 'normal' : 'low';
    final detail = [
      '${recentLogs.length} aktivitas',
      if (harvest > 0) 'panen ${_number(harvest)}',
      if (feeding > 0) 'pakan ${_number(feeding)}',
      if (growth > 0) 'pertumbuhan ${_number(growth)}',
      if (mortality > 0) 'mortalitas ${_number(mortality)}',
    ].join(', ');

    return _recommendation(
      id: 'rec_productivity_${moduleType}_${_dayKey(now)}',
      title:
          'Produktivitas ${FarmModules.nameOf(moduleType)} $category ($score/100)',
      description:
          'Evaluasi rule-based dari 14 hari terakhir: $detail. Gunakan skor ini sebagai sinyal awal, bukan pengganti observasi lapangan.',
      type: 'productivity',
      priority: priority,
      moduleType: moduleType,
      createdAt: now,
      validUntil: now.add(const Duration(days: 7)),
    );
  }

  static RecommendationModel _harvestRecommendation(
    String moduleType,
    List<LogbookEntry> logs,
    DateTime now,
  ) {
    LogbookEntry? startLog;
    for (final log in logs) {
      if (_containsAny(log, _startKeywords)) {
        startLog = log;
        break;
      }
    }
    final lastLog = logs.isEmpty ? null : logs.first;

    if (startLog == null || lastLog == null) {
      return _recommendation(
        id: 'rec_harvest_data_${moduleType}_${_dayKey(now)}',
        title:
            'Data prediksi panen ${FarmModules.nameOf(moduleType)} belum cukup',
        description:
            'Tambahkan catatan tebar/tanam/semai dan logbook berkala agar estimasi panen bisa dihitung.',
        type: 'harvest_prediction',
        priority: 'low',
        moduleType: moduleType,
        createdAt: now,
        validUntil: now.add(const Duration(days: 7)),
      );
    }

    final productionAge = _productionAgeDays[moduleType] ?? 60;
    final ageDays = now.difference(startLog.activityDate).inDays;
    final estimatedHarvestDate = startLog.activityDate.add(
      Duration(days: productionAge),
    );
    final daysToHarvest = estimatedHarvestDate.difference(now).inDays;
    final lastLogAge = now.difference(lastLog.activityDate).inDays;

    if (lastLogAge > 7) {
      return _recommendation(
        id: 'rec_harvest_stale_${moduleType}_${_dayKey(now)}',
        title: 'Perbarui data sebelum prediksi panen',
        description:
            'Tanggal awal produksi tersedia, tetapi logbook terakhir $lastLogAge hari lalu. Update kondisi terbaru agar estimasi ${FarmModules.nameOf(moduleType)} lebih masuk akal.',
        type: 'harvest_prediction',
        priority: 'normal',
        moduleType: moduleType,
        sourceCollection: FirestoreCollections.logbooks,
        sourceId: lastLog.id,
        createdAt: now,
        validUntil: now.add(const Duration(days: 3)),
      );
    }

    if (daysToHarvest <= 7) {
      return _recommendation(
        id: 'rec_harvest_prepare_${moduleType}_${_dayKey(now)}',
        title: 'Persiapan panen ${FarmModules.nameOf(moduleType)}',
        description:
            'Umur produksi sekitar $ageDays hari dari catatan ${startLog.activityType}. Estimasi panen ${daysToHarvest <= 0 ? 'sudah masuk periode panen' : 'sekitar $daysToHarvest hari lagi'}. Siapkan alat, tenaga, dan pencatatan hasil.',
        type: 'harvest_prediction',
        priority: 'high',
        moduleType: moduleType,
        sourceCollection: FirestoreCollections.logbooks,
        sourceId: startLog.id,
        createdAt: now,
        validUntil: now.add(const Duration(days: 7)),
      );
    }

    return _recommendation(
      id: 'rec_harvest_eta_${moduleType}_${_dayKey(now)}',
      title: 'Estimasi panen ${FarmModules.nameOf(moduleType)}',
      description:
          'Berdasarkan catatan ${startLog.activityType}, umur produksi sekitar $ageDays/$productionAge hari. Perkiraan panen masih sekitar $daysToHarvest hari lagi.',
      type: 'harvest_prediction',
      priority: 'low',
      moduleType: moduleType,
      sourceCollection: FirestoreCollections.logbooks,
      sourceId: startLog.id,
      createdAt: now,
      validUntil: now.add(const Duration(days: 7)),
    );
  }

  static List<RecommendationModel> _financeRecommendations(
    List<FinanceRecord> records,
    DateTime now,
  ) {
    final income = records
        .where((record) => record.type == 'income')
        .fold<double>(0, (total, record) => total + record.amount);
    final expense = records
        .where((record) => record.type == 'expense')
        .fold<double>(0, (total, record) => total + record.amount);
    if (expense <= income || records.isEmpty) return const [];

    return [
      _recommendation(
        id: 'rec_finance_negative_${now.year}_${now.month}',
        title: 'Evaluasi biaya operasional bulan ini',
        description:
            'Pengeluaran bulan ini (${_currency(expense)}) lebih besar dari pemasukan (${_currency(income)}). Tinjau komponen biaya terbesar dan jadwalkan pemasukan panen bila memungkinkan.',
        type: 'finance',
        priority: 'high',
        sourceCollection: FirestoreCollections.financeTransactions,
        createdAt: now,
        validUntil: DateTime(now.year, now.month + 1),
      ),
    ];
  }

  static RecommendationModel _recommendation({
    required String id,
    required String title,
    required String description,
    required String type,
    required String priority,
    required DateTime createdAt,
    String? moduleType,
    String? sourceCollection,
    String? sourceId,
    DateTime? validUntil,
  }) {
    return RecommendationModel(
      id: id,
      title: title,
      description: description,
      type: type,
      priority: priority,
      moduleType: moduleType,
      sourceCollection: sourceCollection,
      sourceId: sourceId,
      createdAt: createdAt,
      validUntil: validUntil,
      isResolved: false,
    );
  }

  static bool _containsAny(LogbookEntry log, List<String> keywords) {
    final text = '${log.activityType} ${log.note} ${log.unit}'.toLowerCase();
    return keywords.any(text.contains);
  }

  static double _sumByKeywords(List<LogbookEntry> logs, List<String> keywords) {
    return logs
        .where((log) => _containsAny(log, keywords))
        .fold<double>(0, (total, log) => total + log.quantity);
  }

  static int _compareRecommendation(
    RecommendationModel a,
    RecommendationModel b,
  ) {
    final priorityCompare = _priorityRank(
      b.priority,
    ).compareTo(_priorityRank(a.priority));
    if (priorityCompare != 0) return priorityCompare;
    return a.title.compareTo(b.title);
  }

  static int _priorityRank(String priority) => switch (priority) {
    'high' => 3,
    'normal' => 2,
    'low' => 1,
    _ => 0,
  };

  static String _dayKey(DateTime date) =>
      '${date.year}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}';

  static String _number(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1);

  static String _currency(double value) => 'Rp ${_number(value)}';
}

const _productionAgeDays = {
  'ayam_kampung': 150,
  'maggot_bsf': 15,
  'cacing_tanah': 60,
  'lele': 90,
  'tanaman': 60,
};

const _startKeywords = ['tebar', 'tanam', 'semai', 'bibit', 'benih', 'starter'];
const _harvestKeywords = ['panen', 'hasil', 'produksi'];
const _mortalityKeywords = ['mati', 'mortalitas', 'kematian'];
const _feedKeywords = ['pakan', 'feed', 'makan'];
const _growthKeywords = ['bobot', 'berat', 'panjang', 'tinggi', 'tumbuh'];
