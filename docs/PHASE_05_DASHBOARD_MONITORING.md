# Phase 05/08 — Dashboard Monitoring & Productivity Analytics

## Status dan baseline

Implementasi pada `Freddy47588/sei_cycle`, branch `feature/operational-v2`, dari baseline **aa6bfb8745be50a259a4da6c7b3aef739620bd1e**. Audit/fetch awal tidak menemukan commit remote tambahan. Perubahan lokal pengguna pada `docs/PHASE_01_UI_AUDIT.md` serta empat file generated Linux/macOS tidak disertakan commit Phase 05.

Phase ini menambahkan monitoring baca berbasis Firestore dan memperketat baca finance. Tidak mengerjakan transaksi penjualan, manajemen keuangan lanjutan, material flow editor, atau Phase 06–08. Tidak melakukan seed, migrasi, deployment Firebase, merge main, force push atau PR.

## Tujuan dan arsitektur

Dashboard menjawab kondisi operasional terkini, pengamatan produktivitas lima modul, histori batch, hasil produksi aktual dan arus kas role berwenang.

| Lapisan | Tanggung jawab |
| --- | --- |
| `DashboardFilter` | Satu objek rentang kalender lokal untuk finance, aliran aktual dan monitoring |
| `DashboardService` | Count global, preview bounded, timeline gabungan, validasi saldo dan guard finance |
| `ProductivityService` | Query modul/batch/periode dan verifikasi parent Logbook produksi |
| `calculateProductivity` / model series | Perhitungan murni, kelompok identitas, satuan, validasi dan ketidakpastian |
| `ModuleMonitoringSection` | Pemilih modul, batch berhalaman, metrik, state dan request generation |
| `ProductivityChart` | Grafik line/bar fl_chart, label satuan, tanggal, tooltip dan legenda |
| `DashboardScreen` | Banner/KPI original, filter/refresh, diagram, timeline, finance dan navigasi existing |

Tidak membuat listener global, koleksi agregat persisten, atau dependency baru. Kontrak field summary lama yang dipakai fixture Phase 01 dipertahankan; nama field monthlyIncome/monthlyExpense/monthlyProfit tetap internal, sedangkan UI menampilkan rentang pilihan dan **Arus Kas Bersih**.

## KPI, rumus dan cakupan

| Metrik | Sumber dan filter | Rumus / satuan | Cakupan |
| --- | --- | --- | --- |
| Modul Aktif | farm_modules.isActive == true | aggregate count / modul | Saat Ini; tanpa hardcode 5 |
| Batch Aktif | batches, isDeleted == false, status active | aggregate count / batch | Saat Ini |
| Batch completed | batches, isDeleted == false, status completed | aggregate count / batch | Saat Ini; di helper kartu batch |
| Aktivitas Hari Ini | logbooks, isDeleted false, activityDate [hari lokal, besok) | aggregate count / catatan | Hari Ini; seluruh hasil cocok |
| Jadwal Hari Ini | schedules, isDeleted false, date [hari lokal, besok) | count total dan per pending/done/skipped / agenda | Hari Ini |
| Stok Rendah | inventory, isDeleted false | saldo > 0 dan saldo <= minStock / item | Saat Ini; maksimal 200 item pertama menurut ID |
| Stok Habis | inventory, isDeleted false | saldo <= 0 / item | Saat Ini; cakupan sama |
| Pemasukan/Pengeluaran | finance_transactions, isDeleted false, date dalam periode | sum amount per type / rupiah | Periode pilihan; hanya bila seluruh data <=500 dan valid |
| Arus Kas Bersih | sumber finance sama | pemasukan − pengeluaran / rupiah | Bukan laba akuntansi lengkap |

KPI global memakai **8 count aggregation query**: modul, Logbook harian, jadwal total/status (4), batch active/completed (2). Total jadwal dapat lebih besar dari jumlah tiga status bila ada data legacy berstatus tidak dikenal; status tersebut tidak dianggap selesai. Tidak menampilkan persentase selesai tanpa kebutuhan/basis yang cukup.

Stock dibaca `limit(201)`, hanya 200 dihitung; baris ke-201 mendeteksi truncation. Bila truncation, kedua kartu dan pesan cakupan secara eksplisit menyebut hasil bukan jumlah global. `isLowStock` legacy diabaikan untuk perhitungan. Saldo/minimum tidak valid menghasilkan error, bukan nol. Lima item rendah/habis menjadi preview perhatian; pengelolaan lengkap tetap pada Inventaris existing.

## Filter periode

- Hari Ini, 7, 30, 90 hari, serta rentang custom maksimal 366 hari.
- **Start inklusif, end eksklusif**, berdasarkan tengah malam kalender lokal perangkat; end UI custom inklusif diubah ke tengah malam tanggal berikutnya.
- Tujuh hari dihitung dengan konstruktor tanggal kalender, bukan mengurangi 7×24 jam. Pergantian bulan, tahun dan tahun kabisat diuji.
- Periode dipakai bersama untuk grafik, produksi, finance dan circular flow. KPI Hari Ini/Saat Ini tidak diberi label historis yang menyesatkan.
- Module/batch hanya menyaring monitoring. Finance dan transfer aktual tetap seluruh modul dalam periode tersebut.
- FutureBuilder diberi identitas Future baru agar data periode sebelumnya langsung dibuang. Monitoring memiliki generation guard untuk respons lama, serta generation terpisah bagi pagination batch. Refresh membuang batch pilihan sebelum request baru dan memuat ulang daftar batch.

## Pengamatan lima modul

| Modul canonical | Pengamatan/grafik | Perlakuan |
| --- | --- | --- |
| ayam_kampung | Telur/hari (butir), populasi (ekor), mortalitas (ekor), bobot telur (g), konsumsi pakan (g/ekor) | Telur/mortalitas adalah flow; populasi/bobot/konsumsi adalah pengamatan terakhir per identitas, tidak dijumlahkan antarhari |
| maggot_bsf | Limbah masuk (kg), fase larva (hari), estimasi dan target panen (kg) | Estimasi/target diberi label berbeda dan tidak masuk hasil aktual |
| cacing_tanah | Kelembapan (%), pakan organik (kg), hasil aktual kascing per produk/satuan | Kascing padat kg dan cair liter dipisahkan |
| tanaman | Tinggi (cm), jumlah daun (lembar), hasil aktual per komoditas | Identitas kurva: batch + jenis tanaman + blok + tanggal tanam; identitas tidak lengkap menjadi satu titik per Logbook |
| lele | pH, suhu (°C), maggot pagi/sore (kg), bobot rata-rata (g/ekor), survival numerik (%) dan hasil aktual Lele | Label mengikuti form bisnis terkini, bukan dugaan dari nama key |

`logbook_form_spec.dart` diaudit: `mortalitas_ikan` saat ini berarti **Bobot Rata-rata**, `pakan_lele_kg` berarti **Pakan Maggot Sore**, dan `kondisi_air` berarti **Survival Rate** hanya untuk pengamatan numerik valid 0–100. Data teks legacy tidak diubah menjadi persentase. pH dibatasi 0–14 dan nilai non-finite/negatif diabaikan sebagai titik, tidak diganti nol.

Nilai additive dihitung per hari per kelompok dan memakai bar chart. Nilai state memakai pengamatan terakhir per hari dengan timestamp/ID sebagai urutan stabil, melalui line chart. Batch berbeda tidak dicampur. State legacy tanpa batch tetap titik catatan tersendiri. Grafik tidak mengisi hari hilang; line diputus pada jeda, bar tanpa data tidak dibuat. Tooltip menyebut tanggal, nilai dan satuan; sumbu ditahan di area grafik dan jumlah label dikurangi pada layar kecil. Satu titik tetap tampil. UI memberi pilihan metrik/kelompok, ringkasan total atau pengamatan terbaru, legenda dan empty state.

Persentase tren produktivitas lintas populasi/komoditas tidak dihitung karena basis pembanding dan kelengkapan data tidak dapat dijamin; grafik menampilkan perubahan pengamatan aktual.

## Batch dan navigasi

Pemilih menggunakan **FarmModules existing**, tanpa ID modul baru. Daftar Batch memakai BatchService existing, pagination **20**, filter moduleType dan seluruh status planned/active/completed/archived. Tombol Muat Batch Lainnya meminta halaman selanjutnya; pencarian/CRUD batch tetap di layar existing.

Batch terpilih menampilkan status, komoditas, estimasi panen, jumlah catatan/aktivitas terakhir **dalam periode yang dimuat**, pengamatan dan tautan Detail Batch. Completed/archived tetap terbaca. Dashboard tidak membuat atau mengubah status batch, tidak menebak relasi legacy, dan tidak menjadikan estimasi panen sebagai hasil aktual.

Kartu Batch Aktif membuka daftar batch sesuai capability. Timeline membuka Detail Logbook atau Jadwal Operasional; tautan batch memakai ID batch asli dan membuka Detail Batch. Handler injectable diuji tanpa akses Firebase produksi; layar tujuan existing tetap dilindungi capability dan Rules.

## Integritas produksi

Sumber canonical adalah `production_results`, bukan stok tersisa, inventory transaction atau quantity generik Logbook. Satu panen Lele 20 kg dengan tiga representasi menghasilkan **20 kg**, bukan 60 kg; fixture service membuktikan koleksi inventory/ledger tidak diminta untuk perhitungan produksi.

Hasil valid memiliki tanggal dalam periode, moduleType/batchId sesuai pilihan, quantity finite positif, nama produk/satuan, dan parent Logbook yang ada, tidak dihapus, serta sesuai module/batch. Parent dapat berada di luar activityDate periode karena harvestDate merupakan tanggal terpisah; parent diambil berdasarkan ID dalam kelompok maksimal 30 ID.

Identitas logbookId + nama produk + satuan mencegah duplikasi representasi hasil yang sama. Duplikasi, parent invalid, produksi terpotong atau pengamatan panen legacy tanpa sumber canonical menyebabkan pesan **“Data produksi belum dapat dihitung secara akurat.”** dan total aktual tidak ditampilkan. Tidak mencoba memperbaiki/menghapus data otomatis. Hasil valid dijumlahkan dan digrafikkan per produk/satuan saja. Target/estimasi Maggot tidak termasuk produksi.

## Timeline dan nutrisi

Timeline menggabungkan maksimal 10 Logbook terbaru, 10 jadwal hari ini dan 10 checklist done terbaru, deduplikasi per sumber/ID, diurutkan berdasarkan timestamp relevan, kemudian dibatasi menjadi **10 entri**. Jadwal done menggunakan completedAt, skipped menggunakan skippedAt bila ada, pending menggunakan date. Logbook berstatus tampilan **Tercatat**, tidak otomatis done. Ikon modul, waktu/tanggal, status dan batch ditampilkan. Membuka Dashboard tidak menyelesaikan checklist.

NutrientFlowCard mempertahankan ilustrasi original dengan judul **Ilustrasi Siklus Nutrisi Kebun Sei**. Panah konsep tidak disusun ulang dari transaksi yang tidak saling terkait. Maksimal lima catatan circular_flows terbaru dalam periode ditampilkan terpisah, dengan material, modul sumber/tujuan, quantity, unit dan tanggal. Lima ID defaultCircularFlows lama dikecualikan agar seed ilustratif tidak dianggap transfer operasional. Tidak ada seed saat Dashboard dibuka atau jumlah gabungan kg/liter.

## Query, performa, cache dan index

| Pembacaan dokumen | Batas |
| --- | --- |
| Stock | 201, hitung 200 dan tandai cakupan |
| Timeline | 10 per masing-masing dari 3 sumber query |
| Circular flow | 5 terbaru dalam periode |
| Finance | 501, hitung hanya jika <=500; selain itu minta persempit periode |
| Logbook monitoring | 501, grafik 500 terbaru dengan peringatan cakupan, bukan total periode |
| Production result | 501, hasil tidak dihitung bila >500 |
| Parent Logbook | Maksimal 500 parent unik, query whereIn 30 per permintaan |
| Batch | 20 per halaman, halaman tambahan atas tindakan pengguna |

Tidak ada fallback full collection, query setiap rebuild, listener global atau download histori untuk count. Missing index/permission/network tetap error. Operasional yang gagal tidak ditampilkan sebagai nol; kegagalan finance memiliki section error tersendiri sehingga KPI operasional tetap tersedia. Finance >500 meminta rentang lebih pendek.

Cache hanya Future/state widget selama pilihan aktif; tidak ada klaim realtime atau cache lintas pengguna. Refresh manual menampilkan **Terakhir diperbarui**. Revisi profil/role memuat ulang dengan capability baru.

Empat composite index ditambahkan (**74 → 78**): schedules isDeleted/date DESC; schedules isDeleted/status/completedAt DESC; logbooks isDeleted/moduleType/batchId/activityDate DESC; production_results moduleType/batchId/harvestDate DESC. Dua single-field bermasalah dari sebelum aa6bfb8 tetap tidak ada. Lihat [daftar index](FIRESTORE_INDEXES.md). JSON diperiksa dan kombinasi duplikat/satu-field ditolak pada audit.

## Keamanan finance

UI dan service memakai `canViewFinanceDashboard`. DashboardService memerlukan profil berwenang selain includeFinance; pemanggil tanpa profil tidak diberi akses finance. ReportService default tidak meminta finance, dan hanya menjalankan query saat profil berwenang disertakan. Jalur report existing meneruskan profil/capability tersebut.

Rules `finance_transactions` berubah dari canViewAppData menjadi **canManageFinance** existing, yang memerlukan admin atau operator keuangan aktif. Operator lapangan, legacy pembaca, inaktif dan anonymous ditolak pada dokumen, query, serta count aggregation. Error permission tidak ditangkap menjadi transaksi kosong. Izin tulis finance dan fitur CRUD Phase 01–04 tidak dilonggarkan.

**Rules/index belum diterapkan ke Firebase produksi.** Perlindungan SDK pada project tujuan baru berlaku setelah pengelola meninjau dan deploy manual. Tidak ada akses produksi atau transaksi uji produksi dalam pekerjaan ini.

## Kesesuaian UI dan pengujian

Screenshot Dashboard1/2 dari `origin/main` ditinjau langsung. Palet hijau/coklat/cream, banner welcome, logo, rounded white cards, sistem nutrisi dan timeline dipertahankan; shell/navigasi utama tidak diubah. Finance menggunakan tiga angka bersatuan, tidak membuat pie dari pemasukan/pengeluaran/net negatif. Chip terpilih diberi teks putih dan sumbu tanggal diatur agar terbaca pada lebar kecil.

Baseline lokal: **181 Flutter test**, analyzer tanpa issue. Hasil verifikasi akhir:

| Pemeriksaan | Hasil |
| --- | --- |
| flutter pub get / pub outdated | Berhasil; versi terkunci dipertahankan, temuan versi baru didokumentasikan |
| flutter analyze | **Lulus, 0 issue**; termasuk tidak ada deprecated_member_use pada kode aplikasi |
| flutter test --reporter expanded | **223 lulus, 0 gagal**: 181 regresi dan 42 test Phase 05 |
| Firestore Emulator | **80 test lulus**, 0 gagal; 73 regresi + 7 pengujian Phase 05 |
| Android debug APK | **Berhasil**: build/app/outputs/flutter-apk/app-debug.apk; warning migrasi KGP existing tetap ada |
| Perangkat fisik | Tidak terdeteksi; hanya Chrome/Edge pada flutter devices |
| git diff --check dan JSON | **Lulus**; 11 JSON valid, 78 composite index unik dan tidak ada composite satu-field |

`test/phase05_dashboard_test.dart` mencakup kalender, KPI global/stock terbatas, status jadwal, semantik lima modul, satuan, nilai invalid, legacy/batch, produksi tunggal/duplikat/parent, izin service, finance negatif/error/cap, dan timeline. `test/phase05_dashboard_ui_test.dart` mencakup line/bar pada **320, 360, 768, 1280 px dengan text scale 1.4**, satu titik/no data, respons modul/periode/batch lama, refresh/filter/retry, batch completed, finance error dan navigasi. Seluruh test Phase 01–04 tetap dijalankan, tanpa dihapus atau dinonaktifkan. Fake count ditambahkan pada test existing agar dapat menjalankan API agregasi baru.

Saat CAPTURE_UI dipakai, set `FLUTTER_ROOT` ke SDK lokal bila ingin font Roboto/ikon pada PNG. Render widget dengan fixture lokal ditinjau di `build/phase05/chart-*.png`; itu merupakan bukti layout, bukan bukti Firestore produksi. PNG dapat dibuat ulang:

```bash
flutter test test/phase05_dashboard_ui_test.dart --dart-define=CAPTURE_UI=true
```

Emulator menggunakan project demo, loopback dan port **8095** agar tidak menghentikan emulator pengguna pada 8089. Test membaca FIRESTORE_EMULATOR_HOST; nilai default lama tetap didukung:

```bash
firebase emulators:exec --only firestore --project demo-seicycle-phase02 --config firebase.phase05.json "npm --prefix tools/firestore_tests test"
```

Emulator tidak membuktikan index produksi sudah dibangun. Tidak melakukan Flutter run pada Infinix karena perangkat tidak terhubung. Warning migrasi Kotlin existing dievaluasi dan tetap terlihat, tanpa upgrade konfigurasi. Audit dependency lengkap dan batas jaminannya ada di [Dependency Health](DEPENDENCY_HEALTH.md).

## Batasan dan persiapan Phase 06

- Stok >200 bukan total global; monitoring >500 merupakan preview dengan label, finance/produksi >500 meminta periode/batch lebih sempit.
- Parent produk yang tidak valid, duplicate, dan pengamatan legacy yang belum mempunyai hasil canonical memerlukan tinjauan operasional; Dashboard tidak memigrasikannya.
- Satu curve Tanaman hanya aman untuk identitas yang dicatat; pengamatan legacy tidak diasumsikan berasal dari tanaman yang sama.
- Seluruh API transitif/native dan ekspor lintas platform belum diaudit menyeluruh. `excel` dan constraints archive/image memerlukan pekerjaan maintenance terpisah.
- Smoke test Firebase nyata dan perangkat Infinix dilakukan pengelola setelah Rules/index siap. Tidak ada klaim koneksi produksi telah tervalidasi.
- Phase 06 dapat memakai produksi canonical, ledger immutable, batch, role finance dan periode bersama sebagai fondasi manajemen keuangan, penjualan hasil panen dan pencatatan aliran nutrisi. Fitur tersebut belum diimplementasikan di sini.

## Daftar file Phase 05

- `AGENTS.md`
- `README.md`
- `docs/DEPENDENCY_HEALTH.md`
- `docs/DEPENDENCY_HEALTH_SNAPSHOT.json`
- `docs/FIRESTORE_INDEXES.md`
- `docs/FIRESTORE_RULES.md`
- `docs/FIRESTORE_SCHEMA.md`
- `docs/PHASE_05_DASHBOARD_MONITORING.md`
- `firebase.phase05.json`
- `firestore.indexes.json`
- `firestore.rules`
- `lib/features/circular_flow/services/circular_flow_service.dart`
- `lib/features/dashboard/models/dashboard_filter.dart`
- `lib/features/dashboard/models/dashboard_numbers.dart`
- `lib/features/dashboard/models/dashboard_summary.dart`
- `lib/features/dashboard/models/productivity_point.dart`
- `lib/features/dashboard/screen/dashboard_screen.dart`
- `lib/features/dashboard/services/dashboard_service.dart`
- `lib/features/dashboard/services/productivity_service.dart`
- `lib/features/dashboard/widgets/module_monitoring_section.dart`
- `lib/features/dashboard/widgets/productivity_chart.dart`
- `lib/features/reports/screens/report_screen.dart`
- `lib/features/reports/services/report_service.dart`
- `test/phase01_ui_test.dart`
- `test/phase05_dashboard_test.dart`
- `test/phase05_dashboard_ui_test.dart`
- `test/support/memory_firestore.dart`
- `tools/dependency_health_audit.py`
- `tools/firestore_tests/logbook_rules.test.mjs`
