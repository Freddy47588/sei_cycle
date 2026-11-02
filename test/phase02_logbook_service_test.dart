import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sei_cycle/features/logbook/services/logbook_service.dart';
import 'package:sei_cycle/features/logbook/models/logbook_page.dart';
import 'support/memory_firestore.dart';

Future<String> create(
  LogbookService service, {
  String id = 'request-1',
  Map<String, dynamic> details = const {
    'dedak_padi_kg': 5,
    'produksi_telur_hari_ini': 3,
  },
}) => service.createDailyEntry(
  requestId: id,
  moduleType: 'ayam_kampung',
  title: 'Catatan Ayam',
  activityType: 'input_harian_ayam',
  quantity: 3,
  unit: 'butir',
  notes: 'Asli',
  details: details,
  userId: 'field',
);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MemoryFirestore db;
  late LogbookService service;
  setUp(() {
    db = MemoryFirestore();
    service = LogbookService(firestore: db);
  });
  test(
    'create returns ID, transaction retry and repeated request write stock/production once',
    () async {
      db.retryOnce = true;
      expect(await create(service), 'request-1');
      expect(await create(service), 'request-1');
      expect(
        db.documents.keys.where((p) => p.startsWith('logbooks/')),
        hasLength(1),
      );
      expect(
        db.documents.keys.where((p) => p.startsWith('inventory_transactions/')),
        hasLength(2),
      );
      expect(
        db.documents.keys.where((p) => p.startsWith('production_results/')),
        hasLength(1),
      );
      expect(db.documents['inventory/logbook_dedak_padi']!['currentStock'], -5);
      expect(db.documents['inventory/logbook_telur_ayam']!['currentStock'], 3);
    },
  );
  test(
    'concurrent commit denial verifies stored payload before returning success',
    () async {
      db.commitThenDeny = true;
      expect(await create(service), 'request-1');
      expect(db.documents['inventory/logbook_telur_ayam']!['currentStock'], 3);
    },
  );
  test(
    'failed atomic commit leaves no partial documents, retry uses same ID',
    () async {
      db.failCommit = true;
      await expectLater(create(service), throwsStateError);
      expect(db.documents, isEmpty);
      db.failCommit = false;
      await create(service);
      expect(db.documents['inventory/logbook_telur_ayam']!['currentStock'], 3);
    },
  );
  test(
    'multiple stocked items and multiple entries use current stock',
    () async {
      final details = {
        'dedak_padi_kg': 5,
        'talas_pepaya_kg': 2,
        'maggot_segar_kg': 1,
        'produksi_telur_hari_ini': 3,
      };
      await create(service, details: details);
      await create(service, id: 'request-2', details: details);
      expect(
        db.documents['inventory/logbook_dedak_padi']!['currentStock'],
        -10,
      );
      expect(
        db.documents['inventory/logbook_talas_pepaya']!['currentStock'],
        -4,
      );
      expect(
        db.documents['inventory/logbook_maggot_segar']!['currentStock'],
        -2,
      );
      expect(db.documents['inventory/logbook_telur_ayam']!['currentStock'], 6);
      expect(
        db.documents.keys.where((p) => p.startsWith('production_results/')),
        hasLength(2),
      );
    },
  );
  test(
    'same id with different data rejects; notes edit never touches stock/production and stores audit',
    () async {
      await create(service);
      await expectLater(
        create(service, details: {'dedak_padi_kg': 7}),
        throwsStateError,
      );
      final entry = (await service.getEntry('request-1'))!;
      final stocks =
          db.documents['inventory/logbook_dedak_padi']!['currentStock'];
      await service.updateNotes(
        entry.id,
        notes: 'Koreksi deskripsi',
        userId: 'field',
        expectedUpdatedAt: entry.updatedAt,
      );
      expect(
        db.documents['inventory/logbook_dedak_padi']!['currentStock'],
        stocks,
      );
      expect(
        db.documents.keys.where((p) => p.startsWith('production_results/')),
        hasLength(1),
      );
      expect(
        db.documents.keys.where((p) => p.contains('/note_edits/')),
        hasLength(1),
      );
      expect(db.documents['logbooks/request-1']!['notes'], 'Koreksi deskripsi');
    },
  );
  test(
    'stale edit and failed edit preserve previous note and do not add audit',
    () async {
      await create(service);
      await expectLater(
        service.updateNotes(
          'request-1',
          notes: 'New',
          userId: 'field',
          expectedUpdatedAt: DateTime(2000),
        ),
        throwsStateError,
      );
      final entry = (await service.getEntry('request-1'))!;
      db.failCommit = true;
      await expectLater(
        service.updateNotes(
          'request-1',
          notes: 'New',
          userId: 'field',
          expectedUpdatedAt: entry.updatedAt,
        ),
        throwsStateError,
      );
      expect(db.documents['logbooks/request-1']!['notes'], 'Asli');
      expect(
        db.documents.keys.where((p) => p.contains('/note_edits/')),
        isEmpty,
      );
    },
  );
  test(
    'cancellation disabled even on retry; nothing reverses or removes production',
    () async {
      await create(service);
      for (var i = 0; i < 2; i++) {
        await expectLater(
          service.softDelete('request-1', userId: 'admin'),
          throwsUnsupportedError,
        );
      }
      expect(db.documents['logbooks/request-1']!['isDeleted'], false);
      expect(db.documents['inventory/logbook_telur_ayam']!['currentStock'], 3);
      expect(
        db.documents.keys.where((p) => p.startsWith('production_results/')),
        hasLength(1),
      );
    },
  );
  test(
    'mismatched stock unit aborts all writes across multiple items',
    () async {
      db.documents['inventory/legacy'] = {
        'id': 'legacy',
        'itemKey': 'talas_pepaya',
        'unit': 'liter',
        'currentStock': 20,
        'isDeleted': false,
      };
      await expectLater(
        create(service, details: {'dedak_padi_kg': 5, 'talas_pepaya_kg': 2}),
        throwsStateError,
      );
      expect(db.documents.length, 1);
      expect(db.documents['inventory/legacy']!['currentStock'], 20);
    },
  );
  test(
    'service cursor pagination and date/module filters return actual bounded rows',
    () async {
      for (var i = 0; i < 23; i++) {
        final data = {
          'id': '$i',
          'moduleType': 'ayam_kampung',
          'isDeleted': false,
          'activityDate': Timestamp.fromDate(DateTime(2026, 10, 16, i)),
        };
        db.documents['logbooks/$i'] = data;
      }
      db.documents['logbooks/other'] = {
        'moduleType': 'lele',
        'isDeleted': false,
        'activityDate': Timestamp.fromDate(DateTime(2026, 10, 16)),
      };
      final filter = LogbookFilter.forPeriod(
        moduleId: 'ayam_kampung',
        period: 'Hari ini',
        now: DateTime(2026, 10, 16),
        newestFirst: false,
      );
      final first = await service.getPage(filter: filter);
      final second = await service.getPage(
        filter: filter,
        cursor: first.cursor,
      );
      expect(first.entries, hasLength(20));
      expect(second.entries, hasLength(3));
      expect(second.hasMore, false);
      expect({
        ...first.entries.map((e) => e.id),
        ...second.entries.map((e) => e.id),
      }, hasLength(23));
    },
  );
}
