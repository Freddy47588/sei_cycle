import '../../../core/utils/legacy_firestore.dart';
import '../../../core/utils/sample_data_guard.dart';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/firestore_collections.dart';
import '../../../core/constants/farm_modules.dart';
import '../../../core/utils/firestore_validators.dart';
import '../../logbook/services/inventory_mapping.dart';
import '../models/inventory_item.dart';
import '../../../core/models/firestore_page.dart';
import '../../../core/utils/operational_auth.dart';

class InventoryService {
  InventoryService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection(FirestoreCollections.inventory);

  Stream<List<InventoryItem>> watchItems() =>
      watchOperationalCollections(_firestore, [
        'inventory',
        'inventory_items',
      ]).map(
        (docs) =>
            docs.map(InventoryItem.fromDocument).toList()
              ..sort((a, b) => a.name.compareTo(b.name)),
      );

  /// One bounded listener per loaded page; never an unbounded collection scan.
  Stream<List<InventoryItem>> watchLoaded(List<InventoryItem> items) =>
      watchItems().map(
        (all) => all
            .where(
              (i) => items.any(
                (old) =>
                    old.id == i.id && old.legacyReadOnly == i.legacyReadOnly,
              ),
            )
            .toList(),
      );

  Future<FirestorePage<InventoryItem>> fetchPage({
    String? moduleType,
    String? category,
    DocumentSnapshot<Map<String, dynamic>>? cursor,
    int limit = 20,
  }) async {
    final sources = await Future.wait([
      operationalCollection(_firestore, 'inventory'),
      operationalCollection(_firestore, 'inventory_items'),
    ]);
    final docs =
        [...sources[0], ...sources[1]].where((d) {
          final item = InventoryItem.fromDocument(d);
          return (moduleType == null || item.moduleType == moduleType) &&
              (category == null || item.category == category);
        }).toList()..sort((a, b) {
          final order = InventoryItem.fromDocument(
            a,
          ).name.compareTo(InventoryItem.fromDocument(b).name);
          return order == 0
              ? a.reference.path.compareTo(b.reference.path)
              : order;
        });
    final ids = <String>{};
    for (final d in docs) {
      if (!ids.add(d.id)) {
        throw StateError(
          'Identitas barang lama ambigu; perlu ditinjau pengelola.',
        );
      }
    }
    return compatibilityPage(
      docs,
      InventoryItem.fromDocument,
      cursor: cursor,
      limit: limit,
    );
  }

  Future<String> createItem({
    required String requestId,
    bool isSellable = false,
    required String name,
    required String itemKey,
    required String moduleType,
    required String category,
    required String unit,
    required double minStock,
    required String location,
    double initialStock = 0,
    required String userId,
  }) async {
    validateDocumentId(requestId);
    requireOneOf(moduleType, {
      '',
      ...FarmModules.values.map((m) => m.id),
    }, 'Modul');
    for (final text in [name, itemKey, category, unit]) {
      requireTrimmed(text, 'Master barang');
    }
    validateStockNumber(minStock);
    validateStockNumber(initialStock);
    final payload = jsonEncode([
      isSellable,
      name.trim(),
      itemKey.trim(),
      moduleType,
      category.trim(),
      unit.trim(),
      minStock,
      location.trim(),
      initialStock,
      userId,
    ]);
    final ref = _collection.doc(requestId);
    await runOperationalTransaction(_firestore, (tx) async {
      final actor = await authorizeOperations(_firestore, tx, userId);
      if (isSellable && !actor.isAdmin) {
        throw StateError('Klasifikasi produk jual hanya oleh admin.');
      }
      final prior = await tx.get(ref);
      if (prior.exists) {
        if (prior.data()?['creationPayload'] != payload) {
          throw StateError('Request ID sama dengan payload berbeda.');
        }
        return;
      }
      final now = FieldValue.serverTimestamp();
      final historyId = 'opening_$requestId';
      tx.set(ref, {
        'id': requestId,
        'isSellable': isSellable,
        'productType': isSellable ? 'harvest' : 'operational',
        'name': name.trim(),
        'itemKey': itemKey.trim(),
        'moduleType': moduleType,
        'category': category.trim(),
        'unit': unit.trim(),
        'location': location.trim(),
        'minStock': minStock,
        'currentStock': initialStock,
        'isLowStock': initialStock <= minStock,
        'isDeleted': false,
        'createdBy': userId,
        'updatedBy': userId,
        'createdAt': now,
        'updatedAt': now,
        'creationPayload': payload,
        if (initialStock > 0) 'lastTransactionId': historyId,
      });
      if (initialStock > 0) {
        tx.set(_firestore.collection('inventory_transactions').doc(historyId), {
          'id': historyId,
          'requestId': requestId,
          'itemId': requestId,
          'itemName': name.trim(),
          'itemKey': itemKey.trim(),
          'moduleType': moduleType,
          'type': 'opening',
          'source': 'opening',
          'quantity': initialStock,
          'unit': unit.trim(),
          'beforeStock': 0,
          'afterStock': initialStock,
          'notes': 'Saldo awal',
          'transactionDate': now,
          'createdAt': now,
          'createdBy': userId,
          'isReversed': false,
        });
      }
    });
    return requestId;
  }

  Future<void> saveMetadata({
    required InventoryItem item,
    bool? isSellable,
    required String name,
    required String category,
    required String location,
    required double minStock,
    required String userId,
  }) async {
    requireTrimmed(name, 'Nama');
    requireTrimmed(category, 'Kategori');
    validateStockNumber(minStock);
    await runOperationalTransaction(_firestore, (tx) async {
      final actor = await authorizeOperations(_firestore, tx, userId);
      if (isSellable != null &&
          isSellable != item.isSellable &&
          !actor.isAdmin) {
        throw StateError('Klasifikasi produk jual hanya oleh admin.');
      }
      if (item.legacyReadOnly) {
        throw StateError(
          'Master barang lama hanya dapat dibaca. Hubungi pengelola untuk perubahan.',
        );
      }
      final ref = _collection.doc(item.id);
      final current = await tx.get(ref);
      requireOperationalData([current]);
      if (!current.exists ||
          current.data()?['isDeleted'] != false ||
          InventoryItem.fromDocument(current).updatedAt != item.updatedAt) {
        throw StateError('Barang telah berubah. Muat ulang sebelum mengedit.');
      }
      tx.update(ref, {
        'isSellable': ?isSellable,
        if (isSellable != null)
          'productType': isSellable ? 'harvest' : 'operational',
        'name': name.trim(),
        'category': category.trim(),
        'location': location.trim(),
        'minStock': minStock,
        'isLowStock': (current.data()!['currentStock'] as num) <= minStock,
        'updatedBy': userId,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
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
    String? batchId,
    required String userId,
  }) {
    requireOperationalData([snapshot]);
    if (hasSampleMarker(target.existingData ?? {})) throw SampleDataException();
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
    final itemId = target.reference.id;
    final itemData = <String, dynamic>{
      'id': itemId,
      'name': existing?['name'] ?? action.itemName,
      'itemKey': action.itemKey,
      'moduleType': existing?['moduleType'] ?? action.moduleType ?? '',
      'category': existing?['category'] ?? action.category ?? 'operasional',
      'unit': action.unit,
      'currentStock': afterStock,
      'lastTransactionId': transactionId,
      'minStock': minStock,
      'isLowStock': afterStock <= minStock,
      'location': existing?['location'] ?? '',
      'updatedBy': userId,
      'updatedAt': now,
      'isDeleted': false,
      if (!snapshot.exists) ...{'createdBy': userId, 'createdAt': now},
    };

    if (snapshot.exists) {
      transaction.update(target.reference, {
        'currentStock': afterStock,
        'lastTransactionId': transactionId,
        'isLowStock': afterStock <= minStock,
        'updatedBy': userId,
        'updatedAt': now,
      });
    } else {
      transaction.set(target.reference, itemData);
    }
    transaction.set(
      _firestore
          .collection(FirestoreCollections.inventoryTransactions)
          .doc(transactionId),
      {
        'id': transactionId,
        'itemId': itemId,
        'itemName': existing?['name'] ?? action.itemName,
        'itemKey': action.itemKey,
        'moduleType': action.moduleType ?? '',
        'logbookId': logbookId,
        'source': 'logbook',
        'requestId': logbookId,
        'batchId': ?batchId,
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
    throw UnsupportedError('Pembatalan dan rollback Logbook belum diaktifkan.');
  }

  Future<void> delete(String id, {required String userId}) async {
    await runOperationalTransaction(_firestore, (tx) async {
      final actor = await authorizeOperations(_firestore, tx, userId);
      if (!actor.isAdmin) throw StateError('Hanya admin yang dapat menghapus.');
      final ref = _collection.doc(id);
      final item = await tx.get(ref);
      requireOperationalData([item]);
      if (!item.exists || item.data()?['currentStock'] != 0) {
        throw StateError(
          'Kosongkan stok melalui mutasi sebelum menghapus master.',
        );
      }
      tx.update(ref, {
        'isDeleted': true,
        'updatedBy': userId,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<QueryDocumentSnapshot<Map<String, dynamic>>?> _findByItemKey(
    String itemKey,
  ) async {
    final matches = (await completeCollection(_firestore, 'inventory'))
        .where(
          (d) =>
              legacyFields(d.data())['itemKey'] == itemKey.trim() &&
              legacyFields(d.data())['isDeleted'] != true,
        )
        .toList();
    final real = matches.where((d) => isOperationalRecord(d.data())).toList();
    if (real.length > 1) {
      throw StateError(
        'Master barang operasional ganda; perlu ditinjau pengelola.',
      );
    }
    if (real.isNotEmpty) {
      requireOperationalData(real);
      return real.single;
    }
    if (matches.isNotEmpty) throw SampleDataException();
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
