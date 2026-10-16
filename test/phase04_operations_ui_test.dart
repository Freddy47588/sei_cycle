import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sei_cycle/core/models/firestore_page.dart';
import 'package:sei_cycle/features/inventory/models/inventory_item.dart';
import 'package:sei_cycle/features/inventory/screen/inventory_screen.dart';
import 'package:sei_cycle/features/inventory/screen/inventory_history_screen.dart';
import 'package:sei_cycle/features/inventory/services/inventory_service.dart';
import 'package:sei_cycle/features/inventory/services/inventory_adjustment_service.dart';
import 'package:sei_cycle/features/inventory/services/inventory_transaction_service.dart';
import 'package:sei_cycle/features/inventory/widgets/inventory_master_form.dart';
import 'package:sei_cycle/features/inventory/widgets/inventory_transaction_form.dart';
import 'package:sei_cycle/features/logbook/services/logbook_service.dart';
import 'package:sei_cycle/features/notification/services/notification_service.dart';
import 'package:sei_cycle/features/profile/models/app_user.dart';
import 'package:sei_cycle/features/schedule/screen/schedule_screen.dart';
import 'package:sei_cycle/features/schedule/services/schedule_service.dart';
import 'package:sei_cycle/features/schedule/services/reminder_sync_service.dart';
import 'package:sei_cycle/theme/app_theme.dart';
import 'phase04_operations_test.dart'
    show stockDoc, scheduleDoc, seedUser, FakeReminders;
import 'support/memory_firestore.dart';

const capture = bool.fromEnvironment('CAPTURE_UI');
AppUser profile({String role = 'operator_lapangan', bool active = true}) =>
    AppUser(
      uid: 'field',
      name: 'Petugas',
      email: '',
      photoUrl: '',
      role: role,
      isActive: active,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

class DelayedInventory extends InventoryService {
  DelayedInventory(MemoryFirestore db) : super(firestore: db);
  Completer<FirestorePage<InventoryItem>>? pending;
  bool fail = false;
  @override
  Future<FirestorePage<InventoryItem>> fetchPage({
    String? moduleType,
    String? category,
    DocumentSnapshot<Map<String, dynamic>>? cursor,
    int limit = 20,
  }) {
    if (fail) return Future.error(StateError('offline'));
    return pending?.future ??
        super.fetchPage(
          moduleType: moduleType,
          category: category,
          cursor: cursor,
          limit: limit,
        );
  }
}

class DelayedAdjustment extends InventoryAdjustmentService {
  DelayedAdjustment(MemoryFirestore db) : super(firestore: db);
  final result = Completer<String>();
  int calls = 0;
  @override
  Future<String> mutate({
    required String requestId,
    required String itemId,
    required String type,
    required double value,
    required String unit,
    required String notes,
    required String userId,
    String? batchId,
    bool allowNegative = false,
  }) {
    calls++;
    return result.future;
  }
}

class LiveInventory extends InventoryService {
  LiveInventory(MemoryFirestore db) : super(firestore: db);
  final updates = StreamController<List<InventoryItem>>.broadcast();
  @override
  Stream<List<InventoryItem>> watchLoaded(List<InventoryItem> items) =>
      updates.stream;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await initializeDateFormatting('id_ID');
    if (capture) {
      final root = Platform.environment['FLUTTER_ROOT'] ?? 'C:/src/flutter';
      final font = FontLoader('Roboto')
        ..addFont(
          File(
            '$root/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
          ).readAsBytes().then((b) => ByteData.sublistView(b)),
        );
      await font.load();
      final icons = FontLoader('MaterialIcons')
        ..addFont(
          File(
            '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
          ).readAsBytes().then((b) => ByteData.sublistView(b)),
        );
      await icons.load();
    }
  });
  late MemoryFirestore db;
  late InventoryService inventory;
  late ScheduleService schedules;
  late NotificationService notifications;
  late LogbookService logs;
  late ReminderSyncService reminders;
  setUp(() {
    db = MemoryFirestore();
    seedUser(db);
    inventory = InventoryService(firestore: db);
    schedules = ScheduleService(firestore: db);
    notifications = NotificationService(firestore: db);
    logs = LogbookService(firestore: db);
    reminders = ReminderSyncService(
      schedules: schedules,
      reminders: FakeReminders(),
    );
  });
  Widget inventoryScreen({AppUser? user, InventoryService? service}) =>
      InventoryScreen(
        profile: user ?? profile(),
        service: service ?? inventory,
        adjustments: InventoryAdjustmentService(firestore: db),
        notifications: notifications,
      );
  Widget scheduleScreen({AppUser? user}) => ScheduleScreen(
    profile: user ?? profile(),
    service: schedules,
    reminders: reminders,
    logbooks: logs,
    notifications: notifications,
  );
  Future<void> pump(
    WidgetTester t,
    Widget screen, {
    double width = 600,
    double scale = 1,
  }) async {
    t.view.physicalSize = Size(width, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: RepaintBoundary(
          key: const ValueKey('capture'),
          child: Scaffold(body: screen),
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  Future<void> png(WidgetTester t, String name) async {
    if (!capture) return;
    await t.runAsync(() async {
      final boundary = t.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('capture')),
      );
      final img = await boundary.toImage();
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      final file = File('build/phase04/$name.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(bytes!.buffer.asUint8List());
      img.dispose();
    });
  }

  testWidgets(
    'inventory search, actual low state, local sort and rebuild do not repeat query',
    (t) async {
      db.documents['inventory/feed'] = stockDoc();
      await pump(t, inventoryScreen());
      expect(find.text('Stok Aman'), findsOneWidget);
      expect(find.text('Gudang'), findsNothing);
      expect(find.text('Lokasi: Gudang'), findsOneWidget);
      final count = db.queries.length;
      await t.enterText(find.byType(TextField).first, 'tidak-ada');
      await t.pumpAndSettle();
      expect(find.text('Pakan'), findsNothing);
      expect(db.queries.length, count);
      expect(find.textContaining('Bukan jumlah global'), findsOneWidget);
      await t.enterText(find.byType(TextField).first, 'pakan');
      await t.pumpAndSettle();
      expect(find.text('Pakan'), findsOneWidget);
    },
  );
  testWidgets(
    'inventory pagination loads subsequent items and search spans loaded pages',
    (t) async {
      for (var i = 0; i < 21; i++) {
        db.documents['inventory/item-$i'] = {
          ...stockDoc(),
          'id': 'item-$i',
          'name': 'Pakan ${i.toString().padLeft(2, '0')}',
        };
      }
      await pump(t, inventoryScreen(user: profile(role: 'operator_keuangan')));
      await t.scrollUntilVisible(
        find.text('Muat berikutnya'),
        500,
        scrollable: find.byType(Scrollable).last,
      );
      await t.tap(find.text('Muat berikutnya'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField).first, 'Pakan 20');
      await t.pumpAndSettle();
      t.state<ScrollableState>(find.byType(Scrollable).last).position.jumpTo(0);
      await t.pumpAndSettle();
      expect(
        find.byWidgetPredicate((w) => w is Text && w.data == 'Pakan 20'),
        findsOneWidget,
      );
      expect(find.text('Akhir data'), findsOneWidget);
    },
  );
  testWidgets(
    'loaded inventory follows remote stock recovery without another page scan',
    (t) async {
      db.documents['inventory/feed'] = stockDoc(stock: 2);
      final live = LiveInventory(db);
      await pump(t, inventoryScreen(service: live));
      expect(find.text('Stok Rendah'), findsOneWidget);
      final queryCount = db.queries.length;
      db.documents['inventory/feed']!['currentStock'] = 50;
      live.updates.add([
        InventoryItem.fromDocument(
          await db.collection('inventory').doc('feed').get(),
        ),
      ]);
      await t.pumpAndSettle();
      expect(find.text('Stok Aman'), findsOneWidget);
      expect(find.text('Stok Rendah'), findsNothing);
      expect(db.queries.length, queryCount);
      await t.pumpWidget(const SizedBox());
      expect(live.updates.hasListener, false);
      await live.updates.close();
    },
  );
  testWidgets(
    'master edit exposes no current stock and locks unit, key, module',
    (t) async {
      db.documents['inventory/feed'] = stockDoc();
      final item = InventoryItem.fromDocument(
        await db.collection('inventory').doc('feed').get(),
      );
      await pump(
        t,
        InventoryMasterForm(service: inventory, userId: 'field', item: item),
      );
      expect(find.text('Stok saat ini'), findsNothing);
      expect(find.text('Stok Awal (opsional)'), findsNothing);
      final fields = t
          .widgetList<TextFormField>(find.byType(TextFormField))
          .toList();
      expect(fields.where((f) => f.enabled == false), hasLength(2));
      expect(
        t
            .widget<DropdownButtonFormField<String>>(
              find.byType(DropdownButtonFormField<String>),
            )
            .onChanged,
        isNull,
      );
    },
  );
  testWidgets('new master has optional opening and rejects NaN', (t) async {
    await pump(t, InventoryMasterForm(service: inventory, userId: 'field'));
    expect(find.text('Stok Awal (opsional)'), findsOneWidget);
    await t.enterText(find.byType(TextFormField).last, 'NaN');
    await t.ensureVisible(find.text('Simpan'));
    await t.tap(find.text('Simpan'));
    await t.pumpAndSettle();
    expect(find.text('Masukkan angka 0 sampai 1 triliun'), findsOneWidget);
    expect(db.documents.keys.where((p) => p.startsWith('inventory/')), isEmpty);
  });
  testWidgets(
    'mutation correction states absolute semantics and blocks repeated submit',
    (t) async {
      db.documents['inventory/feed'] = stockDoc();
      final item = InventoryItem.fromDocument(
        await db.collection('inventory').doc('feed').get(),
      );
      final service = DelayedAdjustment(db);
      await pump(
        t,
        InventoryTransactionForm(item: item, userId: 'field', service: service),
      );
      await t.tap(find.byType(DropdownButtonFormField<String>));
      await t.pumpAndSettle();
      await t.tap(find.text('Koreksi Stok').last);
      await t.pumpAndSettle();
      expect(find.text('Stok fisik aktual (nilai absolut)'), findsOneWidget);
      await t.enterText(find.byType(TextFormField).first, '23');
      await t.enterText(find.byType(TextFormField).last, 'Stock opname');
      await t.ensureVisible(find.text('Simpan Mutasi'));
      await t.tap(find.text('Simpan Mutasi'));
      await t.pump();
      await t.tap(find.text('Menyimpan...'));
      await t.pump();
      expect(service.calls, 1);
      service.result.completeError(StateError('retry'));
      await t.pumpAndSettle();
      expect(find.textContaining('retry'), findsOneWidget);
    },
  );
  for (final role in ['operator_keuangan', 'mitra']) {
    testWidgets(
      '$role sees inventory and schedules without mutation or completion actions',
      (t) async {
        db.documents['inventory/feed'] = stockDoc();
        db.documents['schedules/task'] = scheduleDoc(
          'task',
          date: DateTime.now(),
        );
        await pump(t, inventoryScreen(user: profile(role: role)));
        expect(find.text('Mutasi Stok'), findsNothing);
        expect(find.text('Tambah Barang'), findsNothing);
        await pump(t, scheduleScreen(user: profile(role: role)));
        expect(find.text('Pakan sore'), findsOneWidget);
        expect(find.text('Tandai Selesai'), findsNothing);
        expect(find.text('Tambah jadwal'), findsNothing);
      },
    );
  }
  testWidgets(
    'schedule completion is explicit and records actor without stock or logbook writes',
    (t) async {
      db.documents['schedules/task'] = scheduleDoc(
        'task',
        date: DateTime.now(),
      );
      await pump(t, scheduleScreen());
      expect(db.documents['schedules/task']!['status'], 'pending');
      await t.ensureVisible(find.text('Tandai Selesai'));
      await t.tap(find.text('Tandai Selesai'));
      await t.pumpAndSettle();
      expect(db.documents['schedules/task']!['status'], 'done');
      expect(db.documents['schedules/task']!['completedBy'], 'field');
      expect(
        db.documents.keys.where(
          (p) =>
              p.startsWith('inventory_transactions/') ||
              p.startsWith('logbooks/'),
        ),
        isEmpty,
      );
    },
  );
  testWidgets(
    'schedule logbook action carries module, valid batch and referenced title with no writes',
    (t) async {
      db.documents['schedules/task'] = {
        ...scheduleDoc('task', date: DateTime.now()),
        'batchId': 'KOLAM-A',
      };
      db.documents['batches/KOLAM-A'] = {
        'id': 'KOLAM-A',
        'code': 'KOLAM-A',
        'name': 'Kolam A',
        'moduleType': 'lele',
        'locationName': 'Utara',
        'status': 'active',
        'startedAt': Timestamp.fromDate(DateTime(2026)),
        'createdBy': 'field',
        'updatedBy': 'field',
        'isDeleted': false,
      };
      await pump(t, scheduleScreen());
      await t.ensureVisible(find.text('Catat di Logbook'));
      await t.tap(find.text('Catat di Logbook'));
      await t.pumpAndSettle();
      expect(
        find.textContaining('Kegiatan dirujuk: Pakan sore'),
        findsOneWidget,
      );
      expect(find.textContaining('Kolam A'), findsWidgets);
      expect(find.text('Modul Lele'), findsOneWidget);
      expect(db.documents['schedules/task']!['status'], 'pending');
      expect(
        db.documents.keys.where(
          (p) =>
              p.startsWith('inventory_transactions/') ||
              p.startsWith('logbooks/'),
        ),
        isEmpty,
      );
    },
  );
  testWidgets(
    'schedule filters show done only and form retains explicit no-batch option',
    (t) async {
      db.documents['schedules/task'] = scheduleDoc(
        'task',
        date: DateTime.now(),
      );
      db.documents['schedules/done'] = {
        ...scheduleDoc('done', date: DateTime.now(), status: 'done'),
        'title': 'Panen selesai',
      };
      await pump(t, scheduleScreen());
      await t.tap(find.widgetWithText(ChoiceChip, 'Selesai'));
      await t.pumpAndSettle();
      expect(find.text('Pakan sore'), findsNothing);
      expect(find.text('Panen selesai'), findsOneWidget);
      await t.tap(find.text('Tambah jadwal'));
      await t.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.text('Tanpa Batch — Aktivitas Umum'),
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('Jadwal disimpan sebagai pending'),
        findsOneWidget,
      );
      expect(
        db.documents.keys.where((p) => p.startsWith('schedules/')),
        hasLength(2),
      );
    },
  );
  testWidgets(
    'inventory error retries, loading then empty states are visible',
    (t) async {
      final service = DelayedInventory(db)..fail = true;
      await pump(t, inventoryScreen(service: service));
      expect(find.text('Coba lagi'), findsOneWidget);
      service.fail = false;
      service.pending = Completer<FirestorePage<InventoryItem>>();
      await t.tap(find.text('Coba lagi'));
      await t.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      service.pending!.complete(const FirestorePage([], null, false));
      await t.pumpAndSettle();
      expect(find.textContaining('Belum ada data yang sesuai'), findsOneWidget);
    },
  );
  testWidgets('skip reason is persisted only after explicit checklist action', (
    t,
  ) async {
    db.documents['schedules/task'] = scheduleDoc('task', date: DateTime.now());
    await pump(t, scheduleScreen());
    await t.ensureVisible(find.text('Lewati'));
    await t.tap(find.text('Lewati'));
    await t.pumpAndSettle();
    expect(db.documents['schedules/task']!['status'], 'pending');
    await t.enterText(find.byType(TextField).last, 'Hujan');
    await t.tap(find.text('Tandai Dilewati'));
    await t.pumpAndSettle();
    expect(db.documents['schedules/task']!['status'], 'skipped');
    expect(db.documents['schedules/task']!['skipReason'], 'Hujan');
    expect(t.takeException(), isNull);
  });
  testWidgets(
    'device permission failure visibly reports reminder failure after schedule completion',
    (t) async {
      db.documents['schedules/task'] = scheduleDoc(
        'task',
        date: DateTime.now(),
      );
      reminders = ReminderSyncService(
        schedules: schedules,
        reminders: FakeReminders()..granted = false,
      );
      await pump(t, scheduleScreen());
      await t.ensureVisible(find.text('Tandai Selesai'));
      await t.tap(find.text('Tandai Selesai'));
      await t.pumpAndSettle();
      ScaffoldMessenger.of(
        t.element(find.byType(ScheduleScreen)),
      ).removeCurrentSnackBar();
      await t.pumpAndSettle();
      await t.tap(find.text('Modul, tanggal & pengingat perangkat'));
      await t.pumpAndSettle();
      expect(db.documents['schedules/task']!['status'], 'done');
      expect(
        find.textContaining('Izin pengingat perangkat belum diberikan'),
        findsWidgets,
      );
    },
  );
  for (final width in [320.0, 1280.0]) {
    for (final screen in [
      'inventory',
      'history',
      'schedule',
      'master',
      'mutation',
    ]) {
      testWidgets('$screen responsive $width at scale 1.4', (t) async {
        db.documents['inventory/feed'] = stockDoc(stock: 2);
        db.documents['schedules/task'] = scheduleDoc(
          'task',
          date: DateTime.now(),
        );
        db.documents['inventory_transactions/h'] = {
          'itemName': 'Pakan Lele',
          'type': 'out',
          'quantity': 5,
          'unit': 'kg',
          'beforeStock': 7,
          'afterStock': 2,
          'createdBy': 'field',
          'notes': 'Pakan sore',
          'source': 'logbook',
          'logbookId': 'entry',
          'batchId': 'KOLAM-A',
          'transactionDate': Timestamp.fromDate(DateTime.now()),
          'createdAt': Timestamp.fromDate(DateTime.now()),
        };
        final item = InventoryItem.fromDocument(
          await db.collection('inventory').doc('feed').get(),
        );
        final page = switch (screen) {
          'inventory' => inventoryScreen(),
          'schedule' => scheduleScreen(),
          'master' => InventoryMasterForm(
            service: inventory,
            userId: 'field',
            item: item,
          ),
          'mutation' => InventoryTransactionForm(
            item: item,
            userId: 'field',
            service: InventoryAdjustmentService(firestore: db),
          ),
          _ => InventoryHistoryScreen(
            userId: 'field',
            canEdit: true,
            service: InventoryTransactionService(firestore: db),
            logbookService: logs,
          ),
        };
        await pump(t, page, width: width, scale: 1.4);
        expect(t.takeException(), isNull);
        await png(t, '${screen}_${width.toInt()}');
      });
    }
  }
}
