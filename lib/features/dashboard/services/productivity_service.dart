import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/firestore_collections.dart';
import '../../../core/utils/legacy_firestore.dart';
import '../../../core/utils/sample_data_guard.dart';
import '../models/dashboard_filter.dart';
import '../models/productivity_point.dart';

class ProductivityService {
  ProductivityService({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  Future<ProductivityReport> load(
    DashboardFilter filter,
    String module,
    String? batchId,
  ) async {
    final snapshots = await Future.wait([
      completeCollection(_db, FirestoreCollections.logbooks),
      completeCollection(_db, FirestoreCollections.productionResults),
    ]);

    List<AnalyticsDocument> select(int index, String dateField) =>
        snapshots[index]
            .where((doc) => isOperationalRecord(doc.data()))
            .map((doc) => AnalyticsDocument(doc.id, legacyFields(doc.data())))
            .where(
              (doc) =>
                  doc.data['moduleType'] == module &&
                  (batchId == null || doc.data['batchId'] == batchId),
            )
            .where((doc) {
              final value = doc.data[dateField];
              if (value is! Timestamp) {
                throw const FormatException(
                  'Tanggal produktivitas tidak valid.',
                );
              }
              return filter.contains(value.toDate());
            })
            .toList();

    final logs = select(0, 'activityDate');
    final production = select(1, 'harvestDate');
    final selectedIds = <String>{
      ...logs.map((doc) => 'logbooks/${doc.id}'),
      ...production.map((doc) => 'production_results/${doc.id}'),
    };

    // Isolate only known reference conflicts. Never swallow permission errors,
    // malformed data, network errors, or other integrity failures.
    var productionIntegrityUncertain = false;
    try {
      await OperationalIntegrity(_db).check(
        snapshots
            .expand((collection) => collection)
            .where((doc) => selectedIds.contains(doc.reference.path)),
      );
    } on OperationalReferenceConflict {
      // Independent observations may still be shown, but the production
      // aggregate remains unverified while required references are invalid.
      productionIntegrityUncertain = true;
    }

    final parentIds = production
        .map((doc) => doc.data['logbookId'])
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    final parents = <String, Map<String, dynamic>>{};
    // A parent can be outside activityDate range: harvestDate is independent.
    for (var offset = 0; offset < parentIds.length; offset += 30) {
      final ids = parentIds.skip(offset).take(30).toList();
      final docs = await _db
          .collection(FirestoreCollections.logbooks)
          .where(FieldPath.documentId, whereIn: ids)
          .limit(30)
          .get(const GetOptions(source: Source.server));
      for (final doc in docs.docs) {
        parents[doc.id] = legacyFields(doc.data());
      }
    }

    return calculateProductivity(
      samplesExcluded: snapshots.any(
        (collection) => collection.any((doc) => isSeedOrigin(doc.data())),
      ),
      filter: filter,
      module: module,
      batchId: batchId,
      logs: logs,
      production: production,
      parents: parents,
      logsTruncated: false,
      productionTruncated: false,
      productionIntegrityUncertain: productionIntegrityUncertain,
    );
  }
}
