import '../../../core/utils/audit_mode.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:uuid/uuid.dart';

import '../../../core/constants/firestore_collections.dart';
import '../../../core/utils/firestore_validators.dart';
import '../models/education_content.dart';

/// Service CRUD untuk `education_contents`.
///
/// - Admin: baca semua status, bisa create/update/delete.
/// - Semua role aktif: baca hanya status `published`.
/// - Tidak ada Firebase Storage, tidak ada Cloud Functions.
class EducationService {
  EducationService({FirebaseFirestore? firestore, Uuid? uuid})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _uuid = uuid ?? const Uuid();

  final FirebaseFirestore _firestore;
  final Uuid _uuid;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection(FirestoreCollections.educationContents);

  // ---------------------------------------------------------------------------
  // Read
  // ---------------------------------------------------------------------------

  /// Stream daftar konten edukasi.
  ///
  /// [includeDrafts] — admin mendapat semua status; user biasa hanya `published`.
  /// [type] — filter by `artikel`, `video`, atau `sop`; null = semua.
  /// [moduleType] — filter by modul kebun; null = semua.
  /// [status] — filter by status spesifik (override [includeDrafts]).
  Stream<List<EducationContent>> watchContents({
    required bool includeDrafts,
    String? type,
    String? moduleType,
    String? status,
    int limit = 20,
  }) {
    Query<Map<String, dynamic>> query = _collection.where(
      'isDeleted',
      isEqualTo: false,
    );

    // Status filter
    if (includeDrafts && status != null && status.isNotEmpty) {
      query = query.where('status', isEqualTo: status);
    } else if (!includeDrafts) {
      query = query.where('status', isEqualTo: EducationStatus.published);
    }

    // Type filter
    if (type != null && type.trim().isNotEmpty) {
      query = query.where('type', isEqualTo: type.trim());
    }

    // ModuleType filter
    if (moduleType != null && moduleType.trim().isNotEmpty) {
      query = query.where('moduleType', isEqualTo: moduleType.trim());
    }

    return query
        .orderBy('updatedAt', descending: true)
        .limit(limit)
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs.map(EducationContent.fromDocument).toList(),
        );
  }

  /// Ambil satu konten berdasarkan ID (Future, bukan stream).
  Future<EducationContent?> getById(String id) async {
    requireTrimmed(id, 'id');
    final doc = await _collection.doc(id).get();
    if (!doc.exists) return null;
    return EducationContent.fromDocument(doc);
  }

  // ---------------------------------------------------------------------------
  // Write — Article
  // ---------------------------------------------------------------------------

  /// Simpan artikel. Buat baru jika [id] null, update jika ada.
  Future<String> saveArticle({
    String? id,
    String? requestId,
    DateTime? expectedUpdatedAt,
    required String title,
    required String summary,
    required String content,
    required String category,
    required String moduleType,
    required List<String> tags,
    required String status,
    required String userId,
    String thumbnailUrl = '',
  }) async {
    requireWritesEnabled();
    _validateTitle(title, userId);
    requireOneOf(status, EducationStatus.values, 'status');

    final docId = _documentId(id, requestId);
    final now = FieldValue.serverTimestamp();
    final data = <String, dynamic>{
      'id': docId,
      'title': title.trim(),
      'type': EducationType.article,
      'status': status,
      'moduleType': moduleType.trim(),
      'category': category.trim(),
      'tags': tags.map((t) => t.trim()).where((t) => t.isNotEmpty).toList(),
      'summary': summary.trim(),
      'content': content.trim(),
      'thumbnailUrl': thumbnailUrl.trim(),
      'updatedBy': userId,
      'updatedAt': now,
      'isDeleted': false,
    };
    if (id == null) {
      data['authorId'] = userId;
      data['createdBy'] = userId;
      data['createdAt'] = now;
    }
    await _write(
      docId,
      data,
      create: id == null,
      expectedUpdatedAt: expectedUpdatedAt,
    );
    return docId;
  }

  // ---------------------------------------------------------------------------
  // Write — Video
  // ---------------------------------------------------------------------------

  /// Simpan video tutorial. Tidak ada upload; hanya menyimpan URL eksternal.
  Future<String> saveVideo({
    String? id,
    String? requestId,
    DateTime? expectedUpdatedAt,
    required String title,
    required String description,
    required String externalVideoUrl,
    required String category,
    required String moduleType,
    required String status,
    required String userId,
    String duration = '',
    String thumbnailUrl = '',
    List<String> tags = const [],
  }) async {
    requireWritesEnabled();
    _validateTitle(title, userId);
    requireTrimmed(externalVideoUrl, 'externalVideoUrl');
    if (!isSafeEducationUrl(externalVideoUrl)) {
      throw ArgumentError('Gunakan URL HTTPS tanpa kredensial.');
    }
    requireOneOf(status, EducationStatus.values, 'status');

    final docId = _documentId(id, requestId);
    final now = FieldValue.serverTimestamp();
    final data = <String, dynamic>{
      'id': docId,
      'title': title.trim(),
      'type': EducationType.video,
      'status': status,
      'moduleType': moduleType.trim(),
      'category': category.trim(),
      'tags': tags.map((t) => t.trim()).where((t) => t.isNotEmpty).toList(),
      'summary': description.trim(),
      'content': description.trim(),
      'externalVideoUrl': externalVideoUrl.trim(),
      'thumbnailUrl': thumbnailUrl.trim(),
      'duration': duration.trim(),
      'updatedBy': userId,
      'updatedAt': now,
      'isDeleted': false,
    };
    if (id == null) {
      data['authorId'] = userId;
      data['createdBy'] = userId;
      data['createdAt'] = now;
    }
    await _write(
      docId,
      data,
      create: id == null,
      expectedUpdatedAt: expectedUpdatedAt,
    );
    return docId;
  }

  // ---------------------------------------------------------------------------
  // Write — SOP
  // ---------------------------------------------------------------------------

  /// Simpan SOP operasional. Langkah disimpan sebagai `List<String>` di Firestore.
  Future<String> saveSop({
    String? id,
    String? requestId,
    DateTime? expectedUpdatedAt,
    required String title,
    required String moduleType,
    required List<String> steps,
    required String status,
    required String userId,
    String category = '',
    List<String> toolsNeeded = const [],
    String safetyNotes = '',
    List<String> tags = const [],
  }) async {
    requireWritesEnabled();
    _validateTitle(title, userId);
    if (steps.isEmpty) {
      throw ArgumentError('SOP harus memiliki minimal satu langkah.');
    }
    requireOneOf(status, EducationStatus.values, 'status');

    final docId = _documentId(id, requestId);
    final now = FieldValue.serverTimestamp();
    final cleanSteps = steps
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (cleanSteps.isEmpty) throw ArgumentError('Langkah SOP wajib diisi.');
    final data = <String, dynamic>{
      'id': docId,
      'title': title.trim(),
      'type': EducationType.sop,
      'status': status,
      'moduleType': moduleType.trim(),
      'category': category.trim(),
      'tags': tags.map((t) => t.trim()).where((t) => t.isNotEmpty).toList(),
      'steps': cleanSteps,
      'toolsNeeded': toolsNeeded
          .map((t) => t.trim())
          .where((t) => t.isNotEmpty)
          .toList(),
      'safetyNotes': safetyNotes.trim(),
      'summary': cleanSteps.take(2).join(' • '),
      'content': cleanSteps.join('\n'),
      'updatedBy': userId,
      'updatedAt': now,
      'isDeleted': false,
    };
    if (id == null) {
      data['authorId'] = userId;
      data['createdBy'] = userId;
      data['createdAt'] = now;
    }
    await _write(
      docId,
      data,
      create: id == null,
      expectedUpdatedAt: expectedUpdatedAt,
    );
    return docId;
  }

  // ---------------------------------------------------------------------------
  // Generic save (untuk legacy / screen sederhana)
  // ---------------------------------------------------------------------------

  /// Simpan konten generik. Routing ke saveArticle/saveVideo/saveSop berdasarkan [type].
  Future<String> save({
    String? id,
    String? requestId,
    DateTime? expectedUpdatedAt,
    required String title,
    required String type,
    required String content,
    required String status,
    required String userId,
    String moduleType = '',
    String category = '',
    String externalUrl = '',
    List<String> tags = const [],
    List<String> steps = const [],
    List<String> toolsNeeded = const [],
    String safetyNotes = '',
    String duration = '',
    String thumbnailUrl = '',
  }) {
    return switch (type) {
      EducationType.video => saveVideo(
        id: id,
        requestId: requestId,
        expectedUpdatedAt: expectedUpdatedAt,
        title: title,
        description: content,
        externalVideoUrl: externalUrl,
        category: category,
        moduleType: moduleType,
        status: status,
        userId: userId,
        duration: duration,
        thumbnailUrl: thumbnailUrl,
        tags: tags,
      ),
      EducationType.sop => saveSop(
        id: id,
        requestId: requestId,
        expectedUpdatedAt: expectedUpdatedAt,
        title: title,
        moduleType: moduleType,
        steps: steps.isNotEmpty ? steps : content.split('\n'),
        status: status,
        userId: userId,
        category: category,
        toolsNeeded: toolsNeeded,
        safetyNotes: safetyNotes,
        tags: tags,
      ),
      _ => saveArticle(
        id: id,
        requestId: requestId,
        expectedUpdatedAt: expectedUpdatedAt,
        title: title,
        summary: content.length > 200
            ? '${content.substring(0, 200)}...'
            : content,
        content: content,
        category: category,
        moduleType: moduleType,
        tags: tags,
        status: status,
        userId: userId,
        thumbnailUrl: thumbnailUrl,
      ),
    };
  }

  // ---------------------------------------------------------------------------
  // Status management
  // ---------------------------------------------------------------------------

  /// Ubah status konten (draft → published → archived).
  Future<void> updateStatus(
    String id, {
    required String status,
    required String userId,
  }) {
    requireWritesEnabled();
    requireTrimmed(id, 'id');
    requireTrimmed(userId, 'userId');
    requireOneOf(status, EducationStatus.values, 'status');
    return _write(id, {
      'status': status,
      'updatedBy': userId,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ---------------------------------------------------------------------------
  // Delete (soft)
  // ---------------------------------------------------------------------------

  Future<void> delete(String id, {required String userId}) {
    requireWritesEnabled();
    requireTrimmed(id, 'id');
    requireTrimmed(userId, 'userId');
    return _write(id, {
      'isDeleted': true,
      'updatedBy': userId,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  Future<void> _write(
    String id,
    Map<String, dynamic> patch, {
    bool create = false,
    DateTime? expectedUpdatedAt,
  }) async {
    final editId = _uuid.v4();
    await _firestore.runTransaction((tx) async {
      final reference = _collection.doc(id);
      final snapshot = await tx.get(reference);
      if (create &&
          snapshot.exists &&
          _matchesCreation(snapshot.data()!, patch)) {
        return; // An acknowledged receipt prevents duplicate content/audit on retry.
      }
      if (create == snapshot.exists) {
        throw StateError(
          create
              ? 'ID konten telah digunakan.'
              : 'Konten tidak ditemukan. Muat ulang daftar.',
        );
      }
      final before = snapshot.data();
      if (expectedUpdatedAt != null &&
          before?['updatedAt'] != Timestamp.fromDate(expectedUpdatedAt)) {
        throw StateError(
          'Konten telah berubah. Muat versi terbaru sebelum menyimpan.',
        );
      }
      final after = <String, dynamic>{
        ...?before,
        ...patch,
        'lastEditId': editId,
      };
      tx.set(reference, after);
      tx.set(_firestore.collection('education_edits').doc(editId), {
        'targetId': id,
        'actorUid': patch['updatedBy'],
        'requestId': editId,
        'operation': create
            ? 'create'
            : patch['isDeleted'] == true
            ? 'softDelete'
            : 'update',
        'before': before,
        'after': after,
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
  }

  void _validateTitle(String title, String userId) {
    requireTrimmed(title, 'title');
    requireTrimmed(userId, 'userId');
  }

  String _documentId(String? id, String? requestId) {
    final value = id ?? requestId ?? _uuid.v4();
    if (value.trim().isEmpty || value.contains('/') || value.length > 128) {
      throw ArgumentError('ID konten tidak valid.');
    }
    return value;
  }

  bool _matchesCreation(
    Map<String, dynamic> stored,
    Map<String, dynamic> payload,
  ) => payload.entries.every((entry) {
    if (entry.key == 'createdAt' || entry.key == 'updatedAt') return true;
    final previous = stored[entry.key];
    final value = entry.value;
    return value is List
        ? previous is List && listEquals<dynamic>(previous, value)
        : previous == value;
  });
}

/// External educational media must never execute arbitrary URL schemes.
bool isSafeEducationUrl(String value) {
  final uri = Uri.tryParse(value.trim());
  return uri != null &&
      uri.scheme == 'https' &&
      uri.host.isNotEmpty &&
      uri.userInfo.isEmpty;
}
