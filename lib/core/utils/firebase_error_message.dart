import 'package:firebase_auth/firebase_auth.dart';

String firebaseErrorMessage(Object error) {
  if (error is FirebaseAuthException) {
    return switch (error.code) {
      'invalid-credential' ||
      'wrong-password' ||
      'user-not-found' => 'Email atau password tidak valid.',
      'invalid-email' => 'Format email tidak valid.',
      'email-already-in-use' => 'Email sudah digunakan.',
      'weak-password' => 'Password minimal 6 karakter.',
      'user-disabled' => 'Akun ini dinonaktifkan.',
      'network-request-failed' => 'Tidak dapat terhubung ke internet.',
      _ => error.message ?? 'Terjadi kesalahan autentikasi.',
    };
  }
  return error.toString().replaceFirst('Exception: ', '');
}
