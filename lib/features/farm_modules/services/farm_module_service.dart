import '../../../core/utils/audit_mode.dart';
import '../../../core/utils/legacy_firestore.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/farm_modules.dart';
import '../../../core/constants/firestore_collections.dart';
import '../models/farm_module.dart';

class FarmModuleService {
  FarmModuleService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection(FirestoreCollections.farmModules);

  Stream<List<FarmModule>> watchActiveModules() {
    return watchOperationalCollections(_firestore, ['farm_modules']).map((
      docs,
    ) {
      final unique = <String, FarmModule>{};
      // Prefer canonical document IDs while retaining legacy-only modules.
      docs.sort((a, b) => a.id.compareTo(b.id));
      for (final doc in docs) {
        final module = FarmModule.fromDocument(doc);
        final key = canonicalModuleId(
          '${doc.data()['module_id'] ?? module.id}',
        );
        if (module.isActive) unique[key] = module;
      }
      return unique.values.toList()..sort((a, b) => a.name.compareTo(b.name));
    });
  }

  Future<void> seedDefaults() async {
    requireWritesEnabled();
    final batch = _firestore.batch();
    for (final module in FarmModules.values) {
      batch.set(_collection.doc(module.id), {
        'id': module.id,
        'name': module.name,
        'type': module.type,
        'description': module.description,
        'icon': module.icon,
        'color': module.color,
        'isActive': true,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
    await batch.commit();
  }
}
