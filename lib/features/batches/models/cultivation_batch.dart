import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/constants/farm_modules.dart';

const batchStatuses = ['planned', 'active', 'completed', 'archived'];
String batchStatusLabel(String status) => switch (status) {
  'planned' => 'Direncanakan',
  'active' => 'Aktif',
  'completed' => 'Selesai',
  'archived' => 'Diarsipkan',
  _ => status,
};
String? nextBatchStatus(String status) => switch (status) {
  'planned' => 'active',
  'active' => 'completed',
  'completed' => 'archived',
  _ => null,
};

/// Code is also the deterministic document ID: globally unique, never reused.
class BatchInput {
  const BatchInput({
    required this.moduleType,
    required this.name,
    required this.code,
    required this.locationName,
    required this.startedAt,
    this.expectedHarvestAt,
    this.initialQuantity,
    this.initialUnit = '',
    this.commodity = '',
    this.notes = '',
  });
  final String moduleType,
      name,
      code,
      locationName,
      initialUnit,
      commodity,
      notes;
  final DateTime startedAt;
  final DateTime? expectedHarvestAt;
  final double? initialQuantity;
  String get normalizedCode => code.trim().toUpperCase();
  void validate() {
    if (!FarmModules.values.any((m) => m.id == moduleType)) {
      throw ArgumentError('Modul tidak valid.');
    }
    if (name.trim().isEmpty ||
        name.trim().length > 120 ||
        locationName.trim().isEmpty ||
        locationName.trim().length > 120) {
      throw ArgumentError(
        'Nama dan lokasi wajib diisi (maksimal 120 karakter).',
      );
    }
    if (!RegExp(r'^[A-Z0-9][A-Z0-9_-]{2,39}$').hasMatch(normalizedCode)) {
      throw ArgumentError('Kode 3-40 karakter: huruf, angka, - atau _.');
    }
    if (initialQuantity != null &&
        (!initialQuantity!.isFinite ||
            initialQuantity! < 0 ||
            initialQuantity! > 1000000000000000 ||
            initialUnit.trim().isEmpty)) {
      throw ArgumentError(
        'Jumlah awal harus 0-1000000000000000 dan memiliki unit.',
      );
    }
    if (initialUnit.length > 30 ||
        commodity.length > 120 ||
        notes.length > 3000) {
      throw ArgumentError('Teks melebihi batas panjang.');
    }
    if (expectedHarvestAt != null && expectedHarvestAt!.isBefore(startedAt)) {
      throw ArgumentError('Estimasi panen tidak boleh sebelum tanggal mulai.');
    }
  }

  Map<String, dynamic> toFirestore() => {
    'moduleType': moduleType,
    'name': name.trim(),
    'code': normalizedCode,
    'locationName': locationName.trim(),
    'startedAt': Timestamp.fromDate(startedAt),
    'expectedHarvestAt': expectedHarvestAt == null
        ? null
        : Timestamp.fromDate(expectedHarvestAt!),
    'initialQuantity': initialQuantity,
    'initialUnit': initialUnit.trim(),
    'commodity': commodity.trim(),
    'notes': notes.trim(),
  };
}

class CultivationBatch {
  const CultivationBatch({
    required this.id,
    required this.input,
    required this.status,
    required this.createdBy,
    required this.updatedBy,
    this.createdAt,
    this.updatedAt,
    this.completedAt,
    this.isDeleted = false,
  });
  final String id, status, createdBy, updatedBy;
  final BatchInput input;
  final DateTime? createdAt, updatedAt, completedAt;
  final bool isDeleted;
  factory CultivationBatch.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data()!;
    DateTime? date(String key) => (d[key] as Timestamp?)?.toDate();
    return CultivationBatch(
      id: doc.id,
      input: BatchInput(
        moduleType: d['moduleType'] as String,
        name: d['name'] as String,
        code: d['code'] as String,
        locationName: d['locationName'] as String,
        startedAt: date('startedAt')!,
        expectedHarvestAt: date('expectedHarvestAt'),
        initialQuantity: (d['initialQuantity'] as num?)?.toDouble(),
        initialUnit: d['initialUnit'] as String? ?? '',
        commodity: d['commodity'] as String? ?? '',
        notes: d['notes'] as String? ?? '',
      ),
      status: d['status'] as String,
      createdBy: d['createdBy'] as String,
      updatedBy: d['updatedBy'] as String,
      createdAt: date('createdAt'),
      updatedAt: date('updatedAt'),
      completedAt: date('completedAt'),
      isDeleted: d['isDeleted'] == true,
    );
  }
}

class BatchPage {
  const BatchPage({required this.entries, this.cursor, required this.hasMore});
  final List<CultivationBatch> entries;
  final DocumentSnapshot<Map<String, dynamic>>? cursor;
  final bool hasMore;
}
