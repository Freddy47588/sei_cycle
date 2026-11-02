# Phase 06 — Penghapusan fitur sampel dan audit administratif

17 Oktober 2026, Asia/Jakarta. Project produksi yang disebut pengguna: `seicycle-kebun-sei`.

## Status nyata

**Database produksi belum diinventarisasi. Tidak ada query audit, backup, seed, penghapusan, migrasi, atau deployment produksi yang dijalankan.** Tidak ada daftar dokumen produksi yang dinyatakan aman dihapus. Akses administratif terautentikasi untuk membaca seluruh relasi belum diverifikasi dalam pekerjaan ini. Konfigurasi project pada `.firebaserc` bukan bukti otorisasi/inventarisasi database.

Audit yang dijalankan adalah tujuh unit test Python dengan fixture offline. Hasilnya bukan dry-run dataset Kebun Sei. Test Flutter/Firestore memakai fake atau project Emulator `demo-seicycle-phase02` pada loopback.

Pemeriksaan metadata autentikasi CLI mendeteksi dua akun Firebase yang tersimpan; `gcloud` tidak tersedia. Ini tidak membuktikan akun yang dipilih memiliki izin baca administratif terhadap seluruh dokumen/relasi project tujuan. Tidak mengekstrak token atau mengasumsikan snapshot produksi lengkap dari status login CLI. Inventarisasi produksi tetap belum dilakukan.

## Fitur yang dihapus

- Kartu **Data sampel demo**, **Seed sampel**, **Hapus sampel**, dan import service pada Profil.
- File runtime `lib/core/dev/sample_data_service.dart` beserta jalur create/clear/check dataset contoh.
- `CircularFlowService.seedDefaultFlows` dan generator `defaultCircularFlows`, yang sebelumnya dapat menyimpan ilustrasi sebagai transaksi.
- Petunjuk seeding operasional dalam `docs/SAMPLE_DATA.md` diganti dengan rujukan audit ini. README tidak lagi mengarahkan admin membuat demo data.

**FarmModuleService.seedDefaults tetap tersedia**, karena menyiapkan master lima modul canonical: ayam_kampung, maggot_bsf, cacing_tanah, tanaman, lele. Tidak menghapus master, formulir, atau transaksi aktual. Fixture fake, widget, dan Emulator tetap tersedia di test/tools yang terisolasi.

## Identifikasi dan perlindungan

Seeder lama memakai `isSampleData: true`, `sampleVersion: v2`, `createdBy: sample_seed`. Penanda parsial adalah alasan meninjau, bukan izin menghapus. ID dengan prefix sample, nama produk, dan ID canonical **tidak cukup** sebagai bukti sampel.

Target historis meliputi users, farm_modules, logbooks, inventory, inventory_transactions, production_results, circular_flows, schedules, notifications, education_contents, finance_transactions, recommendations. Pemeriksaan relasi juga mencakup batches dan sales serta subcollection audit/reference yang ada.

`tools/sample_data_audit.py` **hanya membaca snapshot JSON lokal dan mencetak laporan ke stdout**. Tidak memerlukan credential, tidak terhubung ke Firebase, tidak memiliki operasi delete, dan tidak mengubah input. Tidak ada opsi yang mengaktifkan penghapusan produksi. Mode default selalu `read-only-dry-run` dan `writes: 0`, termasuk ketika allowlist diberikan.

Format masukan adalah JSON yang sudah didekode ke nilai biasa oleh administrator:

```json
{
  "projectId": "project-yang-ditinjau",
  "completeCollections": ["users", "farm_modules", "logbooks", "inventory", "inventory_transactions", "production_results", "circular_flows", "schedules", "notifications", "education_contents", "finance_transactions", "recommendations", "batches", "sales"],
  "documents": [{"path": "collection/document", "updateTime": "waktu-versi-export", "data": {}}]
}
```

Masukan ini **bukan** format binary managed Firestore export. Simpan export asli sebagai backup; administrator harus membuat snapshot JSON lengkap termasuk subcollection/referensi untuk audit. Pernyataan `completeCollections` harus diperiksa manusia terhadap export asli, karena tool tidak dapat membuktikan kelengkapan deklarasi tersebut.

```powershell
python tools/sample_data_audit.py --project <project-eksplisit> --snapshot <snapshot.json>
python tools/sample_data_audit.py --project <project-eksplisit> --snapshot <snapshot.json> --allowlist <approved_paths.json>
python -m unittest discover -s tools -p test_sample_data_audit.py -v
```

Allowlist adalah array path dokumen lengkap yang sudah ditinjau, bukan prefix/query. Project mismatch, path duplikat/tidak valid, dan approval di luar kandidat ditolak. Laporan menyertakan digest SHA256 snapshot, hitungan per collection, semua penanda, versi update, referensi masuk, serta alasan pemblokiran.

Pemblokiran mencakup metadata parsial, snapshot tidak lengkap, updateTime hilang, relasi masuk atau ID ambigu, dan dokumen operasional terlindungi. Users, farm_modules, inventory, inventory_transactions, production_results, finance_transactions, sales, dan logbooks selalu membutuhkan rekonsiliasi tersendiri meskipun semua penanda cocok. Allowlist tidak melewati pemblokiran tersebut.

Pencarian relasi bersifat konservatif: kecocokan string ID/path/full document resource dianggap referensi potensial. Field teks bebas dapat menghasilkan false positive. Referensi yang disimpan dalam format lain, sistem eksternal, atau snapshot yang tidak lengkap tetap memerlukan pemeriksaan manual.

## Prosedur cleanup setelah review terpisah

1. Administrator memverifikasi project, database, identitas IAM, ruang lingkup export, serta menghentikan sementara penulisan yang dapat mengubah referensi. Ambil backup/export lengkap dan uji pemulihan pada lingkungan terisolasi. Catat waktu, jumlah dokumen, manifest dan hash backup. Jangan memakai fixture sebagai backup.
2. Jalankan audit read-only, simpan output sebagai log review, lalu periksa setiap ID/creator/version serta relasi lintas collection. Jangan menjalankan query delete massal berdasarkan isSampleData saja.
3. Periksa dampak: finance memengaruhi pemasukan/pengeluaran/arus kas dan laporan; Logbook/production memengaruhi produktivitas; ledger memengaruhi saldo historis; schedule/notification memengaruhi tindak lanjut. KPI berbasis count dapat berubah. Tidak boleh menghapus satu sisi hubungan operasional.
4. **Jangan hapus akun asli, master canonical, inventaris aktual, ledger asli, Logbook valid, produksi nyata, atau finance nyata.** Master canonical berpenanda sampel harus ditinjau untuk pemulihan metadata yang tepat, bukan dihapus. Saldo campuran dan histori stok harus direkonsiliasi melalui rencana koreksi ber-audit; tool audit tidak menyusun koreksi otomatis.
5. Buat allowlist path pasti, snapshot hash dan updateTime yang disetujui. Minta persetujuan eksplisit terhadap **daftar aktual** dan dampaknya sebelum penghapusan. Persetujuan menghapus fitur aplikasi bukan persetujuan menghapus dokumen database.
6. Eksekusi administratif merupakan pekerjaan terpisah. Bila akhirnya dibuat executor, default harus dry-run; wajib project eksplisit, backup/review/allowlist, validasi ulang metadata serta referensi pada dataset yang tetap dibekukan, dan precondition updateTime per dokumen. Dokumen berubah/tidak pasti harus ditolak. Jangan memberikan bypass untuk daftar terlindungi.
7. Executor harus mencatat setiap path, versi, aktor, waktu, hasil dan error. Gunakan kelompok kecil yang dapat ditinjau; hentikan pada konflik/error/SIGINT. Simpan hasil sukses sebelum melanjutkan, jangan mengulang delete secara membabi buta setelah kegagalan sebagian. Restore/rekonsiliasi mengikuti manifest backup, bukan mengarang saldo pengganti.
8. Setelah selesai, verifikasi jumlah dokumen, referensi yang tersisa, histori stok dan saldo setiap barang, total finance, produksi per Logbook, jumlah penjualan, serta laporan periode sebelum/sesudah. Jalankan ulang audit dan smoke test pengguna. Log cleanup bukan pengganti audit finansial/stock opname.

Dokumen ini menyediakan prosedur administratif, **bukan executor penghapusan**. Tidak ada cleanup produksi yang dijalankan pada Phase 06 ini.

## Pencegahan pada aplikasi

Dashboard/count produktivitas memeriksa penanda sampel melalui query terbatas sebelum menerbitkan KPI; finance menolak ringkasan ketika penanda terdeteksi. Tidak memakai filter `isSampleData != true` yang dapat menghilangkan dokumen nyata legacy tanpa field tersebut. Error pemeriksaan tidak diubah menjadi statistik nol.

Aliran aktual Dashboard hanya berasal dari `sourceType: manual`, aktor tercatat, jumlah valid, tanpa penanda sampel. Dokumen legacy masih dapat dibaca di daftar dengan label belum terverifikasi, tetapi tidak menjadi bukti aliran aktual. Report menolak sumber bertanda sampel yang dibaca. Penjualan menolak master bertanda sampel; flow menolak referensi sampel. Tidak ada dummy chart, seed otomatis, atau pencatatan ilustrasi.

Guard ini bukan pengganti inventarisasi produksi; data demo tanpa semua penanda yang dikenali tetap memerlukan review administratif. Dataset kosong menampilkan empty state sebenarnya.
