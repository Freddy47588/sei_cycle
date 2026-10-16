import 'package:cloud_firestore/cloud_firestore.dart';
import 'dashboard_numbers.dart';
import 'dashboard_filter.dart';

class AnalyticsDocument {
  const AnalyticsDocument(this.id, this.data);
  final String id;
  final Map<String, dynamic> data;
}

class ProductivityPoint {
  const ProductivityPoint(this.date, this.value);
  final DateTime date;
  final double value;
}

class ProductivitySeries {
  const ProductivitySeries({
    required this.label,
    required this.unit,
    required this.points,
    this.additive = false,
  });
  final String label, unit;
  final List<ProductivityPoint> points;
  final bool additive;
  double get summary =>
      additive ? points.fold(0.0, (a, b) => a + b.value) : points.last.value;
}

class ProductivityReport {
  const ProductivityReport({
    this.series = const [],
    this.production = const {},
    this.logCount = 0,
    this.logsTruncated = false,
    this.productionUncertain = false,
    this.lastActivity,
  });
  final List<ProductivitySeries> series;
  final Map<String, double> production;
  final int logCount;
  final bool logsTruncated, productionUncertain;
  final DateTime? lastActivity;
}

// Labels follow logbook_form_spec.dart, including legacy keys with different meanings.
const _metrics = <String, List<(String, String, String, bool)>>{
  'ayam_kampung': [
    ('produksi_telur_hari_ini', 'Telur tercatat', 'butir', true),
    ('populasi_aktif', 'Populasi terbaru', 'ekor', false),
    ('mortalitas_hari_ini', 'Mortalitas tercatat', 'ekor', true),
    ('berat_rata_rata_telur', 'Berat rata-rata telur', 'g', false),
    ('konsumsi_pakan_g_per_ekor', 'Konsumsi pakan per ekor', 'g/ekor', false),
  ],
  'maggot_bsf': [
    ('volume_limbah_masuk_kg', 'Input limbah', 'kg', true),
    ('fase_larva_hari', 'Fase larva terbaru', 'hari', false),
    ('estimasi_panen_kg', 'Estimasi panen (bukan aktual)', 'kg', false),
    ('target_panen_larva_kg', 'Target panen (bukan aktual)', 'kg', false),
  ],
  'cacing_tanah': [
    ('kelembapan_media_persen', 'Kelembapan media', '%', false),
    ('pakan_organik_kg', 'Pemakaian pakan organik', 'kg', true),
  ],
  'tanaman': [
    ('tinggi_tanaman_cm', 'Tinggi tanaman', 'cm', false),
    ('jumlah_daun', 'Jumlah daun', 'lembar', false),
  ],
  'lele': [
    ('ph_air', 'pH air', 'pH', false),
    ('suhu_air', 'Suhu air', '°C', false),
    ('pakan_maggot_pagi_kg', 'Pakan maggot pagi', 'kg', true),
    ('pakan_lele_kg', 'Pakan maggot sore', 'kg', true),
    ('mortalitas_ikan', 'Bobot rata-rata (key legacy)', 'g/ekor', false),
    ('kondisi_air', 'Survival rate (pengamatan numerik)', '%', false),
  ],
};

ProductivityReport calculateProductivity({
  required DashboardFilter filter,
  required String module,
  String? batchId,
  required List<AnalyticsDocument> logs,
  required List<AnalyticsDocument> production,
  required Map<String, Map<String, dynamic>> parents,
  bool logsTruncated = false,
  bool productionTruncated = false,
}) {
  bool matches(Map<String, dynamic> d, String field) =>
      d['moduleType'] == module &&
      d['isDeleted'] != true &&
      d[field] is Timestamp &&
      filter.contains((d[field] as Timestamp).toDate()) &&
      (batchId == null || d['batchId'] == batchId);
  final selected = logs.where((d) => matches(d.data, 'activityDate')).toList()
    ..sort((a, b) {
      final comparison = (a.data['activityDate'] as Timestamp).compareTo(
        b.data['activityDate'] as Timestamp,
      );
      return comparison == 0 ? a.id.compareTo(b.id) : comparison;
    });
  final series = <ProductivitySeries>[];
  for (final metric in _metrics[module] ?? <(String, String, String, bool)>[]) {
    final groups = <String, Map<DateTime, double>>{};
    for (final log in selected) {
      final d = log.data;
      final details = d['details'];
      if (details is! Map) continue;
      final value = finiteNumber(details[metric.$1]);
      if (value == null ||
          value < 0 ||
          value > 1e15 ||
          (metric.$3 == '%' && value > 100) ||
          (metric.$3 == 'pH' && value > 14)) {
        continue;
      }
      var group = d['batchId'] is String
          ? d['batchId'] as String
          : 'Tanpa batch';
      if (module == 'tanaman') {
        // Unknown legacy identity is one observation, never an invented growth curve.
        final commodity = '${details['jenis_tanaman'] ?? ''}'.trim();
        final block = '${details['blok_lokasi'] ?? ''}'.trim();
        final planted = '${details['tanggal_tanam'] ?? ''}'.trim();
        group =
            '$group · ${commodity.isEmpty ? 'Komoditas tidak diketahui' : commodity} · $block · $planted';
        if (d['batchId'] == null ||
            commodity.isEmpty ||
            block.isEmpty ||
            planted.isEmpty) {
          group = '$group · catatan ${log.id}';
        }
      } else if (!metric.$4 && d['batchId'] == null) {
        group = 'Tanpa batch · catatan ${log.id}';
      }
      final date = (d['activityDate'] as Timestamp).toDate().toLocal();
      final day = DateTime(date.year, date.month, date.day);
      final values = groups.putIfAbsent(group, () => {});
      // Sums are flows; states use the last observation of the day, per identity.
      values[day] = metric.$4 ? (values[day] ?? 0) + value : value;
    }
    for (final group in groups.entries) {
      series.add(
        ProductivitySeries(
          label: '${metric.$2} · ${group.key}',
          unit: metric.$3,
          additive: metric.$4,
          points: [
            for (final e in group.value.entries)
              ProductivityPoint(e.key, e.value),
          ],
        ),
      );
    }
  }
  final totals = <String, double>{};
  final dailyProduction = <String, Map<DateTime, double>>{};
  final productionUnits = <String, String>{};
  var uncertain = productionTruncated;
  final seen = <String>{};
  for (final item in production) {
    final d = item.data;
    if (!matches(d, 'harvestDate') || d['isReversed'] == true) continue;
    final value = finiteNumber(d['quantity']);
    final product = '${d['productName'] ?? ''}'.trim();
    final unit = '${d['unit'] ?? ''}'.trim();
    final parent = parents[d['logbookId']];
    if (value == null ||
        value <= 0 ||
        value > 1e15 ||
        product.isEmpty ||
        unit.isEmpty ||
        parent == null ||
        parent['isDeleted'] == true ||
        parent['moduleType'] != module ||
        parent['batchId'] != d['batchId']) {
      uncertain = true;
      continue;
    }
    // Canonical production only: never add logbook observations or inventory movements.
    final identity = '${d['logbookId']}|$product|$unit';
    if (!seen.add(identity)) {
      uncertain = true;
      continue;
    }
    final key = '$product ($unit)';
    totals[key] = (totals[key] ?? 0) + value;
    final date = (d['harvestDate'] as Timestamp).toDate().toLocal();
    final day = DateTime(date.year, date.month, date.day);
    final days = dailyProduction.putIfAbsent(key, () => {});
    days[day] = (days[day] ?? 0) + value;
    productionUnits[key] = unit;
  }
  // Legacy harvest observations without a canonical result cannot become production totals.
  const harvestKeys = [
    'produksi_telur_hari_ini',
    'panen_maggot_kg',
    'panen_prepupa_kering_kg',
    'panen_kascing_kg',
    'kascing_cair_liter',
    'hasil_panen_kg',
    'panen_lele_kg',
  ];
  final linked = production
      .where((d) => matches(d.data, 'harvestDate'))
      .map((d) => d.data['logbookId'])
      .toSet();
  for (final log in selected) {
    final details = log.data['details'];
    if (details is Map &&
        !linked.contains(log.id) &&
        harvestKeys.any((k) => (finiteNumber(details[k]) ?? 0) > 0)) {
      uncertain = true;
    }
  }
  if (!uncertain) {
    for (final product in dailyProduction.entries) {
      final dates = product.value.entries.toList()
        ..sort((a, b) => a.key.compareTo(b.key));
      series.add(
        ProductivitySeries(
          label: 'Produksi aktual - ${product.key}',
          unit: productionUnits[product.key]!,
          additive: true,
          points: [
            for (final date in dates) ProductivityPoint(date.key, date.value),
          ],
        ),
      );
    }
  }
  return ProductivityReport(
    series: series,
    production: uncertain ? const {} : totals,
    logCount: selected.length,
    logsTruncated: logsTruncated,
    productionUncertain: uncertain,
    lastActivity: selected.isEmpty
        ? null
        : (selected.last.data['activityDate'] as Timestamp).toDate(),
  );
}
