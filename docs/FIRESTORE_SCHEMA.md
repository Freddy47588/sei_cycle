# Firestore Schema SeiCycle

Schema ini adalah kontrak MVP Flutter + Firebase langsung. Tidak ada Firebase Storage, Cloud Functions, atau backend server. Semua timestamp disimpan sebagai Firestore `Timestamp`; sebagian besar data operasional memakai UUID dari Flutter sebagai document ID dan field `id`. Pengecualian batch menggunakan kode unik yang dinormalisasi sebagai ID deterministik.

Nama field canonical memakai camelCase. Model Dart masih membaca beberapa field snake_case lama sebagai fallback agar dokumen lama tidak langsung menyebabkan null error, tetapi write baru harus mengikuti schema di bawah.

## Collection Utama

| Collection | Status | Keterangan |
| --- | --- | --- |
| `users` | aktif | Profil Firebase Auth dan role aplikasi. |
| `batches` | aktif | Identitas kelompok/siklus budidaya lima modul. |
| `logbooks` | aktif | Catatan aktivitas operasional per moduleType. |
| `inventory` | aktif | Stok dan kebutuhan operasional. |
| `inventory_transactions` | aktif | Histori perubahan stok otomatis dari Logbook. |
| `production_results` | aktif | Hasil produksi/panen dari Logbook. |
| `circular_flows` | aktif | Aliran nutrisi antar modul untuk Dashboard. |
| `schedules` | aktif | Jadwal operasional dan status pelaksanaan. |
| `notifications` | didukung | Notifikasi in-app ringan, tanpa FCM server/Cloud Functions. |
| `education_contents` | aktif | Artikel, video link, dan SOP tanpa Storage. |
| `finance_transactions` | aktif | Pemasukan/pengeluaran operasional. |
| `report_metadata` | didukung | Metadata laporan/export di sisi client. |
| `recommendations` | didukung | Snapshot opsional untuk rekomendasi rule-based. Default rekomendasi dibuat on-demand di client. |

## Field Umum Dokumen Operasional

Dokumen operasional memakai field berikut bila relevan:

```json
{
  "id": "uuid-or-document-id",
  "title": "Judul dokumen",
  "name": "Nama item jika bukan berbentuk judul",
  "description": "Deskripsi panjang jika relevan",
  "notes": "Catatan tambahan",
  "status": "pending",
  "date": "timestamp",
  "createdAt": "timestamp",
  "updatedAt": "timestamp",
  "createdBy": "uid",
  "updatedBy": "uid",
  "isDeleted": false
}
```

`isDeleted` digunakan untuk soft delete data operasional agar dashboard/laporan bisa mengabaikan data yang disembunyikan tanpa kehilangan audit trail.

## `users/{uid}`

```json
{
  "id": "firebase-auth-uid",
  "uid": "firebase-auth-uid",
  "name": "Nama Pengguna",
  "email": "user@example.com",
  "photoUrl": "",
  "role": "operator_lapangan",
  "isActive": true,
  "fcmToken": "optional-client-token",
  "fcmTokenUpdatedAt": "timestamp",
  "createdAt": "timestamp",
  "updatedAt": "timestamp"
}
```

Role valid: `admin`, `operator_lapangan`, `operator_keuangan`. Legacy role `operator`, `mitra`, dan `peserta_edukasi` masih dapat dibaca untuk kompatibilitas data lama.

## `farm_modules/{moduleType}`

Collection pendukung untuk daftar modul tetap.

Document ID: `ayam_kampung`, `maggot_bsf`, `cacing_tanah`, `lele`, `tanaman`.

```json
{
  "id": "ayam_kampung",
  "name": "Ayam Kampung",
  "type": "ayam",
  "description": "Pencatatan pakan, produksi telur, dan kesehatan ayam.",
  "icon": "egg_alt",
  "color": "#F59E0B",
  "isActive": true,
  "updatedAt": "timestamp"
}
```

## `logbooks/{id}`

```json
{
  "id": "uuid",
  "title": "Pemberian pakan",
  "moduleType": "ayam_kampung",
  "activityDate": "timestamp",
  "quantity": 10,
  "unit": "kg",
  "status": "Baik",
  "notes": "",
  "createdBy": "uid",
  "updatedBy": "uid",
  "createdAt": "timestamp",
  "updatedAt": "timestamp",
  "isDeleted": false
}
```

`moduleType` wajib salah satu dari `ayam_kampung`, `maggot_bsf`, `cacing_tanah`, `lele`, `tanaman`. Query aktif mengabaikan `isDeleted == true` dan mengurutkan `activityDate` terbaru lebih dulu.

## `inventory/{id}`

```json
{
  "id": "uuid",
  "name": "Pakan ayam",
  "itemKey": "pakan_ayam",
  "moduleType": "ayam_kampung",
  "category": "Pakan",
  "unit": "kg",
  "currentStock": 20,
  "minStock": 25,
  "isLowStock": true,
  "location": "",
  "createdBy": "uid",
  "updatedBy": "uid",
  "createdAt": "timestamp",
  "updatedAt": "timestamp",
  "isDeleted": false
}
```

`itemKey` dipakai untuk integrasi otomatis dari logbook ke stok. Jika data lama belum punya `itemKey`, model Flutter membuat fallback dari `name` dalam format snake_case. `isLowStock` dihitung saat save karena Firestore tidak dapat membandingkan dua field dalam query (`currentStock <= minStock`).

## `inventory_transactions/{id}`

```json
{
  "id": "uuid",
  "itemId": "inventory-id",
  "itemName": "Dedak Padi",
  "itemKey": "dedak_padi",
  "moduleType": "ayam_kampung",
  "logbookId": "logbook-id",
  "type": "out",
  "quantity": 5,
  "unit": "kg",
  "beforeStock": 100,
  "afterStock": 95,
  "notes": "Otomatis dari logbook ...",
  "transactionDate": "timestamp",
  "createdBy": "uid",
  "createdAt": "timestamp",
  "isReversed": false,
  "reversedAt": null,
  "reversedBy": ""
}
```

`type` valid: `in`, `out`, `adjustment`, `rollback`. Semua perubahan stok dari Logbook wajib punya histori di collection ini.

## `production_results/{id}`

```json
{
  "id": "uuid",
  "logbookId": "logbook-id",
  "moduleType": "ayam_kampung",
  "productName": "Telur Ayam",
  "quantity": 85,
  "unit": "butir",
  "qualityStatus": "normal",
  "harvestDate": "timestamp",
  "notes": "Otomatis dari logbook ...",
  "createdBy": "uid",
  "createdAt": "timestamp"
}
```

Dipakai untuk hasil produksi/panen dari Logbook seperti telur, maggot segar, kascing, kascing cair, lele panen, dan hasil panen tanaman.

## `circular_flows/{id}`

```json
{
  "id": "tanaman_to_maggot_bsf",
  "sourceModuleType": "tanaman",
  "destinationModuleType": "maggot_bsf",
  "materialName": "Sisa organik",
  "quantity": 12,
  "unit": "kg",
  "flowDate": "timestamp",
  "notes": "Sisa tanaman dan limbah organik digunakan sebagai bahan media maggot.",
  "createdAt": "timestamp"
}
```

Dipakai Dashboard untuk section Sistem Aliran Nutrisi. Query utama mengurutkan
`flowDate DESC`; jika collection kosong, Dashboard tetap memakai fallback
referensi agar UI tidak blank.

## `schedules/{id}`

```json
{
  "id": "uuid",
  "title": "Pakan lele sore",
  "moduleType": "lele",
  "type": "Pakan",
  "date": "timestamp",
  "status": "pending",
  "notes": "",
  "createdBy": "uid",
  "updatedBy": "uid",
  "createdAt": "timestamp",
  "updatedAt": "timestamp",
  "isDeleted": false
}
```

Status valid: `pending`, `done`, `skipped`.

## `notifications/{id}`

```json
{
  "id": "uuid-or-deterministic-id",
  "title": "Stok menipis",
  "body": "Pakan ayam berada di bawah batas minimum.",
  "type": "low_stock",
  "targetRole": "operator_lapangan",
  "userId": "uid-optional",
  "relatedCollection": "inventory",
  "relatedId": "inventory-id",
  "isRead": false,
  "createdAt": "timestamp",
  "scheduledAt": "timestamp-optional",
  "isDeleted": false
}
```

Tipe awal: `low_stock`, `schedule_overdue`, `production_reminder`, `system`. Collection ini dipakai untuk in-app notification yang dibuat client saat user membuka dashboard/inventory/schedule. Tidak ada Cloud Functions atau trigger server.

## `education_contents/{id}`

```json
{
  "id": "uuid",
  "title": "Judul Edukasi",
  "type": "artikel", // artikel, video, sop
  "status": "published", // draft, published, archived
  "moduleType": "lele", // optional
  "category": "Panduan", // optional
  "tags": ["pemula", "pakan"], // optional
  "authorId": "uid",
  "createdBy": "uid",
  "updatedBy": "uid",
  "createdAt": "timestamp",
  "updatedAt": "timestamp",
  "isDeleted": false,
  
  // Field khusus artikel
  "summary": "Ringkasan pendek...",
  "content": "Isi lengkap...",
  "thumbnailUrl": "url-gambar-eksternal",
  
  // Field khusus video
  "externalVideoUrl": "https://youtube.com/...",
  "duration": "12:34",
  
  // Field khusus SOP
  "steps": ["Langkah 1", "Langkah 2"],
  "toolsNeeded": ["Alat 1", "Alat 2"],
  "safetyNotes": "Catatan K3"
}
```

Tipe valid: `artikel`, `video`, `sop`. Status valid: `draft`, `published`, `archived`.
File media tidak diunggah ke Firebase Storage; gunakan URL eksternal. Field `isPublished` dan `externalUrl` (legacy) digantikan oleh `status` dan `externalVideoUrl`.

## `finance_transactions/{id}`

```json
{
  "id": "uuid",
  "type": "income",
  "category": "Penjualan telur",
  "amount": 500000,
  "date": "timestamp",
  "notes": "",
  "createdBy": "uid",
  "updatedBy": "uid",
  "createdAt": "timestamp",
  "updatedAt": "timestamp",
  "isDeleted": false
}
```

Tipe valid: `income`, `expense`. Admin dan operator keuangan dapat membuat/memperbarui transaksi; soft delete hanya dari peran admin.

## `report_metadata/{id}`

```json
{
  "id": "uuid",
  "title": "Laporan operasional Juni 2026",
  "type": "monthly_summary",
  "periodStart": "timestamp",
  "periodEnd": "timestamp",
  "filters": {
    "moduleType": "lele"
  },
  "status": "ready",
  "createdBy": "uid",
  "updatedBy": "uid",
  "createdAt": "timestamp",
  "updatedAt": "timestamp",
  "isDeleted": false
}
```

Gunakan collection ini hanya untuk metadata laporan yang dihasilkan/dikelola client. Jangan simpan file laporan besar di Firestore.

## `recommendations/{id}`

```json
{
  "id": "rec_harvest_prepare_lele_20260628",
  "title": "Persiapan panen Lele",
  "description": "Estimasi panen sekitar 3 hari lagi.",
  "type": "harvest_prediction",
  "priority": "high",
  "moduleType": "lele",
  "sourceCollection": "logbooks",
  "sourceId": "logbook-id",
  "createdAt": "timestamp",
  "validUntil": "timestamp",
  "isResolved": false
}
```

Rekomendasi tahap awal dibuat on-demand di Flutter oleh `RecommendationService`.
Collection ini hanya untuk snapshot opsional agar tidak boros write Firestore.
Tidak ada machine learning cloud, API AI berbayar, Cloud Functions, atau backend
server untuk membuat rekomendasi otomatis.


## Phase 03: `batches/{normalizedCode}`

| Field | Tipe / kontrak |
| --- | --- |
| `id`, `code` | String sama dengan document ID; kode uppercase 3-40 karakter `[A-Z0-9][A-Z0-9_-]{2,39}`; unik global dan immutable |
| `name`, `locationName` | String wajib 1-120 karakter |
| `moduleType` | `ayam_kampung`, `maggot_bsf`, `cacing_tanah`, `tanaman`, `lele`; immutable |
| `status` | `planned`, `active`, `completed`, `archived`; hanya maju satu tahap |
| `startedAt` | Timestamp tanggal mulai; immutable |
| `expectedHarvestAt` | Timestamp atau null; tidak sebelum startedAt |
| `completedAt` | null sebelum selesai; server timestamp saat active menjadi completed; tetap saat archived |
| `initialQuantity` | Number nonnegatif hingga 10^15 atau null; finite dan immutable |
| `initialUnit` | String maksimal 30 karakter; wajib bila quantity ada; immutable |
| `commodity` | String opsional maksimal 120 karakter |
| `notes` | String opsional maksimal 3000 karakter |
| `createdBy`, `updatedBy` | UID; penulis harus UID autentikasi |
| `createdAt`, `updatedAt` | Server timestamp; createdAt immutable |
| `isDeleted` | false; tidak ada aksi delete/soft delete |

ID bawaan form adalah `B-<UUID-v4>` uppercase. Pengguna dapat memasukkan kode pendek sebelum create. Transaksi membaca dokumen berkode tersebut dan hanya membuat bila belum ada; Rules mengunci code == ID sehingga client lain tidak dapat membuat dokumen kedua dengan kode sama. Tidak ada koleksi reservasi tambahan atau subcollection Logbook di batch.

`logbooks.batchId` opsional untuk kompatibilitas/aktivitas umum. Bila disertakan harus string ID batch aktif, tidak dihapus, dan moduleType sama. Rules menggunakan kondisi sesudah transaksi (`getAfter`) untuk mencegah penyelesaian batch bersamaan dengan create Logbook. Update notes ber-audit tidak dapat mengganti batchId.

Write Logbook baru meneruskan batchId ke `inventory_transactions` dan `production_results` bila relevan; `logbookId` tetap relasi utama dan data lama ditelusuri melalui logbookId. Jangan menggandakan hasil produksi dengan menjumlahkan hasil stok masuk dan production_results. Batch tidak menampung daftar aktivitas atau agregat populasi/panen fiktif.

## Phase 04: saldo, ledger dan checklist

`inventory.currentStock` tetap saldo lokasi. Master menambah `lastTransactionId` pada mutasi, dan `creationPayload` immutable pada pembuatan manual untuk retry. Nama/kategori/lokasi/minimum dapat diperbarui tanpa stok. Unit, itemKey, moduleType, pencipta dan waktu penciptaan tetap. Nonzero opening memerlukan histori `opening_{itemId}` dalam commit yang sama. Soft delete hanya admin pada saldo nol.

`inventory_transactions` mempertahankan field canonical `id`, `itemId`, `itemName`, `itemKey`, `moduleType`, `type`, `quantity`, `unit`, `beforeStock`, `afterStock`, `notes`, `transactionDate`, `createdBy`, `createdAt`, optional batchId/logbookId dan reversal legacy. Tambahan:

| Field | Kontrak |
| --- | --- |
| type | in, out, correction (absolut), opening; in/out lama tetap terbaca |
| source | manual, opening, logbook; dokumen lama tanpa source ditafsirkan untuk tampilan |
| requestId | ID receipt manual; ID master pada opening; ID Logbook pada source logbook |
| requestedValue | Input manual: delta positif untuk in/out, nilai stok fisik untuk correction |
| allowNegative | Izin eksplisit pengguna bila saldo manual menjadi minus |
| quantity koreksi | abs(afterStock-beforeStock), boleh nol untuk observasi fisik yang sama |

Ledger baru selalu immutable dan isReversed=false. Reversal lama tetap dapat dibaca dan ditandai; API rollback/reversal tidak aktif. Rules mensyaratkan lastTransactionId barang menunjuk ledger baru yang sesuai, baik mutasi manual maupun Logbook. Tidak ada migrasi ledger lama atau saldo per batch.

`schedules` mempertahankan id/title/moduleType/type/date/status/notes/createdBy/createdAt/updatedBy/updatedAt/isDeleted. Tambahan opsional: batchId nullable, creationPayload immutable, completedBy/completedAt, skippedBy/skippedAt/skipReason. Baru selalu pending; terminal done/skipped mencatat pengguna dan server timestamp dalam transaksi. Edit hanya pending dengan deteksi versi. Batch baru harus active/cocok modul/tidak dihapus; pembacaan dan penyelesaian jadwal lama tetap diperbolehkan setelah batch ditutup. Tidak menambah linkedLogbookId atau recurrence pada Phase 04.

Kontrak/risiko selengkapnya: [Inventaris & Jadwal Phase 04](PHASE_04_INVENTORY_SCHEDULE.md). Pengelola perlu menerapkan Rules/index yang sudah ditinjau sebelum client baru dipakai; client lama yang menulis stok langsung akan ditolak.


## Phase 05: kontrak analitik baca

Tidak menambah collection summary/cache, field persistent, seed, atau operasi tulis. `production_results` merupakan sumber hasil aktual; `logbookId` wajib dapat ditelusuri ke Logbook tidak dihapus dan sesuai moduleType/batchId. Dashboard menolak total yang tidak dapat diverifikasi, duplikasi identitas produksi per logbook/produk/satuan, angka non-finite, atau cakupan hasil yang melampaui batas pembacaan. Saldo inventory dan ledger tidak dijumlahkan sebagai hasil produksi.

Pengamatan Tanaman dipisahkan berdasarkan batch, komoditas, blok dan tanggal tanam; identitas legacy tidak cukup hanya ditampilkan sebagai titik catatan tersendiri. Field Lele `mortalitas_ikan` mengikuti label form **Bobot Rata-rata**, sedangkan `pakan_lele_kg` berarti **Pakan Maggot Sore**. `kondisi_air` dibaca sebagai survival rate hanya untuk nilai numerik 0–100 sesuai form terkini.

Rumus, periode lokal [start,end), query bounded dan risiko legacy dijelaskan pada [Phase 05](PHASE_05_DASHBOARD_MONITORING.md).
# Tambahan Phase 06 — Finance, Sales, Actual Circular Flow

Kontrak existing tetap berlaku; field tambahan tidak memerlukan migrasi otomatis pada dokumen lama.

| Collection | Field/kontrak baru |
| --- | --- |
| inventory | `isSellable` bool default false, `productType` operational/harvest default operational. Hanya admin mengubah klasifikasi jual. Barang jual wajib harvest, modul canonical, aktif dan bukan data sampel. Saldo tetap currentStock; tidak membuat collection saldo baru. |
| sales | ID=requestId; saleNumber S-ID; creationPayload immutable; inventoryItemId/productName/moduleType; quantity/quantityMilli/unit; integer unitPrice/totalAmount; buyerName opsional (string kosong bila tidak dicatat), paymentMethod tunai/transfer/qris; saleDate; notes; status paid; inventoryTransactionId/financeTransactionId sale_ID; createdBy/createdByName/createdAt, updatedBy/updatedAt. Receipt immutable. Tidak mengisi batchId dari stok gabungan tanpa provenance. |
| inventory_transactions | source sale, saleId/requestId=receiptID, ID sale_receiptID, type out, quantity/unit, beforeStock/afterStock, aktor/waktu dan field master existing. Tidak menyimpan nominal finance pada ledger yang dapat dibaca role operasional. |
| finance_transactions | Manual baru: ID=requestId, source manual, creationPayload asli, version0. Sale: ID sale_receiptID, source sale, saleId/requestId, type income, amount=integer total sale (parser FinanceRecord tetap double kompatibel), date/paymentMethod/moduleType mengikuti receipt. Kedua jenis memakai server timestamps/audit dan isDeleted. |
| finance_transactions/{id}/edits/{requestId} | before/after snapshot penuh, payload, editedBy/editedAt. Parent manual menaikkan version, lastEditId, updatedBy/At dalam write atomik yang sama. Histori append-only, soft delete disimpan sebagai after.isDeleted=true. |
| circular_flows | ID/requestId, creationPayload; sourceModuleType/destinationModuleType berbeda; materialName, quantity finite positif, unit kg/g/liter/ml/butir/ekor, flowDate, notes, sourceType manual, createdBy/createdByName/createdAt. sourceBatchId/destinationBatchId/logbookId/inventoryTransactionId opsional. Append-only, tidak menulis stok. |

Quantity sale dinormalisasi ke thousandths (maksimal1e6 unit). Total Rupiah dihitung half-up sekali: round(quantityMilli × unitPrice /1000), total positif maksimal1e12 dan unitPrice positif maksimal1e9. Payload menyertakan waktu sampai presisi microsecond DateTime, aktor, semua nilai input dan referensi; retry dengan input berbeda ditolak meskipun tanggal hanya berbeda satu microsecond. Field createdByName bersumber dari profil yang dibaca dalam transaction dan diverifikasi Rules bila disertakan.

Aliran legacy tanpa sourceType/aktor tetap dapat diparsing, tetapi tidak dianggap bukti aliran aktual. Aliran manual memverifikasi batch sesuai modul, Logbook aktif/tidak dihapus, ledger jumlah/satuan/modul dan tidak reversed, serta menolak referensi sampel. Tidak menduplikasi saldo/panen/pemasukan.

Lihat [Phase 06](PHASE_06_FINANCE_SALES_CIRCULAR_FLOW.md) dan [audit sampel](PHASE_06_SAMPLE_DATA_CLEANUP.md). Produksi belum diaudit/diubah dan Rules/index belum dideploy.
