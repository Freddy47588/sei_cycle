import 'package:cloud_firestore/cloud_firestore.dart';

String operationError(Object error) {
  if (error is FirebaseException) {
    return switch (error.code) {
      'permission-denied' =>
        'Akses ditolak. Periksa hak akses dan muat ulang data.',
      'unavailable' || 'deadline-exceeded' =>
        'Koneksi terputus. Coba lagi dengan isian yang sama.',
      'failed-precondition' =>
        'Data belum siap. Hubungi pengelola lalu coba lagi.',
      _ => 'Proses belum berhasil. Muat ulang atau coba lagi.',
    };
  }
  if (error is StateError) return error.message;
  if (error is ArgumentError) return '${error.message}';
  return 'Proses belum berhasil. Muat ulang atau coba lagi.';
}
