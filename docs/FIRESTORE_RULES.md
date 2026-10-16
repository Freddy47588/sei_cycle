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
