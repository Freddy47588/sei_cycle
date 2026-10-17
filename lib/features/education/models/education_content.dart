import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/utils/firestore_fields.dart';

/// Status publikasi konten edukasi.
abstract final class EducationStatus {
  static const draft = 'draft';
  static const published = 'published';
  static const archived = 'archived';

  static const values = {draft, published, archived};

  static String label(String status) => switch (status) {
    published => 'Terbit',
    archived => 'Diarsipkan',
    _ => 'Draft',
  };
}

/// Tipe konten edukasi.
abstract final class EducationType {
  static const article = 'artikel';
  static const video = 'video';
  static const sop = 'sop';

  static const values = {article, video, sop};

  static String label(String type) => switch (type) {
    video => 'Video',
    sop => 'SOP',
    _ => 'Artikel',
  };
}

/// Satu dokumen konten edukasi dari collection `education_contents`.
///
/// Mendukung tiga tipe: artikel, video tutorial, dan SOP operasional.
/// Tidak ada Firebase Storage — media disimpan sebagai external URL.
class EducationContent {
  const EducationContent({
    required this.id,
    required this.title,
    required this.type,
    required this.status,
    required this.moduleType,
    required this.category,
    required this.tags,
    required this.authorId,
    required this.createdBy,
    required this.updatedBy,
    required this.createdAt,
    required this.updatedAt,
    required this.isDeleted,
    // Artikel
    this.summary = '',
    this.content = '',
    this.thumbnailUrl = '',
    // Video
    this.externalVideoUrl = '',
    this.duration = '',
    // SOP
    this.steps = const [],
    this.toolsNeeded = const [],
    this.safetyNotes = '',
    // Legacy compat
    this.externalUrl = '',
  });

  final String id;
  final String title;

  /// Tipe: `artikel`, `video`, `sop`.
  final String type;

  /// Status: `draft`, `published`, `archived`.
  final String status;

  /// Modul kebun yang relevan, misalnya `lele`, `ayam_kampung`, atau kosong jika umum.
  final String moduleType;

  /// Kategori bebas, misalnya "Pakan", "Kesehatan", "Panen".
  final String category;

  /// Tag/label tambahan.
  final List<String> tags;

  /// UID penulis / pembuat konten.
  final String authorId;

  final String createdBy;
  String get displayTitle =>
      createdBy == 'sample_seed' ? 'Contoh / Simulasi - $title' : title;
  final String updatedBy;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isDeleted;

  // --- Artikel ---
  /// Ringkasan singkat artikel (tampil di kartu).
  final String summary;

  /// Isi lengkap artikel dalam teks (bisa Markdown atau plain text).
  final String content;

  /// URL gambar thumbnail eksternal (opsional).
  final String thumbnailUrl;

  // --- Video ---
  /// URL video eksternal, misalnya YouTube.
  final String externalVideoUrl;

  /// Durasi video, format bebas, misalnya "12:34" atau "15 menit".
  final String duration;

  // --- SOP ---
  /// Langkah-langkah SOP sebagai list teks.
  final List<String> steps;

  /// Alat/bahan yang dibutuhkan.
  final List<String> toolsNeeded;

  /// Catatan keselamatan.
  final String safetyNotes;

  // --- Legacy ---
  /// Field lama untuk backward compatibility dengan dokumen sebelumnya.
  final String externalUrl;

  bool get isPublished => status == EducationStatus.published;

  /// Teks preview untuk kartu — diprioritaskan summary, lalu content, lalu deskripsi SOP.
  String get previewText {
    if (summary.isNotEmpty) return summary;
    if (type == EducationType.sop && steps.isNotEmpty) {
      return steps.join(' • ');
    }
    if (content.isNotEmpty) return content;
    return '';
  }

  /// URL video aktif (mendukung externalVideoUrl dan externalUrl lama).
  String get videoUrl =>
      externalVideoUrl.isNotEmpty ? externalVideoUrl : externalUrl;

  factory EducationContent.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data() ?? const <String, dynamic>{};

    // Backward compat: isPublished → status
    final rawStatus = stringField(data, const ['status']);
    final isPublishedLegacy = boolField(data, const [
      'isPublished',
      'is_published',
    ]);
    final resolvedStatus = rawStatus.isNotEmpty
        ? rawStatus
        : isPublishedLegacy
        ? EducationStatus.published
        : EducationStatus.draft;

    // steps / toolsNeeded: stored as List<dynamic>
    final stepsRaw = data['steps'];
    final steps = stepsRaw is List
        ? stepsRaw.map((e) => e.toString()).toList()
        : <String>[];

    final toolsRaw = data['toolsNeeded'];
    final tools = toolsRaw is List
        ? toolsRaw.map((e) => e.toString()).toList()
        : <String>[];

    final tagsRaw = data['tags'];
    final tags = tagsRaw is List
        ? tagsRaw.map((e) => e.toString()).toList()
        : <String>[];

    return EducationContent(
      id: stringField(data, const ['id'], fallback: document.id),
      title: stringField(data, const ['title']),
      type: stringField(data, const ['type'], fallback: EducationType.article),
      status: resolvedStatus,
      moduleType: stringField(data, const ['moduleType', 'module_type']),
      category: stringField(data, const ['category']),
      tags: tags,
      authorId: stringField(data, const [
        'authorId',
        'createdBy',
        'created_by',
      ]),
      createdBy: stringField(data, const ['createdBy', 'created_by']),
      updatedBy: stringField(data, const ['updatedBy', 'updated_by']),
      createdAt: dateTimeField(data, const ['createdAt', 'created_at']),
      updatedAt: dateTimeField(data, const ['updatedAt', 'updated_at']),
      isDeleted: boolField(data, const ['isDeleted', 'is_deleted']),
      summary: stringField(data, const ['summary']),
      content: stringField(data, const ['content', 'description']),
      thumbnailUrl: stringField(data, const ['thumbnailUrl', 'thumbnail_url']),
      externalVideoUrl: stringField(data, const [
        'externalVideoUrl',
        'external_video_url',
      ]),
      duration: stringField(data, const ['duration']),
      steps: steps,
      toolsNeeded: tools,
      safetyNotes: stringField(data, const ['safetyNotes', 'safety_notes']),
      externalUrl: stringField(data, const ['externalUrl', 'external_url']),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'id': id,
      'title': title,
      'type': type,
      'status': status,
      'moduleType': moduleType,
      'category': category,
      'tags': tags,
      'authorId': authorId,
      'createdBy': createdBy,
      'updatedBy': updatedBy,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      'isDeleted': isDeleted,
      // Artikel
      'summary': summary,
      'content': content,
      'thumbnailUrl': thumbnailUrl,
      // Video
      'externalVideoUrl': externalVideoUrl,
      'duration': duration,
      // SOP
      'steps': steps,
      'toolsNeeded': toolsNeeded,
      'safetyNotes': safetyNotes,
    };
  }
}
