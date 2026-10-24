import '../../../core/utils/legacy_firestore.dart';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/constants/farm_modules.dart';
import '../../../core/constants/firestore_collections.dart';
import '../../../core/models/firestore_page.dart';
import '../../../core/utils/operational_auth.dart';
import '../../../core/utils/sample_data_guard.dart';
import '../models/circular_flow.dart';

const flowUnits = ['kg', 'g', 'liter', 'ml', 'butir', 'ekor'];

class CircularFlowInput {
  const CircularFlowInput({
    required this.sourceModuleType,
    required this.destinationModuleType,
    required this.materialName,
    required this.quantity,
    required this.unit,
    required this.flowDate,
    this.notes = '',
    this.sourceBatchId,
    this.destinationBatchId,
    this.logbookId,
    this.inventoryTransactionId,
  });
  final String sourceModuleType,
      destinationModuleType,
      materialName,
      unit,
      notes;
  final String? sourceBatchId,
      destinationBatchId,
      logbookId,
      inventoryTransactionId;
  final double quantity;
  final DateTime flowDate;
  void validate() {
    final modules = FarmModules.values.map((m) => m.id).toSet();
    if (!modules.contains(sourceModuleType) ||
        !modules.contains(destinationModuleType) ||
        sourceModuleType == destinationModuleType ||
        materialName.trim().isEmpty ||
        !quantity.isFinite ||
        quantity <= 0 ||
        quantity > 1e12 ||
        !flowUnits.contains(unit) ||
        flowDate.year < 2020 ||
        flowDate.year > 2100) {
      throw ArgumentError(
        'Periksa modul sumber/tujuan yang berbeda, material, jumlah positif, satuan dan tanggal.',
      );
    }
    for (final id in [
      sourceBatchId,
      destinationBatchId,
      logbookId,
      inventoryTransactionId,
    ]) {
      if (id != null) validateDocumentId(id);
    }
  }

  Map<String, dynamic> fields() => {
    'sourceModuleType': sourceModuleType,
    'destinationModuleType': destinationModuleType,
    'materialName': materialName.trim(),
    'quantity': quantity,
    'unit': unit,
    'flowDate': Timestamp.fromDate(flowDate),
    'notes': notes.trim(),
    'sourceType': 'manual',
    if (sourceBatchId != null) 'sourceBatchId': sourceBatchId,
    if (destinationBatchId != null) 'destinationBatchId': destinationBatchId,
    if (logbookId != null) 'logbookId': logbookId,
    if (inventoryTransactionId != null)
      'inventoryTransactionId': inventoryTransactionId,
  };
  String payload(String uid) => jsonEncode([
    sourceModuleType,
    destinationModuleType,
    materialName.trim(),
    quantity,
    unit,
    flowDate.microsecondsSinceEpoch,
    notes.trim(),
    sourceBatchId,
    destinationBatchId,
    logbookId,
    inventoryTransactionId,
    uid,
  ]);
}

class CircularFlowService {
  CircularFlowService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;
  final FirebaseFirestore _firestore;
  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection(FirestoreCollections.circularFlows);

  Future<FirestorePage<FlowReference>> references(
    String kind, {
    DocumentSnapshot<Map<String, dynamic>>? cursor,
  }) async {
    final isLogbook = kind == 'logbooks';
    if (!isLogbook && kind != 'inventory_transactions') {
      throw ArgumentError('Jenis referensi tidak valid.');
    }
    final docs = await operationalCollection(_firestore, kind);
    docs.sort((a, b) => a.id.compareTo(b.id));
    return compatibilityPage(
      docs,
      (d) => FlowReference(
        d.id,
        '${legacyFields(d.data())[isLogbook ? "title" : "itemName"] ?? d.id}',
      ),
      cursor: cursor,
    );
  }

  Future<String> create({
    required String requestId,
    required String userId,
    required CircularFlowInput input,
  }) async {
    input.validate();
    validateDocumentId(requestId);
    final ref = _collection.doc(requestId);
    await runOperationalTransaction(_firestore, (tx) async {
      final actor = await authorizeOperations(_firestore, tx, userId);
      final old = await tx.get(ref);
      if (old.exists) {
        if (old.data()?['creationPayload'] != input.payload(userId)) {
          throw StateError('Request ID sama dengan payload berbeda.');
        }
        return;
      }
      for (final pair in [
        (input.sourceBatchId, input.sourceModuleType),
        (input.destinationBatchId, input.destinationModuleType),
      ]) {
        if (pair.$1 != null) {
          final b = await tx.get(_firestore.collection('batches').doc(pair.$1));
          requireOperationalData([b]);
          if (!b.exists ||
              b.data()?['isDeleted'] != false ||
              b.data()?['moduleType'] != pair.$2) {
            throw StateError('Batch tidak ditemukan atau berbeda modul.');
          }
        }
      }
      final modules = [input.sourceModuleType, input.destinationModuleType];
      if (input.logbookId != null) {
        final l = await tx.get(
          _firestore.collection('logbooks').doc(input.logbookId),
        );
        requireOperationalData([l]);
        if (!l.exists ||
            l.data()?['isDeleted'] != false ||
            !modules.contains(l.data()?['moduleType'])) {
          throw StateError('Referensi Logbook tidak sesuai.');
        }
      }
      if (input.inventoryTransactionId != null) {
        final l = await tx.get(
          _firestore
              .collection('inventory_transactions')
              .doc(input.inventoryTransactionId),
        );
        requireOperationalData([l]);
        if (!l.exists ||
            !modules.contains(l.data()?['moduleType']) ||
            l.data()?['unit'] != input.unit ||
            l.data()?['quantity'] != input.quantity ||
            l.data()?['isReversed'] == true) {
          throw StateError(
            'Referensi mutasi tidak sesuai jumlah, satuan atau modul.',
          );
        }
      }
      tx.set(ref, {
        ...input.fields(),
        'id': requestId,
        'requestId': requestId,
        'creationPayload': input.payload(userId),
        'createdByName': actor.name,
        'createdBy': userId,
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
    return requestId;
  }

  Query<Map<String, dynamic>> queryPeriod(
    DateTime start,
    DateTime end, {
    String? source,
    String? destination,
    String? material,
  }) {
    Query<Map<String, dynamic>> q = _collection
        .where('flowDate', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('flowDate', isLessThan: Timestamp.fromDate(end));
    if (source != null) q = q.where('sourceModuleType', isEqualTo: source);
    if (destination != null) {
      q = q.where('destinationModuleType', isEqualTo: destination);
    }
    if (material != null) q = q.where('materialName', isEqualTo: material);
    return q.orderBy('flowDate', descending: true);
  }

  Future<FirestorePage<CircularFlow>> fetchPage({
    required DateTime start,
    required DateTime end,
    String? source,
    String? destination,
    String? material,
    DocumentSnapshot<Map<String, dynamic>>? cursor,
  }) async {
    final docs =
        (await operationalCollection(_firestore, 'circular_flows')).where((
          doc,
        ) {
          final f = CircularFlow.fromDocument(doc);
          return f.isActual &&
              !f.flowDate.isBefore(start) &&
              f.flowDate.isBefore(end) &&
              (source == null || f.sourceModuleType == source) &&
              (destination == null || f.destinationModuleType == destination) &&
              (material == null || f.materialName == material);
        }).toList()..sort(
          (a, b) => CircularFlow.fromDocument(
            b,
          ).flowDate.compareTo(CircularFlow.fromDocument(a).flowDate),
        );
    return compatibilityPage(docs, CircularFlow.fromDocument, cursor: cursor);
  }

  Future<List<CircularFlow>> getRecentFlows({int limit = 5}) async {
    final docs = await operationalCollection(_firestore, 'circular_flows');
    final flows =
        docs.map(CircularFlow.fromDocument).where((f) => f.isActual).toList()
          ..sort((a, b) => b.flowDate.compareTo(a.flowDate));
    return flows.take(limit.clamp(1, 50)).toList();
  }

  Stream<List<CircularFlow>> streamRecentFlows({int limit = 5}) =>
      watchOperationalCollections(_firestore, ['circular_flows']).map((docs) {
        final flows =
            docs
                .map(CircularFlow.fromDocument)
                .where((f) => f.isActual)
                .toList()
              ..sort((a, b) => b.flowDate.compareTo(a.flowDate));
        return flows.take(limit.clamp(1, 50)).toList();
      });
}

class FlowReference {
  const FlowReference(this.id, this.label);
  final String id, label;
}
