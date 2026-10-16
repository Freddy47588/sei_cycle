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
    Query<Map<String, dynamic>> query(String collection, String field) {
      Query<Map<String, dynamic>> q = _db
          .collection(collection)
          .where('moduleType', isEqualTo: module)
          .where(
            field,
            isGreaterThanOrEqualTo: Timestamp.fromDate(filter.start),
          )
          .where(field, isLessThan: Timestamp.fromDate(filter.end));
      if (batchId != null) q = q.where('batchId', isEqualTo: batchId);
      if (collection == FirestoreCollections.logbooks) {
        q = q.where('isDeleted', isEqualTo: false);
      }
      return q.orderBy(field, descending: true).limit(501);
    }

    final snapshots = await Future.wait([
      query(FirestoreCollections.logbooks, 'activityDate').get(),
      query(FirestoreCollections.productionResults, 'harvestDate').get(),
    ]);
    final logs = snapshots[0].docs
        .take(500)
        .map((d) => AnalyticsDocument(d.id, d.data()))
        .toList();
    final production = snapshots[1].docs
        .take(500)
        .map((d) => AnalyticsDocument(d.id, d.data()))
        .toList();
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
          .get();
      for (final doc in docs.docs) {
        parents[doc.id] = doc.data();
      }
    }
    return calculateProductivity(
      filter: filter,
      module: module,
      batchId: batchId,
      logs: logs,
      production: production,
      parents: parents,
      logsTruncated: snapshots[0].docs.length > 500,
      productionTruncated: snapshots[1].docs.length > 500,
    );
  }
}
