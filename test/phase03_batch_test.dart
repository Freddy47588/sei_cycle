import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sei_cycle/core/constants/farm_modules.dart';
import 'package:sei_cycle/features/batches/models/cultivation_batch.dart';
import 'package:sei_cycle/features/batches/services/batch_service.dart';
import 'package:sei_cycle/features/logbook/models/logbook_entry.dart';
import 'package:sei_cycle/features/logbook/models/logbook_page.dart';
import 'package:sei_cycle/features/logbook/services/logbook_service.dart';
import 'support/memory_firestore.dart';

BatchInput input({
  String code = 'KOLAM-A',
  String module = 'lele',
  String name = 'Kolam A',
  String location = 'Kolam Utara',
  double? quantity = 500,
  String unit = 'ekor',
  DateTime? harvest,
  String notes = '',
}) => BatchInput(
  moduleType: module,
  name: name,
  code: code,
  locationName: location,
  startedAt: DateTime(2026, 10, 1),
  expectedHarvestAt: harvest,
  initialQuantity: quantity,
  initialUnit: unit,
  notes: notes,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MemoryFirestore db;
  late BatchService batches;
  late LogbookService logbooks;
  setUp(() {
    db = MemoryFirestore();
    db.documents['users/field'] = {
      'uid': 'field',
      'role': 'operator_lapangan',
      'isActive': true,
    };
    batches = BatchService(firestore: db);
    logbooks = LogbookService(firestore: db);
  });
  Future<String> active({
    String code = 'KOLAM-A',
    String module = 'lele',
  }) async {
    final id = await batches.create(
      input(code: code, module: module),
      userId: 'field',
    );
    await batches.transition(
      id,
      from: 'planned',
      to: 'active',
      userId: 'field',
    );
    return id;
  }

  Future<String> save({
    String? batchId = 'KOLAM-A',
    String id = 'request-1',
    String module = 'lele',
    Map<String, dynamic> details = const {'panen_lele_kg': 3},
  }) => logbooks.createDailyEntry(
    requestId: id,
    batchId: batchId,
    moduleType: module,
    title: 'Catatan',
    activityType: 'input_harian',
    quantity: 3,
    unit: 'kg',
    notes: 'Asli',
    details: details,
    userId: 'field',
  );

  for (final m in FarmModules.values) {
    test(
      'create ${m.id} persists actual initial quantity and explicit unit',
      () async {
        final id = await batches.create(
          input(module: m.id, unit: m.id == 'tanaman' ? 'm2' : 'kg'),
          userId: 'field',
        );
        final b = await batches.getBatch(id);
        expect(b!.input.moduleType, m.id);
        expect(b.input.initialQuantity, 500);
        expect(b.status, 'planned');
        expect(b.createdBy, 'field');
        expect(db.documents['batches/$id']!['startedAt'], isA<Timestamp>());
      },
    );
  }
  test(
    'invalid required fields, module, quantity, unit, code and dates rejected',
    () async {
      for (final i in [
        input(name: ''),
        input(location: ''),
        input(module: 'unknown'),
        input(quantity: -1),
        input(quantity: double.nan),
        input(quantity: double.infinity),
        input(unit: ''),
        input(code: 'a/b'),
        input(harvest: DateTime(2026, 9, 1)),
      ]) {
        await expectLater(
          batches.create(i, userId: 'field'),
          throwsArgumentError,
        );
      }
      expect(db.documents.keys.where((k) => k.startsWith('batches/')), isEmpty);
    },
  );
  test(
    'normalized deterministic code cannot be reused or overwritten',
    () async {
      await batches.create(input(code: 'kolam-a'), userId: 'field');
      await expectLater(
        batches.create(
          input(code: ' KOLAM-A ', name: 'Overwrite'),
          userId: 'field',
        ),
        throwsStateError,
      );
      expect((await batches.getBatch('KOLAM-A'))!.input.name, 'Kolam A');
    },
  );
  test(
    'edit descriptive fields succeeds while immutable identity and stale edits fail',
    () async {
      await active();
      final b = (await batches.getBatch('KOLAM-A'))!;
      await batches.edit(
        b.id,
        input(name: 'Nama baru', notes: 'Diperiksa'),
        userId: 'field',
        expectedUpdatedAt: b.updatedAt!,
      );
      expect((await batches.getBatch(b.id))!.input.name, 'Nama baru');
      for (final i in [
        input(code: 'OTHER'),
        input(module: 'tanaman'),
        input(quantity: 99),
        input(unit: 'kg'),
      ]) {
        await expectLater(
          batches.edit(
            b.id,
            i,
            userId: 'field',
            expectedUpdatedAt: b.updatedAt!,
          ),
          throwsStateError,
        );
      }
      await expectLater(
        batches.edit(
          b.id,
          input(),
          userId: 'field',
          expectedUpdatedAt: DateTime(2000),
        ),
        throwsStateError,
      );
    },
  );
  test(
    'lifecycle is forward only, retry preserves completion time and history',
    () async {
      await active();
      await expectLater(
        batches.transition(
          'KOLAM-A',
          from: 'active',
          to: 'planned',
          userId: 'field',
        ),
        throwsArgumentError,
      );
      await batches.transition(
        'KOLAM-A',
        from: 'active',
        to: 'completed',
        userId: 'field',
      );
      final completion = (await batches.getBatch('KOLAM-A'))!.completedAt;
      await batches.transition(
        'KOLAM-A',
        from: 'active',
        to: 'completed',
        userId: 'field',
      );
      expect((await batches.getBatch('KOLAM-A'))!.completedAt, completion);
      await expectLater(
        batches.edit(
          'KOLAM-A',
          input(),
          userId: 'field',
          expectedUpdatedAt: completion!,
        ),
        throwsStateError,
      );
      await batches.transition(
        'KOLAM-A',
        from: 'completed',
        to: 'archived',
        userId: 'field',
      );
      expect((await batches.getBatch('KOLAM-A'))!.status, 'archived');
      expect(
        db.documents.keys.where(
          (k) => !k.startsWith('batches/') && !k.startsWith('users/'),
        ),
        isEmpty,
      );
    },
  );
  for (final role in [
    'admin',
    'operator_lapangan',
    'operator',
    'operator_keuangan',
    'mitra',
    'peserta_edukasi',
  ]) {
    test('service role permissions for $role', () async {
      db.documents['users/field']!['role'] = role;
      final future = batches.create(input(), userId: 'field');
      if (['admin', 'operator_lapangan', 'operator'].contains(role)) {
        await future;
      } else {
        await expectLater(future, throwsStateError);
      }
    });
  }
  test('inactive and absent profiles cannot manage batch', () async {
    db.documents['users/field']!['isActive'] = false;
    await expectLater(
      batches.create(input(), userId: 'field'),
      throwsStateError,
    );
    db.documents.remove('users/field');
    await expectLater(
      batches.create(input(), userId: 'field'),
      throwsStateError,
    );
  });
  test(
    'matching active batch accepted, retry has one stock and production effect',
    () async {
      await active();
      db.retryOnce = true;
      expect(await save(), 'request-1');
      await batches.transition(
        'KOLAM-A',
        from: 'active',
        to: 'completed',
        userId: 'field',
      );
      expect(
        await save(),
        'request-1',
      ); // committed request remains valid after completion
      expect(db.documents['logbooks/request-1']!['batchId'], 'KOLAM-A');
      expect(db.documents['inventory/logbook_lele_panen']!['currentStock'], 3);
      final production = db.documents.entries
          .where((e) => e.key.startsWith('production_results/'))
          .toList();
      final inventory = db.documents.entries
          .where((e) => e.key.startsWith('inventory_transactions/'))
          .toList();
      expect(production, hasLength(1));
      expect(inventory, hasLength(1));
      expect(production.single.value['batchId'], 'KOLAM-A');
      expect(inventory.single.value['batchId'], 'KOLAM-A');
      expect(production.single.value['logbookId'], 'request-1');
    },
  );
  test(
    'request ID with changed batch rejected, including ambiguous commit recovery',
    () async {
      await active();
      await active(code: 'KOLAM-B');
      await save();
      await expectLater(save(batchId: 'KOLAM-B'), throwsStateError);
      await expectLater(save(batchId: null), throwsStateError);
      db.commitThenDeny = true;
      expect(await save(id: 'ambiguous'), 'ambiguous');
      await expectLater(
        save(id: 'ambiguous', batchId: 'KOLAM-B'),
        throwsStateError,
      );
    },
  );
  test(
    'missing, wrong-module, planned, completed, archived and deleted batches rejected atomically',
    () async {
      await expectLater(save(), throwsStateError);
      await batches.create(input(module: 'tanaman'), userId: 'field');
      await expectLater(save(), throwsStateError);
      db.documents['batches/KOLAM-A']!['moduleType'] = 'lele';
      await expectLater(save(), throwsStateError);
      await batches.transition(
        'KOLAM-A',
        from: 'planned',
        to: 'active',
        userId: 'field',
      );
      await batches.transition(
        'KOLAM-A',
        from: 'active',
        to: 'completed',
        userId: 'field',
      );
      await expectLater(save(), throwsStateError);
      await batches.transition(
        'KOLAM-A',
        from: 'completed',
        to: 'archived',
        userId: 'field',
      );
      await expectLater(save(), throwsStateError);
      db.documents['batches/KOLAM-A']!.addAll({
        'status': 'active',
        'isDeleted': true,
      });
      await expectLater(save(), throwsStateError);
      expect(
        db.documents.keys.where(
          (k) => k.startsWith('logbooks/') || k.startsWith('inventory/'),
        ),
        isEmpty,
      );
    },
  );
  test(
    'transaction retry rechecks concurrently completed batch before any writes',
    () async {
      await active();
      db.retryOnce = true;
      db.beforeRetry = () {
        db.documents['batches/KOLAM-A']!['status'] = 'completed';
      };
      await expectLater(save(), throwsStateError);
      expect(
        db.documents.keys.where(
          (k) =>
              k.startsWith('logbooks/') ||
              k.startsWith('production_results/') ||
              k.startsWith('inventory/'),
        ),
        isEmpty,
      );
    },
  );
  test('inactive profile rejected during batch logbook transaction', () async {
    await active();
    db.documents['users/field']!['isActive'] = false;
    await expectLater(save(), throwsStateError);
  });
  test('legacy unbatched data and audited notes remain compatible', () async {
    await save(batchId: null);
    final old = (await logbooks.getEntry('request-1'))!;
    expect(old.batchId, isNull);
    expect(
      LogbookEntry.fromDocument(
        await db.collection('logbooks').doc(old.id).get(),
      ).batchId,
      isNull,
    );
    final count = db.documents.length;
    await logbooks.updateNotes(
      old.id,
      notes: 'Revisi',
      userId: 'field',
      expectedUpdatedAt: old.updatedAt,
    );
    expect(db.documents.length, count + 1);
    expect(db.documents['inventory/logbook_lele_panen']!['currentStock'], 3);
  });
  test(
    'batch list filters, sort and cursors return nonduplicated bounded pages',
    () async {
      for (var n = 0; n < 23; n++) {
        await batches.create(input(code: 'PAGE-$n'), userId: 'field');
      }
      await batches.create(
        input(code: 'OTHER', module: 'tanaman'),
        userId: 'field',
      );
      final first = await batches.getPage(
        moduleType: 'lele',
        status: 'planned',
      );
      final second = await batches.getPage(
        moduleType: 'lele',
        status: 'planned',
        cursor: first.cursor,
      );
      expect(first.entries, hasLength(20));
      expect(second.entries, hasLength(3));
      expect({
        ...first.entries.map((e) => e.id),
        ...second.entries.map((e) => e.id),
      }, hasLength(23));
      expect((await batches.getPage(status: 'active')).entries, isEmpty);
      final oldest = await batches.getPage(newestFirst: false);
      expect(oldest.entries, hasLength(20));
    },
  );
  test(
    'batch activities query filters batchId and preserves legacy global listing',
    () async {
      await active();
      await save();
      await save(batchId: null, id: 'general');
      final page = await logbooks.getPage(
        filter: const LogbookFilter(batchId: 'KOLAM-A'),
      );
      expect(page.entries.map((e) => e.id), ['request-1']);
      expect(
        (await logbooks.getPage(filter: const LogbookFilter())).entries,
        hasLength(2),
      );
    },
  );
}
