# Firestore Security Rules SeiCycle

Rules final ada di `firestore.rules` dan sudah direferensikan oleh
`firebase.json`. Aplikasi memakai arsitektur client-side: role dibaca dari
dokumen `users/{uid}`, bukan custom claims, Cloud Functions, backend server,
atau Firebase Storage.

## Prinsip Utama

- Semua data aplikasi mensyaratkan Firebase Auth.
- Koleksi operasional dapat dibaca profil aktif dengan role yang didukung.
- User aktif adalah user yang punya dokumen `users/{uid}` dan `isActive` tidak
  bernilai `false` dan `is_active` tidak false; status ini juga berlaku untuk mutasi.
- Role valid utama: `admin`, `operator_lapangan`, `operator_keuangan`.
- Role legacy `operator`, `mitra`, dan `peserta_edukasi` masih dibaca untuk
  kompatibilitas data lama, tetapi role yang bisa diberikan admin tetap role
  utama.
- Tidak ada rule `allow read, write: if true`; collection yang tidak dikenal
  ditutup oleh fallback `allow read, write: if false`.

## Matriks Akses

| Collection | Read | Create | Update | Delete |
| --- | --- | --- | --- | --- |
| `users` | Semua user login | Owner membuat profil sendiri, admin membuat user valid | Owner update profil ringan; admin update role/status | Admin |
| `farm_modules` | User aktif | Admin | Admin | Admin |
| `logbooks` | User aktif | Admin, operator lapangan | Notes dengan audit atomik | Ditolak |
| `inventory` | Role aktif yang didukung | Admin/lapangan; saldo awal berhistori | Metadata atau stok dengan ledger baru; admin soft delete saldo nol | Ditolak |
| `inventory_transactions` | Role aktif yang didukung | Ledger baru berpasangan: manual/opening/Logbook | Ditolak | Ditolak |
| `production_results` | User aktif | Admin, operator lapangan dari Logbook | Admin | Admin |
| `circular_flows` | User aktif | Admin, operator lapangan | Admin | Admin |
| `schedules` | Role aktif yang didukung | Admin/lapangan, pending, batch valid opsional | Metadata pending/checklist ber-audit; admin soft delete pending | Ditolak |
| `finance_transactions` | User aktif | Admin, operator keuangan | Admin, operator keuangan | Admin, operator keuangan |
| `education_contents` | User aktif | Admin | Admin | Admin |
| `notifications` | User aktif | User aktif untuk alert client miliknya; admin untuk seed/system/demo alert | Penerima boleh set `isRead/readAt`; owner boleh refresh alert client miliknya | Admin |
| `report_metadata` | User aktif | Admin, operator keuangan | Admin, operator keuangan tanpa soft delete | Admin |
| `recommendations` | User aktif | Admin | Admin | Admin |

Catatan "user aktif" dipakai agar semua role tetap bisa membuka semua
tampilan utama. Pembatasan aksi mutasi tetap dilakukan di rules sesuai role.

## Detail Penting

- `users/{uid}`: user hanya dapat mengubah field profil ringan seperti `name`,
  `photoUrl`, `fcmToken`, dan `updatedAt`. Field `role` dan `isActive` hanya
  boleh diubah admin.
- `finance_transactions`: operator lapangan tetap dapat membaca untuk dashboard
  dan laporan, tetapi tidak dapat menulis.
- `education_contents`: semua user login bisa melihat konten untuk kebutuhan
  tampilan, sedangkan create/update/delete tetap hanya admin.
- `notifications`: semua user login bisa membaca koleksi untuk kebutuhan
  tampilan/badge. Alert otomatis dari client tetap dibatasi ke `userId` user
  login dan `targetRole` role user tersebut. Alert sistem global/role dibuat
  admin. Refresh alert client hanya boleh untuk notifikasi milik user yang sama.
- `recommendations`: rekomendasi default dibuat on-demand di Flutter. Collection
  disiapkan hanya bila admin nanti perlu menyimpan snapshot manual.

## Deploy

```powershell
firebase deploy --only firestore:rules,firestore:indexes
```

Jika Firebase Console meminta index tambahan saat app berjalan, buat dari link
error `FAILED_PRECONDITION`, lalu salin definisinya ke `firestore.indexes.json`
dan update `docs/FIRESTORE_INDEXES.md`.

## Phase 04 — kontrak operasional yang diperketat

Bagian ini memperbarui perilaku inventory/inventory_transactions/schedules yang mungkin masih dijelaskan lebih luas pada dokumentasi fondasi sebelumnya. Sumber otoritatif adalah `firestore.rules` dan suite emulator.

- Read operasional hanya untuk profil aktif dengan role yang didukung. isActive=false atau is_active=false menolak, termasuk admin; anonim/role tidak dikenal ditolak.
- Admin/operator lapangan mengelola metadata dan mutasi. Operator keuangan serta mitra/peserta edukasi read-only; legacy operator mengikuti lapangan.
- Tidak ada bypass admin untuk currentStock: pasangan histori **baru** wajib dalam commit atomik, dengan getAfter sebelum/sesudah, pointer lastTransactionId, kuantitas, unit, source dan identitas/waktu yang konsisten.
- Ledger tidak dapat diedit, dihapus atau dibalik oleh client. CreatedBy/createdAt master/jadwal immutable. Unit/key/modul master tetap sesudah create. Soft delete master hanya admin pada saldo nol.
- Jadwal baru pending, batch opsional harus active/cocok modul/tidak dihapus. Transisi pending ke done/skipped membatasi field dan mencatat aktor serta server timestamp. Terminal tidak bisa diedit/reopen; soft delete hanya pending oleh admin. Read/penyelesaian jadwal lama tidak bergantung status batch terkini.
- Perlindungan notes Logbook dan lifecycle batch tidak dilonggarkan. Rollback/pembatalan Logbook tetap nonaktif.

Rules/index belum dideploy. Koordinasikan pembaruan client, audit data/skrip seed lama, review dan deployment manual pada project tujuan. [Phase 04](PHASE_04_INVENTORY_SCHEDULE.md) mencatat hasil emulator, cakupan dan batasnya.


## Phase 05: pembacaan finance

`finance_transactions` sekarang memakai `allow read: if canManageFinance();`. Fungsi existing tersebut mengharuskan admin/operator keuangan aktif, termasuk pemeriksaan kedua flag isActive/is_active. Operator lapangan, legacy pembaca, inaktif, pengguna tanpa profil dan anonymous tidak diberi akses baca finance. Tidak ada perubahan izin tulis transaksi pada phase ini.

Dashboard dan report service tidak meminta finance tanpa `canViewFinanceDashboard`; jika query finance yang sah ditolak, error tetap ditampilkan, bukan dianggap transaksi kosong. Rules test memeriksa pembacaan dokumen, query dan agregasi untuk enam kategori identitas. Semua rules/index perlu review dan deployment manual sebelum perlindungan ini berlaku pada Firebase tujuan.
# Phase 06 — Penguatan Finance, Sales dan Circular Flow

Rules terbaru harus ditinjau dan dideploy **manual** bersama indexes. Pekerjaan ini tidak mengubah Rules pada Firebase produksi. Client Finance lama tanpa request/audit baru tidak kompatibel dengan write contract baru; koordinasikan rilis aplikasi dan Rules.

| Role aktif | Finance/Sales read | Finance manual create/edit/soft-delete | Sales create | Flow read/create |
| --- | --- | --- | --- | --- |
| admin | Ya | Ya, edit/delete ber-audit | Ya, quartet atomik | Ya/Ya |
| operator_keuangan | Ya | Ya, edit/delete ber-audit | Tidak | Ya/Tidak |
| operator_lapangan / operator | Tidak | Tidak | Tidak | Ya/Ya |
| mitra / peserta_edukasi | Tidak | Tidak | Tidak | Ya/Tidak |
| inactive / anonymous | Tidak | Tidak | Tidak | Tidak/Tidak |

Sales receipt, ledger, sale-linked finance dan actual flow immutable untuk semua role termasuk admin. Sales getAfter memverifikasi pasangan inventory/ledger/finance baru, stok before/after nonnegatif, master harvest/sellable, aktor/waktu/status paid, unit, tanggal, harga integer dan rumus pembulatan. Ledger source sale memverifikasi fresh receipt dan saldo inventory; finance source sale memverifikasi saleId, nominal, income, tanggal/modul/metode. Masing-masing sisi memiliki validasi sendiri; menghilangkan salah satu write ditolak tanpa partial commit. Referensi data sampel ditolak. Receipt lama tidak dapat digunakan untuk debit baru.

Finance manual create mengikat ID/request/actor/version; nominal finite positif maksimal1e12 dan tanggal valid. Edit/soft delete membutuhkan subdocument audit baru yang before-nya sama resource lama, after sama parent getAfter, server editedAt/updatedAt, aktor valid, dan version+1. Parent mempertahankan metadata create/payload/source. Histori tidak dapat diedit, dibuat sendiri tanpa mutasi parent, atau dihapus. Hard delete finance ditolak. Sale-linked finance tidak dapat masuk jalur manual.

Circular Flow create memeriksa schema, canonical modules berbeda, quantity/unit/tanggal, actor server audit, sourceType manual dan referensi batch/Logbook/ledger yang relevan. Tidak ada write stok dari flow. Legacy flow read tetap diperbolehkan sesuai role aktif, tetapi tidak dimigrasikan otomatis menjadi aktual.

Validasi penjualan dijalankan pada Firebase Emulator melalui SDK langsung: kompetisi request, overselling, write hilang, total/quantity/precision/unit/actor/status/source/link palsu, immutability, klasifikasi produk dan role. Regresi largest Logbook multi-item Phase04 tetap diuji untuk document access budget. Emulator bukan bukti index/deployment produksi atau semua perilaku native Android. Rincian dan hitungan tes akhir: [Phase 06](PHASE_06_FINANCE_SALES_CIRCULAR_FLOW.md).
