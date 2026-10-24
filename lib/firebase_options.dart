// Android values come from android/app/google-services.json.
// Run `flutterfire configure` when adding Web, iOS, macOS, or desktop apps.

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError(
        'Firebase Web belum dikonfigurasi. Jalankan `flutterfire configure`.',
      );
    }

    return switch (defaultTargetPlatform) {
      TargetPlatform.android => android,
      _ => throw UnsupportedError(
        'Firebase untuk platform ini belum dikonfigurasi. '
        'Jalankan `flutterfire configure`.',
      ),
    };
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyA63XIrPCHczYkyVL5bR2oZHJCsduyjTjY',
    appId: '1:965319862638:android:0171fb543344d4907a797f',
    messagingSenderId: '965319862638',
    projectId: 'seicycle-kebun-sei',
  );

  const DefaultFirebaseOptions._();
}
