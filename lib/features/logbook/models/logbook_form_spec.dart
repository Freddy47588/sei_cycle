import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';

class LogbookModuleSpec {
  const LogbookModuleSpec({
    required this.label,
    required this.moduleType,
    required this.title,
    required this.activityType,
    required this.bannerLabel,
    required this.icon,
    required this.color,
    required this.sections,
    required this.notesKey,
    this.quantityKey,
    this.quantityUnit,
    this.slider,
  });

  final String label;
  final String moduleType;
  final String title;
  final String activityType;
  final String bannerLabel;
  final IconData icon;
  final Color color;
  final List<LogbookFieldSection> sections;
  final String notesKey;
  final String? quantityKey;
  final String? quantityUnit;
  final LogbookSliderSpec? slider;
}

class LogbookFieldSection {
  const LogbookFieldSection({
    required this.title,
    required this.icon,
    required this.color,
    required this.fields,
  });

  final String title;
  final IconData icon;
  final Color color;
  final List<LogbookFieldSpec> fields;
}

class LogbookFieldSpec {
  const LogbookFieldSpec({
    required this.key,
    required this.label,
    required this.hint,
    this.type = TextInputType.text,
    this.suffix,
    this.maxLines = 1,
  });

  final String key;
  final String label;
  final String hint;
  final TextInputType type;
  final String? suffix;
  final int maxLines;
}

class LogbookSliderSpec {
  const LogbookSliderSpec({
    required this.key,
    required this.label,
    required this.unit,
    required this.min,
    required this.max,
    required this.color,
  });

  final String key;
  final String label;
  final String unit;
  final double min;
  final double max;
  final Color color;
}

const ayamSpec = LogbookModuleSpec(
  label: 'Modul Ayam',
  moduleType: 'ayam_kampung',
  title: 'Catatan Harian Modul Ayam',
  activityType: 'input_harian_ayam',
  bannerLabel: 'Modul Ayam',
  icon: Icons.egg_alt_outlined,
  color: AppColors.warning,
  quantityKey: 'produksi_telur_hari_ini',
  quantityUnit: 'butir',
  notesKey: 'catatan_kejadian_khusus',
  slider: LogbookSliderSpec(
    key: 'mortalitas_hari_ini',
    label: 'Mortalitas Hari Ini',
    unit: 'ekor',
    min: 0,
    max: 10,
    color: AppColors.error,
  ),
  sections: [
    LogbookFieldSection(
      title: 'Input Harian',
      icon: Icons.edit_outlined,
      color: AppColors.warning,
      fields: [
        LogbookFieldSpec(
          key: 'populasi_aktif',
          label: 'Populasi Aktif',
          hint: 'Jumlah ekor',
          type: TextInputType.number,
          suffix: 'ekor',
        ),
        LogbookFieldSpec(
          key: 'konsumsi_pakan_g_per_ekor',
          label: 'Konsumsi Pakan',
          hint: 'Gram per ekor per hari',
          type: TextInputType.number,
          suffix: 'g/ekor',
        ),
        LogbookFieldSpec(
          key: 'produksi_telur_hari_ini',
          label: 'Produksi Telur Hari Ini',
          hint: 'Jumlah butir',
          type: TextInputType.number,
          suffix: 'butir',
        ),
        LogbookFieldSpec(
          key: 'berat_rata_rata_telur',
          label: 'Berat Rata-rata Telur',
          hint: 'Gram per butir',
          type: TextInputType.number,
          suffix: 'gram',
        ),
        LogbookFieldSpec(
          key: 'catatan_kejadian_khusus',
          label: 'Catatan Kejadian Khusus',
          hint: 'Contoh: ayam terlihat lesu, perlu vaksin...',
          maxLines: 3,
        ),
      ],
    ),
    LogbookFieldSection(
      title: 'Rincian Pakan & Nutrisi',
      icon: Icons.restaurant_outlined,
      color: AppColors.accentBrown,
      fields: [
        LogbookFieldSpec(
          key: 'dedak_padi_kg',
          label: 'Dedak Padi',
          hint: 'kg',
          type: TextInputType.number,
          suffix: 'kg',
        ),
        LogbookFieldSpec(
          key: 'talas_pepaya_kg',
          label: 'Talas & Pepaya',
          hint: 'kg',
          type: TextInputType.number,
          suffix: 'kg',
        ),
        LogbookFieldSpec(
          key: 'maggot_segar_kg',
          label: 'Maggot Segar (suplemen)',
          hint: 'kg',
          type: TextInputType.number,
          suffix: 'kg',
        ),
        LogbookFieldSpec(
          key: 'total_biaya_pakan',
          label: 'Total Biaya Pakan',
          hint: 'Rp',
          type: TextInputType.number,
          suffix: 'Rp',
        ),
      ],
    ),
    LogbookFieldSection(
      title: 'Catatan Kesehatan',
      icon: Icons.health_and_safety_outlined,
      color: AppColors.info,
      fields: [
        LogbookFieldSpec(
          key: 'kondisi_kandang',
          label: 'Kondisi Kandang',
          hint: '1-10',
          type: TextInputType.number,
        ),
        LogbookFieldSpec(
          key: 'suhu_kandang',
          label: 'Suhu Kandang',
          hint: 'C',
          type: TextInputType.number,
          suffix: 'C',
        ),
        LogbookFieldSpec(
          key: 'gejala_penyakit',
          label: 'Gejala / Penyakit Terdeteksi',
          hint: 'Kosongkan jika tidak ada kejadian',
          maxLines: 2,
        ),
      ],
    ),
  ],
);

const maggotSpec = LogbookModuleSpec(
  label: 'Modul Maggot',
  moduleType: 'maggot_bsf',
  title: 'Catatan Harian Modul Maggot',
  activityType: 'input_harian_maggot',
  bannerLabel: 'Modul Maggot BSF',
  icon: Icons.bug_report_outlined,
  color: AppColors.accentLightGreen,
  quantityKey: 'volume_limbah_masuk_kg',
  quantityUnit: 'kg',
  notesKey: 'catatan_perawatan',
  slider: LogbookSliderSpec(
    key: 'fase_larva_hari',
    label: 'Fase Larva - Hari ke-',
    unit: '/14',
    min: 1,
    max: 14,
    color: AppColors.accentLightGreen,
  ),
  sections: [
    LogbookFieldSection(
      title: 'Input Limbah Organik',
      icon: Icons.recycling_outlined,
      color: AppColors.accentBrown,
      fields: [
        LogbookFieldSpec(
          key: 'volume_limbah_masuk_kg',
          label: 'Volume Limbah Masuk',
          hint: 'kg',
          type: TextInputType.number,
          suffix: 'kg',
        ),
        LogbookFieldSpec(
          key: 'jenis_limbah_utama',
          label: 'Jenis Limbah Utama',
          hint: 'sisa nasi, sayur, dll.',
        ),
        LogbookFieldSpec(
          key: 'kadar_air_limbah_persen',
          label: 'Kadar Air Limbah',
          hint: '% estimasi',
          type: TextInputType.number,
          suffix: '%',
        ),
        LogbookFieldSpec(
          key: 'asal_limbah',
          label: 'Asal Limbah',
          hint: 'RT / warung / pasar',
        ),
      ],
    ),
    LogbookFieldSection(
      title: 'Status Larva & Fase Pertumbuhan',
      icon: Icons.timeline_outlined,
      color: AppColors.accentLightGreen,
      fields: [
        LogbookFieldSpec(
          key: 'suhu_media',
          label: 'Suhu Media',
          hint: 'C',
          type: TextInputType.number,
          suffix: 'C',
        ),
        LogbookFieldSpec(
          key: 'kelembapan_media',
          label: 'Jumlah Rak Aktif',
          hint: 'unit',
          type: TextInputType.number,
          suffix: 'rak',
        ),
      ],
    ),
    LogbookFieldSection(
      title: 'Estimasi & Rencana Panen',
      icon: Icons.agriculture_outlined,
      color: AppColors.primaryGreen,
      fields: [
        LogbookFieldSpec(
          key: 'estimasi_panen_kg',
          label: 'Estimasi Panen Larva',
          hint: 'kg',
          type: TextInputType.number,
          suffix: 'kg',
        ),
        LogbookFieldSpec(
          key: 'target_panen_larva_kg',
          label: 'Target Panen Larva',
          hint: 'kg',
          type: TextInputType.number,
          suffix: 'kg',
        ),
        LogbookFieldSpec(
          key: 'panen_prepupa_kering_kg',
          label: 'Panen Prepupa (kering)',
          hint: 'kg',
          type: TextInputType.number,
          suffix: 'kg',
        ),
        LogbookFieldSpec(
          key: 'alokasi_larva_lele_persen',
          label: 'Alokasi Larva (lele/ayam)',
          hint: '%',
          type: TextInputType.number,
          suffix: '% lele',
        ),
        LogbookFieldSpec(
          key: 'kondisi_media',
          label: 'Kondisi Media',
          hint: 'kering, basah, stabil...',
        ),
        LogbookFieldSpec(
          key: 'catatan_perawatan',
          label: 'Catatan Batch Ini',
          hint: 'kualitas, anomali, suhu, dll.',
          maxLines: 3,
        ),
      ],
    ),
  ],
);

const cacingSpec = LogbookModuleSpec(
  label: 'Modul Cacing',
  moduleType: 'cacing_tanah',
  title: 'Catatan Harian Modul Cacing',
  activityType: 'input_harian_cacing',
  bannerLabel: 'Modul Cacing Tanah (ANC)',
  icon: Icons.grass_outlined,
  color: AppColors.primaryGreenDark,
  quantityKey: 'pakan_organik_kg',
  quantityUnit: 'kg',
  notesKey: 'catatan_perawatan',
  sections: [
    LogbookFieldSection(
      title: 'Input Harian - Cacing',
      icon: Icons.edit_outlined,
      color: AppColors.primaryGreenDark,
      fields: [
        LogbookFieldSpec(
          key: 'media_cacing_kg',
          label: 'Jumlah Bibit',
          hint: 'kg',
          type: TextInputType.number,
          suffix: 'kg',
        ),
        LogbookFieldSpec(
          key: 'kelembapan_media_persen',
          label: 'Kelembaban Media',
          hint: '%',
          type: TextInputType.number,
          suffix: '%',
        ),
        LogbookFieldSpec(
          key: 'pakan_organik_kg',
          label: 'Pakan Diberikan',
          hint: 'kg',
          type: TextInputType.number,
          suffix: 'kg',
        ),
        LogbookFieldSpec(
          key: 'kondisi_media',
          label: 'Jenis Pakan',
          hint: 'Limbah organik, kotoran...',
        ),
        LogbookFieldSpec(
          key: 'panen_kascing_kg',
          label: 'Hasil Kascing (jika panen)',
          hint: 'kg',
          type: TextInputType.number,
          suffix: 'kg',
        ),
        LogbookFieldSpec(
          key: 'suhu_media',
          label: 'Estimasi Panen Berikutnya',
          hint: 'hari ke-',
          type: TextInputType.number,
          suffix: 'hari lagi',
        ),
        LogbookFieldSpec(
          key: 'kascing_cair_liter',
          label: 'Kascing Cair',
          hint: 'liter',
          type: TextInputType.number,
          suffix: 'L',
        ),
        LogbookFieldSpec(
          key: 'catatan_perawatan',
          label: 'Catatan Kejadian',
          hint: 'kondisi media, suhu, dll.',
          maxLines: 2,
        ),
      ],
    ),
  ],
);

const tanamanSpec = LogbookModuleSpec(
  label: 'Modul Tanaman',
  moduleType: 'tanaman',
  title: 'Catatan Harian Modul Tanaman',
  activityType: 'input_harian_tanaman',
  bannerLabel: 'Modul Tanaman Pangan Organik',
  icon: Icons.eco_outlined,
  color: AppColors.success,
  quantityKey: 'pupuk_kascing_cair_liter',
  quantityUnit: 'L/m2',
  notesKey: 'catatan_kondisi_tanaman',
  sections: [
    LogbookFieldSection(
      title: 'Data Tanam & Pertumbuhan',
      icon: Icons.edit_outlined,
      color: AppColors.success,
      fields: [
        LogbookFieldSpec(
          key: 'jenis_tanaman',
          label: 'Jenis Tanaman',
          hint: 'Talas, singkong, dll.',
        ),
        LogbookFieldSpec(
          key: 'blok_lokasi',
          label: 'Blok / Lokasi',
          hint: 'Blok A, B, C...',
        ),
        LogbookFieldSpec(
          key: 'tanggal_tanam',
          label: 'Tanggal Tanam',
          hint: 'DD/MM/YYYY',
        ),
        LogbookFieldSpec(
          key: 'usia_tanaman',
          label: 'Usia Tanaman',
          hint: 'hari',
          type: TextInputType.number,
          suffix: 'hari',
        ),
        LogbookFieldSpec(
          key: 'tinggi_tanaman_cm',
          label: 'Tinggi Tanaman',
          hint: 'cm',
          type: TextInputType.number,
          suffix: 'cm',
        ),
        LogbookFieldSpec(
          key: 'jumlah_daun',
          label: 'Jumlah Daun',
          hint: 'lembar',
          type: TextInputType.number,
          suffix: 'lbr',
        ),
        LogbookFieldSpec(
          key: 'pupuk_kascing_cair_liter',
          label: 'Pupuk Kascing Cair',
          hint: 'L',
          type: TextInputType.number,
          suffix: 'L/m2',
        ),
        LogbookFieldSpec(
          key: 'pupuk_kascing_kg',
          label: 'Pupuk Kascing Padat',
          hint: 'kg',
          type: TextInputType.number,
          suffix: 'kg',
        ),
        LogbookFieldSpec(
          key: 'hasil_panen_kg',
          label: 'Hasil Panen',
          hint: 'kg',
          type: TextInputType.number,
          suffix: 'kg',
        ),
        LogbookFieldSpec(
          key: 'jadwal_pemupukan_berikutnya',
          label: 'Jadwal Pemupukan Berikutnya',
          hint: 'DD/MM/YYYY',
        ),
        LogbookFieldSpec(
          key: 'catatan_kondisi_tanaman',
          label: 'Catatan Kondisi Tanaman',
          hint: 'hama, pertumbuhan, dll.',
          maxLines: 2,
        ),
      ],
    ),
  ],
);

const leleSpec = LogbookModuleSpec(
  label: 'Modul Lele',
  moduleType: 'lele',
  title: 'Catatan Harian Modul Lele',
  activityType: 'input_harian_lele',
  bannerLabel: 'Modul Lele Organik',
  icon: Icons.water_drop_outlined,
  color: AppColors.info,
  quantityKey: 'pakan_lele_kg',
  quantityUnit: 'kg',
  notesKey: 'catatan_kolam',
  sections: [
    LogbookFieldSection(
      title: 'Input Harian - Lele',
      icon: Icons.edit_outlined,
      color: AppColors.info,
      fields: [
        LogbookFieldSpec(
          key: 'jumlah_ikan',
          label: 'Jumlah Tebar Benih',
          hint: 'ekor',
          type: TextInputType.number,
          suffix: 'ekor',
        ),
        LogbookFieldSpec(
          key: 'kondisi_air',
          label: 'Survival Rate Saat Ini',
          hint: '%',
          type: TextInputType.number,
          suffix: '%',
        ),
        LogbookFieldSpec(
          key: 'pakan_maggot_pagi_kg',
          label: 'Pakan Maggot Pagi',
          hint: 'kg',
          type: TextInputType.number,
          suffix: 'kg',
        ),
        LogbookFieldSpec(
          key: 'pakan_lele_kg',
          label: 'Pakan Maggot Sore',
          hint: 'kg',
          type: TextInputType.number,
          suffix: 'kg',
        ),
        LogbookFieldSpec(
          key: 'ph_air',
          label: 'pH Air Kolam',
          hint: '6.5-8.0 ideal',
          type: TextInputType.numberWithOptions(decimal: true),
          suffix: 'pH',
        ),
        LogbookFieldSpec(
          key: 'suhu_air',
          label: 'Suhu Air',
          hint: 'C',
          type: TextInputType.number,
          suffix: 'C',
        ),
        LogbookFieldSpec(
          key: 'mortalitas_ikan',
          label: 'Bobot Rata-rata',
          hint: 'gram/ekor',
          type: TextInputType.number,
          suffix: 'g',
        ),
        LogbookFieldSpec(
          key: 'estimasi_panen_hari',
          label: 'Estimasi Panen',
          hint: 'hari lagi',
          type: TextInputType.number,
          suffix: 'hari',
        ),
        LogbookFieldSpec(
          key: 'panen_lele_kg',
          label: 'Panen Lele',
          hint: 'kg',
          type: TextInputType.number,
          suffix: 'kg',
        ),
        LogbookFieldSpec(
          key: 'catatan_kolam',
          label: 'Catatan Kolam',
          hint: 'kualitas air, kematian, dll.',
          maxLines: 2,
        ),
      ],
    ),
  ],
);

const logbookModuleSpecs = [
  ayamSpec,
  maggotSpec,
  cacingSpec,
  tanamanSpec,
  leleSpec,
];
LogbookModuleSpec moduleSpecFor(String id) => logbookModuleSpecs.firstWhere(
  (spec) => spec.moduleType == id,
  orElse: () => ayamSpec,
);

String humanizeLogbookKey(String key) => key
    .replaceAllMapped(RegExp(r'([a-z])([A-Z])'), (m) => '${m[1]} ${m[2]}')
    .split('_')
    .where((word) => word.isNotEmpty)
    .map((word) => '${word[0].toUpperCase()}${word.substring(1)}')
    .join(' ');

Map<String, String> displayLogbookDetails(
  String moduleId,
  Map<String, dynamic> details,
) {
  final spec = moduleSpecFor(moduleId);
  final fields = {
    for (final section in spec.sections)
      for (final f in section.fields) f.key: f,
  };
  return {
    for (final e in details.entries)
      if (e.value != null && e.value.toString().trim().isNotEmpty)
        fields[e.key]?.label ??
                (spec.slider?.key == e.key
                    ? spec.slider!.label
                    : humanizeLogbookKey(e.key)):
            '${displayLogbookValue(e.value)}${fields[e.key]?.suffix != null
                ? ' ${fields[e.key]!.suffix}'
                : spec.slider?.key == e.key
                ? ' ${spec.slider!.unit}'
                : ''}',
  };
}

String displayLogbookValue(dynamic value) {
  if (value is num && value.isFinite && value == value.roundToDouble()) {
    return value.toInt().toString();
  }
  if (value is bool) return value ? 'Ya' : 'Tidak';
  if (value is Map) {
    return value.entries
        .map(
          (e) =>
              '${humanizeLogbookKey(e.key.toString())}: ${displayLogbookValue(e.value)}',
        )
        .join(', ');
  }
  if (value is List) return value.map(displayLogbookValue).join(', ');
  return value.toString();
}

void validateLogbookDetails(String moduleId, Map<String, dynamic> details) {
  if (!logbookModuleSpecs.any((s) => s.moduleType == moduleId)) {
    throw ArgumentError('Modul tidak dikenal.');
  }
  final spec = moduleSpecFor(moduleId);
  if (details.values.every((v) => v == null || v.toString().trim().isEmpty)) {
    throw ArgumentError('Isi hasil pengamatan sebelum menyimpan catatan.');
  }
  for (final section in spec.sections) {
    for (final field in section.fields) {
      final raw = details[field.key]?.toString().trim() ?? '';
      if (raw.isEmpty) continue;
      if (field.type.index == TextInputType.number.index) {
        final value = double.tryParse(raw.replaceAll(',', '.'));
        if (value == null || !value.isFinite) {
          throw ArgumentError('${field.label}: masukkan angka yang valid.');
        }
        if (field.key == 'kondisi_kandang' && (value < 1 || value > 10)) {
          throw ArgumentError('Kondisi Kandang harus 1-10.');
        }
        if ([
              'ekor',
              'butir',
              'rak',
              'lbr',
              'hari',
              'hari lagi',
            ].contains(field.suffix) &&
            value != value.roundToDouble()) {
          throw ArgumentError('${field.label} harus berupa bilangan bulat.');
        }
        if (value < 0 && field.suffix != 'C') {
          throw ArgumentError('${field.label} tidak boleh negatif.');
        }
        if ((field.suffix?.startsWith('%') ?? false) && value > 100) {
          throw ArgumentError('${field.label} harus 0-100%.');
        }
        if (field.suffix == 'pH' && (value < 0 || value > 14)) {
          throw ArgumentError('pH harus 0-14.');
        }
      }
      if (field.key == 'tanggal_tanam' ||
          field.key == 'jadwal_pemupukan_berikutnya') {
        final iso = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(raw);
        final local = RegExp(r'^(\d{2})/(\d{2})/(\d{4})$').firstMatch(raw);
        final year = int.tryParse(iso?[1] ?? local?[3] ?? '');
        final month = int.tryParse(iso?[2] ?? local?[2] ?? '');
        final day = int.tryParse(iso?[3] ?? local?[1] ?? '');
        final date = year == null || month == null || day == null
            ? null
            : DateTime(year, month, day);
        if (date == null ||
            date.year != year ||
            date.month != month ||
            date.day != day) {
          throw ArgumentError(
            '${field.label}: gunakan tanggal valid DD/MM/YYYY.',
          );
        }
      }
    }
  }
  if (spec.slider case final slider?) {
    final raw = details[slider.key];
    if (raw != null && raw.toString().isNotEmpty) {
      final value = double.tryParse(raw.toString());
      if (value == null ||
          !value.isFinite ||
          value < slider.min ||
          value > slider.max) {
        throw ArgumentError('${slider.label} di luar rentang.');
      }
    }
  }
}

String logbookStatusLabel(String value) => switch (value) {
  'completed' => 'Selesai',
  'pending' => 'Menunggu',
  'cancelled' => 'Dibatalkan',
  '' => 'Belum tersedia',
  _ => humanizeLogbookKey(value),
};
