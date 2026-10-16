# Phase 03 - Manajemen Batch Budidaya

16 Oktober 2026 (Asia/Jakarta). Repository `Freddy47588/sei_cycle`, branch `feature/operational-v2`, baseline remote `c087d199c07db93911161eb926642e3f88972ba3`.

## 1. Gambaran pengembangan

Batch mendefinisikan identitas kelompok/siklus untuk lima modul existing: Ayam Kampung, Maggot BSF, Cacing Tanah, Tanaman, dan Lele. Form original, banner, lima tab, tombol Simpan/Daftar Logbook, detail Phase 02 dan empat bottom navigation dipertahankan. Akses pendukung ditambahkan melalui **Kelola Batch** pada header Logbook dan pemilih batch di atas kartu isian original.

Daftar batch memiliki filter modul/status, pencarian nama/kode lokal, urutan terbaru/terlama berdasarkan createdAt, cursor pagination, kartu berwarna sesuai modul, empty/loading/error/retry dan route detail. Tidak ada angka produksi/progres contoh.

## 2. Arsitektur

- `models/cultivation_batch.dart`: BatchInput, validasi, parser Timestamp, status/transisi, kontrak BatchPage.
- `services/batch_service.dart`: create unik atomik, edit optimistis, transisi idempotent, pembacaan ID dan query cursor 20 dokumen.
- `screen/batch_list_screen.dart`: daftar dan mode pemilih batch aktif; generasi request membuang respons filter lama, penggabungan halaman deduplikasi ID.
- `screen/batch_form_screen.dart`: form responsif, controller bertahan, validasi, guard double submit, tanggal picker, lokasi menurut modul dan unit eksplisit.
- `screen/batch_detail_screen.dart`: identitas, audit UID/tanggal, edit deskriptif, konfirmasi transisi, pemuatan ulang.
- `widgets/batch_card.dart`, `widgets/batch_activities.dart`: presentasi reusable dan aktivitas berhalaman dengan detail Logbook aktual.

Memakai dependency UUID yang sudah tersedia; tidak menambah dependency, layanan, backend, seed atau listener koleksi. Selector menggunakan route daftar berhalaman saat dibuka, bukan listener yang berulang akibat rebuild form.

## 3. Skema Firestore dan keunikan

Collection tunggal `batches`; skema lengkap di [FIRESTORE_SCHEMA.md](FIRESTORE_SCHEMA.md). Field inti mencakup id/name/code/moduleType/locationName/status, Timestamp startedAt/expectedHarvestAt/completedAt, initialQuantity/unit, commodity, notes, UID dan timestamp audit, isDeleted false.

**Keputusan ID:** kode uppercase menjadi document ID deterministik, bukan UUID terpisah. Kode bawaan `B-<UUID-v4>` tetap dapat diganti pengguna sebelum create. Kode valid 3-40 karakter huruf/angka/-/_. Lingkup unik adalah seluruh collection batches pada database; tidak ada tenant terpisah pada fondasi existing. Transaksi membaca dokumen ID tersebut, menolak existing, lalu create. Rules memastikan code == document ID. Concurrent create hanya memiliki satu pemenang, tanpa query cek nama atau koleksi reservasi. Nama boleh sama, kode tidak. Kode batch selesai/arsip tidak digunakan ulang.

Nama/lokasi wajib, jumlah awal opsional nonnegatif, finite dan maksimal 10^15 untuk batas numerik operasional. Unit wajib jika jumlah diisi dan tidak dipaksakan ke satu modul; misalnya ekor, kg, bibit atau luas. Komoditas dapat diisi untuk tanaman maupun jenis lain. Tidak ada nilai jumlah awal contoh yang otomatis disimpan.

## 4. Alur tambah, edit dan status

Logbook > Kelola Batch > Tambah Batch > Simpan Batch > Detail Batch > Aktifkan. Setelah create, detail langsung dibuka agar batch dapat diaktifkan, termasuk saat masuk dari pemilih yang semula kosong. Kembali ke pemilih memuat ulang query active.

Semua batch mulai planned. Transisi hanya planned -> active -> completed -> archived, dengan konfirmasi pengguna. completedAt memakai server timestamp pada transisi active -> completed dan tetap saat arsip. Retry transisi yang sudah mencapai tujuan selesai tanpa write ulang; status lain yang berubah ditolak. Transaksi membaca ulang profil dan batch sebelum write.

Edit hanya pada planned/active: nama, lokasi, estimasi panen, komoditas dan catatan. Modul, kode, startedAt, jumlah/unit awal, metadata create dan identitas tidak dapat diubah. expectedUpdatedAt mendeteksi edit usang. Batch selesai/arsip hanya membaca histori; tidak ada hard/soft delete, cascade, pembukaan kembali, atau panen/stok otomatis. Kebijakan koreksi/reopen admin belum diaktifkan dan memerlukan rancangan audit terpisah.

## 5. Integrasi Logbook

Form tetap memakai spesifikasi original. Pengguna menekan **Pilih batch ... yang aktif**, memilih batch secara eksplisit dari modul yang sesuai, lalu mengisi/simpan form. Tidak ada pilihan batch otomatis. Mode pemilih mengunci modul/status; keadaan kosong menjelaskan cara membuat/mengaktifkan batch. Pilihan batch berada di state masing-masing modul dan dipertahankan oleh keep-alive saat tab berpindah; rebuild input tidak menghilangkan pilihan.

`createDailyEntry()` dan `createLogbookWithInventory()` tetap `Future<String>` dengan requestId existing dan tambahan parameter opsional batchId. Identitas batch menjadi bagian matchesRequest, termasuk verifikasi commit ambigu dari server. Mengganti batch mempersiapkan request baru, tidak mengganti catatan tersimpan. Retry request yang sudah commit tetap mengembalikan ID ketika batch kemudian selesai, tanpa write baru. Request ID sama dengan batch berbeda ditolak.

Sebelum write baru berbatch, transaksi membaca profil aktif dan batch, memverifikasi hak kelola, keberadaan, isDeleted false, status active, dan kecocokan moduleType. Seluruh read (logbook, profil, batch, inventory dan notifikasi) mendahului write. Concurrent completion menyebabkan retry yang membaca status baru atau penolakan Rules; tidak ada hasil parsial.

## 6. Kompatibilitas lama dan Tanpa Batch

`LogbookEntry.batchId` nullable. Dokumen tanpa batch tetap dibaca daftar/detail dan jalur laporan existing tanpa migrasi. Labelnya **Belum terhubung ke batch**. Tidak menebak batch dari tanggal/lokasi/modul. Parser/serialisasi lama dipertahankan; field batchId tidak ditulis bila null.

**Tanpa Batch - aktivitas umum** ditampilkan secara jelas pada form awal dan tersedia untuk melepas pilihan batch. Alasannya: aktivitas umum lintas siklus dan proses operasional transisi tetap perlu dicatat. Opsi ini tidak dipakai untuk melewati validasi batch yang dipilih; batch invalid selalu ditolak. Keterbatasan Phase 02 tetap berlaku: dokumen legacy tanpa isDeleted/activityDate tidak masuk query modern sampai ada audit normalisasi terencana.

## 7. Aturan role dan Rules

| Role aktif | Baca | Tambah/edit/status |
| --- | --- | --- |
| Admin | Ya | Ya |
| Operator lapangan dan alias legacy operator | Ya | Ya |
| Operator keuangan | Ya | Tidak |
| Mitra/peserta edukasi | Ya | Tidak |
| Inaktif/tanpa autentikasi | Tidak | Tidak |

Capability UI mengikuti AppUser.canViewBatches/canManageBatches; service memeriksa profil dalam transaksi; Security Rules tetap batas otorisasi. Batch create/update memvalidasi schema, UID penulis, server timestamp, field identity immutable, transisi dan larangan delete. Tidak ada bypass admin untuk mengubah identitas atau menghapus batch.

Rules create Logbook memakai existsAfter/getAfter batch sehingga missing/wrong-module/inactive/deleted/archived ditolak dan transaksi tidak dapat menyelesaikan batch sekaligus menambahkan Logbook. Pembatasan edit notes + audit immutable Phase 02 tidak berubah; batchId tidak termasuk field yang dapat diedit.

## 8. Query dan index

Delapan kombinasi batch (modul opsional, status opsional, arah createdAt ASC/DESC) dan satu aktivitas batch (isDeleted + batchId + activityDate DESC) ditambahkan. Semua query daftar memakai limit20/cursor; pencarian hanya data termuat. Filter/urutan mereset cursor; request lama diabaikan; halaman digabung berdasarkan ID. Lihat [FIRESTORE_INDEXES.md](FIRESTORE_INDEXES.md).

Ringkasan menampilkan jumlah aktivitas **pada halaman yang dimuat** dan aktivitas terakhir dari urutan terbaru. Populasi terkini, produksi kumulatif dan panen aktual berlabel **Belum dapat dihitung**; Phase 03 tidak menjumlahkan sumber stok dan produksi atau menganggap awal/estimasi sebagai hasil aktual. Detail tidak mengklaim total global dari pagination.

## 9. Integritas stok dan produksi

Mapping dan rumus Phase 02 tidak berubah. Logbook, inventory, inventory_transactions, production_results dan notifikasi tetap ditulis melalui transaksi existing; ID transaksi/produksi disiapkan di luar callback retry. batchId ditambahkan ke metadata inventory_transactions/production_results bila ada; logbookId tetap relasi utama. Tidak menduplikasi Logbook ke batch dan tidak menyimpan daftar aktivitas dalam satu dokumen.

Retry payload identik hanya membaca catatan existing dan mengembalikan ID. Perbedaan batchId tidak dianggap identik. Edit notes tidak memanggil create/mapping atau mengubah stok/produksi. Status batch tidak membuat transaksi panen. Keterbatasan hardening inventory lintas client yang diwarisi Phase 02 tetap memerlukan pekerjaan terpisah; metadata batch tidak menyelesaikan semua invariant bisnis fondasi lama.

## 10. Hasil testing

Baseline sebelum implementasi: flutter analyze tanpa temuan dan **81 test lulus**. Hasil akhir:

| Pemeriksaan | Hasil |
| --- | --- |
| Format 23 file Dart terkait | Lulus; tidak ada perubahan format tersisa |
| flutter analyze | Lulus, tidak ada temuan |
| flutter test --reporter expanded | **121 lulus**: 81 regresi + 24 service/model Phase 03 + 16 widget Phase 03 |
| Firestore Emulator + Firebase JS SDK | **45 lulus**: 25 regresi + 20 Phase 03 |
| Capture UI Phase 03 | 6 PNG daftar/detail/form pada 320/1280 px, skala teks 1,4 |
| git diff --check | Lulus |
| JSON index + kombinasi query + duplikasi | Valid; 9 index baru sesuai query, tanpa duplikasi |
| README dan secret hygiene perubahan | Sesuai; tidak menambah credential atau dependency |
| Android nyata / FlutterFire native | Belum dilakukan |
| Deployment produksi | Tidak dilakukan |

Emulator dijalankan memakai konfigurasi demo Phase 02 yang dipakai ulang. Pada Windows, Firebase CLI meninggalkan proses Java setelah menghentikan runner yang gagal; suite akhir dijalankan dengan `npm --prefix tools/firestore_tests test` ke emulator demo yang sama. Test environment memuat Rules terbaru, lalu 45 test lulus. Tidak memakai endpoint produksi.

Pengujian Phase 03 meliputi model/service lima modul, input invalid, uniqueness deterministik, edit/immutable/conflict, lifecycle/retry, role, batch invalid, idempotency yang mempertimbangkan batch, stok/produksi sekali, concurrent completion melalui fake transaksi, legacy dan notes audit, pagination/filter, state UI, selector yang bertahan lintas rebuild/tab, guard simpan, status UI, aktivitas/detail dan responsive.

Rules/kontrak JS memakai Firestore Emulator pada project demo, mencakup concurrent code create, status race, kondisi getAfter, role, audit, query cursor dan seluruh regresi Phase 02. Fake Dart menolak read-after-write, menstage write atomik dan dapat mengubah status sebelum transaction retry; bukan implementasi Rules atau simulasi jaringan penuh.

Command reproduksi:

```bash
flutter analyze
flutter test --reporter expanded
flutter test test/phase03_batch_ui_test.dart --dart-define=CAPTURE_UI=true --reporter expanded
firebase emulators:exec --only firestore --project demo-seicycle-phase02 --config firebase.phase02.json "npm --prefix tools/firestore_tests test"
git diff --check
```

PNG fixture di build/phase03/ (list/detail/form, 320/1280 px, text scale1.4), font Flutter SDK, diperiksa visual. Artefak build/log tidak di-commit. Emulator tidak membuktikan index produksi atau FlutterFire Android native.

## 11. Batasan dan perlindungan workspace

Tidak ada uji Android nyata/login/keyboard fisik atau Firebase production end-to-end. Rules/index **tidak dideploy**. Pengelola perlu review, persetujuan deployment manual dan menunggu index siap sebelum memakai fitur di lingkungan tujuan.

Request ID Logbook belum persisten lintas restart aplikasi. Kode create batch stabil selama form terbuka dan double submit diblokir; jika respons create ambigu, buka ulang daftar/cari kode sebelum membuat batch berbeda. Dokumen yang sudah commit tidak ditimpa oleh retry create. Identitas siklus tidak dapat dikoreksi setelah create; planned yang keliru tidak dapat dihapus dan perlu kebijakan koreksi admin terpisah. Pelaporan total produksi dan populasi hidup belum diturunkan hanya dari initialQuantity.

git status/branch/remote diverifikasi dan fetch origin berhasil; HEAD sama dengan remote c087d19. Pull tidak diperlukan karena tidak ada commit remote baru dan working tree berisi perubahan pengguna. Audit Phase01 serta registrant Linux/macOS lokal dipertahankan dan tidak dimasukkan commit. Tidak mengubah main/backend, menghapus stash, reset, force push, membuat PR atau melakukan seed/deployment.

## Daftar file Phase 03

| File | Tujuan |
| --- | --- |
| `lib/features/batches/models/cultivation_batch.dart` | Model, input, validasi, status dan halaman |
| `lib/features/batches/services/batch_service.dart` | Transaksi create/edit/status dan query cursor |
| `lib/features/batches/screen/batch_list_screen.dart` | Daftar/filter/search/pemilih active |
| `lib/features/batches/screen/batch_form_screen.dart` | Form tambah/edit dan guard submit |
| `lib/features/batches/screen/batch_detail_screen.dart` | Identitas, metadata, edit dan lifecycle |
| `lib/features/batches/widgets/batch_card.dart` | Kartu modul dan formatter tanggal |
| `lib/features/batches/widgets/batch_activities.dart` | Ringkasan terbatas dan aktivitas berhalaman |
| `lib/core/constants/firestore_collections.dart` | Konstanta batches |
| `lib/features/profile/models/app_user.dart` | Capability batch menurut role/aktif |
| `lib/features/logbook/models/logbook_entry.dart` | Relasi batch nullable dan serialisasi kompatibel |
| `lib/features/logbook/models/logbook_page.dart` | Filter batchId |
| `lib/features/logbook/services/logbook_service.dart` | Validasi transaksi dan retry berbatch |
| `lib/features/logbook/screen/logbook_screen.dart` | Kelola/pilih batch; state per modul bertahan |
| `lib/features/logbook/screen/logbook_list_screen.dart` | Label relasi atau legacy tanpa batch |
| `lib/features/logbook/screen/logbook_detail_screen.dart` | Identitas batch pada catatan aktual |
| `lib/features/inventory/services/inventory_service.dart` | Metadata batchId pada transaksi stok |
| `firestore.rules` | Schema/role/lifecycle dan validasi getAfter batch |
| `firestore.indexes.json` | Sembilan index query yang dipakai |
| `test/phase03_batch_test.dart` | 24 test model/service/integritas |
| `test/phase03_batch_ui_test.dart` | 16 test UI/alur/responsif dan capture |
| `test/support/memory_firestore.dart` | Hook perubahan saat retry untuk uji konflik |
| `test/phase01_ui_test.dart` | Kontrak mock parameter opsional batchId |
| `test/phase02_logbook_test.dart` | Kontrak mock parameter opsional batchId |
| `tools/firestore_tests/logbook_rules.test.mjs` | 20 test Rules/kontrak batch; regresi existing tetap |
| `README.md` | Fitur dan panduan penggunaan batch |
| `docs/FIRESTORE_SCHEMA.md` | Kontrak batch dan relasi baru |
| `docs/FIRESTORE_INDEXES.md` | Query/index dan petunjuk deployment manual |
| `docs/PHASE_03_BATCH_MANAGEMENT.md` | Arsitektur, keputusan, pengujian dan batas |

## 12. Persiapan Phase 04

BatchId stabil siap dipakai untuk integrasi Inventaris dan Jadwal Operasional pada Phase 04. Langkah berikutnya: desain relasi/alokasi stok dan jadwal per batch, kebijakan koreksi/reopen ber-audit, persistensi request serta pengujian Android sesudah rules/index disetujui. Tidak mengimplementasikan Phase 04-08 dalam perubahan ini.
