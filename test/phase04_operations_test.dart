import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sei_cycle/core/services/local_reminder_service.dart';
import 'package:sei_cycle/features/inventory/models/inventory_item.dart';
import 'package:sei_cycle/features/inventory/models/inventory_transaction.dart';
import 'package:sei_cycle/features/inventory/services/inventory_service.dart';
import 'package:sei_cycle/features/inventory/services/inventory_adjustment_service.dart';
import 'package:sei_cycle/features/inventory/services/inventory_transaction_service.dart';
import 'package:sei_cycle/features/logbook/services/logbook_service.dart';
import 'package:sei_cycle/features/notification/services/notification_service.dart';
import 'package:sei_cycle/features/schedule/models/schedule_item.dart';
import 'package:sei_cycle/features/schedule/models/schedule_filter.dart';
import 'package:sei_cycle/features/schedule/services/schedule_service.dart';
import 'package:sei_cycle/features/schedule/services/reminder_sync_service.dart';
import 'support/memory_firestore.dart';

final day = DateTime(2026, 10, 16);
void seedUser(
  MemoryFirestore db, {
  String role = 'operator_lapangan',
  bool active = true,
}) {
  db.documents['users/field'] = {'role': role, 'isActive': active};
}

Map<String, dynamic> stockDoc({double stock = 20}) => {
  'id': 'feed',
  'name': 'Pakan',
  'itemKey': 'pakan',
  'moduleType': 'lele',
  'category': 'pakan',
  'unit': 'kg',
  'currentStock': stock,
  'minStock': 5,
  'isLowStock': stock <= 5,
  'location': 'Gudang',
  'createdBy': 'field',
  'updatedBy': 'field',
  'createdAt': Timestamp.fromDate(day),
  'updatedAt': Timestamp.fromDate(day),
  'isDeleted': false,
};
Map<String, dynamic> scheduleDoc(
  String id, {
  DateTime? date,
  String status = 'pending',
}) => {
  'id': id,
  'title': 'Pakan sore',
  'moduleType': 'lele',
  'type': 'pakan',
  'date': Timestamp.fromDate(date ?? day),
  'status': status,
  'notes': '',
  'createdBy': 'field',
  'updatedBy': 'field',
  'createdAt': Timestamp.fromDate(day),
  'updatedAt': Timestamp.fromDate(day),
  'isDeleted': false,
};

class FakeReminders extends LocalReminderService {
  bool granted = true, fail = false;
  final pending = <String>{};
  final scheduled = <(String, DateTime)>[], cancelled = <String>[];
  @override
  Future<bool> requestPermission() async => granted;
  @override
  Future<Set<String>> pendingScheduleIds() async => Set.of(pending);
  @override
  Future<void> scheduleScheduleReminder({
    required String scheduleId,
    required String title,
    required DateTime scheduledAt,
    String? body,
  }) async {
    if (fail) throw StateError('Native unavailable');
    pending.add(scheduleId);
    scheduled.add((scheduleId, scheduledAt));
  }

  @override
  Future<void> cancelScheduleReminder(String scheduleId) async {
    pending.remove(scheduleId);
    cancelled.add(scheduleId);
  }

  @override
  Future<void> cancelAll() async {
    pending.clear();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MemoryFirestore db;
  late InventoryService master;
  late InventoryAdjustmentService adjustments;
  late ScheduleService schedules;
  setUp(() {
    db = MemoryFirestore();
    seedUser(db);
    db.documents['inventory/feed'] = stockDoc();
    master = InventoryService(firestore: db);
    adjustments = InventoryAdjustmentService(firestore: db);
    schedules = ScheduleService(firestore: db);
  });
  Future<String> mutate({
    String id = 'change',
    String type = 'in',
    double value = 10,
    String unit = 'kg',
    String notes = 'Pengadaan',
    bool negative = false,
    String? batchId,
  }) => adjustments.mutate(
    requestId: id,
    itemId: 'feed',
    type: type,
    value: value,
    unit: unit,
    notes: notes,
    userId: 'field',
    allowNegative: negative,
    batchId: batchId,
  );
  Future<String> createItem({
    String id = 'new',
    double opening = 10,
    String name = 'Baru',
  }) => master.createItem(
    requestId: id,
    name: name,
    itemKey: 'baru',
    moduleType: 'lele',
    category: 'pakan',
    unit: 'kg',
    minStock: 5,
    location: 'Gudang',
    initialStock: opening,
    userId: 'field',
  );
  Future<String> createSchedule({
    String id = 'task',
    String? batchId,
    String module = 'lele',
    String title = 'Pakan',
  }) => schedules.save(
    requestId: id,
    title: title,
    moduleId: module,
    scheduleType: 'pakan',
    scheduledAt: day,
    note: '',
    userId: 'field',
    batchId: batchId,
  );
  Future<ScheduleItem> task() async => ScheduleItem.fromDocument(
    await db.collection('schedules').doc('task').get(),
  );

  test(
    'stock in, out and absolute correction store before/after and deltas',
    () async {
      await mutate();
      await mutate(id: 'out', type: 'out', value: 5);
      await mutate(id: 'correct', type: 'correction', value: 23);
      expect(db.documents['inventory/feed']!['currentStock'], 23);
      final h = db.documents['inventory_transactions/correct']!;
      expect(h['beforeStock'], 25);
      expect(h['afterStock'], 23);
      expect(h['quantity'], 2);
      expect(h['notes'], 'Pengadaan');
      expect(h['createdBy'], 'field');
      expect(h['createdAt'], isA<Timestamp>());
    },
  );
  test(
    'callback retry and request replay create exactly one immutable history',
    () async {
      db.retryOnce = true;
      await mutate();
      await mutate();
      expect(db.documents['inventory/feed']!['currentStock'], 30);
      expect(
        db.documents.keys.where((k) => k.startsWith('inventory_transactions/')),
        hasLength(1),
      );
      await expectLater(mutate(value: 11), throwsStateError);
      await expectLater(mutate(notes: 'Payload berbeda'), throwsStateError);
    },
  );
  test(
    'transaction retry recalculates from concurrent operator stock',
    () async {
      db.retryOnce = true;
      db.beforeRetry = () =>
          db.documents['inventory/feed']!['currentStock'] = 25;
      await mutate();
      expect(db.documents['inventory/feed']!['currentStock'], 35);
      expect(db.documents['inventory_transactions/change']!['beforeStock'], 25);
    },
  );
  test('failed commit leaves no partial history or stock', () async {
    db.failCommit = true;
    await expectLater(mutate(), throwsStateError);
    expect(db.documents['inventory/feed']!['currentStock'], 20);
    expect(
      db.documents.keys.where((k) => k.startsWith('inventory_transactions/')),
      isEmpty,
    );
    db.failCommit = false;
    await mutate();
    expect(db.documents['inventory/feed']!['currentStock'], 30);
  });
  test(
    'ambiguous committed response is recovered by same request receipt',
    () async {
      db.denyNextCommittedWrite = true;
      await mutate();
      await mutate();
      expect(db.documents['inventory/feed']!['currentStock'], 30);
    },
  );
  test(
    'unit mismatch, deleted and missing item reject before any writes',
    () async {
      await expectLater(mutate(unit: 'liter'), throwsStateError);
      db.documents['inventory/feed']!['isDeleted'] = true;
      await expectLater(mutate(), throwsStateError);
      db.documents.remove('inventory/feed');
      await expectLater(mutate(), throwsStateError);
    },
  );
  for (final value in [
    double.nan,
    double.infinity,
    double.negativeInfinity,
    -1.0,
    1e13,
  ]) {
    test('invalid stock input $value rejected', () async {
      await expectLater(mutate(value: value), throwsArgumentError);
    });
  }
  test(
    'manual minus explicit, correction nonnegative, in/out positive',
    () async {
      await expectLater(mutate(type: 'out', value: 25), throwsStateError);
      await mutate(type: 'out', value: 25, negative: true);
      expect(db.documents['inventory/feed']!['currentStock'], -5);
      await mutate(id: 'opname', type: 'correction', value: 0);
      expect(db.documents['inventory/feed']!['currentStock'], 0);
      await expectLater(mutate(id: 'zero', value: 0), throwsArgumentError);
      await expectLater(
        mutate(id: 'bad', type: 'delta', value: 5),
        throwsArgumentError,
      );
      await expectLater(mutate(id: 'reason', notes: ''), throwsArgumentError);
    },
  );
  test(
    'master opening creates item and ledger atomically with stable ID',
    () async {
      db.retryOnce = true;
      await createItem();
      await createItem();
      expect(db.documents['inventory/new']!['currentStock'], 10);
      expect(
        db.documents['inventory_transactions/opening_new']!['quantity'],
        10,
      );
      await expectLater(createItem(name: 'Berbeda'), throwsStateError);
    },
  );
  test(
    'opening zero has no ledger; failed opening leaves neither document',
    () async {
      await createItem(opening: 0);
      expect(db.documents['inventory_transactions/opening_new'], isNull);
      db.failCommit = true;
      await expectLater(createItem(id: 'failed'), throwsStateError);
      expect(db.documents['inventory/failed'], isNull);
      expect(db.documents['inventory_transactions/opening_failed'], isNull);
    },
  );
  test(
    'master metadata updates never write stock or mutable unit/key/module',
    () async {
      final item = InventoryItem.fromDocument(
        await db.collection('inventory').doc('feed').get(),
      );
      await master.saveMetadata(
        item: item,
        name: 'Pakan Baru',
        category: 'pakan',
        location: 'Gudang B',
        minStock: 25,
        userId: 'field',
      );
      final d = db.documents['inventory/feed']!;
      expect(d['currentStock'], 20);
      expect(d['unit'], 'kg');
      expect(d['itemKey'], 'pakan');
      expect(d['isLowStock'], true);
      expect(d['createdAt'], Timestamp.fromDate(day));
      await expectLater(
        master.saveMetadata(
          item: item,
          name: 'Stale',
          category: 'pakan',
          location: '',
          minStock: 0,
          userId: 'field',
        ),
        throwsStateError,
      );
    },
  );
  test(
    'legacy inventory and ledger parse document ID, actual low flag and optional relations',
    () async {
      db.documents['inventory/feed']!['isLowStock'] = true;
      expect(
        InventoryItem.fromDocument(
          await db.collection('inventory').doc('feed').get(),
        ).isLowStock,
        false,
      );
      db.documents['inventory_transactions/legacy'] = {
        'id': 'wrong',
        'type': 'out',
        'logbookId': 'entry',
        'isReversed': true,
      };
      final legacy = InventoryTransaction.fromDocument(
        await db.collection('inventory_transactions').doc('legacy').get(),
      );
      expect(legacy.id, 'legacy');
      expect(legacy.batchId, isNull);
      expect(legacy.isReversed, true);
      expect(legacy.source, 'logbook');
    },
  );
  test(
    'paged inventory category/module and history filters are bounded',
    () async {
      final page = await master.fetchPage(
        moduleType: 'lele',
        category: 'pakan',
        limit: 1,
      );
      expect(page.items, hasLength(1));
      expect(page.hasMore, true);
      expect(
        (await master.fetchPage(
          moduleType: 'lele',
          limit: 1,
          cursor: page.cursor,
        )).items,
        isEmpty,
      );
      await mutate();
      final h = InventoryTransactionService(firestore: db);
      expect(
        (await h.fetchPage(field: 'itemId', value: 'feed')).items,
        hasLength(1),
      );
      expect(
        (await h.fetchPage(field: 'source', value: 'manual')).items,
        hasLength(1),
      );
      expect((await h.fetchPage(field: 'type', value: 'out')).items, isEmpty);
    },
  );
  test('unsafe rollback and reversal remain disabled', () async {
    await expectLater(
      master.rollbackInventoryTransactionsByLogbookId('entry', userId: 'field'),
      throwsUnsupportedError,
    );
    await expectLater(
      InventoryTransactionService(
        firestore: db,
      ).markTransactionsReversed('entry', userId: 'field'),
      throwsUnsupportedError,
    );
  });
  test(
    'logbook idempotency keeps global stock and batch attribution',
    () async {
      final logs = LogbookService(firestore: db);
      Future<String> save() => logs.createDailyEntry(
        requestId: 'once',
        moduleType: 'ayam_kampung',
        title: 'Pengamatan',
        activityType: 'input_harian_ayam',
        notes: '',
        quantity: null,
        unit: null,
        details: {'dedak_padi_kg': 5},
        userId: 'field',
      );
      await save();
      await save();
      expect(db.documents['inventory/logbook_dedak_padi']!['currentStock'], -5);
      expect(
        db.documents.values.where(
          (v) => v['logbookId'] == 'once' && v['type'] == 'out',
        ),
        hasLength(1),
      );
      expect(
        db.documents['inventory/logbook_dedak_padi']!['lastTransactionId'],
        isNotEmpty,
      );
    },
  );
  for (final (role, active, allowed) in [
    ('admin', true, true),
    ('operator_lapangan', true, true),
    ('operator', true, true),
    ('operator_keuangan', true, false),
    ('mitra', true, false),
    ('admin', false, false),
  ]) {
    test('services authorize $role active=$active', () async {
      seedUser(db, role: role, active: active);
      if (allowed) {
        await mutate();
        await createSchedule();
      } else {
        await expectLater(mutate(), throwsStateError);
        await expectLater(createSchedule(), throwsStateError);
      }
    });
  }
  test(
    'schedule creates once and rejects reused request with changed payload',
    () async {
      db.retryOnce = true;
      await createSchedule();
      await createSchedule();
      expect(
        db.documents.keys.where((p) => p.startsWith('schedules/')),
        hasLength(1),
      );
      await expectLater(createSchedule(title: 'Changed'), throwsStateError);
      expect((await task()).batchId, isNull);
    },
  );
  test(
    'schedule accepts active matching batch only and preserves legacy reads',
    () async {
      db.documents['batches/A'] = {
        'status': 'active',
        'moduleType': 'lele',
        'isDeleted': false,
      };
      await createSchedule(batchId: 'A');
      expect((await task()).batchId, 'A');
      await expectLater(
        createSchedule(id: 'wrong', batchId: 'A', module: 'tanaman'),
        throwsStateError,
      );
      for (final status in ['planned', 'completed', 'archived']) {
        db.documents['batches/A']!['status'] = status;
        await expectLater(
          createSchedule(id: status, batchId: 'A'),
          throwsStateError,
        );
      }
      await expectLater(
        createSchedule(id: 'missing', batchId: 'MISSING'),
        throwsStateError,
      );
      db.documents['schedules/legacy'] = {
        'module_id': 'lele',
        'scheduled_at': Timestamp.fromDate(day),
      };
      final old = ScheduleItem.fromDocument(
        await db.collection('schedules').doc('legacy').get(),
      );
      expect(old.moduleId, 'lele');
      expect(old.batchId, isNull);
      expect(old.status, 'pending');
    },
  );
  test(
    'manual mutation records active matching batch attribution on global stock',
    () async {
      db.documents['batches/A'] = {
        'status': 'active',
        'moduleType': 'lele',
        'isDeleted': false,
      };
      await mutate(batchId: 'A');
      expect(db.documents['inventory_transactions/change']!['batchId'], 'A');
      expect(db.documents['inventory/feed']!['currentStock'], 30);
      db.documents['batches/A']!['moduleType'] = 'tanaman';
      await expectLater(
        mutate(id: 'wrong-batch', batchId: 'A'),
        throwsStateError,
      );
      await expectLater(
        mutate(id: 'missing-batch', batchId: 'MISSING'),
        throwsStateError,
      );
    },
  );
  test(
    'schedule date edit preserves audit and deleted pending is excluded from reminders',
    () async {
      await createSchedule();
      final old = await task();
      final future = DateTime.now().add(const Duration(days: 1));
      await schedules.save(
        id: 'task',
        requestId: 'edit',
        title: 'Pakan baru',
        moduleId: 'lele',
        scheduleType: 'pakan',
        scheduledAt: future,
        note: 'Jam diubah',
        userId: 'field',
        expectedUpdatedAt: old.updatedAt,
      );
      expect((await task()).scheduledAt, future);
      expect((await task()).createdAt, old.createdAt);
      expect(await schedules.reminderCandidates(DateTime.now()), hasLength(1));
      seedUser(db, role: 'admin');
      await schedules.delete(
        'task',
        userId: 'field',
        expectedUpdatedAt: (await task()).updatedAt,
      );
      expect(await schedules.reminderCandidates(DateTime.now()), isEmpty);
    },
  );
  test(
    'done stores first actor/time, repeated tap no-op, opposite terminal action rejected',
    () async {
      await createSchedule();
      final old = await task();
      await schedules.updateStatus(
        'task',
        'done',
        userId: 'field',
        expectedUpdatedAt: old.updatedAt,
      );
      final first = await task();
      expect(first.completedBy, 'field');
      expect(first.completedAt, isNotNull);
      await schedules.updateStatus(
        'task',
        'done',
        userId: 'field',
        expectedUpdatedAt: old.updatedAt,
      );
      expect((await task()).completedAt, first.completedAt);
      await expectLater(
        schedules.updateStatus(
          'task',
          'skipped',
          userId: 'field',
          expectedUpdatedAt: old.updatedAt,
        ),
        throwsStateError,
      );
      expect(
        db.documents.keys.where((p) => p.startsWith('inventory_transactions/')),
        isEmpty,
      );
    },
  );
  test(
    'skipped records reason and rejects stale edit and conflicting retry',
    () async {
      await createSchedule();
      final old = await task();
      db.retryOnce = true;
      db.beforeRetry = () => db.documents['schedules/task']!['status'] = 'done';
      await expectLater(
        schedules.updateStatus(
          'task',
          'skipped',
          userId: 'field',
          expectedUpdatedAt: old.updatedAt,
        ),
        throwsStateError,
      );
      db.documents['schedules/task']!['status'] = 'pending';
      await schedules.updateStatus(
        'task',
        'skipped',
        userId: 'field',
        expectedUpdatedAt: old.updatedAt,
        reason: 'Hujan',
      );
      expect((await task()).skippedBy, 'field');
      expect((await task()).skipReason, 'Hujan');
      await expectLater(
        schedules.save(
          id: 'task',
          requestId: 'edit',
          title: 'Stale',
          moduleId: 'lele',
          scheduleType: 'pakan',
          scheduledAt: day,
          note: '',
          userId: 'field',
          expectedUpdatedAt: old.updatedAt,
        ),
        throwsStateError,
      );
    },
  );
  test(
    'schedule filters calendar day, future, overdue, done, date and batch',
    () async {
      final now = DateTime(2026, 10, 16, 12);
      db.documents['schedules/early'] = scheduleDoc(
        'early',
        date: DateTime(2026, 10, 16, 7),
      );
      db.documents['schedules/later'] = scheduleDoc(
        'later',
        date: DateTime(2026, 10, 17, 7),
      );
      db.documents['schedules/done'] = scheduleDoc(
        'done',
        date: day,
        status: 'done',
      );
      expect((await schedules.fetchPage(now: now)).items, hasLength(2));
      expect(
        (await schedules.fetchPage(
          now: now,
          filter: const ScheduleFilter(view: ScheduleView.upcoming),
        )).items.single.id,
        'later',
      );
      expect(
        (await schedules.fetchPage(
          now: now,
          filter: const ScheduleFilter(view: ScheduleView.overdue),
        )).items.single.id,
        'early',
      );
      expect(
        (await schedules.fetchPage(
          now: now,
          filter: const ScheduleFilter(view: ScheduleView.done),
        )).items.single.id,
        'done',
      );
      expect(
        (await schedules.fetchPage(
          now: now,
          filter: ScheduleFilter(
            view: ScheduleView.all,
            date: DateTime(2026, 10, 17),
          ),
        )).items.single.id,
        'later',
      );
    },
  );
  test(
    'low-stock alert deduplicates same information even after read and resolves recovery',
    () async {
      db.documents['inventory/feed']!['currentStock'] = 2;
      final service = NotificationService(firestore: db);
      Future<void> sync() => service.createLowStockAlert(
        userId: 'field',
        role: 'operator_lapangan',
        itemId: 'feed',
        name: 'Stale',
        currentStock: 100,
        minStock: 0,
        unit: 'kg',
      );
      await sync();
      final ref = 'notifications/low_stock_field_feed';
      db.documents[ref]!['isRead'] = true;
      await sync();
      expect(db.documents[ref]!['isRead'], true);
      db.documents['inventory/feed']!['currentStock'] = 20;
      await sync();
      expect(db.documents[ref]!['isDeleted'], true);
      db.documents['inventory/feed']!['currentStock'] = 0;
      await sync();
      expect(db.documents[ref]!['title'], contains('habis'));
    },
  );
  test(
    'reminders future pending only; stable ID; done/skipped/deleted/old cancelled',
    () async {
      final future = DateTime.now().add(const Duration(days: 1));
      for (final status in ['pending', 'done', 'skipped']) {
        db.documents['schedules/$status'] = scheduleDoc(
          status,
          date: future,
          status: status,
        );
      }
      final reminders = FakeReminders()
        ..pending.addAll({'done', 'skipped', 'deleted'});
      final sync = ReminderSyncService(
        schedules: schedules,
        reminders: reminders,
      );
      expect(await sync.sync(), contains('1 pengingat'));
      expect(reminders.pending, {'pending'});
      expect(reminders.cancelled, containsAll(['done', 'skipped', 'deleted']));
      expect(stableReminderId('task'), 2087951912);
      expect(stableReminderId('task'), isNot(stableReminderId('task2')));
      final next = future.add(const Duration(hours: 1));
      db.documents['schedules/pending']!['date'] = Timestamp.fromDate(next);
      await sync.sync();
      expect(reminders.scheduled.last.$2, next);
      expect(reminders.pending, {'pending'});
    },
  );
  test(
    'denied notification permission and native failure never undo schedule or create duplicates',
    () async {
      await createSchedule();
      final reminders = FakeReminders()..granted = false;
      final sync = ReminderSyncService(
        schedules: schedules,
        reminders: reminders,
      );
      expect(await sync.sync(), contains('Izin'));
      expect(db.documents['schedules/task'], isNotNull);
      reminders.granted = true;
      reminders.fail = true;
      db.documents['schedules/task']!['date'] = Timestamp.fromDate(
        DateTime.now().add(const Duration(days: 1)),
      );
      expect(await sync.sync(), contains('belum berhasil'));
      await createSchedule();
      expect(
        db.documents.keys.where((p) => p.startsWith('schedules/')),
        hasLength(1),
      );
    },
  );
  test(
    'sync coalesces repeated calls and logout cancels device reminders before next login',
    () async {
      db.documents['schedules/future'] = scheduleDoc(
        'future',
        date: DateTime.now().add(const Duration(days: 1)),
      );
      final local = FakeReminders();
      final sync = ReminderSyncService(schedules: schedules, reminders: local);
      await Future.wait([sync.sync(), sync.sync()]);
      expect(local.scheduled, hasLength(1));
      await sync.clear();
      expect(local.pending, isEmpty);
      expect(await sync.sync(), contains('berakhir'));
      final nextSession = ReminderSyncService(
        schedules: schedules,
        reminders: local,
      );
      await nextSession.sync();
      expect(local.pending, {'future'});
    },
  );
}
