import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter/foundation.dart';

import '../../../core/constants/farm_modules.dart';
import '../../../core/constants/firestore_collections.dart';
import '../../../core/utils/firestore_validators.dart';
import '../../inventory/services/inventory_service.dart';
import '../models/logbook_entry.dart';
import '../models/logbook_form_spec.dart';
import '../models/logbook_page.dart';
import 'inventory_mapping.dart';
import '../../batches/services/batch_service.dart';
import '../../profile/models/app_user.dart';

class LogbookService {
  LogbookService({FirebaseFirestore? firestore, Uuid? uuid})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _uuid = uuid ?? const Uuid();

  final FirebaseFirestore _firestore;
  final Uuid _uuid;
  BatchService get batches => BatchService(firestore: _firestore);
  late final InventoryService _inventoryService = InventoryService(
    firestore: _firestore,
    uuid: _uuid,
  );

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection(FirestoreCollections.logbooks);

  Stream<List<LogbookEntry>> watchEntries({String? moduleId, DateTime? date}) {
    Query<Map<String, dynamic>> query = _collection.where(
      'isDeleted',
      isEqualTo: false,
    );

    if (moduleId != null) {
      query = query.where('moduleType', isEqualTo: moduleId);
    }

    if (date != null) {
      final start = DateTime(date.year, date.month, date.day);
      final end = start.add(const Duration(days: 1));
      query = query
          .where(
            'activityDate',
            isGreaterThanOrEqualTo: Timestamp.fromDate(start),
          )
          .where('activityDate', isLessThan: Timestamp.fromDate(end));
    }

    return query
        .orderBy('activityDate', descending: true)
        .limit(50)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs.map(LogbookEntry.fromDocument).toList(),
        );
  }

  Future<List<LogbookEntry>> getHistoryByModule(String moduleType) async {
    requireOneOf(
      moduleType,
      FarmModules.values.map((module) => module.id).toSet(),
      'moduleType',
    );
    final snapshot = await _collection
        .where('isDeleted', isEqualTo: false)
        .where('moduleType', isEqualTo: moduleType)
        .orderBy('activityDate', descending: true)
        .limit(20)
        .get();
    return snapshot.docs.map(LogbookEntry.fromDocument).toList();
  }

  Future<String> createDailyEntry({
    String? requestId,
    String? batchId,
    required String moduleType,
    required String title,
    required String activityType,
    required double? quantity,
    required String? unit,
    required String? notes,
    required Map<String, dynamic> details,
    required String userId,
  }) async {
    _validateEntry(
      moduleType: moduleType,
      title: title,
      activityType: activityType,
      userId: userId,
    );

    return createLogbookWithInventory(
      requestId: requestId,
      batchId: batchId,
      moduleType: moduleType,
      title: title,
      activityType: activityType,
      quantity: quantity,
      unit: unit,
      notes: notes,
      details: details,
      userId: userId,
    );
  }

  Future<List<InventoryStockWarning>> previewInventoryStockWarnings({
    required String moduleType,
    required Map<String, dynamic> details,
  }) {
    final actions = mapLogbookDetailsToInventoryActions(
      moduleType: moduleType,
      details: details,
      logbookId: 'preview',
    );
    return _inventoryService.previewNegativeStockWarnings(actions: actions);
  }

  Future<String> createLogbookWithInventory({
    String? requestId,
    String? batchId,
    required String moduleType,
    required String title,
    required String activityType,
    required double? quantity,
    required String? unit,
    required String? notes,
    required Map<String, dynamic> details,
    required String userId,
  }) async {
    _validateEntry(
      moduleType: moduleType,
      title: title,
      activityType: activityType,
      userId: userId,
    );

    validateLogbookDetails(moduleType, details);
    if (quantity != null && (!quantity.isFinite || quantity < 0)) {
      throw ArgumentError('Kuantitas tidak valid.');
    }
    if (batchId != null && (batchId.trim().isEmpty || batchId.contains('/'))) {
      throw ArgumentError('Batch tidak valid.');
    }
    final logbookId = requestId ?? _uuid.v4();
    requireTrimmed(logbookId, 'requestId');
    if (logbookId.contains('/')) throw ArgumentError('ID catatan tidak valid.');
    final actions = mapLogbookDetailsToInventoryActions(
      moduleType: moduleType,
      details: details,
      logbookId: logbookId,
    );
    final targets = await _inventoryService.resolveActionTargets(
      actions: actions,
      userId: userId,
    );
    final transactionIds = {
      for (final target in targets) target.action: _uuid.v4(),
    };
    final productionIds = {
      for (final target in targets)
        if (target.action.shouldCreateProductionResult)
          target.action: _uuid.v4(),
    };

    bool matchesRequest(Map<String, dynamic> data) =>
        data['batchId'] == batchId &&
        data['createdBy'] == userId &&
        data['moduleType'] == moduleType &&
        data['title'] == title.trim() &&
        data['activityType'] == activityType.trim() &&
        data['quantity'] == quantity &&
        data['unit'] == unit?.trim() &&
        data['isDeleted'] == false &&
        data['notes'] == (notes?.trim() ?? '') &&
        data['details'] is Map &&
        mapEquals(Map<String, dynamic>.from(data['details'] as Map), details);
    try {
      await _firestore.runTransaction((transaction) async {
        final existing = await transaction.get(_collection.doc(logbookId));
        if (existing.exists) {
          final data = existing.data()!;
          if (!matchesRequest(data)) {
            throw StateError(
              'ID permintaan sudah digunakan; muat catatan sebelum mencoba kembali.',
            );
          }
          return;
        }
        if (batchId != null) {
          final profile = await transaction.get(
            _firestore.collection('users').doc(userId),
          );
          if (!profile.exists ||
              !AppUser.fromDocument(profile).canManageLogbooks) {
            throw StateError('Tidak memiliki izin mencatat aktivitas batch.');
          }
          final batch = await transaction.get(
            _firestore.collection(FirestoreCollections.batches).doc(batchId),
          );
          final data = batch.data();
          if (!batch.exists ||
              data?['isDeleted'] != false ||
              data?['status'] != 'active' ||
              data?['moduleType'] != moduleType) {
            throw StateError(
              'Batch tidak tersedia, tidak aktif, atau berbeda modul.',
            );
          }
        }
        final inventorySnapshots =
            <InventoryActionTarget, DocumentSnapshot<Map<String, dynamic>>>{};
        final notificationSnapshots =
            <InventoryActionTarget, DocumentSnapshot<Map<String, dynamic>>>{};

        for (final target in targets) {
          inventorySnapshots[target] = await transaction.get(target.reference);
          notificationSnapshots[target] = await transaction.get(
            _lowStockNotificationRef(target.reference.id, userId),
          );
        }

        final now = FieldValue.serverTimestamp();
        transaction.set(_collection.doc(logbookId), {
          'id': logbookId,
          'batchId': ?batchId,
          'title': title.trim(),
          'moduleType': moduleType,
          'activityDate': Timestamp.fromDate(DateTime.now()),
          'activityType': activityType.trim(),
          'quantity': quantity,
          'unit': unit?.trim(),
          'status': 'completed',
          'notes': notes?.trim() ?? '',
          'details': details,
          'createdBy': userId,
          'updatedBy': userId,
          'createdAt': now,
          'updatedAt': now,
          'isDeleted': false,
        });

        for (final target in targets) {
          final snapshot = inventorySnapshots[target]!;
          _inventoryService.applyInventoryActionInTransaction(
            transaction: transaction,
            target: target,
            snapshot: snapshot,
            logbookId: logbookId,
            transactionId: transactionIds[target.action]!,
            batchId: batchId,
            userId: userId,
          );

          final action = target.action;
          if (action.shouldCreateProductionResult) {
            final id = productionIds[action]!;
            transaction.set(
              _firestore
                  .collection(FirestoreCollections.productionResults)
                  .doc(id),
              {
                'id': id,
                'logbookId': logbookId,
                'batchId': ?batchId,
                'moduleType': moduleType,
                'productName': action.productName ?? action.itemName,
                'quantity': action.quantity,
                'unit': action.unit,
                'qualityStatus': 'normal',
                'harvestDate': now,
                'notes': action.notes,
                'createdBy': userId,
                'createdAt': now,
              },
            );
          }

          final data = snapshot.exists ? snapshot.data() : target.existingData;
          final beforeStock = (data?['currentStock'] as num?)?.toDouble() ?? 0;
          final minStock = (data?['minStock'] as num?)?.toDouble() ?? 0;
          final afterStock = action.isOut
              ? beforeStock - action.quantity
              : beforeStock + action.quantity;
          if (afterStock <= minStock) {
            final notificationRef = _lowStockNotificationRef(
              target.reference.id,
              userId,
            );
            final notification = notificationSnapshots[target]!;
            final notificationData = notification.data();
            final shouldCreateNotification =
                !notification.exists ||
                notificationData?['isDeleted'] == true ||
                notificationData?['isRead'] == true;
            if (shouldCreateNotification) {
              transaction.set(notificationRef, {
                'id': notificationRef.id,
                'title': 'Stok ${action.itemName} rendah',
                'body':
                    'Stok ${action.itemName} menipis. Sisa ${_number(afterStock)} ${action.unit}.',
                'type': 'low_stock',
                'targetRole': 'admin',
                'userId': userId,
                'relatedCollection': FirestoreCollections.inventory,
                'relatedId': target.reference.id,
                'isRead': false,
                'createdAt': now,
                'isDeleted': false,
              }, SetOptions(merge: true));
            }
          }
        }
      });
    } on FirebaseException catch (error) {
      if (![
        'permission-denied',
        'aborted',
        'unavailable',
      ].contains(error.code)) {
        rethrow;
      }
      // A concurrent request may have committed before this transaction was
      // rejected. Verify the exact payload on the server before reporting success.
      final committed = await _collection
          .doc(logbookId)
          .get(const GetOptions(source: Source.server));
      if (!committed.exists || !matchesRequest(committed.data()!)) rethrow;
    }
    return logbookId;
  }

  DocumentReference<Map<String, dynamic>> _lowStockNotificationRef(
    String itemId,
    String userId,
  ) {
    return _firestore
        .collection(FirestoreCollections.notifications)
        .doc('low_stock_${userId}_$itemId');
  }

  Future<void> save({
    String? id,
    required String moduleId,
    required String activityType,
    required DateTime activityDate,
    required double quantity,
    required String unit,
    required String condition,
    required String note,
    required String userId,
  }) async {
    if (id != null) {
      throw UnsupportedError(
        'Gunakan edit catatan deskriptif; koreksi stok terpisah.',
      );
    }
    _validateEntry(
      moduleType: moduleId,
      title: activityType,
      activityType: activityType,
      userId: userId,
    );
    requirePositive(quantity, 'quantity');
    requireTrimmed(unit, 'unit');

    final documentId = id ?? _uuid.v4();
    final now = FieldValue.serverTimestamp();
    final data = <String, dynamic>{
      'id': documentId,
      'title': activityType.trim(),
      'moduleType': moduleId,
      'activityDate': Timestamp.fromDate(activityDate),
      'activityType': activityType.trim(),
      'quantity': quantity,
      'unit': unit.trim(),
      'status': condition.trim().isEmpty ? 'completed' : condition.trim(),
      'notes': note.trim(),
      'details': <String, dynamic>{
        'quantity': quantity,
        'unit': unit.trim(),
        'condition': condition.trim(),
      },
      'updatedBy': userId,
      'updatedAt': now,
      'isDeleted': false,
    };
    if (id == null) {
      data['createdBy'] = userId;
      data['createdAt'] = now;
    }
    await _collection.doc(documentId).set(data, SetOptions(merge: true));
  }

  Future<void> softDelete(String id, {required String userId}) async {
    throw UnsupportedError(
      'Pembatalan belum tersedia: perlu koreksi stok dan produksi secara atomik.',
    );
  }

  Future<LogbookPage> getPage({
    required LogbookFilter filter,
    DocumentSnapshot<Map<String, dynamic>>? cursor,
  }) async {
    Query<Map<String, dynamic>> query = _collection.where(
      'isDeleted',
      isEqualTo: false,
    );
    if (filter.batchId != null) {
      query = query.where('batchId', isEqualTo: filter.batchId);
    }
    if (filter.moduleId != null) {
      query = query.where('moduleType', isEqualTo: filter.moduleId);
    }
    if (filter.start != null) {
      query = query.where(
        'activityDate',
        isGreaterThanOrEqualTo: Timestamp.fromDate(filter.start!),
      );
    }
    if (filter.endExclusive != null) {
      query = query.where(
        'activityDate',
        isLessThan: Timestamp.fromDate(filter.endExclusive!),
      );
    }
    query = query
        .orderBy('activityDate', descending: filter.newestFirst)
        .limit(20);
    if (cursor != null) query = query.startAfterDocument(cursor);
    final result = await query.get();
    return LogbookPage(
      entries: result.docs.map(LogbookEntry.fromDocument).toList(),
      cursor: result.docs.lastOrNull,
      hasMore: result.docs.length == 20,
    );
  }

  Future<LogbookEntry?> getEntry(String id) async {
    final doc = await _collection.doc(id).get();
    return doc.exists ? LogbookEntry.fromDocument(doc) : null;
  }

  Future<LogbookLinks> getLinks(String id) async {
    final results = await Future.wait([
      _firestore
          .collection(FirestoreCollections.inventoryTransactions)
          .where('logbookId', isEqualTo: id)
          .limit(50)
          .get(),
      _firestore
          .collection(FirestoreCollections.productionResults)
          .where('logbookId', isEqualTo: id)
          .limit(50)
          .get(),
    ]);
    return LogbookLinks(
      inventory: results[0].docs.map((d) => d.data()).toList(),
      production: results[1].docs.map((d) => d.data()).toList(),
    );
  }

  Future<void> updateNotes(
    String id, {
    required String notes,
    required String userId,
    required DateTime expectedUpdatedAt,
  }) async {
    requireTrimmed(userId, 'userId');
    final auditRef = _collection.doc(id).collection('note_edits').doc();
    await _firestore.runTransaction((tx) async {
      final doc = await tx.get(_collection.doc(id));
      if (!doc.exists || doc.data()?['isDeleted'] == true) {
        throw StateError('Catatan tidak tersedia.');
      }
      final entry = LogbookEntry.fromDocument(doc);
      if (entry.updatedAt != expectedUpdatedAt) {
        throw StateError('Catatan berubah. Muat ulang sebelum mengedit.');
      }
      final now = FieldValue.serverTimestamp();
      tx.set(auditRef, {
        'before': entry.note,
        'after': notes.trim(),
        'editedBy': userId,
        'editedAt': now,
      });
      tx.update(doc.reference, {
        'notes': notes.trim(),
        'updatedBy': userId,
        'updatedAt': now,
        'lastNoteEditId': auditRef.id,
      });
    });
  }

  void _validateEntry({
    required String moduleType,
    required String title,
    required String activityType,
    required String userId,
  }) {
    requireOneOf(
      moduleType,
      FarmModules.values.map((module) => module.id).toSet(),
      'moduleType',
    );
    requireTrimmed(title, 'title');
    requireTrimmed(activityType, 'activityType');
    requireTrimmed(userId, 'userId');
  }
}

String _number(double value) => value == value.roundToDouble()
    ? value.toStringAsFixed(0)
    : value.toStringAsFixed(1);
