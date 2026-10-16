import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

import '../../../core/constants/firestore_collections.dart';
import '../../../core/utils/firestore_validators.dart';
import '../../logbook/services/inventory_mapping.dart';
import '../models/inventory_item.dart';

class InventoryService {
  InventoryService({FirebaseFirestore? firestore, Uuid? uuid})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _uuid = uuid ?? const Uuid();

  final FirebaseFirestore _firestore;
  final Uuid _uuid;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection(FirestoreCollections.inventory);

  Stream<List<InventoryItem>> watchItems() {
    return _collection
        .where('isDeleted', isEqualTo: false)
        .orderBy('isLowStock', descending: true)
        .orderBy('name')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs.map(InventoryItem.fromDocument).toList(),
        );
  }

  Future<void> save({
    String? id,
    required String name,
    String? itemKey,
    String? moduleType,
    required String category,
    required String unit,
    required double currentStock,
    required double minStock,
    required String userId,
  }) async {
    _validateSave(
      name: name,
      category: category,
      unit: unit,
      currentStock: currentStock,
      minStock: minStock,
      userId: userId,
    );

    final documentId = id ?? _uuid.v4();
    final now = FieldValue.serverTimestamp();
    final data = <String, dynamic>{
      'id': documentId,
      'name': name.trim(),
      'itemKey': (itemKey == null || itemKey.trim().isEmpty)
          ? _itemKeyFromName(name)
          : itemKey.trim(),
      'moduleType': moduleType?.trim() ?? '',
      'category': category.trim(),
      'unit': unit.trim(),
      'currentStock': currentStock,
      'minStock': minStock,
      'isLowStock': currentStock <= minStock,
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

  Future<InventoryItem> getOrCreateInventoryItemByKey({
    required String itemKey,
    required String itemName,
    required String unit,
    String? moduleType,
    String? category,
    required String userId,
  }) async {
    requireTrimmed(itemKey, 'itemKey');
    requireTrimmed(itemName, 'itemName');
    requireTrimmed(unit, 'unit');
    requireTrimmed(userId, 'userId');

    final existing = await _findByItemKey(itemKey);
    if (existing != null) return InventoryItem.fromDocument(existing);

    final documentId = _uuid.v4();
    final now = FieldValue.serverTimestamp();
    await _collection.doc(documentId).set({
      'id': documentId,
      'name': itemName.trim(),
      'itemKey': itemKey.trim(),
      'moduleType': moduleType?.trim() ?? '',
      'category': (category == null || category.trim().isEmpty)
          ? 'operasional'
          : category.trim(),
      'unit': unit.trim(),
      'currentStock': 0,
      'minStock': _defaultMinStock(itemKey),
      'isLowStock': true,
      'location': '',
      'createdBy': userId,
      'updatedBy': userId,
      'createdAt': now,
      'updatedAt': now,
      'isDeleted': false,
    });

    final created = await _collection.doc(documentId).get();
    return InventoryItem.fromDocument(created);
  }

  Future<List<InventoryActionTarget>> resolveActionTargets({
    required List<InventoryLogbookAction> actions,
    required String userId,
  }) async {
    final targets = <InventoryActionTarget>[];
    for (final action in actions) {
      final existing = await _findByItemKey(action.itemKey);
      final reference =
          existing?.reference ?? _collection.doc('logbook_${action.itemKey}');
      targets.add(
        InventoryActionTarget(
          action: action,
          reference: reference,
          existingData: existing?.data(),
          isNew: existing == null,
          userId: userId,
        ),
      );
    }
    return targets;
  }

  Future<List<InventoryStockWarning>> previewNegativeStockWarnings({
    required List<InventoryLogbookAction> actions,
  }) async {
    final warnings = <InventoryStockWarning>[];
    for (final action in actions.where((action) => action.isOut)) {
      final existing = await _findByItemKey(action.itemKey);
      final currentStock =
          (existing?.data()['currentStock'] as num?)?.toDouble() ?? 0;
      final afterStock = currentStock - action.quantity;
      if (afterStock < 0) {
        warnings.add(
          InventoryStockWarning(
            itemName: action.itemName,
            currentStock: currentStock,
            requestedQuantity: action.quantity,
            afterStock: afterStock,
            unit: action.unit,
          ),
        );
      }
    }
    return warnings;
  }

  void applyInventoryActionInTransaction({
    required Transaction transaction,
    required InventoryActionTarget target,
    required DocumentSnapshot<Map<String, dynamic>> snapshot,
    required String logbookId,
    required String transactionId,
    required String userId,
  }) {
    final action = target.action;
    if (!snapshot.exists && target.existingData != null) {
      throw StateError('Item stok telah dihapus. Muat ulang inventaris.');
    }
    if (snapshot.exists &&
        (snapshot.data()?['isDeleted'] == true ||
            snapshot.data()?['unit'] != action.unit)) {
      throw StateError(
        'Item stok tidak aktif atau satuannya berbeda. Periksa inventaris.',
      );
    }
    final now = FieldValue.serverTimestamp();
    final existing = snapshot.exists ? snapshot.data() : target.existingData;
    final beforeStock = (existing?['currentStock'] as num?)?.toDouble() ?? 0;
    final minStock =
        (existing?['minStock'] as num?)?.toDouble() ??
        _defaultMinStock(action.itemKey);
    final afterStock = action.isOut
        ? beforeStock - action.quantity
        : beforeStock + action.quantity;
    final itemId = existing?['id'] as String? ?? target.reference.id;
    final itemData = <String, dynamic>{
      'id': itemId,
      'name': action.itemName,
      'itemKey': action.itemKey,
      'moduleType': action.moduleType ?? existing?['moduleType'] ?? '',
      'category': action.category ?? existing?['category'] ?? 'operasional',
      'unit': action.unit,
      'currentStock': afterStock,
      'minStock': minStock,
      'isLowStock': afterStock <= minStock,
      'location': existing?['location'] ?? '',
      'updatedBy': userId,
      'updatedAt': now,
      'isDeleted': false,
      if (!snapshot.exists) ...{'createdBy': userId, 'createdAt': now},
    };

    transaction.set(target.reference, itemData, SetOptions(merge: true));
    transaction.set(
      _firestore
          .collection(FirestoreCollections.inventoryTransactions)
          .doc(transactionId),
      {
        'id': transactionId,
        'itemId': itemId,
        'itemName': action.itemName,
        'itemKey': action.itemKey,
        'moduleType': action.moduleType ?? '',
        'logbookId': logbookId,
        'type': action.type,
        'quantity': action.quantity,
        'unit': action.unit,
        'beforeStock': beforeStock,
        'afterStock': afterStock,
        'notes': afterStock < 0
            ? '${action.notes}. Stok menjadi minus.'
            : action.notes,
        'transactionDate': now,
        'createdBy': userId,
        'createdAt': now,
        'isReversed': false,
        'reversedAt': null,
        'reversedBy': '',
      },
    );
  }

  Future<void> rollbackInventoryTransactionsByLogbookId(
    String logbookId, {
    required String userId,
  }) async {
    requireTrimmed(logbookId, 'logbookId');
    requireTrimmed(userId, 'userId');
    final transactions = await _firestore
        .collection(FirestoreCollections.inventoryTransactions)
        .where('logbookId', isEqualTo: logbookId)
        .where('isReversed', isEqualTo: false)
        .get();
    if (transactions.docs.isEmpty) return;

    await _firestore.runTransaction((transaction) async {
      for (final document in transactions.docs) {
        final data = document.data();
        final itemId = data['itemId'] as String? ?? '';
        if (itemId.isEmpty) continue;
        final itemRef = _collection.doc(itemId);
        final item = await transaction.get(itemRef);
        final currentStock =
            (item.data()?['currentStock'] as num?)?.toDouble() ?? 0;
        final quantity = (data['quantity'] as num?)?.toDouble() ?? 0;
        final type = data['type'];
        final rolledBackStock = type == 'out'
            ? currentStock + quantity
            : currentStock - quantity;
        final minStock = (item.data()?['minStock'] as num?)?.toDouble() ?? 0;
        transaction.update(itemRef, {
          'currentStock': rolledBackStock,
          'isLowStock': rolledBackStock <= minStock,
          'updatedBy': userId,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        transaction.update(document.reference, {
          'isReversed': true,
          'reversedAt': FieldValue.serverTimestamp(),
          'reversedBy': userId,
        });
      }
    });
  }

  Future<void> delete(String id, {required String userId}) {
    requireTrimmed(id, 'id');
    requireTrimmed(userId, 'userId');
    return _collection.doc(id).update({
      'isDeleted': true,
      'updatedBy': userId,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  void _validateSave({
    required String name,
    required String category,
    required String unit,
    required double currentStock,
    required double minStock,
    required String userId,
  }) {
    requireTrimmed(name, 'name');
    requireTrimmed(category, 'category');
    requireTrimmed(unit, 'unit');
    requireNonNegative(currentStock, 'currentStock');
    requireNonNegative(minStock, 'minStock');
    requireTrimmed(userId, 'userId');
  }

  Future<QueryDocumentSnapshot<Map<String, dynamic>>?> _findByItemKey(
    String itemKey,
  ) async {
    final snapshot = await _collection
        .where('itemKey', isEqualTo: itemKey.trim())
        .where('isDeleted', isEqualTo: false)
        .limit(1)
        .get();
    if (snapshot.docs.isNotEmpty) return snapshot.docs.first;
    return null;
  }
}

class InventoryActionTarget {
  const InventoryActionTarget({
    required this.action,
    required this.reference,
    required this.existingData,
    required this.isNew,
    required this.userId,
  });

  final InventoryLogbookAction action;
  final DocumentReference<Map<String, dynamic>> reference;
  final Map<String, dynamic>? existingData;
  final bool isNew;
  final String userId;
}

class InventoryStockWarning {
  const InventoryStockWarning({
    required this.itemName,
    required this.currentStock,
    required this.requestedQuantity,
    required this.afterStock,
    required this.unit,
  });

  final String itemName;
  final double currentStock;
  final double requestedQuantity;
  final double afterStock;
  final String unit;
}

String _itemKeyFromName(String name) {
  return name
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');
}

double _defaultMinStock(String itemKey) {
  return switch (itemKey) {
    'dedak_padi' => 20,
    'talas_pepaya' => 10,
    'maggot_segar' => 5,
    'sampah_organik' => 20,
    'pakan_organik' => 15,
    'media_cacing' => 10,
    'kascing' => 5,
    'kascing_cair' => 5,
    'pakan_lele' => 20,
    _ => 0,
  };
}
