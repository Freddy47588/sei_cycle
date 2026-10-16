import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/constants/firestore_collections.dart';
import '../../profile/models/app_user.dart';
import '../models/cultivation_batch.dart';

class BatchService {
  BatchService({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;
  final FirebaseFirestore _db;
  CollectionReference<Map<String, dynamic>> get _batches =>
      _db.collection(FirestoreCollections.batches);
  Future<void> _authorize(Transaction tx, String userId) async {
    final profile = await tx.get(_db.collection('users').doc(userId));
    if (!profile.exists || !AppUser.fromDocument(profile).canManageBatches) {
      throw StateError('Tidak memiliki izin mengelola batch.');
    }
  }

  Future<String> create(BatchInput input, {required String userId}) async {
    input.validate();
    final id = input.normalizedCode;
    await _db.runTransaction((tx) async {
      await _authorize(tx, userId);
      final ref = _batches.doc(id);
      final existing = await tx.get(ref);
      if (existing.exists) throw StateError('Kode batch sudah digunakan.');
      final now = FieldValue.serverTimestamp();
      tx.set(ref, {
        ...input.toFirestore(),
        'id': id,
        'status': 'planned',
        'completedAt': null,
        'createdBy': userId,
        'updatedBy': userId,
        'createdAt': now,
        'updatedAt': now,
        'isDeleted': false,
      });
    });
    return id;
  }

  Future<void> edit(
    String id,
    BatchInput input, {
    required String userId,
    required DateTime expectedUpdatedAt,
  }) async {
    input.validate();
    await _db.runTransaction((tx) async {
      await _authorize(tx, userId);
      final doc = await tx.get(_batches.doc(id));
      if (!doc.exists) throw StateError('Batch tidak ditemukan.');
      final old = CultivationBatch.fromDocument(doc);
      if (old.isDeleted || !['planned', 'active'].contains(old.status)) {
        throw StateError('Batch selesai/arsip hanya dapat dibaca.');
      }
      if (old.updatedAt != expectedUpdatedAt) {
        throw StateError('Batch berubah. Muat ulang.');
      }
      if (old.input.moduleType != input.moduleType ||
          old.input.code != input.normalizedCode ||
          old.input.startedAt != input.startedAt ||
          old.input.initialQuantity != input.initialQuantity ||
          old.input.initialUnit != input.initialUnit.trim()) {
        throw StateError(
          'Identitas modul, kode, tanggal dan data awal tidak dapat diubah.',
        );
      }
      tx.update(doc.reference, {
        'name': input.name.trim(),
        'locationName': input.locationName.trim(),
        'expectedHarvestAt': input.toFirestore()['expectedHarvestAt'],
        'commodity': input.commodity.trim(),
        'notes': input.notes.trim(),
        'updatedBy': userId,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> transition(
    String id, {
    required String from,
    required String to,
    required String userId,
  }) async {
    if (nextBatchStatus(from) != to) {
      throw ArgumentError('Transisi status tidak valid.');
    }
    await _db.runTransaction((tx) async {
      await _authorize(tx, userId);
      final doc = await tx.get(_batches.doc(id));
      if (!doc.exists || doc.data()?['isDeleted'] == true) {
        throw StateError('Batch tidak tersedia.');
      }
      final current = doc.data()!['status'];
      if (current == to) {
        return; // An already committed retry has no side effects.
      }
      if (current != from) throw StateError('Status berubah. Muat ulang.');
      tx.update(doc.reference, {
        'status': to,
        'updatedBy': userId,
        'updatedAt': FieldValue.serverTimestamp(),
        if (to == 'completed') 'completedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<CultivationBatch?> getBatch(String id) async {
    final doc = await _batches.doc(id).get();
    return doc.exists && doc.data()?['isDeleted'] != true
        ? CultivationBatch.fromDocument(doc)
        : null;
  }

  Future<BatchPage> getPage({
    String? moduleType,
    String? status,
    bool newestFirst = true,
    DocumentSnapshot<Map<String, dynamic>>? cursor,
  }) async {
    Query<Map<String, dynamic>> q = _batches.where(
      'isDeleted',
      isEqualTo: false,
    );
    if (moduleType != null) q = q.where('moduleType', isEqualTo: moduleType);
    if (status != null) q = q.where('status', isEqualTo: status);
    q = q.orderBy('createdAt', descending: newestFirst).limit(20);
    if (cursor != null) q = q.startAfterDocument(cursor);
    final result = await q.get();
    return BatchPage(
      entries: result.docs.map(CultivationBatch.fromDocument).toList(),
      cursor: result.docs.lastOrNull,
      hasMore: result.docs.length == 20,
    );
  }
}
