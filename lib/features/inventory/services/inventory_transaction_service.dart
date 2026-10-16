import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/firestore_collections.dart';
import '../../../core/utils/firestore_validators.dart';
import '../models/inventory_transaction.dart';
import '../../../core/models/firestore_page.dart';

class InventoryTransactionService {
  InventoryTransactionService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection(FirestoreCollections.inventoryTransactions);

  Future<FirestorePage<HistoryReference>> references(
    String field, {
    DocumentSnapshot<Map<String, dynamic>>? cursor,
  }) async {
    final (collection, order, label) = switch (field) {
      'itemId' => ('inventory', 'name', 'name'),
      'batchId' => ('batches', 'createdAt', 'name'),
      'logbookId' => ('logbooks', 'activityDate', 'title'),
      _ => throw ArgumentError('Pilih barang, batch atau Logbook.'),
    };
    var q = _firestore
        .collection(collection)
        .where('isDeleted', isEqualTo: false)
        .orderBy(order, descending: order != 'name')
        .limit(20);
    if (cursor != null) q = q.startAfterDocument(cursor);
    final page = await q.get();
    return FirestorePage(
      page.docs
          .map(
            (d) => HistoryReference(
              d.id,
              '${d.data()[label] ?? d.id}${d.data()["code"] == null ? "" : " (${d.data()["code"]})"}',
            ),
          )
          .toList(),
      page.docs.lastOrNull,
      page.docs.length == 20,
    );
  }

  Future<List<InventoryTransaction>> getTransactionsByLogbookId(
    String logbookId,
  ) async {
    requireTrimmed(logbookId, 'logbookId');
    final snapshot = await _collection
        .where('logbookId', isEqualTo: logbookId)
        .orderBy('transactionDate', descending: true)
        .limit(50)
        .get();
    return snapshot.docs.map(InventoryTransaction.fromDocument).toList();
  }

  Future<List<InventoryTransaction>> getTransactionsByItemId(
    String itemId,
  ) async {
    requireTrimmed(itemId, 'itemId');
    final snapshot = await _collection
        .where('itemId', isEqualTo: itemId)
        .orderBy('transactionDate', descending: true)
        .limit(50)
        .get();
    return snapshot.docs.map(InventoryTransaction.fromDocument).toList();
  }

  Future<FirestorePage<InventoryTransaction>> fetchPage({
    String? field,
    String? value,
    DateTime? from,
    DateTime? until,
    DocumentSnapshot<Map<String, dynamic>>? cursor,
  }) async {
    Query<Map<String, dynamic>> q = _collection;
    if (field != null && value != null && value.isNotEmpty) {
      if (!{
        'itemId',
        'batchId',
        'logbookId',
        'moduleType',
        'type',
        'source',
      }.contains(field)) {
        throw ArgumentError('Filter histori tidak valid.');
      }
      q = q.where(field, isEqualTo: value);
    }
    if (from != null) {
      q = q.where(
        'transactionDate',
        isGreaterThanOrEqualTo: Timestamp.fromDate(from),
      );
    }
    if (until != null) {
      q = q.where('transactionDate', isLessThan: Timestamp.fromDate(until));
    }
    q = q.orderBy('transactionDate', descending: true).limit(20);
    if (cursor != null) q = q.startAfterDocument(cursor);
    final result = await q.get();
    return FirestorePage(
      result.docs.map(InventoryTransaction.fromDocument).toList(),
      result.docs.lastOrNull,
      result.docs.length == 20,
    );
  }

  Future<void> markTransactionsReversed(
    String logbookId, {
    required String userId,
  }) async {
    throw UnsupportedError('Pembalikan transaksi belum diaktifkan.');
  }
}

class HistoryReference {
  const HistoryReference(this.id, this.label);
  final String id, label;
}
