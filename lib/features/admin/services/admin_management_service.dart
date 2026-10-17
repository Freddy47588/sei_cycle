import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';
import '../../../core/utils/audit_mode.dart';

const adminCategories = <String, String>{
  'users': 'Profil pengguna',
  'farm_modules': 'Modul kebun',
  'batches': 'Batch',
  'logbooks': 'Logbook',
  'inventory': 'Master inventaris',
  'inventory_items': 'Inventaris legacy',
  'inventory_transactions': 'Ledger inventaris',
  'production_results': 'Hasil produksi',
  'schedules': 'Jadwal',
  'finance_transactions': 'Transaksi keuangan',
  'finance_records': 'Keuangan legacy',
  'sales': 'Penjualan',
  'circular_flows': 'Aliran sirkular',
  'education_contents': 'Konten edukasi',
  'notifications': 'Notifikasi',
  'recommendations': 'Rekomendasi tersimpan',
  'report_metadata': 'Metadata laporan',
};

class AdminManagementService {
  AdminManagementService({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _db = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;
  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  Future<QuerySnapshot<Map<String, dynamic>>> page(
    String category, {
    DocumentSnapshot<Map<String, dynamic>>? after,
  }) {
    if (!adminCategories.containsKey(category)) {
      throw ArgumentError('Kategori tidak valid.');
    }
    Query<Map<String, dynamic>> query = _db
        .collection(category)
        .orderBy(FieldPath.documentId)
        .limit(20);
    if (after != null) query = query.startAfterDocument(after);
    return query.get(const GetOptions(source: Source.server));
  }

  Future<Map<String, dynamic>> submit({
    required String requestId,
    required String kind,
    required String targetPath,
    required String operation,
    required String reason,
    Map<String, dynamic> patch = const {},
    String previewId = '',
  }) async {
    requireWritesEnabled();
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw StateError('Silakan masuk kembali.');
    final ref = _db.collection('admin_requests').doc(requestId);
    await _db.runTransaction((tx) async {
      final old = await tx.get(ref);
      if (old.exists) {
        return; // Stable receipt: retry never submits a second mutation.
      }
      tx.set(ref, {
        'actorUid': uid,
        'kind': kind,
        'targetPath': targetPath,
        'operation': operation,
        'reason': reason,
        'patch': patch,
        'previewId': previewId,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
    final response = await ref
        .snapshots()
        .firstWhere(
          (s) =>
              s.exists &&
              !['pending', 'identity_pending'].contains(s.data()?['status']),
        )
        .timeout(
          const Duration(seconds: 30),
          onTimeout: () => throw StateError(
            'Layanan Admin belum merespons. Permintaan $requestId tetap tersimpan; periksa status sebelum mencoba ulang.',
          ),
        );
    final result = response.data()!;
    if (['failed', 'needs_review'].contains(result['status'])) {
      throw StateError(result['error']?.toString() ?? 'Operasi ditolak.');
    }
    return result;
  }

  static String newRequestId() => const Uuid().v4();
}
