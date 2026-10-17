# Firestore alignment implementation — 17 Oktober 2026

## 1. Masalah yang ditemukan

Audit produksi berhasil read-only; lihat [inventaris, compatibility matrix dan kronologi](FIRESTORE_LIVE_SCHEMA_AUDIT.md). Smoke Android juga menemukan daftar ber-header menampilkan hitungan nol/empty state ketika query gagal; bug itu diperbaiki dan regresi retry mempertahankan filter ditambahkan. Penyebab kegagalan tidak terbatas pada satu query: guard lama menolak seluruh sumber ketika ada marker sample, query `isDeleted == false`/ordering canonical melewatkan field legacy yang tidak ada, collection `finance_records` dan `inventory_items` tidak dibaca, dan ID master modul berbeda dapat menggandakan jumlah modul. Seluruh master inventory canonical seed-origin, tetapi 22 ledger non-seed menggunakannya.

## 2. Root causes dan batas pemulihan

`requireNoSampleData()` sebagai prasyarat load dihapus dari jalur baca; guard mutasi tetap ketat. Marker `createdBy == sample_seed` membuktikan origin, sedangkan flags pada record ber-UID atau tanpa pembuat memerlukan review. Query inequality pada pembuat dan equality false pada flag tidak digunakan sebagai jalan pintas. Error query/izin/validasi tidak menjadi hasil nol.

Finance legacy awalnya ditolak Rules. Pada verifikasi setelah izin pengguna, Rules aktif sudah cocok dengan patch workspace dan pembacaan Finance/Inventory legacy berhasil di Android. Pemeriksaan hash membatalkan kandidat deployment lama; tidak ada deployment ulang oleh auditor. Stok/produksi yang berelasi dengan master seed sengaja unavailable sampai rekonsiliasi; itu bukan transaksi yang boleh dihapus atau saldo yang boleh ditebak agar dashboard tampak normal.

## 3. Files changed

Perubahan melanjutkan workspace yang sudah memiliki patch lokal sebelum sesi ini. File dokumentasi Phase 01 dan generated Linux/macOS yang sudah dirty tidak dihapus atau dianggap hasil audit ini.

| Area | File utama dan tujuan |
| --- | --- |
| Kebijakan baca | `lib/core/utils/legacy_firestore.dart`: aliases yang dibuktikan, provenance, pagination lengkap, bounded listeners, pemeriksaan relasi; `lib/core/widgets/firestore_paged_list.dart`: error halaman pertama tidak menampilkan empty state/nol |
| Mutasi dan diagnostik | `sample_data_guard.dart`, `audit_mode.dart`, `debug_diagnostics.dart`, `operation_error.dart`, `operational_auth.dart`, `firestore_fields.dart`, `firestore_validators.dart` |
| Dashboard | service, summary nullable, screen, productivity service/calculator, module monitoring: per-section error dan no false zero |
| Auth/profile | `app_user.dart`: actor UID dari document ID; `user_profile_service.dart` dan messaging: startup audit tanpa profile/token write |
| Legacy master | farm module model/service: alias ID yang teramati, deduplikasi lima modul |
| Finance | model/service/screen/detail: multi-source read, metadata opsional, identitas source, legacy read-only, review labels |
| Inventory/ledger | model/service/list/history/reference reads; seed tidak menjadi target mutasi; saldo invalid bukan nol |
| Logbook/batch/schedule | list/history/filter, seed guards pada edit/relasi batch, reminder candidates tanpa seed |
| Sales/production/circular | list/summary/picker isolation; pemeriksaan parent dan batas sumber; transaksi atomik existing dipertahankan |
| Education/alerts/recommendation/report | Contoh / Simulasi pada tampilan saja; isolasi alerts referensi seed; laporan/sinyal dari sumber lengkap yang diverifikasi |
| Security | `firestore.rules`: legacy collection read-only per role, anti-seed operational creates/updates, metadata laporan Finance-only |
| Audit tools | `tools/firestore_readonly_audit.cjs`, `tools/live_schema_summary.py`, `tools/test_live_schema_summary.py`, `tools/prepare_legacy_read_rules.cjs` |
| Regresi | `test/firestore_live_alignment_test.dart`, `test/firestore_paged_error_test.dart`, post-phase06 tests, existing Phase04–06 tests dan fake Firestore; Rules emulator suite |

Patch audit tidak mengubah `firestore.indexes.json`, pubspec/lockfile, Android application ID, Firebase config, branding, atau navigasi. Pada pemeriksaan akhir 07:12 WIB, `.metadata`, `pubspec.lock`, package config lokal dan artefak Android tambahan berubah setelah tes/build selesai; proses pemicunya tidak diketahui. Lockfile workspace saat itu berisi hanya lima package dan bukan dependency graph aplikasi yang diuji. Perubahan tersebut dipertahankan lokal dan tidak disertakan dalam commit audit. Hasil validasi di bawah berlaku untuk source audit dengan lockfile repository sebelumnya; jangan menganggap workspace lokal yang berubah itu sudah tervalidasi atau langsung membangun ulang tanpa memeriksa dependency resolution.

## 4. Compatibility strategy

Adapter hanya membaca alias yang ditemukan. Field canonical yang hadir menang; absent soft-delete dianggap tidak dihapus, tetapi tipe soft-delete yang salah menjadi error. Timestamp bisnis divalidasi sebelum agregasi. Nilai uang dan stok persisted harus numeric finite; string invalid tidak dibuat nol. Data optional seperti catatan/pembuat tidak wajib diciptakan ulang.

Collection lama digabung sebagai sumber terpisah tanpa copy dokumen. ID sumber dipertahankan untuk detail dan cursor. ID sama lintas legacy/canonical memblokir agregat agar tidak menggandakan transaksi. Master/Finance dari collection legacy hanya baca; aksi edit/delete canonical tidak ditawarkan untuk record itu. Tidak membuat migrasi data agar validator baru terpenuhi.

## 5. Dummy isolation dan pagination

`isSeedOrigin()` hanya memakai provenance; `hasSampleMarker()` dipakai untuk guard mutasi dan review. Record seed tidak tampil dalam daftar operasional maupun KPI. Record pengguna dengan flags ditampilkan untuk review pada Finance/Inventory, dengan aksi mutasi ditolak. Missing createdBy sendiri tidak menjadi alasan untuk menghilangkan record.

Pembaca kompatibilitas mengambil halaman document ID maksimal 100 sampai sumber terbukti selesai, dengan ceiling 500 dan sentinel ke-501. Filter periode/modul/provenance diterapkan **sebelum pagination tampilan** setelah sumber terbukti lengkap. Gagal pada halaman kedua membatalkan hasil; tidak menerbitkan halaman pertama sebagai total. Batas memicu alasan yang terlihat. Listeners lengkap dibatasi 501 dan tidak mengklaim cache sebagai verifikasi server. Metadata changes diaktifkan agar konfirmasi server setelah cache diterima; cache awal tidak memunculkan peringatan gagal palsu. Record yang dihapus atau terisolasi pada live update dikeluarkan dari halaman yang sesuai.

Tradeoff: sampai metadata terindeks lengkap tersedia, refresh/list dapat membaca seluruh sumber kecil lagi; ceiling berlaku pada sumber keseluruhan, sehingga mempersempit tanggal UI tidak selalu mengatasi ceiling. Jangan menaikkan batas tanpa estimasi biaya. Perubahan serentak klien lain dapat mengubah hasil antarhalaman; tidak ada klaim snapshot transaksi lintas collection. Tidak menganggap subset query sebagai total global.

## 6. Dashboard recovery

Masing-masing section memiliki hasil/error sendiri. Modul, Logbook hari ini, jadwal, batch, stok, aktivitas, flows, Finance dan Sales tidak saling menggagalkan seluruh dashboard. Angka yang unavailable menggunakan null dan UI **Belum dapat dihitung** dengan alasan/retry. Finance nullable diteruskan sampai widget, bukan diisi `0` saat load gagal. Modul canonical/legacy dihitung sebagai lima identitas kebun.

`OperationalIntegrity` menelusuri batch, Logbook, inventory, sale dan ledger terkait dengan cache lokal per load serta batas verifikasi. Ledger Logbook diperiksa agar seed master tidak tersembunyi di balik parent yang terlihat non-seed. Histori asli tetap ada. Stock KPI menolak menerbitkan “nol barang” ketika ledger nyata memakai master seed. Circular flow harus benar-benar manual/aktual; tidak memutasi stok dua kali. Production calculator mempertahankan deduplikasi existing dan menandai parent bertanda simulasi sebagai uncertain.

Debug diagnostics mencatat operation/query category, runtime error type, FirebaseException.code dan stack trace, hanya pada debug. Tidak mencetak dokumen, UID, jumlah uang, body HTTP, token atau raw exception message. UI menampilkan alasan aman dan tidak membocorkan query backend.

## 7. Finance dan integritas transaksi

Ringkasan/ekspor menggabungkan `finance_transactions` dan `finance_records`, mengecualikan seed, memvalidasi type/amount/date, dan memeriksa relasi sebelum menghitung. Satu sumber denied/unavailable berarti total gabungan unavailable. Detail legacy mengambil collection asal dan tidak mengarang subcollection edit. Histori edits canonical tetap role-restricted.

Sales mempertahankan transaksi atomik receipt + ledger + finance + stock, stable request ID/payload, overselling prevention dan retry semantics existing. Data sale seed tidak masuk daftar/summary; master seed tidak dapat dijual. Sale yang nyata tetapi menunjuk master seed memblokir agregat dan tetap menjadi bukti yang harus direkonsiliasi. Tidak ada saldo, transaction linkage, sale ID atau dokumen Finance diubah pada produksi. Isi dua dokumen manual yang dihapus tetap unknown.

## 8. Write flows dan old clients

Input canonical existing tetap memakai UID aktor dari profil Auth, server timestamps yang sudah digunakan, field bisnis canonical dan source manual/logbook/sale/opening sesuai alur. Tidak ada payload baru yang menambahkan `createdBy: sample_seed`, `isSampleData: true`, atau `sampleVersion: v2`. Identitas sample_seed ditolak validator operational. Update seed/flags dicegah sebelum mutasi; parent batch seed juga ditolak. Tombol seeder tidak dihidupkan kembali.

Build `SEICYCLE_READ_ONLY_AUDIT=true` melewati sinkronisasi profil/FCM dan callback pembuatan notifikasi saat navigasi. Guard write lokal menolak mutasi utama; pengujian produksi hanya membuka/navigasi/refresh, tanpa save, delete, read-mark notification, atau transaksi uji. Flag adalah alat debug lokal, bukan pengganti Security Rules.

Adapter tidak mengubah schema untuk klien lama. Hardening Rules yang kini aktif **menolak operasi klien lama yang masih mengubah seed master atau mengirim marker seed**; dampak operasional tersebut harus dimonitor saat rekonsiliasi. Jangan mengubah pembuat seed untuk melewati guard. Akses baca Finance hanya admin/operator_keuangan; operator_lapangan/mitra/peserta_edukasi tidak mendapat akses Finance.

## 9. Rules/index dan kebutuhan deployment

93 index aktif cocok 93 deklarasi lokal; tidak ada index baru atau deployment index. Query kompatibilitas tidak memerlukan composite index tambahan. Rules Emulator menguji hak legacy read/write, role, anti-seed creates, laporan sensitif dan transaksi atomik. Tidak melonggarkan role untuk menghilangkan permission error.

Pengguna memberi izin eksplisit untuk melanjutkan pada percakapan ini. Sebelum tindakan deployment, pembacaan ulang Rules menemukan konfigurasi aktif telah berubah menjadi patch workspace lengkap, dengan CreateRuleset pada 06:56:41 WIB dan UpdateRelease 06:56:42 WIB. Audit log memakai akun CLI yang sama; auditor tidak mengatribusi proses tersebut ke dirinya sendiri. Source aktif cocok dengan workspace setelah normalisasi line ending.

Kandidat minimal baca legacy sebelumnya lulus lima tes khusus tetapi pemeriksaan hash menghentikannya karena baseline sudah berubah. `tools/prepare_legacy_read_rules.cjs` sekarang memerlukan snapshot Rules terbaru, mengenali bahwa akses legacy sudah ada dan menandai kandidat lama **obsolete**. **Jangan deploy kandidat lama** atau mengembalikan Rules tanpa review. Tidak ada deployment ulang, index deployment atau migrasi oleh auditor.

Smoke Android setelah perubahan Rules membuktikan 18 transaksi aktif Oktober non-seed dan dua transaksi Finance legacy Juni terbaca. Hardening penuh juga berarti old clients yang masih mengubah seed master dapat ditolak; jangan membatalkannya diam-diam agar saldo bercampur kembali. Source rollback baseline tetap tersimpan privat untuk review, bukan dijalankan. Review akses lain, terutama report metadata, tetap mengikuti role di file Rules yang telah diuji Emulator.

## 10. Quality gates dan dependencies

Flutter 3.44.2 / Dart 3.12.2, Firebase CLI 15.34.0, Node 24.5.0. `flutter pub get` dan `flutter pub outdated` dijalankan sebelum coding dan sesudah perubahan; tidak ada dependency ditambah/dihapus/di-upgrade/di-override. Audit resmi metadata 104 hosted packages dan repository direct disimpan lokal: tidak ada flag discontinued/retracted/archived/error. Constraints masih menunjukkan 40 upgradable terkunci dan 13 constraints di bawah resolvable; ini bukan bukti deprecation.

Risiko maintenance `excel 4.0.6` dan keterbatasan audit native/transitive tetap seperti [DEPENDENCY_HEALTH.md](DEPENDENCY_HEALTH.md). Tidak mengklaim semua API/native artifact bebas deprecation/CVE. Warning built-in Kotlin masih muncul; tidak dihilangkan dengan upgrade major atau lint ignore. Flutter doctor melaporkan beberapa Android SDK licenses belum diterima, meskipun debug build berhasil. Tidak menerima lisensi secara otomatis.

Satu request metadata http_parser sempat gagal karena koneksi ditutup; retry resmi berhasil dan error awal tetap dicatat lokal. Hasil QA final dan bukti Android dicatat di bagian hasil validasi di bawah; log detail dan captures berada lokal dalam `build/audit_android/`, di luar Git. Baseline analyzer bersih. Kegagalan compile intermediate pada nama source collection detail sudah diperbaiki dan tidak dinyatakan sebagai build final yang lulus.

## 11. Android device results

ADB dan Flutter menemukan Infinix X6833B, Android 14/API 34, application ID `id.seicycle.app`. Pengujian runtime menggunakan APK audit yang secara eksplisit dibangun dengan flag read-only. Vysor tersedia sebagai konteks mirroring pengguna; audit ini menggunakan ADB dan capture lokal, tidak mengklaim kontrol/visibilitas Vysor otomatis.

Hasil smoke test final dicatat di bagian hasil validasi di bawah. Aplikasi baseline tidak diluncurkan ulang untuk mereproduksi error karena startup baseline dapat menulis profil/metadata; root cause baseline dibuktikan melalui source. Jangan menganggap fixture/screenshot widget membuktikan produksi dapat dibaca oleh Android.

## 12. Production rollout plan

1. Review patch kode dan kedua laporan; pertahankan backup lokal terkontrol, bukan di Git.
2. Rules aktif sudah cocok dengan patch; simpan bukti perubahan dan monitor dampak old client. Jangan deploy kandidat lama yang sudah obsolete.
3. Smoke read-only Finance/Inventory legacy dengan permissions aktif telah dilakukan; ulangi setelah perubahan Rules/schema berikutnya.
4. Rekonsiliasi 22 ledger terhadap 16 master seed oleh pemilik data; identifikasi saldo bisnis sah dan relasi transitif tanpa mengubah origin seed menjadi aktor asli. Audit calon resolusi dalam dry-run sebelum tindakan produksi apa pun.
5. Uji write hanya di Emulator/staging dengan role nyata representatif. Pengujian write produksi membutuhkan izin yang lebih spesifik dari tugas ini.
6. Jika seluruh gate kritis dan smoke test lengkap lolos, commit relevan dengan `fix(firestore): align legacy data and isolate seeded records`, lalu push hanya `origin/feature/operational-v2`; tidak force push atau merge main. Jangan menyertakan dokumen pengguna yang unrelated, generated platform changes, credentials, raw exports atau captures sensitif.

## 13. Remaining blockers

Izin legacy telah terselesaikan dan diverifikasi. Blocker tersisa: rekonsiliasi ledger/master seed; unknown isi/histori dua Finance terhapus; belum ada bukti managed restore/PITR atau audit log historis yang lengkap. Mode compatibility berbatas 500 perlu strategi metadata terindeks yang disetujui bila data tumbuh. Edit record legacy tanpa ownership canonical belum diaktifkan sebagai migrasi terselubung; pembacaan tidak menyatakan semua edit historis diizinkan. Validasi fisik tidak menggantikan verifikasi integritas bisnis.

## 14. Phase 07 readiness

**Belum siap dinyatakan tuntas untuk Phase 07** sampai rekonsiliasi ledger/master seed diselesaikan. Izin baca legacy dan smoke terkait telah lolos. Tidak mengimplementasikan fitur Phase 07/08. Perbaikan kode dapat direview terpisah dari tindakan produksi; tidak ada alasan untuk menghapus seed atau mereset database demi mencapai tampilan tanpa error.


## Hasil validasi akhir

Pemeriksaan final: **17 October 2026 07:10 WIB**.

| Gate | Hasil aktual |
| --- | --- |
| flutter pub get / pub outdated | Berhasil menggunakan lockfile repository; perubahan lockfile lokal sesudah validasi dikecualikan dari commit |
| flutter analyze | **No issues found** |
| flutter test --reporter expanded | **349 passed**; tidak ada test dinonaktifkan |
| Firestore Rules workspace ? Emulator demo 8095 | **155 passed, 0 failed** |
| Kandidat minimal baca legacy ? Emulator demo 8097 | **5 passed, 0 failed**; kandidat kemudian obsolete setelah Rules aktif berubah |
| Python audit/redaction tests | **11 passed** |
| flutter build apk --debug | Berhasil; warning Kotlin existing tetap dicatat |
| APK audit read-only | Berhasil dibangun, dipasang dan dijalankan di Infinix; SHA-256 APK terpasang cocok dengan artefak lokal |
| git diff --check | Lulus |
| Secrets/PII review | Tidak ditemukan private-key/token pattern atau identitas akun produksi pada file diff yang ditinjau; inventory/captures/backup tetap Git-ignored |

| Smoke Android read-only | Hasil |
| --- | --- |
| Auth/profile | Sesi existing pulih; startup audit melewati profile/token writes |
| Dashboard | Terbuka; lima modul aktif; section error terisolasi, stok konflik tidak menjadi nol |
| Finance Oktober | 18 transaksi non-seed aktif tampil; income, expense dan cashflow cocok dengan snapshot audit; nilai uang tidak dipublikasikan |
| Finance Juni | Dua transaksi collection legacy tampil dengan label arsip hanya baca; tidak memasukkan transaksi seed Juni |
| Inventory | Satu master legacy tampil hanya baca; 16 master seed terisolasi; tidak ada false listener warning pada APK terakhir |
| Logbook | Record schema lama 22 Juni terlihat pada daftar; navigasi dan scrolling diuji tanpa save |
| Schedule | Filter Semua Jadwal membaca tiga record aktif; salah satu cocok dengan judul dokumen scheduled_at legacy yang diaudit. Tanggal aktivitas berbeda dari createTime |
| Education | Label Contoh / Simulasi terlihat pada materi seed |
| Notifications | Navigasi/read diuji, tanpa mark-as-read/delete |
| Sales / circular flow | Empty state sesuai sumber operasional kosong; tidak membuat transaksi |
| Reports / productivity / recommendations | Konflik relasi memblokir angka/sinyal yang tidak terverifikasi; tidak membuat export parsial |
| Error/retry | Permission error awal terlihat dan retry diuji; false empty/zero count diperbaiki, di-reinstall dan dibuktikan hilang |
| Runtime logs | Tidak ditemukan RenderFlex overflow atau FATAL EXCEPTION dalam log PID yang diperiksa; ini bukan bukti semua jalur bebas crash |

APK audit untuk smoke disimpan di `build/audit_android/seicycle-readonly-audit.apk`; APK debug biasa berada di `build/app/outputs/flutter-apk/app-debug.apk`. Setelah smoke, aplikasi dihentikan dan APK debug normal dipasang dengan `adb install -r` tanpa menghapus data aplikasi. APK normal tidak diluncurkan lagi oleh auditor agar tidak memicu sinkronisasi profil produksi; runtime smoke menggunakan varian audit dari source yang sama. Pengujian write tetap di Emulator. Tidak menjalankan seeder, transaksi uji, migrasi atau penghapusan produksi. Belum menjalankan write smoke produksi, lifecycle seluruh batch secara fisik, seluruh kombinasi role di perangkat, atau export aktual dengan data produksi yang masih berkonflik.

Perubahan rules aktif dan auditor yang membatalkan kandidat lama dicatat terpisah dari data bisnis. Izin pengguna tidak dipakai untuk menebak saldo, menghapus transaksi, mengubah seed menjadi pengguna asli, atau memulihkan dua Finance terhapus secara rekaan. **Rekonsiliasi bisnis tetap terbuka; Phase 07 belum dinyatakan siap.**
