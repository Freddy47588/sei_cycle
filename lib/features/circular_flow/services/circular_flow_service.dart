import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/firestore_collections.dart';
import '../models/circular_flow.dart';

class CircularFlowService {
  CircularFlowService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection(FirestoreCollections.circularFlows);

  Future<List<CircularFlow>> getRecentFlows({int limit = 5}) async {
    final snapshot = await _collection
        .orderBy('flowDate', descending: true)
        .limit(limit)
        .get();
    return snapshot.docs.map(CircularFlow.fromDocument).toList();
  }

  Stream<List<CircularFlow>> streamRecentFlows({int limit = 5}) {
    return _collection
        .orderBy('flowDate', descending: true)
        .limit(limit)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs.map(CircularFlow.fromDocument).toList(),
        );
  }

  Future<void> seedDefaultFlows() async {
    final now = DateTime.now();
    final batch = _firestore.batch();
    for (final flow in defaultCircularFlows(now)) {
      batch.set(_collection.doc(flow.id), flow.toFirestore());
    }
    await batch.commit();
  }
}

List<CircularFlow> defaultCircularFlows(DateTime now) {
  final day = DateTime(now.year, now.month, now.day);
  return [
    CircularFlow(
      id: 'tanaman_to_maggot_bsf',
      sourceModuleType: 'tanaman',
      destinationModuleType: 'maggot_bsf',
      materialName: 'Sisa organik',
      quantity: 12,
      unit: 'kg',
      flowDate: day.subtract(const Duration(days: 1)),
      notes:
          'Sisa tanaman dan limbah organik digunakan sebagai bahan media maggot.',
      createdAt: now,
    ),
    CircularFlow(
      id: 'maggot_bsf_to_ayam_kampung',
      sourceModuleType: 'maggot_bsf',
      destinationModuleType: 'ayam_kampung',
      materialName: 'Maggot segar',
      quantity: 3,
      unit: 'kg',
      flowDate: day.subtract(const Duration(days: 2)),
      notes: 'Maggot digunakan sebagai sumber protein tambahan untuk ayam.',
      createdAt: now,
    ),
    CircularFlow(
      id: 'ayam_kampung_to_cacing_tanah',
      sourceModuleType: 'ayam_kampung',
      destinationModuleType: 'cacing_tanah',
      materialName: 'Limbah kandang',
      quantity: 18,
      unit: 'kg',
      flowDate: day.subtract(const Duration(days: 3)),
      notes: 'Limbah kandang diolah menjadi media dan pakan cacing.',
      createdAt: now,
    ),
    CircularFlow(
      id: 'cacing_tanah_to_tanaman',
      sourceModuleType: 'cacing_tanah',
      destinationModuleType: 'tanaman',
      materialName: 'Kascing',
      quantity: 20,
      unit: 'kg',
      flowDate: day.subtract(const Duration(days: 4)),
      notes: 'Kascing digunakan sebagai pupuk organik tanaman.',
      createdAt: now,
    ),
    CircularFlow(
      id: 'lele_to_tanaman',
      sourceModuleType: 'lele',
      destinationModuleType: 'tanaman',
      materialName: 'Air kolam kaya nutrisi',
      quantity: 80,
      unit: 'liter',
      flowDate: day.subtract(const Duration(days: 5)),
      notes: 'Air kolam dimanfaatkan untuk penyiraman dan nutrisi tanaman.',
      createdAt: now,
    ),
  ];
}
