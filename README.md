# SeiCycle — Kebun Sei

Aplikasi **Flutter dan Dart** untuk operasional pertanian dan peternakan terintegrasi Kebun Sei: Ayam, Maggot BSF, Cacing Tanah, Tanaman, dan Lele.

SeiCycle menggunakan **Firebase Authentication** untuk autentikasi dan **Cloud Firestore sebagai database aplikasi**. Akses data langsung dari Flutter dilindungi Firestore Security Rules.

## Fitur yang tersedia

- Login email/password dan Google, registrasi, profil, serta role pengguna.
- Dashboard ringkasan modul, logbook, stok rendah, jadwal, aktivitas, dan keuangan sesuai hak akses. Error dan data kosong tidak diganti angka contoh.
- Form Logbook lima modul, simpan catatan, riwayat yang sudah tersedia, transaksi inventaris, serta hasil produksi terkait.
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

## Struktur dan dokumentasi

```text
lib/app/             Shell dan navigasi
lib/core/            Komponen, utilitas, layanan bersama
lib/features/        Modul aplikasi dan layanan Firestore
lib/theme/           Palet dan token desain
test/                Pengujian model, layanan, dan widget
docs/                Dokumentasi implementasi
```

- [Arsitektur backend](docs/BACKEND.md)
- [Schema Cloud Firestore](docs/FIRESTORE_SCHEMA.md)
- [ERD](docs/ERD.md)
- [Firestore Rules](docs/FIRESTORE_RULES.md)
- [Data sampel manual](docs/SAMPLE_DATA.md)

Jangan memasukkan service account, private key, `.env`, atau token pribadi ke repository. Video memakai tautan eksternal. Firebase Storage, pembaca detail edukasi lengkap, pengiriman FCM server, serta hardening produksi lanjutan belum dinyatakan selesai.
