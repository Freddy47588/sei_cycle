import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/firestore_page.dart';
import 'debug_diagnostics.dart';
import 'sample_data_guard.dart';

/// Aliases observed in the read-only production inventory, 17 October 2026.
/// This adapter never writes back, invents a business value, or changes an ID.
Map<String, dynamic> legacyFields(Map<String, dynamic> input) {
  final d = Map<String, dynamic>.from(input);
  const aliases = {
    'activityDate': 'activity_date',
    'activityType': 'activity_type',
    'moduleType': 'module_id',
    'createdBy': 'created_by',
    'updatedBy': 'updated_by',
    'createdAt': 'created_at',
    'updatedAt': 'updated_at',
    'isDeleted': 'is_deleted',
    'currentStock': 'current_stock',
    'minStock': 'min_stock',
    'isLowStock': 'is_low_stock',
    'isActive': 'is_active',
    'name': 'module_name',
    'type': 'module_type',
    'date': 'scheduled_at',
    'notes': 'note',
  };
  for (final e in aliases.entries) {
    if (!d.containsKey(e.key) && d.containsKey(e.value)) d[e.key] = d[e.value];
  }
  return d;
}

/// Exact module identities observed in legacy farm_modules, not guessed aliases.
String canonicalModuleId(String id) =>
    const {
      'module_ayam': 'ayam_kampung',
      'module_cacing': 'cacing_tanah',
      'module_lele': 'lele',
      'module_maggot': 'maggot_bsf',
      'module_tanaman': 'tanaman',
    }[id] ??
    id;

bool isOperationalRecord(Map<String, dynamic> data) {
  final d = legacyFields(data);
  if (d.containsKey('isDeleted') && d['isDeleted'] is! bool) {
    throw const FormatException('Penanda penghapusan tidak valid.');
  }
  return !isSeedOrigin(d) && d['isDeleted'] != true;
}

void requireReviewedProvenance(Map<String, dynamic> data) {
  final d = legacyFields(data);
  if (!isSeedOrigin(d) && hasSampleMarker(d)) {
    throw StateError(
      'Belum dapat dihitung: provenance bertanda simulasi perlu review pengelola.',
    );
  }
}

/// Document-ID pagination includes records without optional indexed fields.
/// The extra document proves completeness. Never return a partial total.
Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> completeCollection(
  FirebaseFirestore db,
  String collection, {
  int maximum = 500,
}) => diagnoseLoad('LegacyFirestore', '$collection.complete', () async {
  final docs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
  DocumentSnapshot<Map<String, dynamic>>? cursor;
  while (true) {
    final remaining = maximum + 1 - docs.length;
    final size = remaining.clamp(1, 100);
    Query<Map<String, dynamic>> q = db
        .collection(collection)
        .orderBy(FieldPath.documentId)
        .limit(size);
    if (cursor != null) q = q.startAfterDocument(cursor);
    final page = await q.get(const GetOptions(source: Source.server));
    docs.addAll(page.docs);
    if (docs.length > maximum) {
      throw StateError(
        'Belum dapat dihitung: sumber melampaui batas $maximum dokumen. Metadata kompatibilitas perlu ditinjau pengelola.',
      );
    }
    if (page.docs.length < size) return docs;
    cursor = page.docs.last;
  }
});

Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> operationalCollection(
  FirebaseFirestore db,
  String collection,
) async => (await completeCollection(
  db,
  collection,
)).where((d) => isOperationalRecord(d.data())).toList();

/// Bounded live reads observe every source, including legacy collections.
/// The sentinel prevents a bounded listener from masquerading as a full list.
Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
watchOperationalCollections(FirebaseFirestore db, List<String> collections) {
  late StreamController<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
  controller;
  final subscriptions =
      <StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>[];
  final loaded = <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
  controller = StreamController(
    onListen: () {
      for (final collection in collections) {
        subscriptions.add(
          db
              .collection(collection)
              .orderBy(FieldPath.documentId)
              .limit(501)
              .snapshots(includeMetadataChanges: true)
              .listen(
                (snapshot) {
                  if (snapshot.metadata.isFromCache) {
                    final previouslyVerified = loaded.containsKey(collection);
                    loaded.remove(collection);
                    if (previouslyVerified) {
                      controller.addError(
                        StateError(
                          'Data server belum terverifikasi. Periksa koneksi lalu coba lagi.',
                        ),
                      );
                    }
                    return;
                  }
                  if (snapshot.docs.length > 500) {
                    loaded.remove(collection);
                    controller.addError(
                      StateError(
                        'Batas baca terlampaui; daftar lengkap belum tersedia.',
                      ),
                    );
                    return;
                  }
                  try {
                    loaded[collection] = snapshot.docs
                        .where((d) => isOperationalRecord(d.data()))
                        .toList();
                    if (loaded.length == collections.length) {
                      controller.add(loaded.values.expand((d) => d).toList());
                    }
                  } catch (error, stack) {
                    loaded.remove(collection);
                    controller.addError(error, stack);
                  }
                },
                onError: (Object error, StackTrace stack) {
                  loaded.remove(collection);
                  controller.addError(error, stack);
                },
              ),
        );
      }
    },
    onCancel: () async {
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
    },
  );
  return controller.stream;
}

/// Pagination happens over the complete filtered set, so leading seed pages
/// cannot produce a false empty state. The cursor retains its collection path.
FirestorePage<T> compatibilityPage<T>(
  List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  T Function(QueryDocumentSnapshot<Map<String, dynamic>>) parse, {
  DocumentSnapshot<Map<String, dynamic>>? cursor,
  int limit = 20,
}) {
  final index = cursor == null
      ? -1
      : docs.indexWhere((d) => d.reference.path == cursor.reference.path);
  if (cursor != null && index < 0) {
    throw StateError('Data berubah. Muat ulang daftar sebelum melanjutkan.');
  }
  final remaining = docs.skip(index + 1).toList();
  final page = remaining.take(limit.clamp(1, 50)).toList();
  return FirestorePage(
    page.map(parse).toList(),
    page.lastOrNull,
    remaining.length > page.length,
  );
}

/// Check real-to-seed references without erasing either side. Cache is scoped
/// to this load only; do not assume a previous audit remains current.
class OperationalIntegrity {
  OperationalIntegrity(this.db);
  final FirebaseFirestore db;
  final _seen = <String>{};
  final _parents = <String, Future<DocumentSnapshot<Map<String, dynamic>>>>{};
  Future<void> check(
    Iterable<DocumentSnapshot<Map<String, dynamic>>> docs,
  ) async {
    for (final doc in docs) {
      if (!_seen.add(doc.reference.path)) continue;
      if (_seen.length > 1000) {
        throw StateError(
          'Belum dapat dihitung: batas verifikasi relasi tercapai.',
        );
      }
      final d = legacyFields(doc.data() ?? {});
      requireReviewedProvenance(d);
      if (doc.reference.path.split('/').first == 'logbooks') {
        final ledger = await db
            .collection('inventory_transactions')
            .where('logbookId', isEqualTo: doc.id)
            .limit(501)
            .get(const GetOptions(source: Source.server));
        if (ledger.docs.length > 500) {
          throw StateError(
            'Belum dapat dihitung: batas verifikasi ledger tercapai.',
          );
        }
        await check(ledger.docs.where((d) => isOperationalRecord(d.data())));
      }
      const refs = {
        'itemId': 'inventory',
        'inventoryItemId': 'inventory',
        'batchId': 'batches',
        'sourceBatchId': 'batches',
        'destinationBatchId': 'batches',
        'logbookId': 'logbooks',
        'saleId': 'sales',
        'inventoryTransactionId': 'inventory_transactions',
        'financeTransactionId': 'finance_transactions',
      };
      for (final ref in refs.entries) {
        final id = d[ref.key];
        if (id == null || id == '') continue;
        if (id is! String || id.contains('/')) {
          throw const FormatException('Referensi operasional tidak valid.');
        }
        final path = '${ref.value}/$id';
        final parent = await _parents.putIfAbsent(
          path,
          () => db
              .collection(ref.value)
              .doc(id)
              .get(const GetOptions(source: Source.server)),
        );
        if (!parent.exists || !isOperationalRecord(parent.data() ?? {})) {
          throw StateError(
            'Belum dapat dihitung: DATA INTEGRITY CONFLICT. Referensi operasional hilang, terhapus, atau berasal dari simulasi. Minta rekonsiliasi pengelola.',
          );
        }
        await check([parent]);
      }
    }
  }
}
