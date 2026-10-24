# Feature Completion Checklist

## Fitur Brief

SeiCycle branch `feature/backend-firebase` menargetkan MVP Flutter direct-to-Firebase untuk operasional Kebun Sei: auth, profil dan role, dashboard, logbook, inventaris, jadwal, edukasi, keuangan, laporan, notifikasi free-mode, dan rekomendasi rule-based.

## Status Fitur

| Area | Status | Catatan |
|---|---|---|
| Flutter dependencies | Selesai | `flutter pub get` berhasil pada 28 Juni 2026. |
| Auth login/register/profile | Selesai | Firebase Auth, Google Sign-In, auto-create `users/{uid}`, dan update profil ringan tersedia. |
| Role guard admin | Selesai | Admin dapat mengelola data utama, user, farm modules, edukasi, finance, report, dan hapus data. |
| Role guard operator_lapangan | Selesai | Bisa tambah/edit logbook, inventory, dan schedules; delete dibatasi. |
| Role guard operator_keuangan | Selesai | Bisa tambah/edit finance dan akses report/finance dashboard. |
| Dashboard collection kosong | Selesai | Query dashboard menghasilkan ringkasan nol; notifikasi stok rendah tidak lagi menggagalkan load dashboard jika write alert gagal. |
| Logbook CRUD | Selesai | Firestore `logbooks`, soft delete, filter modul/tanggal, rules role operations. |
| Inventory CRUD | Selesai | Firestore `inventory`, stok rendah, soft delete, rules role operations. |
| Schedules CRUD | Selesai | Firestore `schedules`, status pending/done/skipped, reminder lokal/free-mode. |
| Education content | Selesai | Firestore `education_contents`, artikel/video/SOP, status draft/published/archived, admin manage. |
| Finance CRUD | Selesai | Firestore `finance_transactions`, income/expense, monthly summary, role finance. |
| Notification free-mode | Selesai | Firestore inbox + local reminder; ID deterministik untuk low stock/overdue mencegah duplicate spam unread. |
| Report PDF/Excel data kosong | Selesai | Analytics kosong tetap bernilai nol; PDF menampilkan pesan kosong, Excel tetap membuat sheet summary. |
| Recommendation rule-based data minim | Selesai | Data minim menghasilkan rekomendasi low-priority yang aman, bukan crash. |
| Firestore rules | Selesai | Rules berbasis profile aktif dan role; role efektif dipakai untuk notifikasi agar legacy casing admin tetap aman. |
| Cloud Functions | Tidak dipakai | Sengaja tidak diaktifkan pada brief free-mode. |
| Firebase Storage | Tidak dipakai | Sengaja tidak diaktifkan; media edukasi memakai URL eksternal/teks Firestore. |
| Backend server | Tidak dipakai | Tidak ada Express/API server pada MVP branch ini. |

## Catatan Free-Mode

- Push server-side dan scheduler backend tidak digunakan.
- Reminder memakai mekanisme client-side/local notification.
- Inbox notifikasi disimpan di Firestore dengan target `userId`, `targetRole`, dan status `isRead`.
- Alert stok rendah dan jadwal overdue memakai document ID deterministik, misalnya `low_stock_{userId}_{itemId}`, agar refresh/dashboard tidak membuat spam unread.

## Catatan Tanpa Firebase Storage

- Konten edukasi video memakai `externalVideoUrl`.
- Thumbnail memakai `thumbnailUrl` eksternal bila diperlukan.
- SOP dan artikel disimpan sebagai field teks/list di Firestore.
- PDF/Excel report dibuat lokal dari client lalu dibagikan, bukan diupload ke Storage.

## Jika Nanti Upgrade Firebase Blaze

- Cloud Functions untuk scheduled reminders, push notification terjadwal, dan server-side aggregation.
- Firebase Storage untuk upload gambar edukasi, lampiran report, dan bukti transaksi.
- App Check enforcement untuk hardening akses client.
- Scheduled export/report generation server-side.
- Backup, audit log, dan admin moderation workflow.
- Rekomendasi lanjutan berbasis model/AI dengan guardrail dan evaluasi data operasional.

## Progress Akhir Terhadap Brief

Perkiraan kesiapan branch terhadap brief: 90-95%.

Sisa risiko utama ada pada validasi manual device/Firebase project nyata, konfigurasi index Firestore yang perlu dideploy, dan hardening produksi seperti App Check serta workflow admin lanjutan.
