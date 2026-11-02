# Phase 02 - Logbook Management

16 Oktober 2026 (Asia/Jakarta). Repository `Freddy47588/sei_cycle`, branch `feature/operational-v2`, baseline `3bb0ec6`.

## 1. Gambaran fitur

Form Phase 01 tetap menjadi halaman utama Logbook: header, banner berwarna, susunan kartu/field, slider, lima tab, dan tombol Simpan Catatan dipertahankan. Referensi `main`: `screenshots/Logbook1.png` dan `screenshots/Loogbook2.png`; dibandingkan dengan spesifikasi form yang dipindahkan tanpa menghapus field.

Fitur baru:

- Daftar Logbook sebagai screen tersendiri, filter awal mengikuti tab asal.
- Pencarian judul/catatan dengan debounce 350 ms pada halaman yang telah dimuat.
- Semua Modul, Ayam, Maggot BSF, Cacing Tanah, Tanaman, Lele.
- Semua tanggal, Hari ini, 7 hari terakhir, Bulan ini, rentang custom; terbaru/terlama.
- Pagination 20 dokumen, loading awal/lanjutan, empty/error/retry, refresh, akhir data.
- Detail dibaca berdasarkan ID dokumen aktual, dapat dimuat ulang; informasi utama, semua rincian bermakna dengan label/unit, catatan, dan relasi inventaris/produksi.
- Edit **catatan tambahan saja**, dilengkapi audit trail atomik dan deteksi konflik.
- Akses langsung ke catatan tersimpan melalui aksi **Lihat Catatan**.

Tidak menambah bottom navigation, dashboard baru, state management, dependency Flutter, layanan pencarian, Cloud Functions, atau Storage. Tooling Node hanya untuk pengujian emulator lokal.

## 2. Alur UI

1. Pilih satu dari lima modul dan isi pengamatan; field dimulai kosong.
2. Simpan Catatan memvalidasi input. Keyboard ditutup; input/tombol diblokir selama request.
3. Preview stok mengikuti perilaku sebelumnya: stok minus memerlukan konfirmasi pengguna. Nilai akhir dihitung dari stok terkini dalam transaksi, bukan hasil preview.
4. Setelah commit, SnackBar menawarkan Lihat Catatan yang membuka detail berdasarkan ID hasil service.
5. Isian tetap terlihat. Simpan dinonaktifkan untuk isian yang baru berhasil disimpan; pesan menjelaskan bahwa mengubah isian akan mempersiapkan catatan baru.
6. Daftar Logbook membuka route baru dengan filter modul asal. Pengguna dapat mengganti filter, mencari, memuat halaman berikut, dan membuka detail.
7. Kembali dari detail memuat ulang daftar agar hasil edit tidak tertahan dalam snapshot lama.

Batas tanggal memakai kalender lokal, bukan pembagian durasi UTC: batas awal inklusif dan awal hari berikutnya eksklusif. Tujuh hari mencakup hari ini dan enam hari sebelumnya. Bulan ini dari tanggal 1 sampai akhir hari ini. Rentang custom mencakup seluruh hari terakhir. Pembatalan picker mengembalikan pilihan filter sebelumnya.

## 3. Struktur data dan kontrak layanan

Collection `logbooks` mempertahankan `id`, `title`, `moduleType`, `activityDate`, `activityType`, `quantity`, `unit`, `status`, `notes`, `details`, `createdBy`, `updatedBy`, `createdAt`, `updatedAt`, `isDeleted`.

- ID navigasi selalu ID dokumen, tidak mempercayai field `id` yang mungkin berbeda pada data lama.
- Model tetap membaca alias legacy. Kuantitas yang hilang tidak ditampilkan sebagai nol; nol yang benar-benar tercatat tetap terlihat. Waktu metadata yang hilang berlabel Belum tersedia pada detail.
- Label, unit, ikon, warna, dan validasi memakai `logbook_form_spec.dart` bersama form dan detail. Key tak dikenal dibuat menjadi label manusiawi; field kosong disembunyikan.
- Field angka menolak NaN/infinity, teks tidak valid, serta negatif pada kuantitas; suhu berunit C boleh negatif. Persentase 0-100, pH 0-14, skor kandang 1-10, jumlah/satuan hitungan harus bulat. Nol mortalitas diterima. Tanggal form menerima DD/MM/YYYY atau YYYY-MM-DD dan menolak overflow kalender.
- Field teks yang menyerupai angka tetap teks; kode lokasi tidak kehilangan nol di depan.
- `createDailyEntry()` dan `createLogbookWithInventory()` kini `Future<String>`, dengan `requestId` opsional. Seluruh call site dan mock Phase 01 diaudit/dimigrasikan.
- ID request tetap saat retry tanpa perubahan input. Transaksi membaca dokumen logbook sebelum menulis. Payload identik yang sudah tersimpan mengembalikan ID yang sama tanpa efek stok/produksi tambahan; payload berbeda ditolak.
- Bila transaksi ditolak setelah request bersamaan lebih dahulu commit, service membaca ulang **dari server** dan hanya mengakui sukses jika pembuat, modul, judul, jenis aktivitas, kuantitas/unit, notes, details, serta status tidak dihapus cocok.
- Perlindungan request berada dalam sesi form. Tidak ada antrean offline persisten lintas restart aplikasi; lihat risiko tersisa.

Edit menambahkan `lastNoteEditId` pada parent dan dokumen immutable `logbooks/{id}/note_edits/{editId}` berisi `before`, `after`, `editedBy`, `editedAt`. Audit dan perubahan notes berada dalam satu transaksi. `expectedUpdatedAt` mencegah penimpaan edit yang sudah berubah. Rincian pengamatan asli, termasuk catatan asli di details, tetap dipertahankan; notes adalah deskripsi tambahan terkini.

## 4. Query, pagination, dan index

Query daftar: `isDeleted == false`, opsional `moduleType == module`, opsional rentang `activityDate`, `orderBy(activityDate, descending: ...)`, `limit(20)`, lalu `startAfterDocument(cursor)`.

- Tidak memakai listener daftar atau full collection scan.
- Filter/urutan/refresh mereset hasil dan cursor. Nomor generasi request mengabaikan respons filter lama yang terlambat.
- ID dideduplikasi ketika halaman digabung. Tie tanggal ditangani urutan dokumen implicit Firestore dalam cursor snapshot.
- Jika halaman tepat 20, tombol berikutnya dapat menghasilkan halaman kosong sebelum menampilkan akhir data; tidak ada total fiktif.
- Search hanya judul/notes dari hasil yang sudah dimuat. Tidak mencari seluruh database atau mengambil koleksi tambahan. Pesan cakupan tersedia di UI.
- Detail: satu dokumen berdasarkan ID. Relasi diquery dengan `logbookId`, masing-masing `limit(50)`, tanpa mengklaim jumlah total. Jika mencapai batas, UI menjelaskan batasnya. Relasi/error dapat di-retry secara terpisah.

`firestore.indexes.json` sudah berisi empat index yang diperlukan: `isDeleted ASC + activityDate ASC/DESC`, dan `isDeleted ASC + moduleType ASC + activityDate ASC/DESC`. Tidak menambah index duplikat. JSON dan kelengkapan empat kombinasi diperiksa; query diuji di emulator. Emulator **tidak membuktikan ketersediaan composite index produksi**; pengelola perlu memastikan index existing telah diterapkan. Tidak melakukan deployment.

Dokumen legacy yang tidak memiliki field query `isDeleted`/`activityDate` tidak dapat masuk query modern ini. Parser detail tetap kompatibel, tetapi normalisasi dokumen lama memerlukan audit/migrasi terencana; tidak memuat seluruh koleksi untuk mengakalinya.

## 5. Matriks hak akses

Semua hak mensyaratkan akun aktif; role `operator` mengikuti operator lapangan.

| Role | Baca daftar/detail | Buat | Edit catatan tambahan + audit | Koreksi kuantitas | Pembatalan/hapus |
| --- | --- | --- | --- | --- | --- |
| Admin | Ya | Ya | Ya | Belum diaktifkan | Belum diaktifkan |
| Operator lapangan | Ya | Ya | Ya | Belum diaktifkan | Tidak |
| Operator keuangan | Ya | Tidak | Tidak | Tidak | Tidak |
| Mitra/peserta edukasi | Ya | Tidak | Tidak | Tidak | Tidak |
| Inaktif/tanpa autentikasi | Tidak | Tidak | Tidak | Tidak | Tidak |

Rules baru tidak memberi pengecualian admin untuk memodifikasi field transaksi/audit parent secara bebas. Update parent hanya notes, updatedBy, updatedAt, lastNoteEditId, dengan timestamp server dan audit baru yang sesuai. Audit tidak dapat diubah/dihapus. Create memerlukan pembuat/updater sendiri serta timestamp server. Delete dan soft delete parent ditolak untuk seluruh role dalam Phase 02. Capability admin legacy `canDeleteLogbooks` tetap merupakan identifikasi role; tidak ada aksi pembatalan aktif pada UI.

**Deployment manual diperlukan:** pengelola harus meninjau dan menerapkan `firestore.rules` pada project tujuan sebelum memakai edit ber-audit. Rules lama belum memberikan pembatasan field baru ini. Tidak menjalankan deployment produksi. Rules koleksi lain mempertahankan fondasi lama; khususnya akses perubahan inventory oleh operator belum membuktikan invariant bisnis terhadap client yang sengaja dimodifikasi. Hardening lintas koleksi tetap pekerjaan berikutnya.

## 6. Inventaris, produksi, dan hasil audit mapping

Create tetap satu transaksi Firestore: logbook, stok, inventory_transactions, production_results, dan notifikasi stok rendah. Semua pembacaan transaksi dilakukan sebelum penulisan; retry callback menggunakan ID transaksi/produksi yang disiapkan sebelumnya.

- Lookup item existing tetap berdasarkan itemKey; item baru dari logbook menggunakan ID deterministik `logbook_{itemKey}` agar request bersamaan tidak membuat dua item baru untuk key yang sama.
- Item stok yang dihapus selama request, tidak aktif, atau memiliki unit berbeda ditolak sehingga tidak dibangkitkan kembali dari snapshot lama.
- Input pakan Lele pagi dan sore sama-sama berlabel Maggot pada form original. Keduanya kini menuju maggot_segar dan digabung sebelum transaksi; satu stock document ditulis satu kali dengan total pakan, bukan saling menimpa.
- Mapping hasil panen aktual yang tersedia (telur, kascing, kascing cair, hasil tanaman dikenal, lele) tetap membuat produksi sekali bersama transaksi stok.

Mapping yang sengaja dibatasi berdasarkan audit label/satuan form:

| Field | Temuan | Perilaku baru |
| --- | --- | --- |
| `estimasi_panen_kg` | Label Estimasi Panen Larva, bukan hasil panen aktual | Simpan pengamatan; tidak otomatis membuat stok/produksi. Key aktual `panen_maggot_kg` tetap didukung service, tetapi form original belum memiliki field ini |
| `media_cacing_kg` | Label Jumlah Bibit, bukan konsumsi Media Cacing | Simpan pengamatan; tidak mengurangi stok media |
| `pupuk_kascing_cair_liter` | Suffix form L/m2, bukan total liter; luas tidak tersedia | Simpan dosis pengamatan; tidak mengurangi total stok kascing cair |
| `pakan_maggot_pagi_kg` + `pakan_lele_kg` | Label Pakan Maggot Pagi/Sore | Kurangi total maggot_segar sekali |

Tidak mengubah/migrasi histori lama. Koreksi mapping berlaku untuk penyimpanan baru. Data lama yang sudah mengalami efek estimasi/dosis atau mapping lama memerlukan rekonsiliasi terpisah. Jenis tanaman tak dikenal tidak ditebak menjadi hasil produksi.

Edit notes tidak memanggil create, mapping, atau penulisan koleksi stok/produksi. Generic `save(id: existing)` ditolak agar tidak menjadi jalur edit kuantitas yang melewati koreksi.

Pembatalan **belum selesai penuh dan tidak diaktifkan**. `softDelete()` sekarang menolak operasi secara eksplisit. Helper rollback lama dibaca dan tidak dipakai: ia melakukan read setelah write untuk beberapa item, memakai snapshot transaksi yang diambil di luar transaksi, tidak membaca ulang isReversed, dan tidak membatalkan produksi. Menggunakannya dapat menyebabkan rollback ganda/parsial. Tidak ada hasil produksi yang disembunyikan sementara stoknya belum dikoreksi.

## 7. Risiko dan batas verifikasi

- Koreksi kuantitas dan pembatalan atomik lintas koleksi ditunda. Tidak ada tombol hapus aktif, termasuk untuk catatan tanpa relasi, sampai strategi pembatalan tervalidasi.
- Kebijakan stok minus yang sudah ada dipertahankan: pengguna diberi konfirmasi preview. Perubahan stok bersamaan dapat mengubah sisa akhir dibanding preview. Penegakan kebijakan stok nonnegatif perlu keputusan bisnis; tidak mengubah rumus diam-diam.
- Identitas request tidak persisten setelah aplikasi ditutup. Retry dengan input berubah adalah catatan baru. Antrean offline dan rekonsiliasi hasil commit ambigu lintas restart perlu pekerjaan lanjutan.
- Pagination bukan snapshot konsisten seluruh database: perubahan activityDate/insert bersamaan dapat mengubah halaman; refresh memulai ulang. Edit notes Phase 02 tidak mengubah field pengurutan.
- Legacy itemKey ganda dan histori salah mapping belum dimigrasi. Query item existing masih mengikuti fondasi lookup lama; perlu audit sebelum migrasi/penegakan uniqueness menyeluruh.
- Detail menampilkan ID pembuat saat tersedia, bukan mengarang nama pengguna atau membaca seluruh daftar profil.
- Logbook parser mempertahankan alias lama; edit memerlukan schema/audit modern dan dapat ditolak rules pada dokumen yang belum ternormalisasi.
- Tidak mengklaim login, FlutterFire native, keyboard perangkat, dan transaksi dari Android nyata telah diuji end-to-end. Emulator menguji rules dan kontrak operasi menggunakan Firebase JS SDK; kode service Dart diuji dengan fake atomik yang menolak read-after-write.

## 8. Pengujian

| Pemeriksaan | Hasil |
| --- | --- |
| Format file Dart terkait | Lulus |
| `flutter analyze` | Lulus, tidak ada temuan |
| `flutter test --reporter expanded` | **81 test lulus**: 45 baseline/regresi dan 36 test Phase 02 |
| Firestore Emulator + Firebase JS SDK | **25 test lulus** |
| Capture visual Phase 02 | 4 test lulus, 4 PNG pada 320/1280 px dan skala teks 1,4 |
| `git diff --check` | Lulus |
| Audit dependency tooling Node | 0 vulnerabilities setelah override patch grpc; tidak menambah dependency Flutter |
| Index JSON dan empat kombinasi daftar | Valid; index existing dipakai ulang |
| FlutterFire Android nyata, login, keyboard fisik | Belum diuji end-to-end |
| Deployment produksi | Tidak dilakukan |

Suite mencakup regresi Phase 01, navigasi lima modul, default filter, debounce dan cakupan pencarian, filter tanggal/urutan, reset dan respons terlambat, pagination/cursor/tie, loading/error/retry/empty, detail, role, save berulang/gagal, nol dan validasi, edit notes, audit, serta pembatasan pembatalan.

Fake service/transaksi menguji retry callback, request identik, verifikasi commit bersamaan, beberapa stok, atomisitas kegagalan, unit berbeda, produksi satu kali, dan edit yang tidak menulis stok. Fake ini bukan implementasi Security Rules atau simulator konflik jaringan.

25 test Firestore Emulator menguji akses empat role, akun inaktif/tanpa auth, audit atomik dan immutable, larangan update kuantitas/soft delete/delete, query pagination, konflik edit, request create bersamaan dengan ID sama, beberapa item stok, dan write produksi yang ditolak tanpa perubahan parsial. Test kontrak create JS mengikuti bentuk operasi service; tidak menggantikan tes FlutterFire native.

Command reproduksi:

```bash
dart format lib/features/logbook lib/features/inventory/services/inventory_service.dart lib/features/profile/models/app_user.dart test/phase01_ui_test.dart test/phase02_logbook_test.dart test/phase02_logbook_service_test.dart test/phase02_visual_test.dart test/support/memory_firestore.dart
flutter analyze
flutter test --reporter expanded
git diff --check
npm ci --prefix tools/firestore_tests
firebase emulators:exec --only firestore --project demo-seicycle-phase02 --config firebase.phase02.json "npm --prefix tools/firestore_tests test"
flutter test test/phase02_visual_test.dart --dart-define=CAPTURE_UI=true --reporter expanded
```

Format dibatasi ke file relevan untuk melindungi perubahan pengguna. PNG fixture di `build/phase02/` menggunakan renderer Flutter, font SDK, lebar 320/1280, skala teks 1,4; bukan screenshot data produksi. PNG form Phase 01 dapat diregenerasi dengan suite capture Phase 01. Folder build dan log emulator tidak di-commit.

## 9. File dan tindak lanjut Phase 03

| File | Tujuan |
| --- | --- |
| `lib/features/logbook/screen/logbook_screen.dart` | Form original, route daftar/detail, save ID/idempotency/state |
| `lib/features/logbook/screen/logbook_list_screen.dart` | Filter/search/pagination dan kartu |
| `lib/features/logbook/screen/logbook_detail_screen.dart` | Pembacaan aktual, rincian/relasi, edit notes |
| `lib/features/logbook/models/logbook_form_spec.dart` | Spesifikasi original bersama, formatter dan validator |
| `lib/features/logbook/models/logbook_page.dart` | Kontrak filter, halaman/cursor, relasi, merge/search lokal |
| `lib/features/logbook/models/logbook_entry.dart` | ID dokumen asli, metadata kuantitas tersedia |
| `lib/features/logbook/services/logbook_service.dart` | Query terbatas, save ID/replay, notes/audit, blok operasi tidak aman |
| `lib/features/logbook/services/inventory_mapping.dart` | Audit estimasi/dosis/bibit dan agregasi pakan |
| `lib/features/inventory/services/inventory_service.dart` | ID item baru deterministik dan pengecekan snapshot/unit |
| `lib/features/profile/models/app_user.dart` | Pengelolaan Logbook mensyaratkan akun aktif |
| `firestore.rules` | Update notes ber-audit; larang koreksi/delete tidak aman |
| `test/phase01_ui_test.dart` | Migrasi return type mock, ekspektasi regresi tetap |
| `test/phase02_*`, `test/support/memory_firestore.dart` | Unit, widget, render, fake atomik |
| `firebase.phase02.json`, `tools/firestore_tests/*` | Konfigurasi demo dan test rules/kontrak JS |
| `README.md`, dokumen ini | Fitur nyata, penggunaan, batas dan hasil verifikasi |

Lanjutan: rancang koreksi delta stok/produksi dengan audit dan otorisasi menyeluruh, pembatalan idempotent yang membaca semua relasi sebelum menulis dan memperbarui agregasi laporan, rekonsiliasi histori/mapping legacy, total liter dari dosis serta luas, field panen Maggot aktual, persistensi request, dan verifikasi Android terhadap rules/index yang diterapkan. Manajemen batch Phase 03 tidak dikerjakan di Phase 02.

## Perlindungan Git/workspace

Fetch dan pull --ff-only ke fork yang ditentukan berhasil; HEAD dan origin awal sama pada `3bb0ec6`. Perubahan lokal pengguna pada audit Phase 01 dan registrant Linux/macOS dipertahankan serta dikecualikan dari commit Phase 02. Stash cadangan Phase 01 tidak diterapkan/dihapus. Tidak membuat branch, PR, merge, force push, reset destruktif, perubahan repository asal, seed, atau deployment produksi.
