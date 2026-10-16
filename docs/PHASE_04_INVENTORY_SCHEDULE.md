# Phase 04 — Inventaris & Jadwal Operasional

16 Oktober 2026 (Asia/Jakarta). Repository `Freddy47588/sei_cycle`, branch `feature/operational-v2`, baseline `f12cf58bc017e8a9059faa1b0d09668c58f28d4f`.

## 1. Gambaran fitur dan UI

Inventaris memiliki daftar barang dengan nama, kategori, modul, unit, stok aktual/minimum, kondisi aman/rendah/habis, lokasi dan waktu update. Pencarian nama/key/lokasi, filter modul/kategori, status stok, pengurutan nama/stok/update, pagination dan state loading/kosong/error/retry tersedia. Edit master, mutasi dan histori dipisahkan. Histori dapat dibuka per barang, Logbook dan batch; pengguna dapat memilih satu dimensi server (barang, batch, Logbook, modul, jenis atau sumber) bersama rentang tanggal.

Jadwal mempertahankan halaman Kalender Operasional dengan checklist Hari Ini/Mendatang/Terlewat/Selesai/Semua, filter modul/tanggal, batch opsional, catatan, audit penyelesaian/dilewati, navigasi ke form Logbook dan retry pengingat perangkat. Detail Batch menyediakan pintu masuk histori stok dan jadwal batch. Tidak menambah bottom navigation, layanan atau dependency; Dashboard dan halaman utama lainnya tidak didesain ulang.

Palet, krem, tipografi, geometri komponen dan shell Phase 01 dipakai kembali. Referensi Logbook `origin/main` dibandingkan dengan sumber Phase 03; form lima modul tetap memakai spesifikasi dan susunan field existing. PNG widget fixture di `build/phase04/` mencakup inventaris, histori, jadwal, master dan mutasi pada 320/1280 px, skala teks 1,4. PNG bukan screenshot Android terhubung Firebase.

## 2. Arsitektur inventaris

- `InventoryService.createItem`: identitas dan stok awal opsional, dengan request ID stabil selama form terbuka.
- `saveMetadata`: transaksi metadata yang tidak menerima currentStock; pemeriksaan versi `updatedAt` mencegah penimpaan data lama.
- `InventoryAdjustmentService.mutate`: satu pintu mutasi manual; `calculateStock` membedakan masuk/keluar dan koreksi absolut.
- `InventoryTransactionService.fetchPage`: query histori/cursor 20, tanpa mengubah ledger lama.
- `InventoryItem` menghitung indikator rendah dari currentStock/minStock aktual, mengabaikan flag legacy yang tidak konsisten. ID navigasi mengikuti document ID.
- Parser transaksi mempertahankan data lama, reversal, sumber legacy/Logbook, batch opsional dan nama field canonical.

Unit, itemKey dan modul master immutable setelah create karena menggantinya dapat mengubah makna ledger/mapping existing. Nama, kategori, lokasi dan minimum dapat diedit. Admin hanya dapat soft delete master bersaldo nol. Ledger tidak pernah dihapus atau diedit; barang soft deleted tidak diaktifkan ulang melalui retry.

## 3. Strategi transaksi stok

Setiap mutasi membaca profil aktif, receipt request, dokumen barang dan batch opsional **sebelum** menulis. Stock dihitung dari snapshot transaksi terkini. Write atomik mencakup `currentStock`, `isLowStock`, `updatedBy`, server `updatedAt`, `lastTransactionId` dan dokumen baru `inventory_transactions/{requestId}`.

| Operasi | Input | Saldo akhir | Quantity histori |
| --- | --- | --- | --- |
| Masuk | kuantitas positif | before + nilai | nilai |
| Keluar | kuantitas positif | before - nilai | nilai |
| Koreksi | stok fisik nonnegatif absolut | nilai | abs(after - before) |
| Saldo awal | stok awal positif | nilai dari nol | nilai |

Koreksi wajib memiliki alasan/catatan. Koreksi ke nilai yang sama tetap menjadi observasi stock opname dengan delta nol. Saldo awal nol/tidak diisi tidak membuat histori; nilai positif memakai ID `opening_{itemId}` dan commit bersama master. Kuantitas awal, minimum dan input manual menolak NaN/infinity/negatif serta membatasi nilai sampai 10^12 di Dart. Rules menjaga finite/batas 10^15 untuk kompatibilitas kontrak stok Logbook sebelumnya.

Kebijakan Logbook Phase 02 tetap mengizinkan saldo minus setelah konfirmasi di form. Mutasi manual juga dapat menghasilkan minus hanya dengan `allowNegative: true` yang disetujui pengguna dan tersimpan pada audit. Koreksi adalah jumlah fisik nonnegatif, bukan delta negatif. Preview stok di form hanya informasi; saldo saat commit selalu dibaca ulang.

## 4. Integritas dan idempotency

Receipt manual menyimpan requestId, requestedValue, type, unit, notes, aktor, batch dan izin minus. Retry dengan payload identik mengembalikan sukses tanpa mengubah saldo/histori. Request ID sama dengan payload berbeda ditolak. Create master/jadwal menyimpan `creationPayload` immutable untuk memverifikasi retry, termasuk setelah metadata kemudian berubah. Form mempertahankan ID dan input saat gagal, serta menonaktifkan tombol ketika request berjalan.

Transaksi Firestore menangani konflik snapshot. Emulator juga memperlihatkan bahwa pemeriksaan pasangan ledger melalui Rules dapat menolak attempt yang sudah tertinggal dengan permission-denied sebelum retry SDK. `runOperationalTransaction` mencoba ulang maksimal tiga pemanggilan transaksi untuk permission-denied/aborted, selalu membaca ulang dan memakai ID yang sama. Penolakan otorisasi atau kontrak tetap ditolak; tidak ada fallback write di luar transaksi. Jalur create Logbook mempertahankan pemeriksaan payload tersimpan dari server setelah respons ambigu.

`lastTransactionId` mengikat satu write stok dengan **histori baru**. Rules sisi inventaris membandingkan before/after serta aktor/waktu receipt. Rules sisi ledger membandingkan barang sesudah commit, nama/key/unit, stok sebelumnya, pointer, kuantitas, perhitungan operasi, source dan audit. Replay receipt lama, stok tanpa histori, histori tanpa stok, reversal palsu, perubahan createdBy/createdAt, unit ilegal dan edit histori ditolak untuk admin sekalipun.

Keunikan global itemKey belum menggunakan koleksi reservasi/migrasi. Jangan membuat master kedua untuk itemKey mapping yang sudah ada; gunakan mutasi pada master existing. Sistem ini bukan transfer/reservasi antarlokasi atau saldo per batch.

## 5. Integrasi Logbook dan Batch

Mapping pakan/hasil produksi Phase 02 dipertahankan. Logbook menambahkan pointer/source/request pada write stok existing; untuk barang existing hanya saldo, flag dan audit update yang berubah. Nama/unit/key/modul master tidak ditimpa oleh modul Logbook yang memakai persediaan bersama.

`batchId` ledger merupakan atribusi pemakaian/produksi; `inventory.currentStock` tetap saldo lokasi. Batch manual harus aktif, tidak dihapus dan cocok dengan modul master. Batch jadwal divalidasi dalam transaksi dan Rules `getAfter`. Catatan lama tanpa batch tetap dibaca. Pembacaan/penyelesaian jadwal lama tidak mensyaratkan batch tetap aktif; tidak ada pemindahan batch diam-diam.

Detail Logbook membuka Histori Stok berdasarkan logbookId. Histori membuka Detail Logbook aktual. Detail Batch membuka mutasi dan kalender batch. Reversal lama ditandai DIBALIK, tanpa dijumlahkan sebagai mutasi baru. Helper rollback/reversal lama melempar UnsupportedError dan Rules menolak perubahan ledger. Koreksi kuantitas, pembatalan, soft delete Logbook dan edit pengamatan tetap dinonaktifkan; notes audit Phase 02 tidak dilonggarkan.

## 6. Jadwal dan checklist

Create selalu `pending`; batch dipilih eksplisit atau null untuk Aktivitas Umum. Save menggunakan ID stabil dan menyimpan metadata penciptaan immutable. Edit hanya untuk pending, memeriksa versi serta keabsahan batch terkini. Status tersimpan tetap `pending`, `done`, `skipped`.

- Done menyimpan completedAt server dan completedBy pengguna pertama.
- Skipped menyimpan skippedAt, skippedBy dan skipReason opsional.
- Tap identik adalah no-op; status terminal yang berbeda/versi lama ditolak.
- Jadwal selesai/dilewati menjadi histori, tanpa reopen atau edit bebas. Admin hanya soft delete pending; hard delete ditolak.
- Penyelesaian tidak membuat Logbook, produksi atau mutasi stok.

Catat di Logbook memuat batch aktual terlebih dahulu, membuka tab modul yang sesuai, mengisi konteks batch yang masih valid dan menampilkan judul kegiatan. Jika batch sudah tidak aktif, pengguna diberi pesan dan form terbuka tanpa batch; form tidak memilih pengganti. Pengamatan dimulai kosong dan Simpan Catatan tetap eksplisit. Tidak menyimpan linkedLogbookId dalam Phase 04, sehingga navigasi ini tidak mengklaim jadwal telah memiliki satu catatan unik. Perlindungan request Logbook yang sudah ada tetap berlaku saat save.

## 7. Pengingat lokal dan notifikasi

Penyimpanan Firestore selesai sebelum proses perangkat. Kegagalan izin/native/sinkronisasi tidak dilaporkan sebagai gagal menyimpan jadwal dan tidak menjalankan create kedua. Hasil pengingat tampil tersendiri; Sinkronkan Pengingat dapat dicoba ulang.

Sinkronisasi saat login, resume, perubahan jadwal dan aksi manual mengambil maksimal 50 pending masa depan dalam horizon 14 hari. Reminder yang tidak lagi sesuai dibatalkan; setiap kandidat dijadwalkan dengan ID DJB2 deterministik berdasarkan schedule ID. Pending reminder legacy berbasis hashCode dibatalkan melalui ID aslinya saat rekonsiliasi. Benturan ID terdeteksi dan ditampilkan sebagai gagal sinkronisasi, bukan keberhasilan palsu.

Sesudah edit/done/skipped/delete, reminder lama dibatalkan sebelum query rekonsiliasi agar kegagalan pembacaan berikutnya tidak mempertahankan jam lama. Operasi perangkat lintas instance diantrikan, double sync satu instance digabung, dan logout membatalkan pengingat sebelum sesi login baru memasang ulang. Dispose dan state async dijaga agar tidak memperbarui widget yang sudah ditutup.

Waktu picker mengikuti timezone perangkat; konversi ke `TZDateTime` UTC mempertahankan instant yang sama tanpa mengasumsikan tz.local telah terdeteksi. Android tetap memakai inexactAllowWhileIdle, bukan exact alarm. Manifest menambahkan receiver jadwal/boot dan RECEIVE_BOOT_COMPLETED; POST_NOTIFICATIONS serta desugaring existing dipertahankan. Izin yang ditolak ditampilkan dan tidak membatalkan Firestore. Perangkat/platform tanpa implementasi native tidak diberi klaim berhasil.

Notifikasi low_stock menggunakan ID existing `low_stock_{uid}_{itemId}`; informasi identik tidak mereset status baca. Safe recovery menutup alert milik aktor saat diperiksa, dan pesan selalu menjelaskan kondisi **saat pemeriksaan**, bukan menjamin saldo sekarang. Pembukaan inventaris tidak membuat write notifikasi dari rebuild. Notifikasi overdue juga memeriksa jadwal aktual dan memakai ID deterministik; tidak dibuka ulang hanya karena sudah dibaca. Sistem tidak mengirim push server atau menjamin perubahan status antardevice saat semua aplikasi tertutup.

Recurrence harian/mingguan **belum diaktifkan**, sesuai prioritas integritas pada brief. Tidak ada materialisasi occurrence atau scheduler server yang diklaim selesai.

## 8. Hak akses

| Pengguna | Baca Inventaris/Jadwal/Histori | Kelola master/mutasi/jadwal/checklist | Soft delete master nol/pending |
| --- | --- | --- | --- |
| Admin aktif | Ya | Ya | Ya |
| Operator lapangan aktif / legacy operator | Ya | Ya | Tidak |
| Operator keuangan aktif | Ya | Tidak | Tidak |
| Mitra/peserta edukasi aktif | Ya | Tidak | Tidak |
| Inaktif, tanpa autentikasi, role tidak didukung | Tidak | Tidak | Tidak |

`isActive == false` atau `is_active == false` menolak akses, termasuk bila flag satunya true. Capability Flutter juga mensyaratkan akun aktif. Tidak ada bypass stok admin. Batas baca/finance lain yang diwarisi Phase 01 di luar koleksi operasional ini tidak dipresentasikan sebagai hardening keamanan seluruh aplikasi.

## 9. Rules, index dan efisiensi

Rules inventory/schedules memisahkan metadata, mutasi berpasangan dan perubahan status/audit. Ledger immutable. Tidak mengubah aturan notes Logbook, lifecycle batch atau memberi jalur rollback baru. Seluruh get pada callback Dart berada sebelum write. Regression Rules mencakup Logbook empat item + batch + notifikasi/produksi agar batas document-access Rules tidak diasumsikan cukup.

17 composite index ditambahkan tanpa menambah duplikat dari baseline: 4 inventory (`isDeleted`, kombinasi modul/kategori, `name ASC`), 3 histori (batch/type/source + transactionDate DESC; item/modul/Logbook existing dipakai ulang), serta 10 jadwal (kombinasi batch/modul/status dengan date ASC atau DESC sesuai tampilan). Total definisi kini 76. Index tanggal histori tanpa equality memakai index field bawaan.

Halaman memakai limit/cursor 20, deduplikasi ID dan generasi query untuk mengabaikan respons lama. Inventory memasang satu listener berisi ID barang pada setiap halaman yang sudah dimuat; listener dibatalkan ketika filter/reset/dispose. Tidak mengambil koleksi penuh di build. Pencarian, status stok dan sort tambahan berlaku pada hasil yang telah dimuat. Filter modul/kategori dan filter histori/tanggal/status jadwal memakai Firestore. Angka daftar secara eksplisit berlabel data dimuat, bukan statistik global.

Listener barang mengikuti perubahan saldo dan kondisi aman/rendah saat operator lain menulis. Barang baru/keanggotaan kategori yang baru perlu refresh daftar; listener berfokus pada ID halaman. Jadwal/histori adalah snapshot berhalaman; operator dapat memuat ulang. Query reminder hanya horizon terbatas. API kompatibilitas watchItems/watchSchedules juga dibatasi 100; screen Phase 04 menggunakan pagination.

Rules/index **tidak dideploy**. Pengelola perlu review, persetujuan deployment manual pada project tujuan dan menunggu index siap. Emulator tidak membuktikan index produksi sudah terpasang. Client lama yang menulis currentStock langsung akan ditolak oleh Rules baru; pembaruan aplikasi dan Rules harus dikoordinasikan.

Rujukan teknis: [kondisi Rules/getAfter dan batas akses](https://firebase.google.com/docs/firestore/security/rules-conditions), [setup flutter_local_notifications 22.0.1](https://pub.dev/packages/flutter_local_notifications/versions/22.0.1).

## 10. Pengujian

Baseline: flutter analyze bersih, 121 test Flutter lulus. Seluruh regresi Phase 01–03 dijalankan bersama tambahan Phase 04. Test double Dart menstage write atomik, menolak read-after-write, menyuntik kegagalan/retry serta respons commit ambigu; Rules nyata dan konkurensi diuji melalui Firebase JS SDK terhadap Firestore Emulator demo, bukan database produksi.

| Pemeriksaan akhir | Hasil |
| --- | --- |
| flutter analyze | Lulus, tidak ada temuan |
| flutter test --reporter expanded | 181 lulus: 121 regresi + 36 service/unit + 24 widget Phase 04 |
| Firestore Emulator, regresi Phase 02/03 dan Phase 04 | 73 lulus |
| Capture widget Phase 04 | 10 PNG, 5 tampilan, 320/1280 px, teks 1,4 |
| git diff --check | Lulus |
| Format | Hanya file Dart Phase 04 yang berubah |
| JSON/query index dan duplikasi tambahan | Diverifikasi terhadap kombinasi query yang dipakai |
| Android/native notification end-to-end | Belum diuji; hanya Chrome/Edge terdeteksi |

Perintah reproduksi:

```bash
flutter analyze
flutter test --reporter expanded
flutter test test/phase04_operations_ui_test.dart --dart-define=CAPTURE_UI=true --reporter expanded
firebase emulators:exec --only firestore --project demo-seicycle-phase02 --config firebase.phase02.json "npm --prefix tools/firestore_tests test"
git diff --check
```

Dalam sesi ini CLI memulai emulator demo di 127.0.0.1:8089. Karena proses emulator masih tersedia sesudah runner pertama, suite berikutnya dijalankan dengan `npm --prefix tools/firestore_tests test`; test environment memuat Rules dari file terbaru. Tidak ada endpoint produksi, seed produksi, deployment atau dependency baru.

Cakupan tambahan: masuk/keluar/koreksi dan saldo awal; setiap receipt; replay/payload beda; konflik dua operator; kegagalan atomik; metadata/unit/NaN/infinity; kebijakan minus; histori/filter/cursor/legacy/reversal; Logbook tanpa duplikasi; batch cocok/tidak cocok/inaktif; checklist aktor/waktu/idempotency/race; filter tanggal/status/modul/batch; navigasi Logbook tanpa write; cancel/rejadwal/reminder denied; retry/login/logout; otorisasi admin/lapangan/keuangan/legacy/inaktif/anonim/unknown; UI states, pagination, stok live dan aksesibilitas ukuran teks.

## 11. Risiko dan batasan

- Tidak ada Android terhubung untuk uji native notification, reboot, permission, login Firebase nyata, keyboard fisik atau E2E FlutterFire. Waktu tampil reminder tunduk pada izin dan kebijakan OS.
- Request ID create/mutasi tersimpan selama form aktif, belum ada outbox persisten lintas restart. Sesudah respons ambigu dan form ditutup, periksa histori/jadwal dahulu sebelum membuat permintaan baru.
- Tidak ada recurrence, transfer/reservasi, saldo fisik per batch, reopen checklist, koreksi kuantitas/pembatalan Logbook, atau linkedLogbookId persisten.
- Belum ada reservasi keunikan global itemKey. Duplikat legacy perlu audit/migrasi terencana; jangan menambah itemKey mapping yang sama pada dua master.
- Dokumen legacy tanpa field query canonical masih dapat diparsing lewat ID tetapi memerlukan normalisasi terencana agar masuk query modern. Tidak ada full scan/migrasi otomatis.
> Catatan historis: fitur data sampel runtime dihapus pada Phase 06. Jangan membuat data demo pada project operasional; lihat PHASE_06_SAMPLE_DATA_CLEANUP.md.
- Ledger bukan bukti pekerjaan fisik atau stok opname benar-benar terjadi; kebenaran operasional tetap tanggung jawab aktor yang tercatat. Koleksi produksi/finance dan sistem registrasi yang diwarisi belum diaudit ulang sebagai seluruh backend.
- Peringatan pengguna lain tidak dihapus secara massal; pesan historisnya bertanggal dan mengarahkan pembaca memeriksa inventaris terkini. Alert pribadi direkonsiliasi saat aktor memproses data terkait.
- Tidak ada jaminan push server, sinkronisasi reminder saat semua perangkat offline, atau jadwal occurrence otomatis ketika aplikasi tertutup.

Lima perubahan lokal pengguna pada audit Phase 01 serta registrant Linux/macOS dipertahankan dan dikecualikan dari staging. Tidak menghapus stash, melakukan reset/force push, merge/PR, atau mengubah main/backend/repository upstream.

## 12. Persiapan Phase 05

Ledger bertipe/source/batch dan audit checklist siap menjadi input Dashboard & Monitoring Produktivitas. Phase 05 perlu menetapkan agregasi global yang membedakan saldo fisik, mutasi dan hasil produksi, strategi pagination/cache, dan statistik produktivitas yang tidak menggandakan produksi dari ledger stok masuk. Tidak mengimplementasikan Dashboard monitoring dalam Phase 04.

## Daftar file Phase 04

| Kelompok file | Fungsi |
| --- | --- |
| `lib/features/inventory/models/{inventory_item,inventory_transaction}.dart` | ID nyata, kondisi stok, sumber dan batch legacy |
| `lib/features/inventory/services/{inventory_service,inventory_adjustment_service,inventory_transaction_service}.dart` | Master, saldo awal, transaksi idempotent, listener terbatas, query histori dan guard rollback |
| `lib/features/inventory/screen/{inventory_screen,inventory_history_screen}.dart` | Daftar/filter/status, mutasi dan audit berhalaman |
| `lib/features/inventory/widgets/{inventory_master_form,inventory_transaction_form}.dart` | Form terpisah, validasi dan guard retry |
| `lib/features/schedule/models/{schedule_item,schedule_filter}.dart` | Batch, audit checklist dan query tampilan |
| `lib/features/schedule/services/{schedule_service,reminder_sync_service}.dart` | Transaksi batch/checklist, versi, reminder dan hasil terpisah |
| `lib/features/schedule/screen/schedule_screen.dart`, `widgets/schedule_form.dart` | Kalender/checklist, filter, input dan rute Logbook |
| `lib/core/models/firestore_page.dart`, `widgets/firestore_paged_list.dart`, `utils/operational_auth.dart` | Cursor/generasi/listener, profil aktif, angka dan retry terbatas |
| `lib/core/services/local_reminder_service.dart`, AndroidManifest | Permission, stable ID, instant UTC, rekonsiliasi reminder lama dan receiver |
| `lib/app/app_shell.dart` | Login/resume/logout reminder tanpa perubahan menu utama |
| `lib/features/batches/widgets/operational_batch_picker.dart`, `screen/batch_detail_screen.dart` | Pemilih batch eksplisit serta pintu histori/jadwal batch |
| `lib/features/logbook/screen/{logbook_screen,logbook_detail_screen}.dart`, `services/logbook_service.dart` | Konteks jadwal/tab/batch, rute histori, pointer stok, retry dan alert |
| `lib/features/notification/services/notification_service.dart`, `profile/models/app_user.dart` | Alert aktual/dedupe serta capability akun aktif |
| `firestore.rules`, `firestore.indexes.json` | Pasangan saldo/ledger, audit/role/status/batch dan 17 query index |
| `test/phase04_operations{,_ui}_test.dart`, `test/support/memory_firestore.dart` | 60 test Phase 04 dan fake transaksi/query/listener |
| `tools/firestore_tests/logbook_rules.test.mjs` | Kontrak fixture ledger baru, uji Rules Phase 04 dan seluruh regresi |
| `README.md`, `docs/PHASE_04_INVENTORY_SCHEDULE.md`, `docs/FIRESTORE_{INDEXES,SCHEMA,RULES}.md` | Panduan fitur, kontrak, deployment manual, hasil dan risiko |

Commit/push Phase 04 hanya dilakukan setelah seluruh quality gate lulus, dengan pesan `feat(operations): integrate inventory and operational schedules`, ke `origin/feature/operational-v2`. SHA diverifikasi terhadap remote dan dilaporkan pada hasil pengerjaan.
