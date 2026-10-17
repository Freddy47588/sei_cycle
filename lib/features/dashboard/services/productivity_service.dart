import '../../../core/utils/legacy_firestore.dart';
import '../../../core/utils/sample_data_guard.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/constants/firestore_collections.dart';
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
    List<AnalyticsDocument> select(int index, String date) => snapshots[index]
        .where((d) => isOperationalRecord(d.data()))
        .map((d) => AnalyticsDocument(d.id, legacyFields(d.data())))
        .where(
          (d) =>
              d.data['moduleType'] == module &&
              (batchId == null || d.data['batchId'] == batchId),
        )
        .where((d) {
          if (d.data[date] is! Timestamp) {
            throw const FormatException('Tanggal produktivitas tidak valid.');
          }
          return filter.contains((d.data[date] as Timestamp).toDate());
        })
        .toList();
    final logs = select(0, 'activityDate');
    final production = select(1, 'harvestDate');
    final selectedIds = {
      ...logs.map((d) => 'logbooks/${d.id}'),
      ...production.map((d) => 'production_results/${d.id}'),
    };
    await OperationalIntegrity(_db).check(
      snapshots
          .expand((s) => s)
          .where((d) => selectedIds.contains(d.reference.path)),
    );
    final parentIds = production
        .map((d) => d.data['logbookId'])
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    final parents = <String, Map<String, dynamic>>{};
    // A parent can be outside activityDate range: harvestDate is independently recorded.
    for (var offset = 0; offset < parentIds.length; offset += 30) {
      final docs = await _db
          .collection(FirestoreCollections.logbooks)
          .where(
            FieldPath.documentId,
            whereIn: parentIds.skip(offset).take(30).toList(),
          )
          .limit(30)
          .get(const GetOptions(source: Source.server));
      for (final doc in docs.docs) {
        parents[doc.id] = legacyFields(doc.data());
      }
    }
    return calculateProductivity(
      samplesExcluded: snapshots.any(
        (s) => s.any((d) => isSeedOrigin(d.data())),
      ),
      filter: filter,
      module: module,
      batchId: batchId,
      logs: logs,
      production: production,
      parents: parents,
      logsTruncated: false,
      productionTruncated: false,
    );
  }
}
