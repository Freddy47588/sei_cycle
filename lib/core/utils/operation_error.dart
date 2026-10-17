import 'dart:async';
import 'sample_data_guard.dart';
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

String dashboardLoadError(Object? error) {
  if (error is TimeoutException) {
    return 'Koneksi tidak tersedia atau terlalu lambat. Periksa jaringan, lalu coba lagi.';
  }
  if (error is SampleDataException) return error.message;
  if (error is StateError &&
      (error.message.startsWith('Lebih dari') ||
          error.message.startsWith('Belum dapat dihitung:'))) {
    return error.message;
  }
  if (error is FirebaseException) {
    return switch (error.code) {
      'permission-denied' =>
        'Akses data ditolak. Minta admin memeriksa role dan Security Rules, lalu coba lagi.',
      'unauthenticated' => 'Sesi berakhir. Masuk kembali untuk memuat data.',
      'unavailable' || 'deadline-exceeded' || 'network-request-failed' =>
        'Koneksi tidak tersedia. Periksa jaringan, lalu coba lagi.',
      'failed-precondition'
          when (error.message ?? '').toLowerCase().contains('index') =>
        'Indeks data belum siap. Minta admin meninjau indeks Firestore, lalu coba lagi.',
      'failed-precondition' =>
        'Data belum siap. Minta pengelola memeriksa konfigurasi, lalu coba lagi.',
      _ =>
        'Terjadi kesalahan saat memuat data. Coba lagi; hubungi pengelola jika berulang.',
    };
  }
  if (error is FormatException || error is ArgumentError) {
    return 'Data tidak valid. Bagian ini belum dapat dihitung. Minta pengelola memeriksa data.';
  }
  return 'Terjadi kesalahan saat memuat data. Coba lagi; hubungi pengelola jika berulang.';
}
