# SeiCycle — Kebun Sei

Aplikasi **Flutter dan Dart** untuk operasional pertanian dan peternakan terintegrasi Kebun Sei: Ayam, Maggot BSF, Cacing Tanah, Tanaman, dan Lele.

SeiCycle menggunakan **Firebase Authentication** untuk autentikasi dan **Cloud Firestore sebagai database aplikasi**. Akses data langsung dari Flutter dilindungi Firestore Security Rules.

## Fitur yang tersedia

- Login email/password dan Google, registrasi, profil, serta role pengguna.
- Dashboard ringkasan modul, logbook, stok rendah, jadwal, aktivitas, dan keuangan sesuai hak akses. Error dan data kosong tidak diganti angka contoh.
- Form Logbook original lima modul, simpan dengan perlindungan permintaan berulang, dan akses langsung ke catatan baru.
- **Daftar Logbook** dengan pencarian pada catatan yang sudah dimuat, filter modul/tanggal, urutan terbaru/terlama, serta pagination 20 catatan.
- **Detail Logbook** dari dokumen aktual, rincian bersatuan, relasi inventaris/produksi, dan edit catatan tambahan dengan audit trail untuk admin/operator lapangan. Koreksi kuantitas serta pembatalan belum diaktifkan.
- Inventaris, jadwal, keuangan, rekomendasi berbasis aturan, dan laporan PDF/Excel.
- Katalog edukasi artikel, SOP, serta video dari teks/URL eksternal; thumbnail dan gambar lokal sebagai fallback. Pembaca detail lengkap dikembangkan pada Phase 07.
- Notifikasi dalam aplikasi melalui inbox Firestore dan pengingat lokal. FCM saat ini terbatas pada permission/token client; pengiriman push terjadwal dari server belum tersedia.
- Profil dan penyiapan lima modul operasional resmi; aplikasi tidak menyediakan pembuatan/penghapusan transaksi demo.

Empat menu utama: **Dashboard, Logbook, Edukasi, Notifikasi**. Fitur tambahan di mobile tersedia melalui **Lainnya**. Sidebar tampil mulai lebar 768 px mengikuti shell asli `main`.

## Finance, Penjualan dan Aliran Nutrisi — Phase 06

- **Profil bersih dari demo:** fitur Seed/Hapus sampel dan service runtime sudah dihapus. Penyiapan lima modul operasional resmi tetap tersedia. Data produksi tidak dihapus; [prosedur audit/cleanup administratif](docs/PHASE_06_SAMPLE_DATA_CLEANUP.md) memerlukan review daftar aktual terlebih dahulu.
- **Draft Logbook** bertahan saat berpindah menu selama sesi; draft dipisahkan per modul dan dibuang saat akun berganti/logout. Tidak menyimpan draft sebagai catatan final atau menulis ke Firebase sebelum Simpan.
- **Keuangan** memiliki ringkasan pemasukan/pengeluaran/arus kas bersih, filter periode/jenis/kategori/modul, pencarian pada data dimuat, pagination dan detail audit. Form tetap terbuka ketika simpan gagal; retry menggunakan ID yang sama. Edit/soft delete manual menyimpan histori before/after; finance terkait sale tidak dapat diedit sepihak.
- **Penjualan Hasil Panen:** admin menandai master hasil panen aktual sebagai layak dijual di Inventaris. Admin aktif mencatat penjualan lunas; operator keuangan dapat membaca. Sales, pengurangan stok, ledger keluar dan pemasukan disimpan atomik. Quantity maksimal tiga desimal; harga/total integer Rupiah dengan pembulatan half-up. Stok tidak boleh negatif. Receipt selesai permanen, tanpa cancel/reversal yang belum tersedia.
- **Aliran Nutrisi Aktual:** pencatatan material, jumlah/satuan, sumber/tujuan, tanggal, batch dan referensi kegiatan opsional. Tidak mengubah stok atau menyimpan ilustrasi Dashboard sebagai transaksi. Dokumen lama tanpa provenance tetap terbaca dengan penjelasan bahwa belum terverifikasi.
- Dashboard menampilkan ringkasan penjualan serta tautan aliran aktual. Laporan PDF/Excel memisahkan penjualan dari pemasukan agar tidak dihitung dua kali; akses finance mengikuti role. Ringkasan keuangan/penjualan maksimal500 transaksi, laporan maksimal1000 dokumen per sumber; jika melebihi batas, persempit periode/filter dan ekspor parsial tidak diklaim lengkap.

Rules dan **93 composite indexes** perlu ditinjau/deploy manual sebelum menggunakan versi ini pada Firebase tujuan. Tidak ada deployment atau cleanup produksi otomatis. Detail kontrak, hasil pengujian, Android dan batas implementasi ada di [Phase 06](docs/PHASE_06_FINANCE_SALES_CIRCULAR_FLOW.md).

## Role dan akses UI

| Role | Akses |
| --- | --- |
| `admin` | Seluruh menu dan pengelolaan sesuai kemampuan fitur |
| `operator_lapangan` | Operasional, inventaris, jadwal, edukasi, notifikasi, rekomendasi operasional, laporan operasional/inventaris, profil |
| `operator_keuangan` | Seluruh menu; pengelolaan keuangan; form Logbook dapat dibaca tetapi tombol simpan nonaktif |
| `operator` | Role lama dipetakan ke `operator_lapangan` |
| `mitra` / `peserta_edukasi` | Role lama tetap dapat membaca modul nonkeuangan |

Keuangan dan laporan keuangan dibatasi ke admin/operator keuangan aktif melalui capability UI, guard service, dan Firestore Rules Phase 05. Operator lapangan, legacy read-only, akun inaktif dan pengguna tanpa autentikasi ditolak saat membaca `finance_transactions`, termasuk melalui SDK langsung. Pengelola perlu menerapkan Rules baru secara manual setelah review.

Akun baru memakai `operator_lapangan`. Pengelola berwenang mengatur role pada `users/{uid}`. Pastikan akun aktif melalui `isActive`/`is_active`.

## Dashboard Monitoring & Produktivitas

Dashboard mempertahankan banner hijau, kartu rounded, diagram nutrisi, timeline dan empat navigasi original. Sumber operasional tetap **Cloud Firestore**, tanpa dataset contoh otomatis. Grafik menggunakan **fl_chart 1.2.0** existing.

- **KPI aktual:** modul aktif, batch aktif/completed, aktivitas Logbook hari ini, jadwal pending/done/skipped, serta stok rendah/habis berdasarkan saldo aktual. Count global memakai agregasi; stok dibaca maksimal 200 item dan diberi label cakupan terbatas bila lebih banyak.
- **Periode bersama:** Hari Ini, 7/30/90 Hari Terakhir, atau rentang custom maksimal 366 hari kalender lokal. Kartu kondisi terkini tetap berlabel **Saat Ini**; KPI harian tetap **Hari Ini**.
- **Lima modul:** telur/populasi Ayam, limbah/fase/estimasi Maggot, kelembapan/pakan Cacing, tinggi/daun Tanaman, serta pH/suhu/pakan/bobot Lele. Metrik dan kelompok pengamatan dapat dipilih; satuan dan batch/komoditas dipisahkan. Hari tanpa data tidak diisi angka buatan.
- **Monitoring batch:** semua status termasuk completed/archived dapat dipilih dari daftar berhalaman, dengan estimasi panen, aktivitas terakhir pada periode dan tautan Detail Batch. Catatan tanpa batch tetap terbaca.
- **Produksi aktual:** hanya production result valid yang terhubung ke Logbook, per jenis produk/satuan. Tidak menjumlahkan ulang pengamatan dan mutasi stok. Estimasi/target bukan panen aktual; sumber yang tidak dapat diverifikasi diberi pesan ketidakpastian.
- **Timeline terpadu:** Logbook terbaru, jadwal hari ini, dan checklist selesai; tautan Detail Logbook/Jadwal/Batch mempertahankan identitas catatan.
- **Nutrisi dan keuangan:** ilustrasi siklus diberi label konsep; catatan transfer aktual ditampilkan terpisah. Finance menampilkan pemasukan, pengeluaran dan arus kas bersih hanya untuk role berwenang, dengan error tersendiri bila gagal.

Data diambil melalui refresh manual, dengan waktu pembaruan terakhir. Tidak ada klaim LIVE. Detail rumus, batas pembacaan, hasil QA, serta deployment Rules/index manual tersedia di [Phase 05](docs/PHASE_05_DASHBOARD_MONITORING.md). Kebijakan untuk semua phase berikutnya dan audit dependency ada di [Dependency Health](docs/DEPENDENCY_HEALTH.md).

## Alur Logbook

**Form ? Simpan Catatan ? Lihat Catatan ? Detail**, atau buka **Daftar Logbook** dari form. Filter awal mengikuti modul yang sedang digunakan. Input tetap terlihat setelah simpan; tombol simpan nonaktif sampai isian diubah. Kegagalan simpan mempertahankan input dan ID permintaan untuk retry.

Pencarian judul/catatan memakai debounce 350 ms dan hanya mencakup halaman yang sudah dimuat. Gunakan **Muat berikutnya** untuk memperluas cakupan. Detail dapat dimuat ulang dari Cloud Firestore.

Perubahan catatan tambahan tidak mengubah stok atau hasil produksi. Pembatalan/penghapusan serta koreksi kuantitas memerlukan mekanisme koreksi terintegrasi dan belum tersedia. Rules Phase 02 harus diterapkan oleh pengelola sebelum menggunakan edit dengan audit trail; pekerjaan ini tidak melakukan deployment produksi. Lihat [dokumentasi Phase 02](docs/PHASE_02_LOGBOOK_MANAGEMENT.md) untuk batas mapping dan keamanan data.

## Manajemen Batch Budidaya

Batch adalah identitas kelompok atau siklus untuk **Ayam, Maggot BSF, Cacing Tanah, Tanaman, dan Lele**. Modul dan form Logbook original tetap digunakan; tidak ada menu utama tambahan.

1. Buka **Logbook > Kelola Batch > Tambah Batch**. Isi modul, nama, kode unik, lokasi dan tanggal mulai. Jumlah awal beserta unit, komoditas, estimasi panen dan catatan bersifat opsional.
2. Batch baru **Direncanakan**. Buka Detail Batch dan pilih **Ubah ke Aktif** untuk mulai mencatat aktivitas.
3. Pada form Logbook modul terkait, tekan **Pilih batch ... yang aktif**, pilih batch secara eksplisit, lalu **Simpan Catatan**. **Tanpa Batch** tersedia untuk aktivitas umum lintas siklus. Catatan lama berlabel **Belum terhubung ke batch**; aplikasi tidak menebak relasi.
4. Buka Detail Batch untuk identitas, metadata audit, ringkasan aktivitas pada halaman yang dimuat, dan **Aktivitas Batch > Lihat Detail Logbook**. Filter modul/status, pencarian nama/kode pada data termuat, urutan dan pagination tersedia di daftar batch.
5. Siklus: **Direncanakan > Aktif > Selesai > Diarsipkan**. Selesai/arsip tetap memiliki riwayat dan tidak menerima catatan baru. Perubahan status tidak membuat panen atau mengubah stok.

Admin dan operator lapangan aktif dapat mengelola batch; operator keuangan serta mitra/peserta edukasi hanya membaca. Role lama `operator` tetap mengikuti operator lapangan. Kode, modul, tanggal mulai dan data awal tidak dapat diubah setelah dibuat. Kode unik secara global memakai ID dokumen deterministik dan tidak digunakan ulang.

Rules dan sembilan index tambahan Phase 03 perlu ditinjau dan diterapkan secara manual oleh pengelola sebelum fitur digunakan pada lingkungan tujuan. Tidak ada deployment otomatis. Lihat [Phase 03](docs/PHASE_03_BATCH_MANAGEMENT.md) untuk kontrak transaksi, hasil pengujian dan batas verifikasi.

## Manajemen Inventaris

Buka **Lainnya > Inventaris** untuk mencari barang, memfilter modul/kategori, melihat stok aman/rendah/habis, dan mengurutkan data yang sudah dimuat. Daftar dibaca per 20 barang; indikator stok barang yang dimuat mengikuti pembaruan data. Pencarian, status stok, dan urutan tambahan hanya mencakup data yang dimuat, bukan total seluruh persediaan.

- **Tambah Barang** mengisi identitas, lokasi, satuan, minimum stok, dan Stok Awal opsional. Saldo awal dan historinya disimpan bersama.
- **Edit Master** mengubah nama, kategori, lokasi, dan batas minimum tanpa mengubah saldo. Item key, modul, dan satuan dipertahankan setelah pembuatan agar histori tetap konsisten.
- **Mutasi Stok** menyediakan Stok Masuk, Stok Keluar, serta Koreksi Stok berdasarkan jumlah fisik aktual. Catatan/alasan wajib; stok minus membutuhkan persetujuan eksplisit. Kegagalan simpan mempertahankan isian dan ID permintaan untuk retry.
- **Riwayat Mutasi** menampilkan sebelum/sesudah, kuantitas, sumber, waktu, pengguna, serta relasi batch/Logbook dengan pagination. Histori juga dapat dibuka dari Detail Logbook dan Detail Batch.
- Pemakaian/produksi yang sudah disimpan melalui **Logbook** tidak perlu dicatat ulang sebagai mutasi manual. Stok merupakan persediaan lokasi; batch hanya atribusi kegiatan, bukan saldo fisik terpisah.

Peringatan stok rendah memakai ID notifikasi tetap dan tidak membuka ulang informasi identik yang sudah dibaca. Stok habis dibedakan dari stok rendah; pesan notifikasi menjelaskan kondisi saat pemeriksaan dan mengarahkan pengguna ke Inventaris untuk kondisi terbaru. Penghapusan master hanya tersedia bagi admin ketika stok nol; histori tetap disimpan.

## Jadwal Operasional

Buka **Lainnya > Jadwal**, atau **Detail Batch > Jadwal Batch**. Buat kegiatan per modul, pilih batch aktif yang sesuai secara eksplisit, atau gunakan **Tanpa Batch — Aktivitas Umum**. Isi jenis aktivitas, waktu perangkat, dan catatan. Daftar memiliki tampilan **Hari Ini, Mendatang, Terlewat, Selesai, Semua Jadwal**, filter modul/tanggal, serta pagination.

**Tandai Selesai** dan **Lewati** merupakan keputusan petugas dan menyimpan pengguna serta waktu pelaksanaan. Jadwal selesai/dilewati menjadi histori; pembukaan form atau munculnya pengingat tidak menyelesaikan kegiatan. **Catat di Logbook** membuka modul dan konteks batch yang masih aktif, menampilkan kegiatan yang dirujuk, dan tetap meminta pengamatan serta Simpan Catatan dari pengguna. Aksi ini tidak membuat catatan otomatis atau mengurangi stok.

Pengingat lokal disinkronkan saat login, aplikasi kembali aktif, sesudah perubahan jadwal, atau lewat **Sinkronkan Pengingat**. Perubahan waktu mengganti pengingat; selesai/dilewati/hapus membatalkannya. Izin perangkat yang ditolak tidak membatalkan penyimpanan jadwal. Pesan hasil penyimpanan dan hasil pengingat ditampilkan terpisah agar retry pengingat tidak membuat jadwal kedua.

Sinkronisasi dibatasi maksimal 50 jadwal pending dalam 14 hari. Android memakai pengingat waktu perkiraan sesuai kebijakan perangkat. Tidak ada penjadwal push server atau jadwal berulang otomatis; recurrence belum diaktifkan. Admin/operator lapangan aktif dapat mengelola, sedangkan operator keuangan dan role pembaca hanya melihat. Rules dan index Phase 04 harus ditinjau serta diterapkan manual sebelum fitur digunakan pada project tujuan. Lihat [Phase 04](docs/PHASE_04_INVENTORY_SCHEDULE.md) untuk kontrak, pengujian, dan batasannya.

## Instalasi dan konfigurasi

Prasyarat: Flutter stable, Dart sesuai `pubspec.yaml`, project Firebase, dan perangkat/emulator. Versi pengujian Phase 01: Flutter 3.44.2, Dart 3.12.2.

```bash
git clone https://github.com/Freddy47588/sei_cycle.git
cd sei_cycle
git switch feature/operational-v2
flutter pub get
```

1. Daftarkan aplikasi Android dengan package `id.seicycle.app` pada project Firebase.
2. Simpan konfigurasi lokal di `android/app/google-services.json` (diabaikan Git).
3. Aktifkan Authentication email/password dan Google; daftarkan SHA-1/SHA-256 untuk Google Sign-In Android.
4. Siapkan database Cloud Firestore, rules dan indexes sesuai lingkungan. Baca [backend](docs/BACKEND.md), [schema](docs/FIRESTORE_SCHEMA.md), serta [indexes](docs/FIRESTORE_INDEXES.md) sebelum deployment.
5. Konfigurasi FlutterFire untuk platform yang akan digunakan:

```bash
dart pub global activate flutterfire_cli
flutterfire configure
flutter run
```

`lib/firebase_options.dart` saat ini hanya mendukung Android. Web, iOS, macOS, Windows, dan Linux memerlukan konfigurasi tambahan. Aplikasi tidak menggunakan backend Express, Firebase Admin SDK, atau Firebase Storage. Jangan memakai credential milik orang lain.

## Validasi

```bash
flutter analyze
flutter test
git diff --check
```

Widget tests memakai loader, streams, dan service mock tanpa mengakses Firebase. Untuk menghasilkan PNG di `build/phase01/`:

```bash
flutter test test/phase01_ui_test.dart --dart-define=CAPTURE_UI=true
```

Opsional: set environment variable `FLUTTER_ROOT` ke direktori Flutter SDK agar PNG memakai font Roboto dari cache SDK. PNG adalah render widget dengan data uji lokal, bukan bukti koneksi produksi.

[Audit Phase 01](docs/PHASE_01_UI_AUDIT.md) mencatat baseline, perbandingan desain, pengujian, dan batas verifikasi. Referensi asli tersedia di folder `screenshots/` pada branch `main`.

Uji rules dan kontrak transaksi dengan Firestore Emulator (Node.js ?20, Java ?21, Firebase CLI):

```bash
npm ci --prefix tools/firestore_tests
firebase emulators:exec --only firestore --project demo-seicycle-phase02 --config firebase.phase02.json "npm --prefix tools/firestore_tests test"
```

Gunakan project demo tersebut; konfigurasi pengujian terpisah dari produksi. Untuk PNG daftar/detail: `flutter test test/phase02_visual_test.dart --dart-define=CAPTURE_UI=true` (hasil di `build/phase02/`).

## Struktur dan dokumentasi

```text
lib/app/             Shell dan navigasi
lib/core/            Komponen, utilitas, layanan bersama
lib/features/        Modul aplikasi dan layanan Firestore
lib/theme/           Palet dan token desain
test/                Pengujian model, layanan, dan widget
docs/                Dokumentasi implementasi
```

- [Logbook Management Phase 02](docs/PHASE_02_LOGBOOK_MANAGEMENT.md)
- [Inventaris & Jadwal Phase 04](docs/PHASE_04_INVENTORY_SCHEDULE.md)
- [Arsitektur backend](docs/BACKEND.md)
- [Schema Cloud Firestore](docs/FIRESTORE_SCHEMA.md)
- [ERD](docs/ERD.md)
- [Firestore Rules](docs/FIRESTORE_RULES.md)
- [Data sampel manual](docs/SAMPLE_DATA.md)

Jangan memasukkan service account, private key, `.env`, atau token pribadi ke repository. Video memakai tautan eksternal. Firebase Storage, pembaca detail edukasi lengkap, pengiriman FCM server, serta hardening produksi lanjutan belum dinyatakan selesai.
