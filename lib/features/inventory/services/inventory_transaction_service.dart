import '../../../core/utils/legacy_firestore.dart';
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
    final docs = await operationalCollection(_firestore, collection);
    docs.sort(
      (a, b) =>
          '${a.data()[order] ?? ''}'.compareTo('${b.data()[order] ?? ''}'),
    );
    return compatibilityPage(
      docs,
      (d) => HistoryReference(d.id, '${legacyFields(d.data())[label] ?? d.id}'),
      cursor: cursor,
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
    return snapshot.docs
        .where((d) => isOperationalRecord(d.data()))
        .map(InventoryTransaction.fromDocument)
        .toList();
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
    return snapshot.docs
        .where((d) => isOperationalRecord(d.data()))
        .map(InventoryTransaction.fromDocument)
        .toList();
  }

  Future<FirestorePage<InventoryTransaction>> fetchPage({
    String? field,
    String? value,
    DateTime? from,
    DateTime? until,
    DocumentSnapshot<Map<String, dynamic>>? cursor,
  }) async {
    if (field != null &&
        !{
          'itemId',
          'batchId',
          'logbookId',
          'moduleType',
          'type',
          'source',
        }.contains(field)) {
      throw ArgumentError('Filter histori tidak valid.');
    }
    final docs =
        (await operationalCollection(
            _firestore,
            'inventory_transactions',
          )).where((doc) {
            final d = doc.data();
            if (field != null &&
                value != null &&
                value.isNotEmpty &&
                d[field] != value) {
              return false;
            }
            if (d['transactionDate'] is! Timestamp) {
              throw const FormatException('Tanggal ledger tidak valid.');
            }
            final date = (d['transactionDate'] as Timestamp).toDate();
            return (from == null || !date.isBefore(from)) &&
                (until == null || date.isBefore(until));
          }).toList()
          ..sort((a, b) {
            final order = (b.data()['transactionDate'] as Timestamp).compareTo(
              a.data()['transactionDate'] as Timestamp,
            );
            return order == 0 ? a.id.compareTo(b.id) : order;
          });
    return compatibilityPage(
      docs,
      InventoryTransaction.fromDocument,
      cursor: cursor,
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
