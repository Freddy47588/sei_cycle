import '../../../core/utils/audit_mode.dart';
import '../../../core/utils/legacy_firestore.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

import '../../../core/constants/firestore_collections.dart';
import '../../../core/utils/firestore_validators.dart';
import '../../logbook/services/inventory_mapping.dart';
import '../models/production_result.dart';

class ProductionResultService {
  ProductionResultService({FirebaseFirestore? firestore, Uuid? uuid})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _uuid = uuid ?? const Uuid();

  final FirebaseFirestore _firestore;
  final Uuid _uuid;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection(FirestoreCollections.productionResults);

  Future<List<ProductionResult>> getRecentResults({int limit = 5}) async {
    final docs = await operationalCollection(_firestore, 'production_results');
    docs.sort(
      (a, b) => ProductionResult.fromDocument(
        b,
      ).harvestDate.compareTo(ProductionResult.fromDocument(a).harvestDate),
    );
    return docs.take(limit).map(ProductionResult.fromDocument).toList();
  }

  Future<List<ProductionResult>> getResultsByModule(String moduleType) async {
    requireTrimmed(moduleType, 'moduleType');
    return (await operationalCollection(_firestore, 'production_results'))
        .map(ProductionResult.fromDocument)
        .where((r) => r.moduleType == moduleType)
        .toList();
  }

  Future<void> createResult(ProductionResult result) {
    requireWritesEnabled();
    requireTrimmed(result.id, 'id');
    requireTrimmed(result.moduleType, 'moduleType');
    requireTrimmed(result.productName, 'productName');
    requirePositive(result.quantity, 'quantity');
    requireTrimmed(result.unit, 'unit');
    requireTrimmed(result.createdBy, 'createdBy');
    return _collection.doc(result.id).set({
      'id': result.id,
      'logbookId': result.logbookId,
      'moduleType': result.moduleType,
      'productName': result.productName,
      'quantity': result.quantity,
      'unit': result.unit,
      'qualityStatus': result.qualityStatus,
      'harvestDate': Timestamp.fromDate(result.harvestDate),
      'notes': result.notes,
      'createdBy': result.createdBy,
      'createdAt': Timestamp.fromDate(result.createdAt),
    });
  }

  Future<void> createProductionResultFromInventoryAction({
    required InventoryLogbookAction action,
    required String logbookId,
    required String userId,
  }) async {
    requireWritesEnabled();
    requireTrimmed(logbookId, 'logbookId');
    requireTrimmed(userId, 'userId');
    if (!action.shouldCreateProductionResult || action.quantity <= 0) return;
    final id = _uuid.v4();
    await _collection.doc(id).set({
      'id': id,
      'logbookId': logbookId,
      'moduleType': action.moduleType ?? '',
      'productName': action.productName ?? action.itemName,
      'quantity': action.quantity,
      'unit': action.unit,
      'qualityStatus': 'normal',
      'harvestDate': FieldValue.serverTimestamp(),
      'notes': action.notes,
      'createdBy': userId,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}
