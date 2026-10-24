import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sei_cycle/features/logbook/models/logbook_entry.dart';
import 'package:sei_cycle/features/logbook/models/logbook_form_spec.dart';
import 'package:sei_cycle/features/logbook/models/logbook_page.dart';
import 'package:sei_cycle/features/logbook/screen/logbook_screen.dart';
import 'package:sei_cycle/features/logbook/screen/logbook_list_screen.dart';
import 'package:sei_cycle/features/logbook/screen/logbook_detail_screen.dart';
import 'package:sei_cycle/features/logbook/services/logbook_service.dart';
import 'package:sei_cycle/features/logbook/services/inventory_mapping.dart';
import 'package:sei_cycle/features/inventory/services/inventory_service.dart';
import 'package:sei_cycle/features/profile/models/app_user.dart';
import 'package:sei_cycle/theme/app_theme.dart';

final date = DateTime(2026, 10, 16, 14);
LogbookEntry entry(
  String id, {
  String title = 'Pengamatan Ayam',
  String note = 'Sehat',
  Map<String, dynamic> details = const {'mortalitas_hari_ini': 0},
}) => LogbookEntry(
  id: id,
  title: title,
  moduleId: 'ayam_kampung',
  activityType: 'input_harian_ayam',
  activityDate: date,
  quantity: 0,
  unit: 'butir',
  note: note,
  status: 'completed',
  details: details,
  createdBy: 'user',
  updatedBy: 'user',
  createdAt: date,
  updatedAt: date,
  isDeleted: false,
);
AppUser user(String role) => AppUser(
  uid: 'user',
  name: 'Tester',
  email: '',
  photoUrl: '',
  role: role,
  isActive: true,
  createdAt: date,
  updatedAt: date,
);
Future<void> pump(
  WidgetTester tester,
  Widget widget, {
  double width = 320,
  bool settle = true,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(body: widget),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

void main() {
  setUpAll(() => initializeDateFormatting('id_ID'));
  test(
    'date filters use local calendar inclusive days and exclusive next day',
    () {
      final today = LogbookFilter.forPeriod(period: 'Hari ini', now: date);
      expect(today.start, DateTime(2026, 10, 16));
      expect(today.endExclusive, DateTime(2026, 10, 17));
      expect(
        LogbookFilter.forPeriod(period: '7 hari terakhir', now: date).start,
        DateTime(2026, 10, 10),
      );
      expect(
        LogbookFilter.forPeriod(period: 'Bulan ini', now: date).start,
        DateTime(2026, 10),
      );
      expect(
        LogbookFilter.forPeriod(
          period: 'Semua tanggal',
          now: date,
        ).endExclusive,
        isNull,
      );
      final custom = LogbookFilter.forPeriod(
        period: 'Rentang tanggal',
        now: date,
        customStart: DateTime(2026, 9, 29, 12),
        customEnd: DateTime(2026, 9, 30, 20),
      );
      expect(custom.start, DateTime(2026, 9, 29));
      expect(custom.endExclusive, DateTime(2026, 10, 1));
    },
  );
  test('search only loaded titles/notes, merge removes overlapping IDs', () {
    final rows = mergeLogbookPages(
      [entry('a')],
      [entry('a'), entry('b', title: 'Panen', note: 'Siap jual')],
    );
    expect(rows.length, 2);
    expect(searchLoadedLogbooks(rows, '  JUAL ').single.id, 'b');
    expect(searchLoadedLogbooks(rows, 'tidak ada'), isEmpty);
  });
  test(
    'detail formatter retains zero, labels and units without inventing empty values',
    () {
      final display = displayLogbookDetails('ayam_kampung', {
        'mortalitas_hari_ini': 0,
        'dedak_padi_kg': 5.5,
        'catatan_kejadian_khusus': '',
        'legacy_key': 'Lama',
      });
      expect(display['Mortalitas Hari Ini'], '0 ekor');
      expect(display['Dedak Padi'], '5.5 kg');
      expect(display['Legacy Key'], 'Lama');
      expect(display.containsKey('Catatan Kejadian Khusus'), isFalse);
    },
  );
  test(
    'validation accepts zero and rejects NaN, infinity, negative, percentage and invalid dates',
    () {
      validateLogbookDetails('ayam_kampung', {'mortalitas_hari_ini': 0});
      for (final value in ['NaN', 'Infinity', 'abc', '-1']) {
        expect(
          () =>
              validateLogbookDetails('ayam_kampung', {'dedak_padi_kg': value}),
          throwsArgumentError,
        );
      }
      expect(
        () => validateLogbookDetails('maggot_bsf', {
          'kadar_air_limbah_persen': 101,
        }),
        throwsArgumentError,
      );
      expect(
        () => validateLogbookDetails('lele', {'ph_air': 15}),
        throwsArgumentError,
      );
      expect(
        () =>
            validateLogbookDetails('tanaman', {'tanggal_tanam': '31/02/2026'}),
        throwsArgumentError,
      );
      validateLogbookDetails('tanaman', {'tanggal_tanam': '16/10/2026'});
      expect(
        () => validateLogbookDetails('ayam_kampung', {}),
        throwsArgumentError,
      );
    },
  );
  test(
    'estimates, seed amount, and L/m2 doses do not create stock or production',
    () {
      for (final module in ['maggot_bsf', 'cacing_tanah', 'tanaman']) {
        expect(
          mapLogbookDetailsToInventoryActions(
            moduleType: module,
            details: {
              'estimasi_panen_kg': 10,
              'media_cacing_kg': 2,
              'pupuk_kascing_cair_liter': 3,
            },
            logbookId: 'id',
          ),
          isEmpty,
        );
      }
      final feed = mapLogbookDetailsToInventoryActions(
        moduleType: 'lele',
        details: {'pakan_maggot_pagi_kg': 2, 'pakan_lele_kg': 3},
        logbookId: 'id',
      );
      expect(feed.single.itemKey, 'maggot_segar');
      expect(feed.single.quantity, 5);
      expect(
        mapLogbookDetailsToInventoryActions(
          moduleType: 'ayam_kampung',
          details: {'dedak_padi_kg': double.infinity},
          logbookId: 'id',
        ),
        isEmpty,
      );
    },
  );
  for (final module in logbookModuleSpecs) {
    testWidgets('list navigation keeps default module ${module.moduleType}', (
      tester,
    ) async {
      final service = FakeLogbook();
      await pump(
        tester,
        LogbookScreen(profile: user('admin'), service: service),
      );
      expect(find.byType(Tab), findsNWidgets(5));
      final tabLabel = module.moduleType == 'ayam_kampung'
          ? 'Modul Ayam'
          : module.moduleType == 'maggot_bsf'
          ? 'Modul Maggot'
          : module.moduleType == 'cacing_tanah'
          ? 'Modul Cacing'
          : module.moduleType == 'tanaman'
          ? 'Modul Tanaman'
          : 'Modul Lele';
      await tester.ensureVisible(find.widgetWithText(Tab, tabLabel));
      await tester.tap(find.widgetWithText(Tab, tabLabel));
      await tester.pumpAndSettle();
      await tester.dragUntilVisible(
        find.text('Daftar Logbook'),
        find.byType(SingleChildScrollView).last,
        const Offset(0, -450),
      );
      await tester.tap(find.text('Daftar Logbook'));
      await tester.pumpAndSettle();
      expect(find.byType(LogbookListScreen), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
      expect(service.filters.last.moduleId, module.moduleType);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
    'list debounce, module/date/order filters, pagination and no overflow',
    (tester) async {
      final service = FakeLogbook()
        ..pages = [
          LogbookPage(
            entries: [
              entry('a'),
              entry('b', title: 'Panen'),
            ],
            hasMore: true,
          ),
          LogbookPage(
            entries: [
              entry('b', title: 'Panen'),
              entry('c', title: 'Catatan baru'),
            ],
            hasMore: false,
          ),
        ];
      await pump(
        tester,
        LogbookListScreen(service: service, userId: 'user', canEdit: true),
      );
      await tester.enterText(find.byType(TextField), 'Panen');
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Pengamatan Ayam'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Pengamatan Ayam'), findsNothing);
      expect(
        find.byWidgetPredicate((w) => w is Text && w.data == 'Panen'),
        findsOneWidget,
      );
      await tester.enterText(find.byType(TextField), '');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.scrollUntilVisible(
        find.text('Muat berikutnya'),
        300,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.text('Muat berikutnya'));
      await tester.pumpAndSettle();
      expect(find.text('Panen'), findsOneWidget);
      expect(find.text('Catatan baru'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Tidak ada data tambahan.'),
        250,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.text('Tidak ada data tambahan.'), findsOneWidget);
      tester
          .state<ScrollableState>(
            find
                .descendant(
                  of: find.byType(ListView),
                  matching: find.byType(Scrollable),
                )
                .first,
          )
          .position
          .jumpTo(0);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tanaman').last);
      await tester.pumpAndSettle();
      expect(service.filters.last.moduleId, 'tanaman');
      await tester.tap(find.byType(DropdownButtonFormField<String>).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hari ini').last);
      await tester.pumpAndSettle();
      expect(service.filters.last.start, isNotNull);
      await tester.tap(find.byType(DropdownButtonFormField<bool>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Terlama').last);
      await tester.pumpAndSettle();
      expect(service.filters.last.newestFirst, false);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('list loading/error/retry/empty states', (tester) async {
    final pending = Completer<LogbookPage>();
    final service = FakeLogbook()..pending = pending;
    await pump(
      tester,
      LogbookListScreen(service: service, userId: 'user', canEdit: false),
      settle: false,
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    pending.completeError(StateError('offline'));
    await tester.pumpAndSettle();
    expect(find.text('Coba lagi'), findsOneWidget);
    service.pending = null;
    await tester.tap(find.text('Coba lagi'));
    await tester.pumpAndSettle();
    expect(find.text('Tidak ada catatan yang cocok.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  for (final role in [
    'admin',
    'operator_lapangan',
    'operator_keuangan',
    'mitra',
  ]) {
    testWidgets('detail actual data and role $role', (tester) async {
      final service = FakeLogbook()..actual = entry('detail');
      await pump(
        tester,
        LogbookDetailScreen(
          service: service,
          entryId: 'detail',
          userId: 'user',
          canEdit: user(role).canManageLogbooks,
        ),
      );
      expect(service.requestedId, 'detail');
      expect(find.text('Mortalitas Hari Ini: 0 ekor'), findsOneWidget);
      expect(
        find.text('Edit Catatan Tambahan'),
        user(role).canManageLogbooks ? findsOneWidget : findsNothing,
      );
      expect(find.byIcon(Icons.delete_outline), findsNothing);
      await tester.tap(find.byTooltip('Muat ulang'));
      await tester.pumpAndSettle();
      expect(service.detailReads, 2);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('detail edits notes only and keeps original details', (
    tester,
  ) async {
    final service = FakeLogbook()..actual = entry('edit');
    await pump(
      tester,
      LogbookDetailScreen(
        service: service,
        entryId: 'edit',
        userId: 'user',
        canEdit: true,
      ),
    );
    await tester.ensureVisible(find.text('Edit Catatan Tambahan'));
    await tester.tap(find.text('Edit Catatan Tambahan'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Baru');
    await tester.tap(find.text('Simpan'));
    await tester.pumpAndSettle();
    expect(service.editedNotes, 'Baru');
    expect(service.actual!.details, {'mortalitas_hari_ini': 0});
    expect(tester.takeException(), isNull);
  });
  testWidgets('save guarded against double tap, returns ID and opens detail', (
    tester,
  ) async {
    final pending = Completer<String>();
    final service = FakeLogbook()..savePending = pending;
    await pump(tester, LogbookScreen(profile: user('admin'), service: service));
    await tester.enterText(find.byType(TextFormField).first, '0');
    await tester.dragUntilVisible(
      find.text('Simpan Catatan'),
      find.byType(SingleChildScrollView).last,
      const Offset(0, -450),
    );
    await tester.tap(find.text('Simpan Catatan'));
    await tester.tap(find.text('Simpan Catatan'));
    await tester.pump();
    expect(service.saveCalls, 1);
    pending.complete('saved');
    service.actual = entry('saved');
    await tester.pumpAndSettle();
    final button = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Simpan Catatan'),
    );
    expect(button.onPressed, isNull);
    await tester.tap(find.text('Lihat Catatan'));
    await tester.pumpAndSettle();
    expect(service.requestedId, 'saved');
    expect(find.byType(LogbookDetailScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('failed save retains input and retry request ID', (tester) async {
    final service = FakeLogbook()..failSave = true;
    await pump(tester, LogbookScreen(profile: user('admin'), service: service));
    await tester.enterText(find.byType(TextFormField).first, '7');
    await tester.dragUntilVisible(
      find.text('Simpan Catatan'),
      find.byType(SingleChildScrollView).last,
      const Offset(0, -450),
    );
    await tester.tap(find.text('Simpan Catatan'));
    await tester.pumpAndSettle();
    final key = service.savedRequestId;
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    service.failSave = false;
    await tester.ensureVisible(find.text('Simpan Catatan'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Simpan Catatan'));
    await tester.pumpAndSettle();
    expect(service.savedRequestId, key);
    expect(service.saveCalls, 2);
    await tester.drag(
      find.byType(SingleChildScrollView).last,
      const Offset(0, 1400),
    );
    await tester.pumpAndSettle();
    expect(find.text('7'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
  testWidgets('cancel custom date range restores the active date filter', (
    tester,
  ) async {
    final service = FakeLogbook();
    await pump(
      tester,
      LogbookListScreen(service: service, userId: 'user', canEdit: false),
    );
    await tester.tap(find.byType(DropdownButtonFormField<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rentang tanggal').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.text('Semua tanggal'), findsOneWidget);
    expect(service.filters.length, 1);
  });
  testWidgets('late old filter response cannot replace newer filtered result', (
    tester,
  ) async {
    final old = Completer<LogbookPage>();
    final service = FakeLogbook()..pending = old;
    await pump(
      tester,
      LogbookListScreen(service: service, userId: 'user', canEdit: false),
      settle: false,
    );
    service.pending = null;
    service.pages = [
      LogbookPage(
        entries: [entry('new', title: 'Hasil filter terbaru')],
        hasMore: false,
      ),
    ];
    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Tanaman').last);
    await tester.pumpAndSettle();
    old.complete(
      LogbookPage(entries: [entry('old', title: 'Hasil lama')], hasMore: false),
    );
    await tester.pumpAndSettle();
    expect(find.text('Hasil lama'), findsNothing);
    expect(find.text('Hasil filter terbaru'), findsOneWidget);
  });
  testWidgets('invalid numeric form rejects before service save', (
    tester,
  ) async {
    final service = FakeLogbook();
    await pump(tester, LogbookScreen(profile: user('admin'), service: service));
    await tester.enterText(find.byType(TextFormField).first, 'NaN');
    await tester.dragUntilVisible(
      find.text('Simpan Catatan'),
      find.byType(SingleChildScrollView).last,
      const Offset(0, -450),
    );
    await tester.tap(find.text('Simpan Catatan'));
    await tester.pumpAndSettle();
    expect(service.saveCalls, 0);
    expect(find.textContaining('masukkan angka yang valid'), findsOneWidget);
  });
  testWidgets(
    'detail error, retry, missing entry and related error are honest',
    (tester) async {
      final service = FakeLogbook()..failDetail = true;
      await pump(
        tester,
        LogbookDetailScreen(
          service: service,
          entryId: 'missing',
          userId: 'user',
          canEdit: false,
        ),
      );
      expect(find.text('Detail gagal dimuat.'), findsOneWidget);
      service.failDetail = false;
      await tester.tap(find.text('Coba lagi'));
      await tester.pumpAndSettle();
      expect(
        find.text('Catatan tidak tersedia atau sudah dibatalkan.'),
        findsOneWidget,
      );
      service.actual = entry('found');
      service.failLinks = true;
      await tester.tap(find.byTooltip('Muat ulang'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Data terkait gagal dimuat.'),
        300,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      service.failLinks = false;
      await tester.ensureVisible(find.text('Coba lagi data terkait'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Coba lagi data terkait'));
      await tester.pumpAndSettle();
      expect(
        find.text('Tidak ada transaksi inventaris terkait.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}

class FakeLogbook extends LogbookService {
  FakeLogbook() : super(firestore: NoFirestore());
  List<LogbookFilter> filters = [];
  List<LogbookPage> pages = [];
  int pageIndex = 0;
  Completer<LogbookPage>? pending;
  Completer<String>? savePending;
  LogbookEntry? actual;
  String? requestedId, editedNotes, savedRequestId;
  int detailReads = 0, saveCalls = 0;
  bool failSave = false;
  bool failDetail = false;
  bool failLinks = false;
  @override
  Future<LogbookPage> getPage({
    required LogbookFilter filter,
    DocumentSnapshot<Map<String, dynamic>>? cursor,
  }) async {
    filters.add(filter);
    if (pending != null) return pending!.future;
    return pages.isEmpty
        ? const LogbookPage(entries: [], hasMore: false)
        : pages[(pageIndex++).clamp(0, pages.length - 1)];
  }

  @override
  Future<LogbookEntry?> getEntry(String id) async {
    if (failDetail) throw StateError('offline');
    requestedId = id;
    detailReads++;
    return actual;
  }

  @override
  Future<LogbookLinks> getLinks(String id) async {
    if (failLinks) throw StateError('offline');
    return const LogbookLinks();
  }

  @override
  Future<void> updateNotes(
    String id, {
    required String notes,
    required String userId,
    required DateTime expectedUpdatedAt,
  }) async {
    editedNotes = notes;
  }

  @override
  Future<List<InventoryStockWarning>> previewInventoryStockWarnings({
    required String moduleType,
    required Map<String, dynamic> details,
  }) async => [];
  @override
  Future<String> createDailyEntry({
    String? requestId,
    String? batchId,
    required String moduleType,
    required String title,
    required String activityType,
    required double? quantity,
    required String? unit,
    required String? notes,
    required Map<String, dynamic> details,
    required String userId,
  }) async {
    saveCalls++;
    savedRequestId = requestId;
    if (failSave) throw StateError('offline');
    return savePending?.future ?? Future.value(requestId ?? 'saved');
  }
}

class NoFirestore implements FirebaseFirestore {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
