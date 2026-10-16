# SeiCycle — Kebun Sei

Aplikasi **Flutter dan Dart** untuk operasional pertanian dan peternakan terintegrasi Kebun Sei: Ayam, Maggot BSF, Cacing Tanah, Tanaman, dan Lele.

SeiCycle menggunakan **Firebase Authentication** untuk autentikasi dan **Cloud Firestore sebagai database aplikasi**. Akses data langsung dari Flutter dilindungi Firestore Security Rules.

## Fitur yang tersedia

- Login email/password dan Google, registrasi, profil, serta role pengguna.
- Dashboard ringkasan modul, logbook, stok rendah, jadwal, aktivitas, dan keuangan sesuai hak akses. Error dan data kosong tidak diganti angka contoh.
- Form Logbook original lima modul, simpan dengan perlindungan permintaan berulang, dan akses langsung ke catatan baru.
- **Daftar Logbook** dengan pencarian pada catatan yang sudah dimuat, filter modul/tanggal, urutan terbaru/terlama, serta pagination 20 catatan.
- **Detail Logbook** dari dokumen aktual, rincian bersatuan, relasi inventaris/produksi, dan edit catatan tambahan dengan audit trail untuk admin/operator lapangan. Koreksi kuantitas serta pembatalan belum diaktifkan.
- Inventaris, jadwal, keuangan, rekomendasi berbasis aturan, dan laporan PDF/Excel.
- Katalog edukasi artikel, SOP, serta video dari teks/URL eksternal; thumbnail dan gambar lokal sebagai fallback. Pembaca detail lengkap dikembangkan pada Phase 07.
- Notifikasi dalam aplikasi melalui inbox Firestore dan pengingat lokal. FCM saat ini terbatas pada permission/token client; pengiriman push terjadwal dari server belum tersedia.
- Pengelolaan data admin yang sudah tersedia. Data sampel hanya dibuat melalui tindakan admin manual; pengujian UI tidak melakukan seed database.

Empat menu utama: **Dashboard, Logbook, Edukasi, Notifikasi**. Fitur tambahan di mobile tersedia melalui **Lainnya**. Sidebar tampil mulai lebar 768 px mengikuti shell asli `main`.

## Role dan akses UI

| Role | Akses |
| --- | --- |
| `admin` | Seluruh menu dan pengelolaan sesuai kemampuan fitur |
| `operator_lapangan` | Operasional, inventaris, jadwal, edukasi, notifikasi, rekomendasi operasional, laporan operasional/inventaris, profil |
| `operator_keuangan` | Seluruh menu; pengelolaan keuangan; form Logbook dapat dibaca tetapi tombol simpan nonaktif |
| `operator` | Role lama dipetakan ke `operator_lapangan` |
| `mitra` / `peserta_edukasi` | Role lama tetap dapat membaca modul nonkeuangan |

Keuangan dan laporan keuangan pada UI dibatasi ke admin/operator keuangan aktif. Pembatasan UI tidak menggantikan Firestore Security Rules. Rules yang diwarisi masih mengizinkan pembacaan transaksi oleh semua pengguna aktif; evaluasi penyempitan rules memerlukan pekerjaan keamanan terpisah. Phase 01 tidak mengubah rules.

Akun baru memakai `operator_lapangan`. Pengelola berwenang mengatur role pada `users/{uid}`. Pastikan akun aktif melalui `isActive`/`is_active`.

## Alur Logbook

**Form ? Simpan Catatan ? Lihat Catatan ? Detail**, atau buka **Daftar Logbook** dari form. Filter awal mengikuti modul yang sedang digunakan. Input tetap terlihat setelah simpan; tombol simpan nonaktif sampai isian diubah. Kegagalan simpan mempertahankan input dan ID permintaan untuk retry.

Pencarian judul/catatan memakai debounce 350 ms dan hanya mencakup halaman yang sudah dimuat. Gunakan **Muat berikutnya** untuk memperluas cakupan. Detail dapat dimuat ulang dari Cloud Firestore.

Perubahan catatan tambahan tidak mengubah stok atau hasil produksi. Pembatalan/penghapusan serta koreksi kuantitas memerlukan mekanisme koreksi terintegrasi dan belum tersedia. Rules Phase 02 harus diterapkan oleh pengelola sebelum menggunakan edit dengan audit trail; pekerjaan ini tidak melakukan deployment produksi. Lihat [dokumentasi Phase 02](docs/PHASE_02_LOGBOOK_MANAGEMENT.md) untuk batas mapping dan keamanan data.

## Manajemen Batch Budidaya

Batch adalah identitas kelompok atau siklus untuk **Ayam, Maggot BSF, Cacing Tanah, Tanaman, dan Lele**. Modul dan form Logbook original tetap digunakan; tidak ada menu utama tambahan.

1. Buka **Logbook > Kelola Batch > Tambah Batch**. Isi modul, nama, kode unik, lokasi dan tanggal mulai. Jumlah awal beserta unit, komoditas, estimasi panen dan catatan bersifat opsional.
2. Batch baru **Direncanakan**. Buka Detail Batch dan pilih **Ubah ke Aktif** untuk mulai mencatat aktivitas.
3. Pada form Logbook modul terkait, tekan **Pilih batch ... yang aktif**, pilih batch secara eksplisit, lalu **Simpan Catatan**. **Tanpa Batch** tersedia untuk aktivitas umum lintas siklus. Catatan lama berlabel **Belum terhubung ke batch**; aplikasi tidak menebak relasi.
4. Buka Detail Batch untuk identitas, metadata audit, ringkasan aktivitas pada halaman yang dimuat, dan **Aktivitas Batch > Lihat Detail Logbook**. Filter modul/status, pencarian nama/kode pada data termuat, urutan dan pagination tersedia di daftar batch.
5. Siklus: **Direncanakan > Aktif > Selesai > Diarsipkan**. Selesai/arsip tetap memiliki riwayat dan tidak menerima catatan baru. Perubahan status tidak membuat panen atau mengubah stok.

Admin dan operator lapangan aktif dapat mengelola batch; operator keuangan serta mitra/peserta edukasi hanya membaca. Role lama `operator` tetap mengikuti operator lapangan. Kode, modul, tanggal mulai dan data awal tidak dapat diubah setelah dibuat. Kode unik secara global memakai ID dokumen deterministik dan tidak digunakan ulang.

Rules dan sembilan index tambahan Phase 03 perlu ditinjau dan diterapkan secara manual oleh pengelola sebelum fitur digunakan pada lingkungan tujuan. Tidak ada deployment otomatis. Lihat [Phase 03](docs/PHASE_03_BATCH_MANAGEMENT.md) untuk kontrak transaksi, hasil pengujian dan batas verifikasi.

## Instalasi dan konfigurasi

Prasyarat: Flutter stable, Dart sesuai `pubspec.yaml`, project Firebase, dan perangkat/emulator. Versi pengujian Phase 01: Flutter 3.44.2, Dart 3.12.2.

```bash
git clone https://github.com/Freddy47588/sei_cycle.git
cd sei_cycle
git switch feature/operational-v2
flutter pub get
```

1. Daftarkan aplikasi Android dengan package `id.seicycle.app` pada project Firebase.
2. Simpan konfigurasi lokal di `android/app/google-services.json` (diabaikan Git).
3. Aktifkan Authentication email/password dan Google; daftarkan SHA-1/SHA-256 untuk Google Sign-In Android.
4. Siapkan database Cloud Firestore, rules dan indexes sesuai lingkungan. Baca [backend](docs/BACKEND.md), [schema](docs/FIRESTORE_SCHEMA.md), serta [indexes](docs/FIRESTORE_INDEXES.md) sebelum deployment.
5. Konfigurasi FlutterFire untuk platform yang akan digunakan:

```bash
dart pub global activate flutterfire_cli
flutterfire configure
flutter run
```

`lib/firebase_options.dart` saat ini hanya mendukung Android. Web, iOS, macOS, Windows, dan Linux memerlukan konfigurasi tambahan. Aplikasi tidak menggunakan backend Express, Firebase Admin SDK, atau Firebase Storage. Jangan memakai credential milik orang lain.

## Validasi

```bash
flutter analyze
flutter test
git diff --check
```

Widget tests memakai loader, streams, dan service mock tanpa mengakses Firebase. Untuk menghasilkan PNG di `build/phase01/`:

```bash
flutter test test/phase01_ui_test.dart --dart-define=CAPTURE_UI=true
```

Opsional: set environment variable `FLUTTER_ROOT` ke direktori Flutter SDK agar PNG memakai font Roboto dari cache SDK. PNG adalah render widget dengan data uji lokal, bukan bukti koneksi produksi.

[Audit Phase 01](docs/PHASE_01_UI_AUDIT.md) mencatat baseline, perbandingan desain, pengujian, dan batas verifikasi. Referensi asli tersedia di folder `screenshots/` pada branch `main`.

Uji rules dan kontrak transaksi dengan Firestore Emulator (Node.js ?20, Java ?21, Firebase CLI):

```bash
npm ci --prefix tools/firestore_tests
firebase emulators:exec --only firestore --project demo-seicycle-phase02 --config firebase.phase02.json "npm --prefix tools/firestore_tests test"
```

Gunakan project demo tersebut; konfigurasi pengujian terpisah dari produksi. Untuk PNG daftar/detail: `flutter test test/phase02_visual_test.dart --dart-define=CAPTURE_UI=true` (hasil di `build/phase02/`).

## Struktur dan dokumentasi

```text
lib/app/             Shell dan navigasi
lib/core/            Komponen, utilitas, layanan bersama
lib/features/        Modul aplikasi dan layanan Firestore
lib/theme/           Palet dan token desain
test/                Pengujian model, layanan, dan widget
docs/                Dokumentasi implementasi
```

- [Logbook Management Phase 02](docs/PHASE_02_LOGBOOK_MANAGEMENT.md)
- [Arsitektur backend](docs/BACKEND.md)
- [Schema Cloud Firestore](docs/FIRESTORE_SCHEMA.md)
- [ERD](docs/ERD.md)
- [Firestore Rules](docs/FIRESTORE_RULES.md)
- [Data sampel manual](docs/SAMPLE_DATA.md)

Jangan memasukkan service account, private key, `.env`, atau token pribadi ke repository. Video memakai tautan eksternal. Firebase Storage, pembaca detail edukasi lengkap, pengiriman FCM server, serta hardening produksi lanjutan belum dinyatakan selesai.
