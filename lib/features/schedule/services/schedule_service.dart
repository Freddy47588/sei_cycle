import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/constants/farm_modules.dart';
import '../../../core/models/firestore_page.dart';
import '../../../core/utils/firestore_validators.dart';
import '../../../core/utils/operational_auth.dart';
import '../models/schedule_item.dart';
import '../models/schedule_filter.dart';

class ScheduleService {
  ScheduleService({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;
  final FirebaseFirestore _db;
  CollectionReference<Map<String, dynamic>> get _collection =>
      _db.collection('schedules');

  Future<FirestorePage<ScheduleItem>> fetchPage({
    ScheduleFilter filter = const ScheduleFilter(),
    DocumentSnapshot<Map<String, dynamic>>? cursor,
    DateTime? now,
  }) async {
    var q = filter.apply(_collection, now ?? DateTime.now()).limit(20);
    if (cursor != null) q = q.startAfterDocument(cursor);
    final result = await q.get();
    return FirestorePage(
      result.docs.map(ScheduleItem.fromDocument).toList(),
      result.docs.lastOrNull,
      result.docs.length == 20,
    );
  }

  Stream<List<ScheduleItem>> watchSchedules({DateTime? date}) =>
      ScheduleFilter(view: ScheduleView.all, date: date)
          .apply(_collection, DateTime.now())
          .limit(100)
          .snapshots()
          .map((s) => s.docs.map(ScheduleItem.fromDocument).toList());

  Future<void> _validateBatch(
    Transaction tx,
    String? batchId,
    String moduleId,
  ) async {
    if (batchId == null) return;
    validateDocumentId(batchId);
    final b = await tx.get(_db.collection('batches').doc(batchId));
    if (!b.exists ||
        b.data()?['isDeleted'] != false ||
        b.data()?['status'] != 'active' ||
        b.data()?['moduleType'] != moduleId) {
      throw StateError(
        'Batch tidak aktif, tidak tersedia, atau berbeda modul.',
      );
    }
  }

  Future<String> save({
    String? id,
    required String requestId,
    required String title,
    required String moduleId,
    required String scheduleType,
    required DateTime scheduledAt,
    String status = 'pending',
    required String note,
    required String userId,
    String? batchId,
    DateTime? expectedUpdatedAt,
  }) async {
    validateDocumentId(requestId);
    if (id != null) validateDocumentId(id);
    requireTrimmed(title, 'Judul');
    requireTrimmed(scheduleType, 'Jenis');
    requireOneOf(
      moduleId,
      FarmModules.values.map((m) => m.id).toSet(),
      'Modul',
    );
    if (status != 'pending') {
      throw StateError('Gunakan aksi checklist untuk menyelesaikan jadwal.');
    }
    final payload = jsonEncode([
      title.trim(),
      moduleId,
      scheduleType.trim(),
      scheduledAt.toUtc().toIso8601String(),
      note.trim(),
      userId,
      batchId,
    ]);
    final documentId = id ?? requestId;
    await runOperationalTransaction(_db, (tx) async {
      await authorizeOperations(_db, tx, userId);
      final ref = _collection.doc(documentId);
      final old = await tx.get(ref);
      if (id == null && old.exists) {
        if (old.data()?['creationPayload'] != payload) {
          throw StateError('Request ID sama dengan payload berbeda.');
        }
        return;
      }
      if (id != null) {
        if (!old.exists ||
            old.data()?['isDeleted'] != false ||
            old.data()?['status'] != 'pending' ||
            expectedUpdatedAt == null ||
            ScheduleItem.fromDocument(old).updatedAt != expectedUpdatedAt) {
          throw StateError(
            'Jadwal berubah atau sudah diselesaikan. Muat ulang.',
          );
        }
      }
      await _validateBatch(tx, batchId, moduleId);
      final now = FieldValue.serverTimestamp();
      final data = <String, dynamic>{
        'id': documentId,
        'title': title.trim(),
        'moduleType': moduleId,
        'type': scheduleType.trim(),
        'date': Timestamp.fromDate(scheduledAt),
        'status': 'pending',
        'notes': note.trim(),
        'batchId': batchId,
        'isDeleted': false,
        'updatedBy': userId,
        'updatedAt': now,
      };
      if (id == null) {
        data.addAll({
          'createdBy': userId,
          'createdAt': now,
          'creationPayload': payload,
        });
        tx.set(ref, data);
      } else {
        tx.update(ref, data);
      }
    });
    return documentId;
  }

  Future<void> updateStatus(
    String id,
    String status, {
    required String userId,
    required DateTime expectedUpdatedAt,
    String reason = '',
  }) async {
    requireOneOf(status, {'done', 'skipped'}, 'Status');
    await runOperationalTransaction(_db, (tx) async {
      await authorizeOperations(_db, tx, userId);
      final ref = _collection.doc(id);
      final doc = await tx.get(ref);
      if (!doc.exists || doc.data()?['isDeleted'] != false) {
        throw StateError('Jadwal tidak tersedia.');
      }
      final old = ScheduleItem.fromDocument(doc);
      // Identical tap is a no-op and preserves the first actor/time.
      if (old.status == status) return;
      if (old.status != 'pending' || old.updatedAt != expectedUpdatedAt) {
        throw StateError('Status jadwal telah berubah. Muat ulang.');
      }
      final now = FieldValue.serverTimestamp();
      tx.update(ref, {
        'status': status,
        'updatedBy': userId,
        'updatedAt': now,
        if (status == 'done') ...{'completedBy': userId, 'completedAt': now},
        if (status == 'skipped') ...{
          'skippedBy': userId,
          'skippedAt': now,
          'skipReason': reason.trim(),
        },
      });
    });
  }

  Future<void> delete(
    String id, {
    required String userId,
    required DateTime expectedUpdatedAt,
  }) async {
    await runOperationalTransaction(_db, (tx) async {
      final actor = await authorizeOperations(_db, tx, userId);
      if (!actor.isAdmin) throw StateError('Hanya admin yang dapat menghapus.');
      final ref = _collection.doc(id);
      final doc = await tx.get(ref);
      if (!doc.exists) throw StateError('Jadwal tidak tersedia.');
      if (doc.data()?['isDeleted'] == true) return;
      if (ScheduleItem.fromDocument(doc).updatedAt != expectedUpdatedAt ||
          doc.data()?['status'] != 'pending') {
        throw StateError('Jadwal berubah atau telah selesai. Muat ulang.');
      }
      tx.update(ref, {
        'isDeleted': true,
        'updatedBy': userId,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<List<ScheduleItem>> reminderCandidates(DateTime now) async {
    final result = await _collection
        .where('isDeleted', isEqualTo: false)
        .where('status', isEqualTo: 'pending')
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(now))
        .where(
          'date',
          isLessThan: Timestamp.fromDate(now.add(const Duration(days: 14))),
        )
        .orderBy('date')
        .limit(50)
        .get();
    return result.docs.map(ScheduleItem.fromDocument).toList();
  }
}
