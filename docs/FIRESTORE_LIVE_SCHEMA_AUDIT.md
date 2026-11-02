# Firestore live schema audit — 17 Oktober 2026

## 1. Waktu dan lingkup

Inventaris dibaca mulai **17 Oktober 2026 06:26:00 WIB** (16 Oktober 23:26:00 UTC). Verifikasi metadata/IAM/log dilakukan 06:36 WIB. Project terverifikasi: **seicycle-kebun-sei**; database **(default)**; tipe **FIRESTORE_NATIVE**; lokasi **asia-southeast2**. Tanggal di dokumen ini memakai Asia/Jakarta, bukan timezone commit Git.

HEAD `890df58cb60a1733f34d28d2d07859dfe30ca7e1`, branch `feature/operational-v2`; fetch origin berhasil. HEAD tidak berubah dari baseline pengguna. Workspace sudah memiliki perubahan lokal sebelum audit; patch awal disimpan lokal dan perubahan tersebut dipertahankan. Tidak mengubah remote/upstream.

## 2. Koneksi dan batas audit

Firebase MCP tidak tersedia dalam daftar tools. Firebase CLI 15.34.0 memiliki sesi autentikasi lokal. Auditor memakai token OAuth sesi CLI dalam memori untuk API administratif resmi; **tidak mengasumsikan login CLI menyediakan ADC/Admin SDK**. Identitas akun diperiksa lokal dan tidak dicantumkan di Git. IAM mengonfirmasi `datastore.entities.get`, `datastore.entities.list`, `datastore.databases.getMetadata`, `logging.logEntries.list`, dan `logging.privateLogEntries.list`.

`tools/firestore_readonly_audit.cjs` hanya menggunakan GET dan endpoint read-only `listCollectionIds`, `testIamPermissions`, dan `entries:list`. Tidak mengimplementasikan write/delete Firestore, Authentication mutation, deployment, atau migrasi. Project dipatok secara eksplisit. Root collections dan descendants, termasuk missing parents, ditelusuri dengan pagination. Batas pengulangan berikutnya: 2.000 request administratif, 1.000 dokumen per collection, 5.000 dokumen global; hentikan tanpa menyatakan inventaris lengkap jika batas terlampaui. Pembacaan awal menemukan hanya 273 dokumen; tidak melakukan scan produksi berulang untuk setiap analisis.

Inventaris adalah rangkaian pembacaan, bukan snapshot transaksi atomik seluruh database. Aktivitas klien lain dapat berlangsung selama audit. Keberhasilan API administratif **tidak membuktikan** izin Rules aplikasi Android.

## 3. Collections dan jumlah

**270 dokumen root + 3 dokumen subcollection `finance_transactions/{redacted}/edits/{redacted}` = 273.** Lima belas root collections berisi dokumen ditemukan; `sales` diperiksa kosong. `report_metadata` tidak ditemukan oleh enumerasi root; tidak ada dokumen yang ditemukan di sana. Tidak ditemukan subcollection lain dalam inventaris saat itu.

| Collection | Root | Seed-origin | Non-seed dengan pembuat | Provenance belum jelas |
| --- | ---: | ---: | ---: | ---: |
| users | 10 | 0 | 0 | 10 |
| farm_modules | 10 | 0 | 0 | 10 |
| logbooks | 35 | 15 | 20 | 0 |
| batches | 1 | 0 | 1 | 0 |
| inventory | 16 | 16 | 0 | 0 |
| inventory_items — legacy tambahan | 1 | 0 | 1 | 0 |
| inventory_transactions | 29 | 7 | 22 | 0 |
| production_results | 11 | 6 | 5 | 0 |
| circular_flows | 5 | 5 | 0 | 0 |
| schedules | 16 | 11 | 5 | 0 |
| notifications | 75 | 5 | 0 | 70 |
| education_contents | 9 | 9 | 0 | 0 |
| finance_transactions | 45 | 14 | 31 | 0 |
| finance_records — legacy tambahan | 2 | 0 | 2 | 0 |
| recommendations | 5 | 5 | 0 | 0 |
| sales | 0 | 0 | 0 | 0 |
| **Total root** | **270** | **93** | **87** | **90** |

Tiga dokumen edits adalah audit historis dan tidak dihitung sebagai transaksi Finance tambahan. Pembuat snake_case `created_by` diperiksa sebagai provenance legacy. “Non-seed” tidak sama dengan transaksi bisnis sudah tervalidasi. Profil, master modul, dan notifikasi tanpa pembuat tidak otomatis disembunyikan.

## 4. Distribusi seed dan review

Seluruh **93** root seed-origin memiliki `createdBy == sample_seed`, `isSampleData == true`, dan `sampleVersion == v2`. Jumlah masing-masing marker adalah 93; bukan 279 dokumen berbeda. Tidak ditemukan dokumen ber-UID non-seed dengan flag simulasi dalam snapshot ini; jalur **PERLU REVIEW** tetap diimplementasikan dan diuji. Dokumen tanpa pembuat tidak otomatis diperlakukan sebagai seed.

Seed-origin tidak dihapus atau diubah pembuatnya. Daftar dan KPI operasional mengecualikan provenance seed. Flags saja tidak menjadi bukti seed: daftar menyimpan record pengguna untuk review, sedangkan agregat menolak mengklaim hasil terverifikasi sampai provenance ditinjau. Sembilan konten pendidikan seed ditampilkan sebagai **Contoh / Simulasi**; label presentasi tidak ditulis ke judul sumber.

## 5. Compatibility matrix berdasarkan data aktual

| Actual collection/field | Expected Flutter | Tipe teramati | Status dan dampak | Adaptasi |
| --- | --- | --- | --- | --- |
| users: is_active / isActive | isActive | bool | Campuran legacy; akun nonaktif tidak boleh aktif kembali | Kedua penanda harus tidak false; Rules tetap memeriksa keduanya |
| users: id/uid dan document ID | UID Auth | string | Jangan memakai identitas field lama sebagai actor | Actor memakai document ID profil Auth |
| users: photo_url, created_at, updated_at | photoUrl, createdAt, updatedAt | string, Timestamp | Adapter model sudah tersedia | Pertahankan alias; jangan rewrite profil saat audit |
| farm_modules: module_id/module_type/module_name/is_active | ID/type/name/isActive | string/string/string/bool | Sepuluh dokumen mewakili lima modul dengan dua konvensi ID | Mapping persis module_ayam/module_cacing/module_maggot/module_lele/module_tanaman; deduplikasi baca |
| logbooks: activity_date/module_id/activity_type/note/is_deleted | activityDate/moduleType/activityType/notes/isDeleted | Timestamp/string/string/string/bool | Satu record snake_case terlewat query canonical | Adapter + query ID dokumen yang tidak mensyaratkan field optional |
| logbooks: details, batchId optional | details, batchId | map; batchId tidak tersedia pada records lama | Jangan mengarang batch atau mengubah detail lama | Optional tetap kosong; pemetaan batch hanya bila ada |
| finance_records | finance_transactions | Collection berbeda | Dua transaksi lama awalnya tidak terlihat; Rules awal menolak collection lama | Gabungkan baca dengan identitas sumber; legacy hanya baca; izin aktif kini terverifikasi Android |
| finance_records: created_by/created_at/updated_at/note | createdBy/createdAt/updatedAt/notes | string/Timestamp/Timestamp/string | Adapter model sudah mendukung; query collection belum | Retain aliases; jangan copy transaksi ke canonical |
| finance_transactions: amount/type/date | amount/type/date | double/string/Timestamp | Bentuk canonical pada 45 root; 14 seed | Validasi jumlah finite positif dan income/expense; exclude seed |
| finance_transactions: isDeleted | isDeleted | bool pada 45 root | Canonical ada; legacy finance_records tidak memiliki field ini | Absent berarti tidak soft-deleted, bukan otomatis sample |
| finance_transactions/.../edits: before/after/editedAt | Audit edits | map/map/Timestamp | Tiga dokumen audit sensitif | Hanya role Finance; tidak diagregasi sebagai transaksi |
| inventory_items: current_stock/min_stock/is_low_stock | currentStock/minStock/isLowStock | double/double/bool | Satu master lama tidak terlihat | Adapter baca; sumber legacy tidak dapat dimutasi sebagai canonical |
| inventory: currentStock/minStock/isDeleted | Field canonical | double/double/bool | Seluruh 16 master seed, sembilan pernah diperbarui | Exclude daftar, jangan rekonstruksi saldo; periksa ledger nyata |
| inventory_transactions: itemId/logbookId/quantity/transactionDate | Field canonical | string/string/double/Timestamp | 22 transaksi non-seed mereferensikan master seed | Konflik integritas; histori dipertahankan, KPI stok ditolak |
| batches: initialQuantity/expectedHarvestAt/completedAt | Optional fields | null/null/null | Satu batch aktif; initialUnit string | Null tetap null; jangan memaksa kuantitas awal fiktif |
| schedules: scheduled_at/module_id/schedule_type/note | date/moduleType/type/notes | Timestamp/string/string/string | Satu record legacy; isDeleted absent | Adapter + filter periode setelah kelengkapan terbukti |
| schedules: status/type | status/type | string | pending/done/skipped; jenis aktivitas juga teks bebas existing | Jangan paksa jenis kegiatan lama ke enum baru |
| production_results: harvestDate/logbookId/batchId | Field canonical | Timestamp/string; batchId hanya 1 record | Lima hasil non-seed, sebagian lewat Logbook memakai inventory seed | Verifikasi parent dan ledger; jangan jumlahkan hasil duplikat |
| circular_flows: sourceType absent | sourceType manual | Absent pada 5 record | Semua seed; bukan pergerakan aktual yang terbukti | Tidak dihitung sebagai nutrisi operasional |
| education_contents: status/type | published/artikel,sop,video | string | Sembilan materi seed published | Label contoh; tidak masuk KPI operasional |
| notifications: createdBy absent | Optional provenance | Absent pada 70 record | Tidak otomatis seed; 60 alert terkait master seed | Baca penerima tetap server-constrained; isolasi referensi seed |
| recommendations | Sinyal dihitung dari data nyata | Semua 5 seed | Konten lama tidak dapat dijadikan sinyal operasional | Generator memakai sumber nyata lengkap dan memeriksa konflik |
| sales / report_metadata | Canonical | Tidak ada data ditemukan | Tidak ada bukti format transaksi legacy di collection ini | Jangan mengarang alias; regresi memakai fixtures sintetis |

Tidak ditemukan `stok` atau quantity bertipe string pada root operasional yang diaudit. Tidak menambahkan alias spekulatif untuk contoh tersebut. Semua timestamp bisnis yang teramati menggunakan Firestore Timestamp; string tanggal/nilai uang invalid tidak diberi fallback nol. Default optional tidak menjadi bukti data bisnis valid.

## 6. Analisis waktu

`createTime` dan `updateTime` berasal dari metadata server, berbeda dari `createdAt`/`updatedAt` dan tanggal aktivitas. Inventaris lokal memuat histogram terpisah: document create day, document update day, dan business activity day dalam WIB. Field `createdAt` tidak dianggap sumber waktu yang pasti; tidak menggunakan tanggal commit sebagai tanggal transaksi.

Sembilan dari 16 master inventory seed memiliki metadata `updateTime` berbeda dari `createTime`: lima diperbarui 15 Oktober, empat 17 Oktober WIB. Ini membuktikan dokumen seed pernah berubah, tetapi tidak cukup untuk menyatakan saldo berasal seluruhnya dari aktivitas asli. Notifikasi dan jadwal juga memiliki update pada tanggal lain; perubahan metadata bukan otomatis transaksi bisnis.

## 7. Kronologi Finance dan aktivitas terbaru

- 22 Juni: dua `finance_records` legacy dibuat dan diperbarui; satu income dan satu expense. Identitas dan jumlah uang tidak dipublikasikan.
- 28–29 Juni: 14 root Finance seed dibuat; tidak ditemukan perubahan metadata server setelah penciptaannya.
- **15 Oktober: 31 root Finance non-seed dibuat.** Sebanyak 28 masih memiliki hari update 15 Oktober, tiga diperbarui **17 Oktober WIB**.
- 15 Oktober: lima Logbook dibuat, sepuluh ledger inventory dibuat, dua production results dibuat; lima master modul dan lima master inventory diperbarui. Ini membantah asumsi database tidak digunakan.
- 17 Oktober: satu batch dibuat, empat ledger inventory dan satu production result dibuat; empat master inventory diperbarui. Audit tidak menjalankan operasi ini.

Pencarian Cloud Audit Logs read-only untuk DeleteDocument/Commit/BatchWrite pada rentang 15 Oktober 00:00 sampai 17 Oktober 06:59:59 WIB menghasilkan **0 entri**. Ketersediaan/retensi Data Access logs pada saat penghapusan tidak terbukti. **Isi, identitas, relasi, dan keamanan penghapusan dua dokumen Finance manual tidak diketahui.** Jangan mencoba memulihkannya dengan data rekaan.

## 8. DATA INTEGRITY CONFLICT

| Sumber non-seed / provenance tidak jelas | Relasi ke seed | Jumlah |
| --- | --- | ---: |
| inventory_transactions | itemId → inventory | 22 |
| notifications | relatedId → inventory | 34 |
| notifications | relatedId → schedules | 26 |

Konflik ledger juga dapat memengaruhi Logbook/production secara transitif. Pemeriksa runtime menelusuri parent serta ledger Logbook tanpa mengganti parent. Histori nyata tetap dapat ditinjau; angka stok, produksi atau keuangan terkait tidak diklaim aman sebelum verifikasi. Tidak ditemukan sales dalam snapshot; tidak menyimpulkan integritas penjualan sudah terbukti hanya dari kondisi kosong.

## 9. Rules dan index

93 composite indexes aktif cocok dengan 93 deklarasi lokal setelah normalisasi implicit document ID ordering: **0 missing, 0 extra**. Tidak mengubah atau deploy index. Query kompatibilitas memakai ordering document ID sehingga tidak membutuhkan composite index baru.

Pada audit awal 06:26 WIB, Rules aktif tidak memiliki match `finance_records` atau `inventory_items`; fallback deny berlaku dan smoke Android mengonfirmasi permission-denied. Patch workspace menyediakan read-only sesuai role dan hardening provenance/report metadata; seluruh patch diuji pada Emulator.

Pada pengecekan setelah pengguna memberikan izin eksplisit di percakapan, source Rules aktif ternyata telah berubah. Ruleset baru dibuat **17 Oktober 2026 06:56:41 WIB** dan release diperbarui 06:56:42; isinya cocok dengan `firestore.rules` workspace setelah normalisasi line ending. Cloud Audit Logs mengonfirmasi CreateRuleset/UpdateRelease memakai akun yang sama dengan sesi CLI; identitas tidak dipublikasikan dan initiator proses tidak dapat dipastikan. Auditor ini tidak mengirim deployment ulang: pemeriksaan hash membatalkan kandidat minimal berbasis baseline lama. Kandidat lama ditandai obsolete agar tidak menimpa hardening yang sudah aktif.

Pembacaan Android selanjutnya membuktikan Finance dan Inventory legacy dapat diakses. Hardening penuh yang sekarang aktif dapat menolak mutasi klien lama pada master seed; ini harus diperhitungkan dalam rekonsiliasi, bukan diatasi dengan mengubah origin seed menjadi pengguna asli. Tidak ada index atau dokumen bisnis dimutasi oleh audit. [Rules bukan filter](https://firebase.google.com/docs/firestore/security/rules-query); [orderBy mengecualikan field yang tidak ada](https://firebase.google.com/docs/firestore/query-data/order-limit-data).

## 10. Strategi tanpa migrasi produksi

Adapter cukup untuk volume saat audit; tidak perlu rename/copy collection. Baca lengkap berpaginasi dibatasi **500 dokumen per sumber**; sentinel ke-501 membuat sumber unavailable, bukan total parsial. Tidak ada `createdBy != sample_seed`, filter `isSampleData == false`, atau fallback error menjadi nol. Jika salah satu sumber legacy ditolak, total gabungan tidak diterbitkan. Field bisnis canonical menang bila keduanya ada; konflik alias nilai historis perlu review tersendiri.

Untuk skala di atas batas tersebut, usulkan metadata versi dan provenance terindeks setelah review: origin seed/operational/review, schemaVersion, reconciliation state dan canonical query fields, dengan coverage manifest yang membuktikan dokumen legacy seluruhnya ikut query. **Ini proposal, bukan migrasi yang dijalankan.** Review flags atau UID tidak boleh otomatis dikonversi menjadi operational. Saldo tidak dihitung ulang otomatis. Koleksi lama tetap tersedia untuk klien lama.

## 11. Backup/restore sebelum perubahan database kelak

Sebelum migrasi atau rekonsiliasi yang disetujui: tetapkan scope/path allowlist dan precondition updateTime, ambil backup sah terenkripsi dengan akses terbatas, backup Rules/index aktif, verifikasi pemulihan di project staging/Emulator, lalu siapkan dry-run mapping before/after, idempotency ledger, verifikasi jumlah/checksum dan rencana rollback. Kelola data pribadi di luar Git. Snapshot lokal audit bukan managed export lengkap: tidak mencakup Auth, sejarah dokumen terhapus, TTL/PITR atau jaminan restore metadata waktu server. Tidak ada restore/migration produksi dijalankan.

## 12. Inventaris machine-readable

`build/audit_android/inventory.json` berisi agregat, histogram WIB, tipe field, provenance dan jumlah konflik. Folder `build/` diabaikan Git. `tools/live_schema_summary.py` menghitungnya secara offline dan dites agar tidak memuat UID/path individual, email, nilai finansial atau isi dokumen. Dokumen ini tidak menyertakan dump mentah atau credential.

## 13. Known unknowns

Kebenaran bisnis 177 root non-seed belum otomatis terbukti; 90 tidak memiliki pembuat yang dapat diklasifikasi. Histori sebelum snapshot, isi dua Finance yang dihapus, retensi audit log, keberadaan managed backup/PITR yang dapat digunakan, serta asal komponen saldo inventory tidak dapat disimpulkan dari inventaris. Klien lama mungkin masih menulis ke master seed atau collection legacy. Jumlah collection dan dokumen dapat berubah setelah audit. Query gabungan bukan satu transaksi lintas collection.

## 14. Keputusan keselamatan

**Tidak ada dokumen bisnis produksi, akun Authentication, saldo, marker, relasi atau index produksi diubah oleh auditor.** Tidak menjalankan seeder atau migrasi. Perubahan Rules yang teramati dicatat pada bagian 9; auditor tidak men-deploy ulang kandidat yang sudah kedaluwarsa. Izin baca legacy kini terverifikasi di Android. Rekonsiliasi saldo tetap membutuhkan bukti dan keputusan pemilik data; izin umum tidak dapat menetapkan saldo yang belum diketahui.
