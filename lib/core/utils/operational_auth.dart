import 'audit_mode.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../features/profile/models/app_user.dart';

Future<AppUser> authorizeOperations(
  FirebaseFirestore db,
  Transaction tx,
  String userId,
) async {
  final profile = await tx.get(db.collection('users').doc(userId));
  if (!profile.exists || !AppUser.fromDocument(profile).canManageLogbooks) {
    throw StateError('Tidak memiliki izin operasional.');
  }
  return AppUser.fromDocument(profile);
}

void validateDocumentId(String id) {
  if (id.trim().isEmpty || id.contains('/') || id.length > 150) {
    throw ArgumentError('ID permintaan tidak valid.');
  }
}

void validateStockNumber(double value, {bool nonNegative = true}) {
  if (!value.isFinite || value.abs() > 1e12 || (nonNegative && value < 0)) {
    throw ArgumentError(
      'Jumlah harus berupa angka valid (maksimal 1 triliun).',
    );
  }
}

/// A competing commit can make a getAfter/before-stock check reject a stale
/// attempt before Firestore reports an optimistic concurrency abort. Every
/// attempt re-reads current documents; stable request IDs make replay harmless.
Future<T> runOperationalTransaction<T>(
  FirebaseFirestore db,
  TransactionHandler<T> body,
) async {
  requireWritesEnabled();
  for (var attempt = 0; ; attempt++) {
    try {
      return await db.runTransaction(body);
    } on FirebaseException catch (e) {
      if (attempt >= 2 || !{'permission-denied', 'aborted'}.contains(e.code)) {
        rethrow;
      }
    }
  }
}
