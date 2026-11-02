# Phase 06/08 — Finance, Sales, Circular Flow dan UX

17 Oktober 2026 (Asia/Jakarta), `Freddy47588/sei_cycle`, branch `feature/operational-v2`, baseline `c14f5718b52256736220372728deddc8f4424b06`.

## Lingkup dan baseline

Audit membaca instruksi repository, dokumentasi Phase 01–05, dependency, schema/rules/index, serta implementasi Auth/role, shell, tema, Dashboard, Logbook, Batch, Inventory, Jadwal, Finance, Circular Flow dan Report. Remote origin/fetch sesuai baseline dan tidak memiliki commit baru saat pemeriksaan awal. Working tree berisi lima perubahan pengguna yang dipertahankan: audit Phase 01 dan registrant Linux/macOS. Tidak melakukan pull karena remote sama dan working tree berisi perubahan pengguna.

Baseline dijalankan ulang: **223 Flutter tests, 80 Emulator tests, analyzer 0 issue**. Flutter 3.44.2 stable, Dart 3.12.2. Phase 07–08 tidak dikerjakan. Tidak menambah dependency atau mengganti arsitektur/desain.

## Penghapusan fitur sampel

Profil tidak memiliki kartu/tombol demo atau import service. `lib/core/dev/sample_data_service.dart` dihapus, begitu pula generator/penyimpanan aliran ilustrasi dalam CircularFlowService. Penyiapan lima modul resmi dipertahankan. Test memeriksa seluruh sumber Dart agar jalur seeder tidak kembali.

Audit offline dan prosedur administratif ada di [cleanup data sampel](PHASE_06_SAMPLE_DATA_CLEANUP.md). **Produksi belum diinventarisasi dan tidak dihapus.** Guard penanda sampel pada Dashboard/produktivitas/finance mencegah statistik demo diklaim sebagai operasional. Pemeriksaan terbatas menambah maksimal tiga query limit1 per collection yang dilindungi; tidak memakai full scan. Data legacy tanpa penanda tidak disembunyikan oleh filter field yang tidak ada.

## UX Logbook dan navigasi

Shell mempertahankan hanya subtree Logbook setelah pertama dibuka melalui IndexedStack/TickerMode dan GlobalKey. Form lima modul tetap memakai keep-alive existing. Input, tanggal, batch, slider, status simpan, dan requestId tetap berada pada instance form yang sama saat membuka Dashboard/Notifikasi/menu lainnya; tidak ada write draft ke Firebase. Fokus keyboard dilepas saat pindah menu.

AuthGate mengunci shell dengan key UID. Shell juga membuang cache ketika UID/status aktif berubah; TabBarView Logbook diberi key akun untuk pemakaian langsung. Logout/unmount membuang draft, tidak menyimpannya sebagai Logbook final atau membagikannya ke akun berikut. Draft tidak persisten lintas restart/penutupan aplikasi.

Empat tab utama, Lainnya, sidebar desktop, palet hijau/krem, kartu dan komponen app_ui tetap digunakan. Menu baru ditempatkan setelah menu existing agar akses lama tidak bergeser. Filter baru dapat digulir bersama daftar. Finance memakai dropdown jenis transaksi agar teks tidak pecah pada 320 px/skala 1,4. Label Inventaris memakai Kategori Barang, Filter Status Stok, dan Kode Barang. Histori memilih barang/batch/Logbook dari daftar berhalaman; ID tetap disimpan internal. Sumber Penjualan diberi label Indonesia.

## Finance

Collection canonical tetap `finance_transactions`. Ringkasan menyebut **Pemasukan − Pengeluaran = Arus Kas Bersih**, bukan laba akuntansi. Periode Hari Ini, 7 Hari Terakhir, Bulan Ini, Bulan Sebelumnya, Custom; end query eksklusif. Filter jenis/kategori/modul dijalankan server, pencarian kategori/catatan hanya data dimuat dan tidak mengubah ringkasan periode/filter. Pagination20; API listener kompatibilitas dibatasi100.

Ringkasan membaca maksimal501 dan menolak menghitung bila >500 atau nominal/jenis invalid. Error tampil eksplisit dengan retry, tidak menjadi nol. Daftar tidak diperlakukan sebagai total global.

Create manual memakai requestId sebagai document ID dan menyimpan creationPayload asli. Payload sama no-op; payload berbeda dengan ID sama ditolak. Form menunggu service selesai, menonaktifkan submit/penutupan saat pending, mempertahankan input/ID ketika gagal, lalu menutup hanya sesudah sukses. Nominal finite positif maksimal Rp1 triliun; kategori/jenis/tanggal/modul divalidasi. Metode pembayaran manual tetap kompatibel dengan teks existing.

Edit/delete manual membaca profil dan transaksi sebelum write, memeriksa expectedUpdatedAt, lalu menaikkan version dan membuat `edits/{requestId}` atomik dengan before/after penuh, editedBy/At serta payload. Soft delete mengeluarkan transaksi dari laporan; histori tetap permanen. Audit juga idempotent dan tidak dapat ditimpa. Detail menampilkan receipt dan histori berhalaman. Transaksi source sale/saleId tidak bisa diedit/dihapus melalui service, UI, atau Rules umum.

## Master produk dan penjualan

`inventory.isSellable == true` dan `productType == harvest` wajib ditetapkan eksplisit oleh admin. Legacy/default operational tidak otomatis dapat dijual. Hanya hasil panen nyata boleh diklasifikasikan; pakan/obat/bibit/peralatan tidak dianggap produk jual berdasarkan nama. Operator lapangan tidak dapat menetapkan klasifikasi jual melalui SDK langsung.

Sales memiliki model/input/service/list/form/detail, filter modul/periode, pencarian lokal dan cursor20. Pemilih produk memakai master aktual berhalaman. Form menampilkan saldo, kuantitas/satuan, harga, total, tanggal, pembeli opsional, pembayaran, catatan serta konfirmasi. Penjualan hanya langsung/lunas (tunai, transfer, qris). Create **admin aktif saja**; operator keuangan dapat membaca receipt, tanpa hak mutasi stok manual.

Harga dan total adalah integer Rupiah. Quantity maksimal tiga desimal, dinormalisasi menjadi quantityMilli; total = round-half-up(quantityMilli × unitPrice /1000) sekali per sale. Harga maksimal Rp1 miliar, total maksimal Rp1 triliun; UI total selalu dihitung ulang service dan Rules. Tidak ada gateway/piutang/pajak/e-commerce.

## Transaksi atomik dan provenance

Read sebelum write: profil aktif, receipt sales requestId, master inventory terkini, serta calon ledger dan finance. Receipt lama cocok payload dikembalikan tanpa mutasi ulang. Collision ID pasangan ditolak. Semua read mendahului write.

| Dokumen | Hasil atomik |
| --- | --- |
| sales/{requestId} | Receipt immutable, nomor S-requestId, payload, produk/modul/satuan, quantityMilli, harga/total, paid, aktor/nama dan server timestamps |
| inventory/{itemId} | Saldo terkini − quantity, flag rendah, pointer ledger dan audit update |
| inventory_transactions/sale_{requestId} | out/source sale, saleId, before/after, quantity/unit, aktor/waktu; immutable |
| finance_transactions/sale_{requestId} | income/source sale, saleId, total, tanggal/metode/modul, audit; immutable |

Tidak menulis production_results atau Logbook pada penjualan. Produksi20 kg, penjualan5 dan8 menghasilkan stok7, pemasukan Rp325.000 dengan harga Rp25.000/kg, dan produksi tetap20. Source canonical: production_results untuk panen, inventory untuk saldo, sales untuk penjualan, finance_transactions untuk pemasukan. Nilai tersebut tidak ditambahkan ulang satu sama lain.

Stok gabungan tidak memiliki saldo per batch, sehingga sale tidak menebak batch asal atau mengaitkannya dengan batch terbaru. Field batch tidak ditulis pada receipt sale Phase 06. Detail menjelaskan provenance ini dan menuju histori barang serta pemasukan terkait. Tidak ada tombol cancel/edit/delete sale tanpa reversal atomik.

SDK Firestore mengulang transaksi saat konflik; helper existing mencoba ulang permission-denied/aborted terbatas dengan receipt ID tetap dan pembacaan ulang. Test membuktikan satu pemenang untuk dua penjualan8 kg dari stok10, serta satu debit untuk request identik bersamaan. Kegagalan salah satu write menggagalkan seluruh commit. Receipt ID stabil selama form/sesi, belum ada outbox persisten lintas restart; setelah respons ambigu dan form ditutup, periksa histori sebelum membuat request baru.

## Circular Flow aktual

Daftar/filter sumber/tujuan/material/periode, cursor20, form/detail dan metadata aktor tersedia. Create append-only dengan requestId/creationPayload, sourceType manual, jumlah finite positif maksimal1e12, enam satuan terdaftar (kg, g, liter, ml, butir, ekor), serta modul sumber/tujuan canonical yang berbeda.

Batch sumber/tujuan opsional dipilih eksplisit; referensi Logbook/mutasi opsional dipilih dari daftar. Service/Rules memeriksa keberadaan, modul, status delete dan penanda sampel. Ledger harus sama jumlah/satuan, tidak reversed. Referensi tidak mengeksekusi ulang mutasi. Catatan/bukti kegiatan tetap dapat diisi tanpa referensi.

Tidak ada mutasi stok, transfer lokasi, finance atau produksi otomatis dari pencatatan flow. Histori immutable. Parser legacy dipertahankan; dokumen tanpa provenance/aktor diberi label belum terverifikasi. Dashboard hanya menampilkan flow manual valid tanpa penanda sampel. NutrientFlowCard tetap berjudul **Ilustrasi Siklus Nutrisi Kebun Sei** dan tidak menyimpan diagram.

## Dashboard dan laporan

Dashboard Phase 05 tetap memakai monitoring, sumber produksi dan timeline existing. Kartu penjualan menampilkan total periode serta kuantitas per nama produk/satuan, dengan tautan detail. Finance tetap sumber pemasukan lengkap dan memiliki error terpisah. Role tanpa hak finance tidak menanyakan sales/finance. Tautan Aliran Aktual membuka daftar operasional tanpa menambah tab utama.

Report memuat sale per periode/produk/modul, pemasukan/pengeluaran dan flow per material/satuan. Finance/sales hanya ditanyakan jika includeFinance dan capability aktif mengizinkan. Filter modul berlaku pada sumber terkait; pada flow berarti modul sumber. Inventory adalah saldo saat ini, bukan rekonstruksi saldo historis periode.

Setiap sumber report dibatasi1001, dan laporan ditolak jika >1000 agar tidak mengekspor hasil parsial sebagai lengkap. Persempit periode/modul; inventaris >1000 dalam satu modul memerlukan strategi export administratif terpisah. Tanggal akhir laporan inklusif dikonversi menjadi end eksklusif hari berikutnya.

PDF/Excel existing dipertahankan memakai package yang sama. Ringkasan sale/flow ditambahkan; export tanpa financeIncluded tidak mencantumkan nominal keuangan atau sheet Penjualan/Keuangan. Tes membaca ulang XLSX untuk memeriksa nominal integer dan quantity desimal, serta membangun PDF valid. Export platform share/native belum diuji pada Android fisik.

## Security Rules dan indexes

Capabilities manajemen AppUser seluruhnya mensyaratkan akun aktif. Rules menjadi batas utama, termasuk untuk SDK yang dimodifikasi. Sales read dibatasi active admin/operator keuangan; create admin; immutable bagi semua role. Ledger sale memakai pairing inventory existing dan fresh receipt sale; finance sale memverifikasi pasangan sale, jenis income, nominal/tanggal/modul/metode yang sama. Sale memeriksa saldo sebelum/sesudah, master harvest, receipt pasangan baru, rumus uang dan audit. Tidak ada bypass admin untuk stok/receipt.

Finance manual create membatasi actor/request/version; update harus membawa histori baru yang sama persis before/after dan versi berikut. Delete fisik ditolak. Flow memvalidasi schema/aktor/reference dan append-only. Akun inactive dan legacy tanpa finance tidak dapat membaca nominal sales/finance. Detail nama aktor memakai snapshot profil yang sudah dibaca dalam transaksi; UID tetap metadata audit.

**15 composite index baru, total93:** finance6, circular7, sales1, inventory1. Kombinasi persis dijelaskan di [indexes](FIRESTORE_INDEXES.md). Tidak menambah dua index satu-field yang pernah menyebabkan HTTP400. JSON, duplikasi dan bentuk query diperiksa; Emulator tidak membuktikan ketersediaan index produksi.

**Rules/index tidak dideploy otomatis.** Review serta deployment manual keduanya dan tunggu index siap sebelum menggunakan versi aplikasi ini pada project tujuan. Client Finance lama yang menulis tanpa receipt/audit akan ditolak oleh Rules baru; koordinasikan rilis aplikasi dan Rules.

## Dependency dan kualitas

Tidak ada perubahan pubspec/lockfile/Android Gradle/Kotlin/Firebase options. Audit ulang104 hosted packages melalui metadata pub.dev dan sumber upstream resmi: tidak ada flag discontinued/retracted pada versi terkunci. Rincian snapshot Phase06 dan batas audit tercatat di [Dependency Health](DEPENDENCY_HEALTH.md). Risiko maintenance excel existing tetap dicatat; tidak ditambah package baru atau ignore deprecation. Analyzer mendeteksi API aplikasi, bukan seluruh API internal transitif/native.

Hasil akhir quality gate dan bukti artefak dicatat di bagian verifikasi setelah seluruh command selesai. Uji device fisik Infinix X6833B belum tersedia; flutter devices hanya mendeteksi Chrome/Edge. Tidak mengklaim login/keyboard fisik/notifikasi/Firestore native produksi telah diuji.

## Batas dan kesiapan Phase 07

Tidak mengimplementasikan reversal sale, koreksi kuantitas Logbook, transfer lokasi, persistensi draft/request lintas restart, piutang, atau backend agregasi. Penjualan tidak mengatribusikan batch tanpa saldo/provenance yang sah. Data legacy tanpa field query canonical membutuhkan audit terencana, bukan migrasi otomatis.

Fondasi operasional Phase06 siap ditinjau untuk kelanjutan Phase07 setelah deployment manual Rules/index dan smoke test perangkat. Audit dataset produksi serta persetujuan cleanup tetap pekerjaan administratif terpisah. Phase07/08 tidak diimplementasikan dalam commit ini.

## Daftar file Phase 06

Sebanyak 55 file ditambahkan/diubah/dihapus pada scope ini. Lima perubahan lokal pengguna di luar daftar tetap dipertahankan dan tidak di-stage. File runtime sample_data_service.dart adalah satu-satunya file yang dihapus.

- `.gitignore`
- `README.md`
- `docs/DEPENDENCY_HEALTH.md`
- `docs/FIRESTORE_INDEXES.md`
- `docs/FIRESTORE_RULES.md`
- `docs/FIRESTORE_SCHEMA.md`
- `docs/PHASE_04_INVENTORY_SCHEDULE.md`
- `docs/PHASE_06_DEPENDENCY_HEALTH_SNAPSHOT.json`
- `docs/PHASE_06_FINANCE_SALES_CIRCULAR_FLOW.md`
- `docs/PHASE_06_SAMPLE_DATA_CLEANUP.md`
- `docs/SAMPLE_DATA.md`
- `firestore.indexes.json`
- `firestore.rules`
- `lib/app/app_shell.dart`
- `lib/core/constants/firestore_collections.dart`
- `lib/core/dev/sample_data_service.dart` ? dihapus
- `lib/core/utils/excel_generator.dart`
- `lib/core/utils/operation_error.dart`
- `lib/core/utils/pdf_generator.dart`
- `lib/core/utils/sample_data_guard.dart`
- `lib/core/widgets/firestore_paged_list.dart`
- `lib/core/widgets/period_filter.dart`
- `lib/features/auth/screen/auth_gate.dart`
- `lib/features/batches/screen/batch_detail_screen.dart`
- `lib/features/circular_flow/models/circular_flow.dart`
- `lib/features/circular_flow/screen/circular_flow_screen.dart`
- `lib/features/circular_flow/services/circular_flow_service.dart`
- `lib/features/dashboard/models/dashboard_summary.dart`
- `lib/features/dashboard/screen/dashboard_screen.dart`
- `lib/features/dashboard/services/dashboard_service.dart`
- `lib/features/dashboard/services/productivity_service.dart`
- `lib/features/finance/models/finance_record.dart`
- `lib/features/finance/screen/finance_detail_screen.dart`
- `lib/features/finance/screen/finance_screen.dart`
- `lib/features/finance/services/finance_service.dart`
- `lib/features/inventory/models/inventory_item.dart`
- `lib/features/inventory/screen/inventory_history_screen.dart`
- `lib/features/inventory/screen/inventory_screen.dart`
- `lib/features/inventory/services/inventory_service.dart`
- `lib/features/inventory/services/inventory_transaction_service.dart`
- `lib/features/inventory/widgets/inventory_master_form.dart`
- `lib/features/logbook/screen/logbook_screen.dart`
- `lib/features/profile/models/app_user.dart`
- `lib/features/profile/screen/profile_screen.dart`
- `lib/features/reports/models/analytics_model.dart`
- `lib/features/reports/screens/report_screen.dart`
- `lib/features/reports/services/report_service.dart`
- `lib/features/sales/models/sale.dart`
- `lib/features/sales/screen/sales_screen.dart`
- `lib/features/sales/services/sales_service.dart`
- `test/phase06_services_test.dart`
- `test/phase06_ui_test.dart`
- `tools/firestore_tests/logbook_rules.test.mjs`
- `tools/sample_data_audit.py`
- `tools/test_sample_data_audit.py`

## Verifikasi akhir

| Pemeriksaan | Hasil aktual |
| --- | --- |
| flutter pub get / pub outdated | Lulus; versi tetap, 40 upgradable terkunci dan 13 constraints di bawah resolvable |
| flutter analyze | 0 issue; tidak ada deprecated API baru yang terdeteksi |
| flutter test --reporter expanded | **311 lulus**: 223 regresi + 47 service/model/export Phase06 + 41 UI Phase06 |
| Firestore Emulator + SDK Rules | **139 lulus**: 80 regresi + 59 Phase06; 0 gagal/skipped |
| Python sample audit | **7 lulus**, fixture offline, 0 database write |
| flutter build apk --debug | Berhasil; APK di build/app/outputs/flutter-apk/app-debug.apk |
| UI Phase06 | 48 PNG fixture di build/phase06; 320/360/768/1280 px, skala teks1,4; inspeksi visual form/list/detail/profil; mode font test default juga lulus |
| JSON/index | 93 composite unik; 78 baseline tetap, tanpa composite satu-field |
| git diff --check | Lulus |
| Perlindungan lokal | SHA256 kelima file pengguna sama seperti sebelum implementasi; tidak di-stage |
| Dependency/native configuration | Pubspec/lockfile/Android/Firebase options tetap; google-services.json dan credential tidak di-stage |
| Firebase produksi | Tidak diinventarisasi, tidak di-seed/cleanup/deploy |
| Android fisik Infinix | Belum diuji; perangkat tidak terdeteksi |

Command utama yang dijalankan:

```powershell
flutter --version
flutter pub get
flutter pub outdated
flutter analyze
flutter test --reporter expanded
flutter test --reporter expanded --dart-define=CAPTURE_UI=true
flutter build apk --debug
python tools/dependency_health_audit.py --output build/phase06-dependency-health.json
python -m unittest discover -s tools -p test_sample_data_audit.py -v
git diff --check
```

Emulator memakai konfigurasi demo Phase05 di 127.0.0.1:8095. Runner awal `firebase emulators:exec --only firestore --project demo-seicycle-phase02 --config firebase.phase05.json "npm --prefix tools/firestore_tests test"` lulus. Pada pengulangan CLI mendeteksi port masih dipakai oleh proses Emulator dari runner sebelumnya; proses tidak dihentikan secara paksa. Suite akhir memakai FIRESTORE_EMULATOR_HOST=127.0.0.1:8095 dan `npm --prefix tools/firestore_tests test` terhadap demo project yang sama; initializeTestEnvironment memuat Rules terbaru. Tidak ada fallback ke produksi.

Log pengujian/build disimpan di build/phase06-*.log dan tidak di-commit. Capture adalah render fixture, bukan screenshot database produksi. APK SHA256: `8f5fde41984bd5cc9c51f3a3ab7b2d4b622b0ba7b27ea3a3858394004f47c2e0`.

Warning Kotlin Gradle Plugin existing tetap tercatat meskipun assembleDebug berhasil. Uji autentikasi/Firestore/push notification/keyboard fisik di Android nyata belum dilakukan. Laporan ini tidak menyatakan semua integrasi produksi telah diverifikasi.

Commit/push memakai pesan yang diminta ke origin/feature/operational-v2 setelah gate di atas; SHA akhir dan kesamaan remote dilaporkan dalam hasil pengerjaan. Tidak membuat PR, merge main, force push, deployment, atau perubahan upstream.
