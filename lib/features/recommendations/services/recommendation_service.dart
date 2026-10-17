import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/utils/legacy_firestore.dart';
import '../../../core/constants/farm_modules.dart';
import '../../finance/services/finance_service.dart';
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
    final sources = await Future.wait([
      for (final collection in [
        'logbooks',
        'inventory',
        'schedules',
        'batches',
        'production_results',
        'circular_flows',
      ])
        operationalCollection(_firestore, collection),
    ]);
    await OperationalIntegrity(
      _firestore,
    ).check([...sources[0], ...sources[4], ...sources[5]]);
    final finance = includeFinance
        ? (await FinanceService(firestore: _firestore).loadSummaryByDateRange(
            start: DateTime(anchor.year, anchor.month),
            end: DateTime(anchor.year, anchor.month + 1),
          )).transactions
        : <FinanceRecord>[];
    return generateFromData(
      logbooks: sources[0].map(LogbookEntry.fromDocument).toList(),
      lowStockItems: sources[1].map(InventoryItem.fromDocument).toList(),
      overdueSchedules: sources[2].map(ScheduleItem.fromDocument).toList(),
      financeRecords: finance,
      includeFinance: includeFinance,
      now: anchor,
      inventoryAvailable: sources[1].isNotEmpty,
      batches: sources[3].map((d) => {...d.data(), 'id': d.id}).toList(),
      production: sources[4].map((d) => {...d.data(), 'id': d.id}).toList(),
      flows: sources[5].map((d) => {...d.data(), 'id': d.id}).toList(),
    );
  }

  static List<RecommendationModel> generateFromData({
    required List<LogbookEntry> logbooks,
    required List<InventoryItem> lowStockItems,
    required List<ScheduleItem> overdueSchedules,
    required List<FinanceRecord> financeRecords,
    required bool includeFinance,
    DateTime? now,
    bool? inventoryAvailable,
    List<Map<String, dynamic>> batches = const [],
    List<Map<String, dynamic>> production = const [],
    List<Map<String, dynamic>> flows = const [],
  }) {
    final anchor = now ?? DateTime.now();
    final result = <RecommendationModel>[];
    void add(
      String id,
      String title,
      String reason,
      String type,
      String priority,
      String action, {
      String? module,
      String? collection,
      String? sourceId,
      DateTime? sourceDate,
    }) {
      result.add(
        RecommendationModel(
          id: id,
          title: title,
          description: reason,
          type: type,
          priority: priority,
          recommendedAction: action,
          moduleType: module,
          sourceCollection: collection,
          sourceId: sourceId,
          sourceDate: sourceDate,
          createdAt: anchor,
          isResolved: false,
        ),
      );
    }

    final validItems = lowStockItems.where(
      (i) =>
          !i.isDeleted &&
          i.createdBy != 'sample_seed' &&
          !i.legacyReadOnly &&
          !i.requiresProvenanceReview &&
          i.currentStock.isFinite &&
          i.minStock.isFinite,
    );
    for (final item in validItems.where((i) => i.currentStock <= i.minStock)) {
      add(
        'rec_stock_${item.id}',
        'Restock ${item.name}',
        'Stok tercatat ${item.currentStock} ${item.unit}; minimum ${item.minStock} ${item.unit}.',
        'inventory',
        item.currentStock <= 0 ? 'high' : 'medium',
        'Periksa stok fisik lalu rencanakan pengadaan.',
        module: item.moduleType.isEmpty ? null : item.moduleType,
        collection: 'inventory',
        sourceId: item.id,
      );
    }
    if (inventoryAvailable == false) {
      add(
        'rec_inventory_missing',
        'Data inventaris belum tersedia',
        'Tidak ada master inventaris aktif yang terverifikasi. Ledger historis tidak digunakan sebagai stok fisik.',
        'inventory',
        'low',
        'Catat master dan hasil pengamatan stok fisik yang sah.',
      );
    }
    for (final schedule in overdueSchedules.where(
      (s) =>
          !s.isDeleted && s.createdBy != 'sample_seed' && s.status == 'pending',
    )) {
      final overdue = schedule.scheduledAt.isBefore(anchor);
      if (!overdue && schedule.scheduledAt.difference(anchor).inDays > 7) {
        continue;
      }
      add(
        'rec_schedule_${schedule.id}',
        overdue ? 'Selesaikan jadwal terlambat' : 'Siapkan kegiatan mendatang',
        '${schedule.title} dijadwalkan ${schedule.scheduledAt.toIso8601String()} dan masih pending.',
        'schedule',
        overdue ? 'high' : 'medium',
        'Buka Jadwal, kerjakan atau jadwalkan ulang sesuai keadaan.',
        module: schedule.moduleId,
        collection: 'schedules',
        sourceId: schedule.id,
        sourceDate: schedule.scheduledAt,
      );
    }
    final validLogs = logbooks
        .where(
          (l) =>
              !l.isDeleted &&
              l.createdBy != 'sample_seed' &&
              !l.activityDate.isAfter(anchor),
        )
        .toList();
    for (final module in FarmModules.values) {
      final logs = validLogs.where((l) => l.moduleId == module.id).toList()
        ..sort((a, b) => b.activityDate.compareTo(a.activityDate));
      if (logs.isNotEmpty &&
          anchor.difference(logs.first.activityDate).inDays >= 4) {
        add(
          'rec_logbook_gap_${module.id}',
          'Update logbook ${module.name}',
          'Catatan terakhir ${anchor.difference(logs.first.activityDate).inDays} hari lalu.',
          'logbook',
          'medium',
          'Catat pengamatan terbaru sesuai rutinitas batch.',
          module: module.id,
          collection: 'logbooks',
          sourceId: logs.first.id,
          sourceDate: logs.first.activityDate,
        );
      }
    }
    for (final batch in batches.where(isOperationalRecord)) {
      if (batch['status'] != 'active') continue;
      final module = batch['moduleType'] as String?;
      final id = batch['id']?.toString();
      if (id == null || !FarmModules.values.any((m) => m.id == module)) {
        continue;
      }
      final expected = batch['expectedHarvestAt'];
      final date = expected is Timestamp
          ? expected.toDate()
          : expected is DateTime
          ? expected
          : null;
      if (date != null && date.difference(anchor).inDays <= 7) {
        add(
          'rec_batch_harvest_$id',
          'Tinjau rencana panen ${batch['name'] ?? id}',
          'Tanggal rencana panen yang dicatat: ${date.toIso8601String()}. Ini rencana, bukan hasil aktual.',
          'harvest_prediction',
          'medium',
          'Periksa kesiapan panen dan catat hasil aktual setelah panen.',
          module: module,
          collection: 'batches',
          sourceId: id,
          sourceDate: date,
        );
      } else {
        add(
          'rec_batch_followup_$id',
          'Tindak lanjut batch ${batch['name'] ?? id}',
          'Batch berstatus aktif${date == null ? '; tanggal panen belum dicatat' : ''}.',
          'batch',
          'low',
          'Tinjau jadwal dan pengamatan batch.',
          module: module,
          collection: 'batches',
          sourceId: id,
        );
      }
    }
    // Trend comparisons are restricted to the same module, product and unit.
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final p in production.where(isOperationalRecord)) {
      if (p['quantity'] is! num ||
          !(p['quantity'] as num).isFinite ||
          p['harvestDate'] is! Timestamp ||
          (p['harvestDate'] as Timestamp).toDate().isAfter(anchor) ||
          p['unit'] is! String ||
          p['moduleType'] is! String) {
        continue;
      }
      groups
          .putIfAbsent(
            '${p['moduleType']}_${p['productName']}_${p['unit']}',
            () => [],
          )
          .add(p);
    }
    for (final entries in groups.values) {
      entries.sort(
        (a, b) => (b['harvestDate'] as Timestamp).compareTo(
          a['harvestDate'] as Timestamp,
        ),
      );
      if (entries.length < 2) continue;
      final last = entries[0], previous = entries[1];
      add(
        'rec_production_${last['id']}',
        'Tinjau hasil aktual ${last['productName']}',
        'Dua pencatatan terakhir: ${last['quantity']} dan ${previous['quantity']} ${last['unit']}. Volume belum dinormalisasi terhadap luas, populasi, atau durasi.',
        'production',
        'low',
        'Bandingkan konteks dua panen sebelum mengambil keputusan.',
        module: last['moduleType'] as String,
        collection: 'production_results',
        sourceId: '${last['id']}',
      );
    }
    if (includeFinance) {
      final cash = financeRecords.where(
        (f) =>
            !f.isDeleted &&
            f.createdBy != 'sample_seed' &&
            f.date.year == anchor.year &&
            f.date.month == anchor.month &&
            f.amount.isFinite,
      );
      final income = cash
          .where((f) => f.type == 'income')
          .fold<double>(0, (t, f) => t + f.amount);
      final expense = cash
          .where((f) => f.type == 'expense')
          .fold<double>(0, (t, f) => t + f.amount);
      if (expense > income) {
        add(
          'rec_finance_${anchor.year}_${anchor.month}',
          'Evaluasi biaya operasional bulan ini',
          'Pemasukan tercatat Rp $income, pengeluaran Rp $expense pada bulan berjalan.',
          'finance',
          'medium',
          'Tinjau rincian pengeluaran dan kelengkapan pencatatan.',
          collection: 'finance_transactions',
        );
      }
    }
    for (final flow in flows.where(isOperationalRecord).take(3)) {
      if (flow['id'] == null ||
          flow['quantity'] is! num ||
          (flow['quantity'] as num) <= 0) {
        continue;
      }
      add(
        'rec_flow_${flow['id']}',
        'Tinjau pemanfaatan ${flow['materialName'] ?? 'bahan'}',
        'Aliran aktual tercatat ${flow['quantity']} ${flow['unit'] ?? ''}. Pencatatan ini tidak otomatis mengubah stok.',
        'circular_flow',
        'low',
        'Periksa manfaat dan kebutuhan kegiatan berikutnya sebelum mencatat aliran baru.',
        collection: 'circular_flows',
        sourceId: '${flow['id']}',
      );
    }
    if (result.isEmpty) {
      add(
        'rec_insufficient',
        'Data belum cukup untuk menghasilkan rekomendasi yang akurat.',
        'Belum ada sinyal yang didukung sumber operasional terverifikasi.',
        'insight',
        'low',
        'Lengkapi pengamatan, master inventaris, dan jadwal sesuai kegiatan nyata.',
      );
    }
    const rank = {'high': 3, 'medium': 2, 'low': 1};
    result.sort(
      (a, b) => (rank[b.priority] ?? 0).compareTo(rank[a.priority] ?? 0),
    );
    return List.unmodifiable(result);
  }
}
