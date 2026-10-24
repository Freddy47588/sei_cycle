import '../../../core/utils/legacy_firestore.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/constants/firestore_collections.dart';
import '../../../core/models/firestore_page.dart';
import '../../../core/utils/operational_auth.dart';
import '../../../core/utils/sample_data_guard.dart';
import '../../inventory/models/inventory_item.dart';
import '../../profile/models/app_user.dart';
import '../models/sale.dart';

class SalesService {
  SalesService({FirebaseFirestore? firestore})
    : db = firestore ?? FirebaseFirestore.instance;
  final FirebaseFirestore db;

  Future<FirestorePage<InventoryItem>> products({
    DocumentSnapshot<Map<String, dynamic>>? cursor,
  }) async {
    final docs =
        (await operationalCollection(db, 'inventory'))
            .where(
              (d) =>
                  d.data()['isSellable'] == true &&
                  d.data()['productType'] == 'harvest',
            )
            .toList()
          ..sort(
            (a, b) => InventoryItem.fromDocument(
              a,
            ).name.compareTo(InventoryItem.fromDocument(b).name),
          );
    return compatibilityPage(docs, InventoryItem.fromDocument, cursor: cursor);
  }

  Future<String> create({
    required String requestId,
    required String userId,
    required SaleInput input,
  }) async {
    validateDocumentId(requestId);
    input.validate();
    final ref = db.collection(FirestoreCollections.sales).doc(requestId);
    final ledgerId = 'sale_$requestId';
    await runOperationalTransaction(db, (tx) async {
      final actor = await tx.get(db.collection('users').doc(userId));
      if (!actor.exists || !AppUser.fromDocument(actor).canManageSales) {
        throw StateError('Penjualan hanya dapat dicatat admin aktif.');
      }
      final prior = await tx.get(ref);
      if (prior.exists) {
        if (prior.data()?['creationPayload'] != input.payload(userId)) {
          throw StateError('Request ID sama dengan payload berbeda.');
        }
        return;
      }
      final itemRef = db.collection('inventory').doc(input.inventoryItemId);
      final item = await tx.get(itemRef);
      final ledgerRef = db.collection('inventory_transactions').doc(ledgerId);
      final financeRef = db.collection('finance_transactions').doc(ledgerId);
      final ledger = await tx.get(ledgerRef);
      final finance = await tx.get(financeRef);
      final d = item.data();
      requireOperationalData([item]);
      if (!item.exists ||
          d?['isDeleted'] != false ||
          d?['isSellable'] != true ||
          d?['productType'] != 'harvest' ||
          d?['unit'] != input.unit.trim() ||
          ![
            'ayam_kampung',
            'maggot_bsf',
            'cacing_tanah',
            'tanaman',
            'lele',
          ].contains(d?['moduleType'])) {
        throw StateError(
          'Produk tidak aktif, belum layak dijual, atau satuan tidak sesuai.',
        );
      }
      if (ledger.exists || finance.exists) {
        throw StateError('Kode transaksi telah digunakan.');
      }
      final before = (d!['currentStock'] as num).toDouble();
      final quantity = input.quantityMilli / 1000;
      if (!before.isFinite || before < quantity) {
        throw StateError(
          'Stok tidak cukup. Muat ulang produk dan periksa jumlah.',
        );
      }
      final after = before - quantity;
      final now = FieldValue.serverTimestamp();
      tx.set(ref, {
        'createdByName': actor.data()?['name'] ?? userId,
        'id': requestId,
        'requestId': requestId,
        'saleNumber': 'S-$requestId',
        'creationPayload': input.payload(userId),
        'inventoryItemId': item.id,
        'productName': d['name'],
        'moduleType': d['moduleType'],
        'quantity': quantity,
        'quantityMilli': input.quantityMilli,
        'unit': d['unit'],
        'unitPrice': input.unitPrice,
        'totalAmount': input.totalAmount,
        'buyerName': input.buyerName.trim(),
        'paymentMethod': input.paymentMethod,
        'saleDate': Timestamp.fromDate(input.saleDate),
        'notes': input.notes.trim(),
        'status': 'paid',
        'inventoryTransactionId': ledgerId,
        'financeTransactionId': ledgerId,
        'createdBy': userId,
        'updatedBy': userId,
        'createdAt': now,
        'updatedAt': now,
      });
      tx.update(itemRef, {
        'currentStock': after,
        'isLowStock': after <= (d['minStock'] as num),
        'lastTransactionId': ledgerId,
        'updatedBy': userId,
        'updatedAt': now,
      });
      tx.set(ledgerRef, {
        'id': ledgerId,
        'requestId': requestId,
        'saleId': requestId,
        'itemId': item.id,
        'itemName': d['name'],
        'itemKey': d['itemKey'],
        'moduleType': d['moduleType'],
        'type': 'out',
        'source': 'sale',
        'quantity': quantity,
        'unit': d['unit'],
        'beforeStock': before,
        'afterStock': after,
        'notes': 'Penjualan S-$requestId',
        'transactionDate': now,
        'createdAt': now,
        'createdBy': userId,
        'isReversed': false,
      });
      tx.set(financeRef, {
        'id': ledgerId,
        'requestId': requestId,
        'saleId': requestId,
        'source': 'sale',
        'type': 'income',
        'category': 'Penjualan hasil panen',
        'amount': input.totalAmount,
        'date': Timestamp.fromDate(input.saleDate),
        'description': 'Penjualan S-$requestId',
        'notes': 'Penjualan S-$requestId',
        'paymentMethod': input.paymentMethod,
        'moduleType': d['moduleType'],
        'isDeleted': false,
        'version': 0,
        'createdBy': userId,
        'updatedBy': userId,
        'createdAt': now,
        'updatedAt': now,
      });
    });
    return requestId;
  }

  Query<Map<String, dynamic>> queryPeriod(
    DateTime start,
    DateTime end, {
    String? moduleType,
  }) {
    Query<Map<String, dynamic>> q = db
        .collection('sales')
        .where('saleDate', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('saleDate', isLessThan: Timestamp.fromDate(end));
    if (moduleType != null) q = q.where('moduleType', isEqualTo: moduleType);
    return q.orderBy('saleDate', descending: true);
  }

  Future<FirestorePage<Sale>> fetchPage({
    required DateTime start,
    required DateTime end,
    String? moduleType,
    DocumentSnapshot<Map<String, dynamic>>? cursor,
  }) async {
    final docs = await _saleDocuments(start, end, moduleType: moduleType);
    return compatibilityPage(docs, Sale.fromDocument, cursor: cursor);
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _saleDocuments(
    DateTime start,
    DateTime end, {
    String? moduleType,
  }) async {
    final docs =
        (await operationalCollection(db, 'sales')).where((d) {
          final date = d.data()['saleDate'];
          if (date is! Timestamp) {
            throw const FormatException('Tanggal penjualan tidak valid.');
          }
          return !date.toDate().isBefore(start) &&
              date.toDate().isBefore(end) &&
              (moduleType == null || d.data()['moduleType'] == moduleType);
        }).toList()..sort((a, b) {
          final order = (b.data()['saleDate'] as Timestamp).compareTo(
            a.data()['saleDate'] as Timestamp,
          );
          return order == 0 ? a.id.compareTo(b.id) : order;
        });
    await OperationalIntegrity(db).check(docs);
    return docs;
  }

  Future<List<Sale>> summary(DateTime start, DateTime end) async {
    return (await _saleDocuments(start, end)).map(Sale.fromDocument).toList();
  }
}
