# Backend SeiCycle

SeiCycle saat ini tidak memakai backend Express, server Node.js, Cloud Functions,
atau Firebase Admin SDK. Backend aplikasi adalah Firebase client-side dari
Flutter dengan Firebase Authentication dan Cloud Firestore.

## Mode Spark-compatible

Layanan yang dipakai:

- Firebase Authentication untuk login email/password dan Google.
- Cloud Firestore untuk data operasional dan role pengguna.
- Firebase Cloud Messaging hanya untuk request permission dan mengambil token di
  client.
- Flutter local notification boleh ditambahkan untuk reminder lokal tanpa server.

Layanan yang tidak dipakai pada MVP:

- Firebase Storage.
- Cloud Functions.
- Backend Express/API/server hosting.
- Script seeder Node.js.
- Firebase Admin SDK dan `serviceAccountKey.json`.

## Hasil audit struktur

Audit pada 2026-06-27 menunjukkan struktur repo aktif berada di root Flutter
`sei_cycle/` dan tidak memiliki folder backend/server yang tracked:

- Tidak ada `backend/` atau `functions/`.
- Tidak ada `package.json`, `package-lock.json`, `server.js`, `app.js`, atau
  `index.js` untuk runtime Node.js.
- Tidak ada seeder Node.js atau dependency Express lama.
- Tidak ada `firebase_storage`, `cloud_functions`, atau package server backend
  di `pubspec.yaml`.
- `firebase.json` hanya mendaftarkan Firestore rules dan indexes.
- `.gitignore` menutup `.env`, `serviceAccountKey.json`, `*.pem`, `*.key`, dan
  `node_modules/`.

File lokal `android/app/google-services.json` dapat ada di mesin developer dan
sudah di-ignore. File itu adalah konfigurasi client Firebase, bukan admin
service account. Jangan commit file tersebut pada tahap MVP ini.

## Alur data

Flutter memakai Firebase SDK langsung:

```text
Flutter UI -> Firebase Auth -> Cloud Firestore -> firestore.rules
```

Semua operasi data harus melewati Firestore Rules. Role disimpan pada dokumen
`users/{uid}` dengan nilai brief `admin`, `operator_lapangan`, atau `operator_keuangan`. Legacy `operator` tetap dipetakan sebagai operator lapangan, sedangkan `mitra` dan `peserta_edukasi` tetap read-only untuk aksi mutasi. Semua user aktif dapat membuka tampilan semua fitur; tambah dan edit dibatasi per role, sedangkan hapus data utama dibatasi untuk admin.

## Seed data awal

Master `farm_modules` dibuat dari menu Profil admin melalui
`FarmModuleService.seedDefaults()`. Seeder ini berjalan dari Flutter client dan
memakai permission admin di Firestore Rules. Jangan menambahkan seeder Node.js
atau service account hanya untuk seed data MVP.

## Batasan backend

Perubahan backend harus tetap memenuhi batasan berikut kecuali project secara
sengaja naik ke rencana Blaze:

- Jangan menambahkan Storage upload.
- Jangan menambahkan Cloud Functions atau scheduler server-side.
- Jangan menambahkan Express, Nest, Fastify, atau server hosting lain.
- Jangan memakai Firebase Admin SDK di aplikasi client.
- Jangan commit credential, private key, atau service account.

Untuk kebutuhan file/media, gunakan URL eksternal pada collection edukasi sampai
ada keputusan billing. Untuk notifikasi, MVP hanya menyiapkan permission dan FCM
token dari client; pengiriman push server-side ditunda.
