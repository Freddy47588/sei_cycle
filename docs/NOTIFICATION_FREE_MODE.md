# Notification Free Mode — SeiCycle

Sistem notifikasi SeiCycle berjalan sepenuhnya di Firebase **Spark (free) plan** tanpa Cloud Functions,
tanpa Firebase Storage, dan tanpa backend Express.

---

## Arsitektur Sistem

```
┌─────────────────────────────────────────────────────────────┐
│                      Flutter Client                         │
│                                                             │
│  ┌────────────┐   ┌─────────────────┐   ┌───────────────┐  │
│  │ Inventory/ │   │    Schedule     │   │   Dashboard   │  │
│  │  Screen    │   │    Screen       │   │    Screen     │  │
│  └─────┬──────┘   └────────┬────────┘   └──────┬────────┘  │
│        │                   │                    │           │
│        └───────────────────┼────────────────────┘           │
│                            │                                │
│              ┌─────────────▼──────────────┐                 │
│              │      NotificationService   │                 │
│              │  createLowStockAlert()     │                 │
│              │  createScheduleOverdue()   │                 │
│              │  createProductionReminder()│                 │
│              │  createSystemAlert()       │                 │
│              │  watchUnreadCount()        │                 │
│              │  watchNotifications()      │                 │
│              │  markAsRead()              │                 │
│              │  markAllAsRead()           │                 │
│              └─────────────┬──────────────┘                 │
│                            │                                │
│           ┌────────────────┼────────────────┐               │
│           │                │                │               │
│  ┌────────▼──────┐  ┌──────▼───────┐  ┌────▼──────────┐   │
│  │  Firestore    │  │ LocalReminder│  │   Messaging   │   │
│  │  notifications│  │  Service     │  │   Service     │   │
│  │  collection   │  │  (device)    │  │  (FCM token)  │   │
│  └───────────────┘  └──────────────┘  └───────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

---

## Komponen

### 1. In-App Notification (Firestore)

Data disimpan di collection `notifications`. Notifikasi dibuat oleh **client-side** saat user membuka
fitur yang relevan (dashboard, inventory, schedule).

**Kapan dibuat:**

| Trigger | Di mana | Helper |
|---|---|---|
| Stok item < minimum | `InventoryScreen` & `DashboardScreen` | `createLowStockAlert()` |
| Schedule pending & lewat waktu | `ScheduleScreen` | `createScheduleOverdueAlert()` |
| Schedule baru dibuat/diedit | `ScheduleScreen` | `createProductionReminder()` |
| Alert manual admin | Anywhere | `createSystemAlert()` |

### 2. Local Reminder (Device Notification)

Menggunakan `flutter_local_notifications` + `timezone`.

- Dibuat saat user **membuat atau mengedit schedule** dengan status `pending`.
- **Dibatalkan** otomatis saat status schedule diubah jadi `done` / `skipped` / dihapus.
- Hanya aktif di device yang membuat jadwal dan sudah memberikan izin notifikasi.
- Android menggunakan `AndroidScheduleMode.inexactAllowWhileIdle` agar tidak membutuhkan
  `USE_EXACT_ALARM` permission (bebas Doze mode).

### 3. FCM Token (Persiapan Push)

- App meminta permission `firebase_messaging` saat user mengetuk **"Aktifkan notifikasi"** di layar Profil.
- Token disimpan di `users/{uid}.fcmToken` dan `fcmTokenUpdatedAt`.
- **Tidak ada push otomatis** — tidak ada server yang mengirim pesan FCM karena tidak ada
  Cloud Functions atau backend berbayar.
- Token disimpan sebagai **persiapan upgrade Blaze** (lihat bagian Batasan Free Mode).

---

## Schema Dokumen `notifications/{id}`

```json
{
  "id": "low_stock_uid123_itemABC",
  "title": "Stok Pakan Lele rendah",
  "body": "Stok Pakan Lele tersisa 3 kg, batas minimum 10 kg.",
  "type": "low_stock",
  "targetRole": "operator_lapangan",
  "userId": "uid123",
  "relatedCollection": "inventory",
  "relatedId": "itemABC",
  "isRead": false,
  "createdAt": "Firestore Timestamp",
  "scheduledAt": "Firestore Timestamp (opsional)",
  "isDeleted": false
}
```

### Tipe Notifikasi

| `type` | Deskripsi |
|---|---|
| `low_stock` | Stok item di bawah batas minimum |
| `schedule_overdue` | Jadwal pending sudah melewati waktu terjadwal |
| `production_reminder` | Pengingat kegiatan produksi dari jadwal baru/diedit |
| `system` | Alert sistem dari admin untuk role tertentu atau semua |

---

## Guard Anti-Spam Write

Semua tipe notifikasi menggunakan **ID deterministik** + **read-before-write guard** untuk mencegah
duplikat dokumen setiap kali layar di-refresh.

### Pola ID Deterministik

```
low_stock_{userId}_{inventoryId}
schedule_overdue_{userId}_{scheduleId}
production_reminder_{userId}_{scheduleId}
```

### Logika Guard

Sebelum menulis notifikasi, client membaca dokumen dengan ID deterministik tersebut:

```dart
final existing = await reference.get();
// Skip jika sudah ada dan belum dibaca
if (existing.exists && existing.data()?['isRead'] != true) return;
```

Jika dokumen **sudah ada dan belum dibaca** → tidak menulis ulang (tidak spam Firestore).

Jika dokumen **belum ada** atau **sudah ditandai dibaca** → buat/timpa dokumen baru.

### Guard Tambahan di UI

- `InventoryScreen._syncedLowStockAlertIds` — Set berisi item ID yang sudah di-sync dalam sesi ini.
  Mencegah `createLowStockAlert` dipanggil berulang dari `StreamBuilder` yang rebuild.
- `ScheduleScreen._syncedOverdueAlertIds` — Sama, untuk jadwal overdue.

---

## Unread Badge di Navigasi

`AppShell` memanggil `NotificationService.watchUnreadCount()` saat `initState` dan mempass
hasilnya ke `_MobileShell` (NavigationBar `Badge.count`) dan `_DesktopShell` (sidebar `Badge.count`).

Badge otomatis hilang saat semua notifikasi ditandai dibaca.

---

## Query dan Akses

Notification inbox mengambil notifikasi yang cocok dengan salah satu kondisi:

```
isDeleted == false AND (
  userId == currentUser.uid
  OR targetRole == currentUser.role
  OR targetRole == 'all'
)
```

Diurutkan berdasarkan `createdAt` descending (terbaru di atas).

**Aksi yang diizinkan user:**

| Aksi | Siapa |
|---|---|
| Baca notifikasi personal/role/global | Semua user aktif |
| Buat notifikasi (client-side guard) | User aktif sesuai kondisi `canReadNotification` |
| Mark single notifikasi sebagai read | User yang bisa membaca notifikasi tersebut |
| Mark all as read (batch max 50) | User yang bisa membaca notifikasi tersebut |
| Hapus notifikasi | Hanya admin |

---

## File Utama

| File | Peran |
|---|---|
| `lib/features/notification/models/app_notification.dart` | Model Firestore ↔ Dart |
| `lib/features/notification/services/notification_service.dart` | CRUD + helper alerts + badge stream |
| `lib/features/notification/screen/notification_screen.dart` | UI inbox, filter, mark read |
| `lib/core/services/local_reminder_service.dart` | Local notification (device) via flutter_local_notifications |
| `lib/core/services/messaging_service.dart` | FCM permission + token save |
| `lib/app/app_shell.dart` | Unread badge di nav (mobile & desktop) |

---

## Batasan Free Mode

| Batasan | Penjelasan |
|---|---|
| Local reminder | Hanya aktif di device yang membuat jadwal. Pindah device atau reinstall → reminder hilang |
| FCM push otomatis | Tidak tersedia tanpa server tepercaya (Cloud Functions / backend berbayar) |
| Firestore writes | Dikontrol guard client-side; tidak ada trigger server-side |
| Unread count | Selalu dihitung ulang via Firestore query — tidak ada counter cache |

---

## Upgrade Path ke Blaze (Opsional)

Jika project upgrade ke **Firebase Blaze plan**, FCM push otomatis bisa diaktifkan dengan:

1. Membuat **Cloud Function** yang dipicu oleh Firestore `onCreate` di collection `notifications`.
2. Fungsi membaca `targetRole` dan mengambil semua `fcmToken` dari collection `users`
   yang memiliki role tersebut.
3. Mengirim pesan via **Firebase Admin SDK** ke token yang ditemukan.

Token sudah disimpan di `users/{uid}.fcmToken` — tidak perlu perubahan client.

```
// Contoh struktur Cloud Function (Node.js) — BELUM DIIMPLEMENTASI
exports.onNotificationCreated = onDocumentCreated(
  'notifications/{id}',
  async (event) => {
    const data = event.data?.data();
    if (!data) return;
    const tokens = await getTokensForRole(data.targetRole, data.userId);
    await admin.messaging().sendEachForMulticast({ tokens, notification: { ... } });
  },
);
```

---

*Dokumentasi ini diperbarui pada: 2026-06-27. Lihat juga: `FIRESTORE_SCHEMA.md`, `BACKEND.md`.*
