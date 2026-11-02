# Phase 01 — UI Audit & Design Foundation

16 Oktober 2026 (Asia/Jakarta). Repository: `Freddy47588/sei_cycle`. Branch: `feature/operational-v2`, baseline `af1539c`.

## Perlindungan workspace dan sumber desain

Workspace awal berada di `main` dengan lima perubahan lokal: registrant `.cc`/`.h`/CMake Linux, registrant macOS, dan `pubspec.lock`. Sebelum berpindah branch, seluruhnya diamankan dalam stash bernama `user-local-before-phase01-20261016` serta salinan patch/status di `<private local workspace>`. Stash tetap disimpan, tidak diterapkan ke branch berbeda.

Branch kerja melacak `origin/feature/operational-v2`. Tidak ada perubahan pada branch sumber, push, merge, rebase, PR, reset destruktif, seed, deployment rules, atau penulisan database.

Enam screenshot dibaca dari arsip read-only `origin/main`, bersama kode theme, shell, dan halaman asli. Salinan lokal: `<private local workspace>`. Referensi berasal dari objek Git lokal; tidak mengklaim telah melakukan fetch terbaru.

## Baseline

| Perintah | Hasil sebelum implementasi |
| --- | --- |
| `git status --short` | Lima perubahan lokal pada main, diamankan |
| `git branch --show-current` | Setelah pengamanan: feature/operational-v2 |
| `git remote -v` | Fetch/push ke https://github.com/Freddy47588/sei_cycle.git |
| `flutter --version` | Flutter 3.44.2, Dart 3.12.2 |
| `flutter pub get` | Berhasil, tanpa upgrade dependency |
| `flutter analyze` | Tidak ada temuan |
| `flutter test` | 13 test lulus |

Pengujian baru yang mengimpor shell lengkap menemukan cache lokal `url_launcher_linux-3.2.2` kosong. Folder kosong dipindah ke backup, lalu versi yang sama diunduh melalui `dart pub cache add url_launcher_linux --version 3.2.2`. Masalah lingkungan ini tidak tercakup 13 test baseline. Tidak ada dependency baru atau perubahan versi paket.

## Audit perbandingan UI

| Halaman | Referensi main | Temuan awal | Perbaikan | Status |
| --- | --- | --- | --- | --- |
| Fondasi/navigasi | Theme/shell main dan keenam PNG | Krem lebih gelap, radius berbeda, breakpoint berubah dari 768 menjadi 900 | Krem asli #F7F5F0, field #F0EDE6, token radius/elevation/shadow, tombol minimal 48 px, sidebar kembali 768 px; kelompok Lainnya desktop | Kode diterapkan; navigasi diuji untuk tiga role/empat ukuran |
| Dashboard atas | Dashboard1.png | Banner sudah ada; badge Live saat loading; hitungan operasional berbeda dari contoh desain | Banner hijau tetap, grid adaptif, loading/error nyata, badge Dimuat untuk hasil Future | Widget diperiksa; statistik bisnis luas Phase 05 |
| Dashboard bawah | Dashboard2.png | Aktivitas/aliran/pendapatan contoh menggantikan hasil kosong; proyeksi lama terlihat tanpa data | Hapus substitusi demo, empty state, finance gate, judul flow dipulihkan; ilustrasi siklus berlabel tanpa angka efisiensi fiktif | Data kosong diuji; Firebase langsung belum diuji |
| Logbook Ayam | Logbook1.png | Form sudah tersedia; pengukuran contoh otomatis tersimpan, role baca bisa menekan simpan | Form/field/slider/riwayat tetap; input kosong, slider menunggu pengamatan, banner merangkum input; tombol sempit bertumpuk dan role baca nonaktif | Simpan melalui service mock untuk lima modul |
| Logbook Tanaman | Loogbook2.png | Tanggal/pengukuran contoh dianggap input | Input dimulai kosong; kartu hijau serta semua field dipertahankan; padding keyboard dan dismiss saat scroll | Lima modul diuji; daftar/detail penuh Phase 02 |
| Edukasi | Edukasi.png | Thumbnail 100 px dan kartu 274 px terlalu padat; loading gambar belum ada | Thumbnail 150 px, kartu lebih lapang mengikuti skala teks, jarak grid 20 px, dua kolom mulai lebar halaman 600 px mengikuti main, filter modul didahulukan, progress gambar/fallback lokal | Katalog/state diuji; pembaca detail Phase 07 |
| Notifikasi | Notifikasi.png | Label overdue disebut Produksi; status dibaca kurang jelas | Ikon 44 px, indikator dibaca eksplisit, label Jadwal Terlewat, token kartu bersama; tanpa jumlah fiktif | Widget/state diuji; inbox/reminder tetap |

Palet hijau `#2D6A27`, `#3D8A35`, `#1A4A17`, cokelat `#8B6F47`, hijau muda `#6DBF67`, putih, dan warna status dipertahankan. Screenshot main memakai data contoh dan ruang kartu besar. Implementasi mempertahankan bahasanya dengan data aktual/kosong dan ukuran yang nyaman; tidak mengklaim identik per piksel.

## Kejujuran data dan akses

- DashboardService mengembalikan hasil kosong sesungguhnya. Konstanta fallback demo dihapus setelah memeriksa pemakaian: hanya jalur dashboard yang memakainya.
- Query untuk hitungan harian/stok tidak lagi terpotong maksimal 20. Preview tetap terpisah. Agregasi dan efisiensi dataset besar perlu dievaluasi pada Phase 05.
- Tidak ada indikator Live karena pembacaan berbentuk Future. Refresh menunggu request dan menampilkan error bila gagal.
- Finance UI hanya bagi admin/operator keuangan aktif. Dashboard dan rekomendasi memakai capability sama. Laporan lapangan hanya operasional/inventaris dan tidak mengambil koleksi finance.
- **Batas keamanan:** rules backend masih mengizinkan read transaksi bagi user aktif. UI bukan batas keamanan database. Rules tidak diubah; peninjauan pembatasan read perlu pekerjaan keamanan terpisah dan pengujian kebutuhan bisnis.
- Logbook tetap memakai mapping inventaris/produksi, validasi layanan, history, dan transaksi Firebase asli. Form kosong ditolak; slider hanya masuk payload setelah dipilih. Semua input pengamatan dimulai kosong; nilai contoh yang tidak lagi terpakai dihapus dari spesifikasi setelah pemeriksaan dependensi.
- Auth, inventaris, produksi, jadwal, inbox Firestore, reminder lokal, laporan, dan rekomendasi dipertahankan. Tidak ada seed yang dijalankan.

## Daftar file berubah

| File | Alasan |
| --- | --- |
| lib/theme/app_theme.dart | Palet asli; token geometri/shadow/breakpoint, input dan tombol |
| lib/core/widgets/app_ui.dart | Spacing dan kartu reusable konsisten |
| lib/app/app_shell.dart | Breakpoint referensi, navigasi sekunder, header tablet, injeksi untuk pengujian |
| lib/features/dashboard/screen/dashboard_screen.dart | State nyata, refresh, grid, finance gate, ilustrasi flow |
| lib/features/dashboard/services/dashboard_service.dart | Hilangkan substitusi demo dan batas hitungan 20 |
| lib/features/logbook/screen/logbook_screen.dart | Form asli, input kosong, role simpan, keyboard/tombol, injeksi layanan |
| lib/features/education/screen/education_screen.dart | Kartu, thumbnail, pencarian, loading/error gambar, injeksi stream |
| lib/features/notification/screen/notification_screen.dart | Ikon/status/label kategori dan injeksi stream |
| lib/features/profile/models/app_user.dart | Capability finance sesuai role |
| lib/features/reports/screens/report_screen.dart | Filter dan request mengikuti capability finance |
| lib/features/reports/services/report_service.dart | Flag pengambilan finance |
| test/widget_test.dart | Ekspektasi capability terbaru |
| test/phase01_ui_test.dart | Regresi data kosong, role, form/save mock, responsive, states, render PNG |
| README.md | Dokumentasi Flutter/Dart/Auth/Cloud Firestore dan batas fitur aktual |
| docs/PHASE_01_UI_AUDIT.md | Audit ini |

## Verifikasi akhir dan keterbatasan

| Pemeriksaan | Hasil |
| --- | --- |
| `dart format` pada 13 file Dart berubah | Berhasil |
| `flutter analyze` | Tidak ada temuan |
| `flutter test --reporter expanded` | 45 test lulus, termasuk 13 test baseline dan 32 tambahan |
| `flutter test test/phase01_ui_test.dart --dart-define=CAPTURE_UI=true --reporter expanded` | 32 test lulus; 24 PNG di build/phase01/ |
| `git diff --check` | Bersih |
| Pemeriksaan README | Tidak memuat istilah paket/kuota Firebase yang dilarang |

Cakupan: navigasi dan menu sekunder untuk tiga role pada 320/600/768/1280 px; badge dengan hitungan stream uji; dashboard loading/error dan hasil kosong tanpa substitusi demo; tidak meminta finance untuk operator lapangan; simpan input pada lima modul melalui mock; form kosong ditolak; role baca tidak bisa simpan; tombol simpan terjangkau dengan inset keyboard 300 px; pencarian edukasi; loading/empty/error edukasi dan notifikasi; indikator dibaca; empat halaman dengan skala teks 1,4 pada lebar 320 px.

PNG menyertakan shell mobile/desktop, dashboard bagian atas/bawah, Logbook Ayam/Tanaman, edukasi, dan notifikasi. Render pada 600 px dibandingkan secara visual dengan keenam referensi main; sidebar desktop juga diperiksa. Struktur, palet, banner, form, thumbnail, dan indikator dipertahankan. Perbedaan disengaja: data contoh tidak disalin, form dimulai kosong, statistik bisnis memakai hitungan yang tersedia, dan kartu lebih ringkas. Pemeriksaan ini bukan uji kesamaan piksel. Font Roboto/MaterialIcons untuk capture dibaca dari Flutter SDK lokal melalui FLUTTER_ROOT.

Selama pengembangan, test tambahan menemukan assertion keyboard multiline dan overflow badge/header pada layar sempit/teks besar. Semuanya diperbaiki dan suite akhir lulus. File registrant platform yang diregenerasi tooling dikembalikan ke baseline branch agar perubahan Phase 01 tetap fokus; perubahan lokal pengguna tetap aman di stash/patch.

PNG di `build/phase01/` berasal dari renderer widget dengan fixture lokal, bukan aplikasi yang tersambung Firebase. Perangkat tersedia hanya Chrome dan Edge; konfigurasi Firebase hanya Android. Tidak ada perangkat/emulator Android tersambung. Login, Security Rules, commit transaksi Firestore, notifikasi sistem, dan keyboard perangkat fisik belum diverifikasi end-to-end.

Checklist terverifikasi:

- [x] Keenam screenshot asli diperiksa dan dibandingkan dengan render widget.
- [x] Token palet, tipografi, komponen, navigasi dan form diselaraskan.
- [x] Menu tambahan tetap tersedia sesuai role; tiga role utama diuji.
- [x] Tidak ada overflow pada ukuran/skala teks yang diuji.
- [x] Lima form dan jalur simpan terjaga melalui service mock.
- [x] Tidak ada operasi destruktif Firebase atau demo pengganti data aktual.
- [x] README dan dokumen audit diperbarui.
- [ ] Validasi login, save transaksi Firestore, rules dan reminder pada Android nyata/emulator.

Git akhir: 13 file terlacak diubah dan dua file baru (audit dan test), tanpa commit/push/PR/merge. Stash perubahan pengguna tetap tersimpan. `pubspec.yaml`, `pubspec.lock`, Firebase options dan rules tidak berubah.

## Ditunda per phase

| Phase | Pekerjaan |
| --- | --- |
| 02 | Daftar dan Detail Logbook penuh; perluasan history/filter sesuai brief berikutnya |
| 03–04 | Scope rinci belum diberikan; fondasi inventaris, produksi, jadwal tetap dipertahankan |
| 05 | Statistik bisnis populasi/produksi/limbah/ekonomi, agregasi dan efisiensi query |
| 06 | Scope rinci belum diberikan; tidak menambah sistem bisnis baru |
| 07 | Detail artikel/video/SOP, kategori notifikasi, pengingat dan integrasi operasional |
| 08 | Scope rinci belum diberikan; validasi produksi dan peninjauan rules perlu dijadwalkan sebelum rilis |

Kesiapan menuju Phase 02 mencakup fondasi form dan navigasi; tidak menyatakan integrasi produksi sudah diuji.
