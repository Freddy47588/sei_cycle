import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/utils/operational_auth.dart';
import '../../../core/utils/firestore_validators.dart';

/// Corrections are absolute counts; quantity in the ledger is the absolute delta.
double calculateStock({
  required double before,
  required String type,
  required double value,
  bool allowNegative = false,
}) {
  validateStockNumber(before, nonNegative: false);
  validateStockNumber(value);
  if (!{'in', 'out', 'correction'}.contains(type) ||
      (type != 'correction' && value == 0)) {
    throw ArgumentError('Jenis atau jumlah mutasi tidak valid.');
  }
  final after = switch (type) {
    'in' => before + value,
    'out' => before - value,
    _ => value,
  };
  validateStockNumber(after, nonNegative: false);
  if (after < 0 && !allowNegative) {
    throw StateError(
      'Stok menjadi minus. Konfirmasi izin stok minus diperlukan.',
    );
  }
  return after;
}

class InventoryAdjustmentService {
  InventoryAdjustmentService({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;
  final FirebaseFirestore _db;

  Future<String> mutate({
    required String requestId,
    required String itemId,
    required String type,
    required double value,
    required String unit,
    required String notes,
    required String userId,
    String? batchId,
    bool allowNegative = false,
  }) async {
    validateDocumentId(requestId);
    validateDocumentId(itemId);
    requireTrimmed(unit, 'Satuan');
    requireTrimmed(notes, 'Alasan/catatan');
    validateStockNumber(value);
    final payload = <String, dynamic>{
      'itemId': itemId,
      'type': type,
      'requestedValue': value,
      'unit': unit.trim(),
      'notes': notes.trim(),
      'createdBy': userId,
      'batchId': batchId,
      'allowNegative': allowNegative,
    };
    final ref = _db.collection('inventory_transactions').doc(requestId);
    await runOperationalTransaction(_db, (tx) async {
      await authorizeOperations(_db, tx, userId);
      final prior = await tx.get(ref);
      if (prior.exists) {
        if (!payload.entries.every((e) => prior.data()?[e.key] == e.value) ||
            prior.data()?['source'] != 'manual') {
          throw StateError('Request ID sama dengan payload berbeda.');
        }
        return;
      }
      final itemRef = _db.collection('inventory').doc(itemId);
      final item = await tx.get(itemRef);
      final d = item.data();
      if (!item.exists ||
          d?['isDeleted'] != false ||
          d?['unit'] != unit.trim()) {
        throw StateError('Barang tidak aktif atau satuan tidak cocok.');
      }
      if (batchId != null) {
        validateDocumentId(batchId);
        final batch = await tx.get(_db.collection('batches').doc(batchId));
        if (!batch.exists ||
            batch.data()?['status'] != 'active' ||
            batch.data()?['isDeleted'] != false ||
            batch.data()?['moduleType'] != d?['moduleType']) {
          throw StateError('Batch tidak aktif atau berbeda modul.');
        }
      }
      final before = (d!['currentStock'] as num).toDouble();
      final after = calculateStock(
        before: before,
        type: type,
        value: value,
        allowNegative: allowNegative,
      );
      final now = FieldValue.serverTimestamp();
      tx.update(itemRef, {
        'currentStock': after,
        'isLowStock': after <= (d['minStock'] as num),
        'lastTransactionId': requestId,
        'updatedBy': userId,
        'updatedAt': now,
      });
      tx.set(ref, {
        ...payload,
        'id': requestId,
        'requestId': requestId,
        'itemName': d['name'],
        'itemKey': d['itemKey'],
        'moduleType': d['moduleType'],
        'source': 'manual',
        'quantity': type == 'correction' ? (after - before).abs() : value,
        'beforeStock': before,
        'afterStock': after,
        'transactionDate': now,
        'createdAt': now,
        'isReversed': false,
      });
    });
    return requestId;
  }
}
