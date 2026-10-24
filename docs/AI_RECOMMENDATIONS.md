# Rule-Based AI Recommendation

Fitur `AI Recommendation` pada tahap awal SeiCycle adalah rekomendasi
rule-based yang berjalan di Flutter client/service-side. Fitur ini bukan
machine learning cloud, tidak memakai API AI berbayar, tidak memakai Cloud
Functions, tidak memakai backend server, dan tidak memakai Firebase Storage.

## Sumber Data

RecommendationService membaca data Firestore secara on-demand saat halaman
rekomendasi dibuka:

- `logbooks`: aktivitas 45 hari terakhir, dibatasi maksimal 80 dokumen.
- `inventory`: item stok rendah, dibatasi maksimal 10 dokumen.
- `schedules`: jadwal pending yang sudah overdue, dibatasi maksimal 10 dokumen.
- `finance_transactions`: transaksi bulan berjalan, hanya jika role boleh
  melihat finance, dibatasi maksimal 80 dokumen.

## Aturan Rekomendasi

- Prediksi panen sederhana memakai `moduleType`, catatan tebar/tanam/semai,
  umur produksi default per modul, dan logbook terakhir.
- Jika catatan awal produksi atau logbook berkala belum ada, rekomendasi
  menampilkan status data belum cukup.
- Evaluasi produktivitas memakai jumlah aktivitas 14 hari terakhir dan indikator
  yang tersedia di logbook seperti panen, mortalitas, pakan, dan pertumbuhan.
- Stok rendah menghasilkan rekomendasi restock.
- Jadwal overdue menghasilkan rekomendasi penyelesaian atau penjadwalan ulang.
- Modul yang tidak dicatat beberapa hari menghasilkan rekomendasi update
  logbook.
- Jika pengeluaran bulan ini lebih besar dari pemasukan, sistem menyarankan
  evaluasi biaya.
- Jika estimasi panen sudah dekat, sistem menyarankan persiapan panen.

## Penyimpanan Opsional

Model rekomendasi sudah mendukung field:

`id`, `title`, `description`, `type`, `priority`, `moduleType`,
`sourceCollection`, `sourceId`, `createdAt`, `validUntil`, dan `isResolved`.

Default implementasi saat ini tidak menulis otomatis ke collection
`recommendations` agar tidak boros write Firestore. Jika suatu saat ingin
menyimpan snapshot rekomendasi, gunakan id deterministik dan TTL `validUntil`
supaya write tidak terjadi berulang setiap refresh.
