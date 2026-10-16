# Firestore Composite Indexes SeiCycle

Daftar ini mengikuti query Flutter saat ini. Buat index lewat Firebase Console bila app menampilkan error `FAILED_PRECONDITION` berisi link pembuatan index. Tidak ada seed data besar yang diperlukan untuk index ini.

## Aktif Dipakai App

| Collection | Query | Field index yang disarankan |
| --- | --- | --- |
| `logbooks` | daftar semua logbook aktif terbaru | `isDeleted ASC`, `activityDate DESC` |
| `logbooks` | dashboard/report rentang tanggal | `isDeleted ASC`, `activityDate ASC` |
| `logbooks` | filter moduleType + logbook aktif terbaru | `isDeleted ASC`, `moduleType ASC`, `activityDate DESC` |
| `logbooks` | filter moduleType + report rentang tanggal | `isDeleted ASC`, `moduleType ASC`, `activityDate ASC` |
| `logbooks` | filter tanggal + logbook aktif terbaru | `isDeleted ASC`, `activityDate DESC` |
| `logbooks` | filter moduleType + tanggal + logbook aktif terbaru | `isDeleted ASC`, `moduleType ASC`, `activityDate DESC` |
| `logbooks` | AI recommendation logbook 45 hari terakhir | `isDeleted ASC`, `activityDate DESC` |
| `inventory` | item aktif, stok menipis di atas, urut nama | `isDeleted ASC`, `isLowStock DESC`, `name ASC` |
| `inventory` | dashboard stok rendah maksimal 5 item | `isDeleted ASC`, `isLowStock ASC`, `name ASC` |
| `inventory` | lookup otomatis logbook berdasarkan itemKey | `itemKey ASC`, `isDeleted ASC` |
| `inventory` | filter stok rendah per kategori | `isLowStock ASC`, `category ASC` |
| `schedules` | jadwal aktif urut tanggal | `isDeleted ASC`, `date ASC` |
| `schedules` | dashboard jadwal pending | `isDeleted ASC`, `status ASC` |
| `schedules` | dashboard jadwal overdue | `isDeleted ASC`, `status ASC`, `date ASC` |
| `schedules` | AI recommendation jadwal overdue | `isDeleted ASC`, `status ASC`, `date ASC` |
| `education_contents` | konten aktif terbaru untuk admin | `isDeleted ASC`, `updatedAt DESC` |
| `education_contents` | konten status tertentu terbaru | `isDeleted ASC`, `status ASC`, `updatedAt DESC` |
| `education_contents` | filter type untuk admin | `isDeleted ASC`, `type ASC`, `updatedAt DESC` |
| `education_contents` | filter moduleType untuk admin | `isDeleted ASC`, `moduleType ASC`, `updatedAt DESC` |
| `education_contents` | konten published + type terbaru | `isDeleted ASC`, `status ASC`, `type ASC`, `updatedAt DESC` |
| `education_contents` | konten published + moduleType terbaru | `isDeleted ASC`, `status ASC`, `moduleType ASC`, `updatedAt DESC` |
| `education_contents` | filter type + moduleType untuk admin | `isDeleted ASC`, `type ASC`, `moduleType ASC`, `updatedAt DESC` |
| `education_contents` | konten published + type + moduleType terbaru | `isDeleted ASC`, `status ASC`, `type ASC`, `moduleType ASC`, `updatedAt DESC` |
| `finance_transactions` | transaksi aktif terbaru | `isDeleted ASC`, `date DESC` |
| `finance_transactions` | report rentang tanggal | `isDeleted ASC`, `date ASC` |
| `finance_transactions` | AI recommendation finance bulan berjalan | `isDeleted ASC`, `date DESC` |
| `farm_modules` | modul aktif urut nama | `isActive ASC`, `name ASC` |
| `farm_modules` | dashboard modul aktif sesuai urutan brief | `isActive ASC`, `order ASC` |
| `users` | daftar user urut nama | `name ASC` |
| `notifications` | notifikasi personal aktif terbaru | `isDeleted ASC`, `userId ASC`, `createdAt DESC` |
| `notifications` | notifikasi role/global aktif terbaru | `isDeleted ASC`, `targetRole ASC`, `createdAt DESC` |
| `notifications` | filter tipe notifikasi personal | `isDeleted ASC`, `type ASC`, `userId ASC`, `createdAt DESC` |
| `notifications` | filter tipe notifikasi role/global | `isDeleted ASC`, `type ASC`, `targetRole ASC`, `createdAt DESC` |
| `notifications` | mark all unread personal | `isDeleted ASC`, `isRead ASC`, `userId ASC` |
| `notifications` | mark all unread role/global | `isDeleted ASC`, `isRead ASC`, `targetRole ASC` |
| `notifications` | low stock unread terbaru | `type ASC`, `isRead ASC`, `createdAt DESC` |
| `notifications` | cegah duplikasi notifikasi related item | `relatedCollection ASC`, `relatedId ASC`, `createdAt DESC` |
| `notifications` | notifikasi unread terbaru | `isDeleted ASC`, `isRead ASC`, `createdAt DESC` |
| `notifications` | filter tipe unread terbaru | `isDeleted ASC`, `type ASC`, `isRead ASC`, `createdAt DESC` |
| `notifications` | cegah duplikasi notifikasi related item aktif | `isDeleted ASC`, `relatedCollection ASC`, `relatedId ASC`, `createdAt DESC` |

## Disiapkan Untuk Collection Pendukung

| Collection | Query yang mungkin dibutuhkan | Field index yang disarankan |
| --- | --- | --- |
| `report_metadata` | laporan per tipe/periode | `type ASC`, `isDeleted ASC`, `periodStart DESC` |
| `recommendations` | snapshot rekomendasi opsional per modul | `moduleType ASC`, `isResolved ASC`, `priority ASC`, `createdAt DESC` |
| `inventory_transactions` | histori stok per logbook | `logbookId ASC`, `transactionDate DESC` |
| `inventory_transactions` | histori stok per item | `itemId ASC`, `transactionDate DESC` |
| `inventory_transactions` | histori stok per modul | `moduleType ASC`, `transactionDate DESC` |
| `production_results` | hasil produksi per modul | `moduleType ASC`, `harvestDate DESC` |
| `production_results` | hasil produksi per logbook | `logbookId ASC`, `harvestDate DESC` |
| `production_results` | dashboard hasil produksi terbaru | `harvestDate DESC` |
| `circular_flows` | dashboard aliran nutrisi terbaru | `flowDate DESC` |
| `circular_flows` | aliran nutrisi per sumber | `sourceModuleType ASC`, `flowDate DESC` |
| `circular_flows` | aliran nutrisi per tujuan | `destinationModuleType ASC`, `flowDate DESC` |

## Catatan

- Equality filter seperti `where('isDeleted', isEqualTo: false)` sering tetap perlu composite index ketika digabung dengan `orderBy` field lain.
- Untuk range tanggal, Firestore mengharuskan field range menjadi urutan pertama yang relevan pada `orderBy`; service sudah memakai `activityDate` dan `date` sesuai query.
- Query notifikasi memakai OR untuk personal dan role/global. Jika Firebase Console meminta index tambahan, buat dari link error dan update file ini.
- File deployable index berada di `firestore.indexes.json` dan sudah direferensikan oleh `firebase.json`.
- Jangan membuat collection tambahan untuk file laporan atau media; batasan MVP tetap tanpa Storage dan tanpa backend server.


## Phase 03: query batch yang dipakai

Sembilan index ditambahkan ke `firestore.indexes.json`, tanpa mengubah index existing:

| Collection | Equality fields (ASC) | Order |
| --- | --- | --- |
| `batches` | `isDeleted` | `createdAt ASC` dan `DESC` (2 index) |
| `batches` | `isDeleted`, `moduleType` | `createdAt ASC` dan `DESC` (2 index) |
| `batches` | `isDeleted`, `status` | `createdAt ASC` dan `DESC` (2 index) |
| `batches` | `isDeleted`, `moduleType`, `status` | `createdAt ASC` dan `DESC` (2 index) |
| `logbooks` | `isDeleted`, `batchId` | `activityDate DESC` (1 index) |

Daftar/pemilih batch memakai `limit(20)` dan `startAfterDocument(cursor)`. Pemilih hanya query modul terkait + status active; urutan masih dapat dipilih. Aktivitas batch memakai limit/cursor 20 catatan, tanpa filter modul tambahan karena batch sudah memiliki modul tetap. Pencarian nama/kode hanya di hasil yang dimuat. Tidak ada index produksi per batch karena Phase 03 tidak melakukan query tersebut.

Emulator membuktikan bentuk query dan pagination, bukan ketersediaan composite index produksi. Deployment harus dilakukan manual sesudah review dan persetujuan pengelola terhadap project tujuan:

```bash
firebase deploy --only firestore:rules,firestore:indexes --project <project-yang-disetujui>
```

Perintah ini adalah petunjuk untuk pengelola dan tidak dijalankan dalam pengerjaan Phase 03. Tunggu index selesai dibangun sebelum uji perangkat.
