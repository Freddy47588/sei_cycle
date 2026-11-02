# Dependency Health & Deprecation Policy

Berlaku untuk Phase 05 dan semua phase berikutnya. Audit dilakukan 16 Oktober 2026, dengan Flutter **3.44.2 stable** dan Dart **3.12.2**. Baseline analyzer bersih dan 181 Flutter test lulus sebelum perubahan kode.

## Kebijakan wajib

1. Sebelum coding: `flutter --version`, `flutter pub get`, `flutter pub outdated`, `flutter analyze`; baca pubspec dan lockfile.
2. Periksa metadata discontinued/retracted, rilis stabil, SDK constraints, sumber maintenance resmi, dependensi transitif, serta kompatibilitas Android/Firebase. Versi terbaru yang tersedia bukan bukti deprecation.
3. Prioritaskan package resmi, aktif, stabil dan kompatibel; gunakan dependency existing yang didukung. Jangan menambahkan package discontinued/unmaintained atau API deprecated. Jangan upgrade major tanpa alasan dan regresi yang memadai.
4. Jangan menghapus atau mengganti dependency existing tanpa pemeriksaan dampak. Evaluasi pengganti yang terawat bila dependency existing terbukti deprecated; migrasi hanya bila aman dan regresinya dapat diuji.
5. Perbaiki `deprecated_member_use` pada kode baru/diubah melalui API pengganti resmi. Jangan menambahkan ignore lint. Deprecation existing yang tidak terkait didokumentasikan dan diperbaiki hanya bila aman.
6. Pertahankan konfigurasi Android/Firebase yang bekerja. Evaluasi migrasi Kotlin terpisah terhadap prasyarat Flutter/AGP dan plugin; jangan upgrade major sekadar membuang warning.
7. Sesudah implementasi: `flutter pub get`, `flutter pub outdated`, `flutter analyze`, `flutter test --reporter expanded`, dan `flutter build apk --debug` bila SDK Android tersedia. Laporkan perubahan versi, alasan, sumber resmi, warning tersisa, hasil aktual dan batas verifikasi.

## Hasil audit Phase 05

**Tidak ada dependency ditambah, dihapus, di-upgrade, atau di-override.** `pubspec.yaml` dan `pubspec.lock` dipertahankan. Grafik memakai `fl_chart 1.2.0` existing. Resolver berhasil pada SDK yang tersedia; lockfile mensyaratkan Dart >=3.12.0 dan Flutter >=3.44.0 walaupun pubspec root mencantumkan Dart ^3.10.3. Gunakan toolchain yang memenuhi seluruh constraints, bukan hanya root pubspec.

`flutter pub outdated` menemukan **40 dependency upgradable yang masih terkunci**, **13 constraints di bawah versi resolvable**, dan **57 package dengan versi lebih baru** pada output pub get. Hal ini tidak sama dengan deprecated. Tidak dilakukan upgrade massal karena scope Phase 05 tidak memerlukan dependency baru dan konfigurasi Android sudah bekerja.

Metadata **104 package hosted** dari lockfile diperiksa melalui API resmi pub.dev: tidak ditemukan flag discontinued atau retracted pada versi terkunci. Sepuluh repository upstream yang menaungi 17 dependency direct/dev diperiksa melalui GitHub API resmi: tidak archived/disabled saat audit. Daftar versi, constraints, waktu rilis dan bukti mentah ada di [snapshot](DEPENDENCY_HEALTH_SNAPSHOT.json).

| Dependency | Versi terkunci | Stabil terbaru saat audit | Keputusan/status |
| --- | --- | --- | --- |
| [cloud_firestore](https://pub.dev/packages/cloud_firestore) | 6.6.0 | 7.0.0 | Tidak discontinued/retracted; repo upstream aktif dan tidak archived saat audit. |
| [cupertino_icons](https://pub.dev/packages/cupertino_icons) | 1.0.8 | 2.0.0 | Tidak discontinued/retracted; repo upstream aktif dan tidak archived saat audit. |
| [excel](https://pub.dev/packages/excel) | 4.0.6 | 4.0.6 | Perlu tinjauan maintenance terpisah: rilis terakhir 2024; repo terakhir didorong Juli 2025. |
| [firebase_auth](https://pub.dev/packages/firebase_auth) | 6.5.3 | 7.0.0 | Tidak discontinued/retracted; repo upstream aktif dan tidak archived saat audit. |
| [firebase_core](https://pub.dev/packages/firebase_core) | 4.11.0 | 5.0.0 | Tidak discontinued/retracted; repo upstream aktif dan tidak archived saat audit. |
| [firebase_messaging](https://pub.dev/packages/firebase_messaging) | 16.4.0 | 17.0.0 | Tidak discontinued/retracted; repo upstream aktif dan tidak archived saat audit. |
| [fl_chart](https://pub.dev/packages/fl_chart) | 1.2.0 | 1.2.0 | Tidak discontinued/retracted; repo upstream aktif dan tidak archived saat audit. |
| [flutter_lints](https://pub.dev/packages/flutter_lints) | 6.0.0 | 6.0.0 | Tidak discontinued/retracted; repo upstream aktif dan tidak archived saat audit. |
| [flutter_local_notifications](https://pub.dev/packages/flutter_local_notifications) | 22.0.1 | 22.3.2 | Tidak discontinued/retracted; repo upstream aktif dan tidak archived saat audit. |
| [google_sign_in](https://pub.dev/packages/google_sign_in) | 7.2.0 | 7.2.0 | Tidak discontinued/retracted; repo upstream aktif dan tidak archived saat audit. |
| [intl](https://pub.dev/packages/intl) | 0.20.2 | 0.20.3 | Tidak discontinued/retracted; repo upstream aktif dan tidak archived saat audit. |
| [path_provider](https://pub.dev/packages/path_provider) | 2.1.6 | 2.1.6 | Tidak discontinued/retracted; repo upstream aktif dan tidak archived saat audit. |
| [pdf](https://pub.dev/packages/pdf) | 3.12.0 | 3.13.1 | Tidak discontinued/retracted; repo upstream aktif dan tidak archived saat audit. |
| [printing](https://pub.dev/packages/printing) | 5.14.3 | 5.15.1 | Tidak discontinued/retracted; repo upstream aktif dan tidak archived saat audit. |
| [share_plus](https://pub.dev/packages/share_plus) | 13.2.0 | 13.3.1 | Tidak discontinued/retracted; repo upstream aktif dan tidak archived saat audit. |
| [timezone](https://pub.dev/packages/timezone) | 0.11.0 | 0.11.2 | Tidak discontinued/retracted; repo upstream aktif dan tidak archived saat audit. |
| [uuid](https://pub.dev/packages/uuid) | 4.5.3 | 4.6.0 | Tidak discontinued/retracted; repo upstream aktif dan tidak archived saat audit. |

### Risiko existing dan lingkup yang belum terverifikasi

- `excel 4.0.6`: belum ditandai discontinued, tetapi rilis terakhir 20 Agustus 2024 dan push repository terakhir 15 Juli 2025. Ini **risiko maintenance**, bukan bukti formal package deprecated. Pertahankan untuk kompatibilitas ekspor existing; jangan menambah pemakaian baru di Phase 05. Penggantian membutuhkan audit pemetaan tipe sel, formatting, file hasil, dan pengujian round-trip ekspor sebelum migrasi.
- Rantai `excel -> archive 3.6.1` dan `pdf/printing -> image 4.3.0 -> archive` masih tertahan constraints existing; `archive` terbaru memiliki major berbeda. Jangan memaksa versi melalui dependency_overrides. Parser arsip/gambar dan ekspor perlu peninjauan tersendiri sebelum upgrade.
- Metadata pub.dev diperiksa untuk seluruh 104 package hosted; status aktivitas semua repository transitif, seluruh API internal package, native Maven/CocoaPods, CVE, perilaku iOS/web/desktop, dan fitur ekspor PDF/Excel belum diaudit menyeluruh. Hasil ini **bukan klaim seluruh dependency bebas deprecation atau kerentanan**.
- Analyzer baseline tidak menemukan penggunaan API deprecated pada kode aplikasi. Hasil akhir dicatat di [Phase 05](PHASE_05_DASHBOARD_MONITORING.md). Tidak ada suppression lint deprecation yang ditambahkan.

## Android dan Firebase

Konfigurasi existing dipertahankan: **Gradle 8.14, AGP 8.11.1, Kotlin 2.2.20**, target Java 17, desugar_jdk_libs 2.1.4. [Tabel resmi Kotlin](https://kotlinlang.org/docs/gradle-configure-project.html) mendukung KGP 2.2.20–2.2.21 dengan Gradle 7.6.3–8.14 dan AGP 7.3.1–8.11.1. [AGP 8.11](https://developer.android.com/build/releases/agp-8-11-0-release-notes) memerlukan setidaknya Gradle 8.13/JDK 17. Kombinasi proyek berada pada batas dukungan tersebut.

Firebase Core **4.11.0**, Auth **6.5.3**, Firestore **6.6.0**, dan Messaging **16.4.0** merupakan keluarga FlutterFire existing. Android Core lokal menentukan Firebase BoM **34.15.0** dan plugin Auth/Firestore mengikuti Core. SDK constraints terselesaikan dan APK debug berhasil dibangun; runtime autentikasi/Firestore produksi tetap memerlukan smoke test perangkat. Tidak mengubah Firebase options, google-services.json, BoM override atau konfigurasi Android.

Warning Flutter **“applies the Kotlin Gradle Plugin”** masih muncul. [Panduan migrasi resmi Flutter](https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin) menjelaskan perubahan built-in Kotlin dan kesiapan seluruh plugin. Migrasi dikerjakan terpisah setelah prasyarat diperiksa; warning tidak disembunyikan dan tidak dijadikan alasan upgrade major dalam Phase 05.

## Mengulang audit

```bash
flutter --version
flutter pub get
flutter pub outdated
flutter analyze
python tools/dependency_health_audit.py --output build/dependency-health.json
flutter test --reporter expanded
flutter build apk --debug
```

Tool audit memakai Python standard library, membaca versi terkunci, memeriksa status pub.dev/repository direct, dan menghasilkan laporan JSON. Metadata yang gagal diambil tetap dicatat sebagai error; jangan menganggapnya sudah lolos. Bukti audit adalah snapshot waktu tertentu dan harus diperbarui ketika versi/dependency atau toolchain berubah.
# Audit ulang Phase 06 — 17 Oktober 2026

Toolchain tetap Flutter3.44.2/Dart3.12.2. `flutter pub get`, `flutter pub outdated` dan analyzer dijalankan sebelum coding dan quality gate akhir. **Tidak menambah, menghapus, upgrade atau override dependency.** Pubspec/lockfile serta konfigurasi Android/Firebase tidak diubah.

Audit `python tools/dependency_health_audit.py --output build/phase06-dependency-health.json` memeriksa104 hosted versions terkunci dan metadata upstream resmi. Tidak ada flags discontinued/retracted/error dari auditor. Snapshot Phase06 disimpan terpisah agar bukti Phase05 tidak ditimpa: [PHASE_06_DEPENDENCY_HEALTH_SNAPSHOT.json](PHASE_06_DEPENDENCY_HEALTH_SNAPSHOT.json). Status package juga dibandingkan dengan [pub.dev cloud_firestore](https://pub.dev/packages/cloud_firestore) dan [uuid](https://pub.dev/packages/uuid); implementasi transaksi mengikuti [dokumentasi Firebase](https://firebase.google.com/docs/firestore/manage-data/transactions) dan [kondisi Rules/getAfter](https://firebase.google.com/docs/firestore/security/rules-conditions).

Resolver tetap melaporkan40 upgradable terkunci dan13 constraints di bawah resolvable; itu bukan bukti deprecation. `excel` tetap memiliki risiko maintenance yang sudah dicatat. Export diuji baca ulang XLSX (uang integer dan quantity desimal), PDF berhasil dibuat, tanpa mengganti package export existing.

Analyzer akhir tidak menemukan deprecated API atau lint aplikasi. Tidak ada lint ignore baru untuk menutupi deprecation. Audit ini tidak membuktikan seluruh API internal transitif/native bebas deprecation/CVE. Warning Flutter tentang aplikasi yang masih applies Kotlin Gradle Plugin tetap tampil pada build APK sukses; tidak disembunyikan atau dijadikan alasan migrasi major. Smoke test Android fisik belum dilakukan.

## Phase 07 ? 17 October 2026

Flutter 3.44.2 / Dart 3.12.2 retained. Removed Google Sign-In after provider/call-site inspection; added official url_launcher 6.3.3 for HTTPS educational video links and a separately locked firebase-admin 14.5.0 trusted worker (Node 22+). Unrelated locked versions and Android/Firebase configuration remain unchanged. `flutter pub get`, `flutter pub outdated` and clean analyzer completed. Outdated reports 38 upgradable locked packages and 13 constrained below resolvable, which does not itself establish deprecation.

Official hosted metadata: 102 locked packages inspected, 101 successful metadata results without discontinued/retracted flags after targeted retries; path_parsing API retrieval remained unavailable and its [official maintained package page](https://pub.dev/packages/path_parsing) was checked separately. Direct upstream repository checks completed without archived/disabled results. Worker `npm audit --omit=dev` found zero advisory entries, but npm reports deprecated glob 10.5.0 and node-domexception 1.0.0 transitives under the maintained Admin SDK. These remain explicit production rollout review items; no override hides them. Existing excel/archive/native caveats still apply.

## Phase 08 — 17 October 2026

Flutter 3.44.2 / Dart 3.12.2 retained. Required resolver/outdated/analyzer commands were run before editing and repeated after a clean. **No dependency version, override or lockfile content changed.** Candidate app version advanced to 1.0.1+2; this is application versioning, not a package upgrade. Official metadata auditor completed all **102 hosted locked versions** and direct upstream repository checks with zero discontinued/retracted/error/archived/disabled flags. Private raw evidence remains ignored. `flutter pub outdated` still reports 38 upgradable locked dependencies and 13 constrained below resolvable; no mass upgrade was justified.

Worker npm audit reports zero known advisory findings at check time. Existing deprecated `glob`/`node-domexception` transitives and `excel` maintenance/archive/image constraints remain explicit risks; no override suppresses them. Package metadata and an advisory scan do not establish every native/transitive API is free of deprecation or vulnerabilities.

Android versions remain AGP 8.11.1 / Gradle 8.14 / Kotlin 2.2.20. The changed signing build script uses the supported Kotlin `compilerOptions`/`JvmTarget.JVM_17` API, replacing the deprecated `kotlinOptions.jvmTarget` setter. Gradle configuration/credential checks passed without that setter warning. Flutter's existing built-in-Kotlin migration warning and remaining Gradle deprecation summary are retained; they were not hidden. See the [official Kotlin compatibility table](https://kotlinlang.org/docs/gradle-configure-project.html), [AGP requirements](https://developer.android.com/build/releases/agp-8-11-0-release-notes) and [Flutter signing guide](https://docs.flutter.dev/deployment/android).

Phase 08 adds actual Education article/video/SOP CRUD, retry and metadata-preservation tests; existing export round-trip tests remain part of the full suite. Final analyzer/test/build outcomes and native-device limitations are recorded in [Phase 08 test report](PHASE_08_TEST_REPORT.md).

[Phase 07 report](PHASE_07_COMPLETION_REPORT.md) records test/build outcomes, actual capabilities and production gates. This audit does not establish that all transitive/native APIs are free of deprecation or vulnerabilities. The existing Kotlin migration warning remains; no major SDK migration or paid backend deployment was performed.

## Resumed final verification ? 24 October 2026

Toolchain remains Flutter 3.44.2/Dart 3.12.2; pub get, outdated and clean analyzer repeated. No lockfile/dependency version changed. Outdated now reports 39 upgradable locked packages and 13 constrained below resolvable. Final Flutter regression contains 503 passing tests including eight original-logo responsive cases. Android and dependency-metadata results are recorded in the Phase 08 test report.

The resumed official metadata audit completed all 102 hosted versions and direct upstream checks with zero flags. Final debug/release builds passed; remaining KGP and native Java/unchecked-API warnings were retained, not suppressed.
