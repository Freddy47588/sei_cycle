import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sei_cycle/features/batches/models/cultivation_batch.dart';
import 'package:sei_cycle/features/batches/services/batch_service.dart';
import 'package:sei_cycle/features/batches/screen/batch_list_screen.dart';
import 'package:sei_cycle/features/batches/screen/batch_detail_screen.dart';
import 'package:sei_cycle/features/batches/screen/batch_form_screen.dart';
import 'package:sei_cycle/features/logbook/screen/logbook_screen.dart';
import 'package:sei_cycle/features/logbook/services/logbook_service.dart';
import 'package:sei_cycle/features/profile/models/app_user.dart';
import 'package:sei_cycle/theme/app_theme.dart';
import 'support/memory_firestore.dart';

const capture = bool.fromEnvironment('CAPTURE_UI');
final day = DateTime(2026, 10, 16);
AppUser profile({bool active = true, String role = 'operator_lapangan'}) =>
    AppUser(
      uid: 'field',
      name: 'Petugas',
      email: '',
      photoUrl: '',
      role: role,
      isActive: active,
      createdAt: day,
      updatedAt: day,
    );
Map<String, dynamic> batchDoc(
  String id, {
  String module = 'lele',
  String status = 'active',
}) => {
  'id': id,
  'code': id,
  'name': 'Siklus $id',
  'moduleType': module,
  'locationName': 'Kolam Utara',
  'status': status,
  'startedAt': Timestamp.fromDate(day),
  'expectedHarvestAt': null,
  'initialQuantity': 500,
  'initialUnit': 'ekor',
  'commodity': '',
  'notes': 'Pengamatan aktual',
  'completedAt': null,
  'createdBy': 'field',
  'updatedBy': 'field',
  'createdAt': Timestamp.fromDate(day),
  'updatedAt': Timestamp.fromDate(day),
  'isDeleted': false,
};

class RecordingBatches extends BatchService {
  RecordingBatches(this.db) : super(firestore: db);
  final MemoryFirestore db;
  final calls = <(String?, String?, bool, bool)>[];
  Completer<BatchPage>? pending;
  bool fail = false;
  int createCalls = 0;
  Completer<String>? createPending;
  @override
  Future<String> create(BatchInput input, {required String userId}) {
    createCalls++;
    return createPending?.future ?? super.create(input, userId: userId);
  }

  @override
  Future<BatchPage> getPage({
    String? moduleType,
    String? status,
    bool newestFirst = true,
    DocumentSnapshot<Map<String, dynamic>>? cursor,
  }) {
    calls.add((moduleType, status, newestFirst, cursor != null));
    if (pending != null) {
      final p = pending!;
      pending = null;
      return p.future;
    }
    if (fail) return Future.error(StateError('offline'));
    return super.getPage(
      moduleType: moduleType,
      status: status,
      newestFirst: newestFirst,
      cursor: cursor,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await initializeDateFormatting('id_ID');
    if (capture) {
      final root = Platform.environment['FLUTTER_ROOT'] ?? 'C:/src/flutter';
      for (final family in ['Roboto', 'Ahem', 'MaterialIcons']) {
        final file = File(
          '$root/bin/cache/artifacts/material_fonts/${family == 'MaterialIcons' ? 'materialicons-regular.otf' : 'Roboto-Regular.ttf'}',
        );
        if (file.existsSync()) {
          await (FontLoader(family)..addFont(
                Future.value(ByteData.sublistView(file.readAsBytesSync())),
              ))
              .load();
        }
      }
    }
  });
  late MemoryFirestore db;
  late RecordingBatches batches;
  late LogbookService logbooks;
  setUp(() {
    db = MemoryFirestore();
    batches = RecordingBatches(db);
    logbooks = LogbookService(firestore: db);
    db.documents['users/field'] = {
      'uid': 'field',
      'role': 'operator_lapangan',
      'isActive': true,
    };
  });
  Widget list({bool canManage = true, bool select = false}) => BatchListScreen(
    service: batches,
    logbookService: logbooks,
    userId: 'field',
    canManage: canManage,
    selectActive: select,
    initialModule: select ? 'lele' : null,
  );
  Future<void> pump(
    WidgetTester t,
    Widget widget, {
    double width = 600,
    double scale = 1,
  }) async {
    t.view.physicalSize = Size(width, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        builder: (c, child) => MediaQuery(
          data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: widget,
      ),
    );
    await t.pumpAndSettle();
  }

  testWidgets(
    'list opens, filters module/status, sorts and searches loaded records',
    (t) async {
      db.documents['batches/KOLAM-A'] = batchDoc('KOLAM-A');
      db.documents['batches/AYAM-A'] = batchDoc(
        'AYAM-A',
        module: 'ayam_kampung',
        status: 'planned',
      );
      await pump(t, list());
      expect(find.text('Manajemen Batch Budidaya'), findsWidgets);
      await t.tap(find.byType(DropdownButtonFormField<String>).first);
      await t.pumpAndSettle();
      await t.tap(find.text('Lele').last);
      await t.pumpAndSettle();
      expect(batches.calls.last.$1, 'lele');
      await t.tap(find.byType(DropdownButtonFormField<String>).last);
      await t.pumpAndSettle();
      await t.tap(find.text('Aktif').last);
      await t.pumpAndSettle();
      expect(batches.calls.last.$2, 'active');
      await t.tap(find.byType(DropdownButton<bool>));
      await t.pumpAndSettle();
      await t.tap(find.text('Terlama').last);
      await t.pumpAndSettle();
      expect(batches.calls.last.$3, isFalse);
      await t.enterText(find.byType(TextField).first, 'tidak cocok');
      await t.pumpAndSettle();
      expect(
        find.text('Tidak ada hasil pada data yang dimuat.'),
        findsOneWidget,
      );
      await t.enterText(find.byType(TextField).first, 'KOLAM-A');
      await t.pumpAndSettle();
      expect(find.text('Siklus KOLAM-A'), findsOneWidget);
    },
  );
  testWidgets('pagination passes cursor and renders each batch once', (
    t,
  ) async {
    for (var n = 0; n < 21; n++) {
      db.documents['batches/PAGE-$n'] = batchDoc('PAGE-$n');
    }
    await pump(t, list());
    await t.scrollUntilVisible(
      find.text('Muat lebih banyak'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await t.tap(find.text('Muat lebih banyak'));
    await t.pumpAndSettle();
    expect(batches.calls.last.$4, isTrue);
    await t.scrollUntilVisible(
      find.text('Semua halaman telah dimuat.'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Semua halaman telah dimuat.'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets('empty, loading, error and retry states with no invented data', (
    t,
  ) async {
    final pending = Completer<BatchPage>();
    batches.pending = pending;
    await t.pumpWidget(MaterialApp(home: list()));
    await t.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    pending.completeError(StateError('offline'));
    await t.pumpAndSettle();
    expect(find.text('Daftar batch gagal dimuat.'), findsOneWidget);
    await t.tap(find.text('Coba lagi'));
    await t.pumpAndSettle();
    expect(find.text('Belum ada batch sesuai filter.'), findsOneWidget);
  });
  testWidgets('active picker locks module/status and explains absence', (
    t,
  ) async {
    await pump(t, list(select: true));
    expect(batches.calls.single.$1, 'lele');
    expect(batches.calls.single.$2, 'active');
    for (final field in t.widgetList<DropdownButtonFormField<String>>(
      find.byType(DropdownButtonFormField<String>),
    )) {
      expect(field.onChanged, isNull);
    }
    expect(find.textContaining('Belum ada batch aktif'), findsOneWidget);
    expect(find.text('Tambah Batch'), findsOneWidget);
  });
  testWidgets('read-only list exposes no create action', (t) async {
    await pump(t, list(canManage: false));
    expect(find.text('Tambah Batch'), findsNothing);
  });
  testWidgets('detail displays actual metadata and only linked logbooks', (
    t,
  ) async {
    db.documents['batches/KOLAM-A'] = batchDoc('KOLAM-A', status: 'completed')
      ..['completedAt'] = Timestamp.fromDate(day);
    db.documents['logbooks/actual'] = {
      'id': 'actual',
      'batchId': 'KOLAM-A',
      'title': 'Pemeriksaan Kolam',
      'moduleType': 'lele',
      'activityDate': Timestamp.fromDate(day),
      'notes': 'Air teramati',
      'details': {},
      'isDeleted': false,
    };
    db.documents['logbooks/other'] = {
      'id': 'other',
      'batchId': 'OTHER',
      'title': 'Jangan tampil',
      'activityDate': Timestamp.fromDate(day),
      'isDeleted': false,
    };
    await pump(
      t,
      BatchDetailScreen(
        batchId: 'KOLAM-A',
        service: batches,
        logbookService: logbooks,
        userId: 'field',
        canManage: false,
      ),
    );
    expect(find.text('Jumlah awal: 500.0 ekor'), findsOneWidget);
    expect(find.text('Status: Selesai'), findsOneWidget);
    await t.scrollUntilVisible(
      find.text('Pemeriksaan Kolam'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Pemeriksaan Kolam'), findsOneWidget);
    expect(find.text('Jangan tampil'), findsNothing);
    expect(find.text('Edit Batch'), findsNothing);
    expect(find.textContaining('Ubah ke'), findsNothing);
  });
  testWidgets(
    'selection survives unrelated input rebuild and switching original tabs',
    (t) async {
      db.documents['batches/AYAM-A'] = batchDoc(
        'AYAM-A',
        module: 'ayam_kampung',
      );
      await pump(
        t,
        Scaffold(
          body: LogbookScreen(profile: profile(), service: logbooks),
        ),
      );
      await t.tap(find.text('Pilih batch ayam yang aktif'));
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Pilih Batch'));
      await t.tap(find.text('Pilih Batch'));
      await t.pumpAndSettle();
      expect(find.text('Siklus AYAM-A (AYAM-A)'), findsOneWidget);
      await t.enterText(find.byType(TextFormField).first, '10');
      await t.pump();
      expect(find.text('Siklus AYAM-A (AYAM-A)'), findsOneWidget);
      final plantTab = find.descendant(
        of: find.byType(TabBar),
        matching: find.text('Modul Tanaman'),
      );
      await t.ensureVisible(plantTab);
      await t.pumpAndSettle();
      await t.tap(plantTab);
      await t.pumpAndSettle();
      final chickenTab = find.descendant(
        of: find.byType(TabBar),
        matching: find.text('Modul Ayam'),
      );
      await t.ensureVisible(chickenTab);
      await t.pumpAndSettle();
      await t.tap(chickenTab);
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Siklus AYAM-A (AYAM-A)'));
      expect(find.text('Siklus AYAM-A (AYAM-A)'), findsOneWidget);
      await t.scrollUntilVisible(
        find.text('Simpan Catatan'),
        400,
        scrollable: find.byType(Scrollable).last,
      );
      await t.tap(find.text('Simpan Catatan'));
      await t.pumpAndSettle();
      expect(
        db.documents.entries
            .where((e) => e.key.startsWith('logbooks/'))
            .single
            .value['batchId'],
        'AYAM-A',
      );
    },
  );
  testWidgets(
    'batch form rejects invalid input and blocks concurrent submission',
    (t) async {
      final pending = Completer<String>();
      batches.createPending = pending;
      await pump(
        t,
        BatchFormScreen(
          service: batches,
          userId: 'field',
          initialModule: 'lele',
        ),
      );
      await t.enterText(
        find.widgetWithText(TextFormField, 'Nama batch'),
        'Siklus Kolam',
      );
      await t.enterText(
        find.widgetWithText(TextFormField, 'Nama / nomor kolam'),
        'Kolam A',
      );
      await t.enterText(
        find.widgetWithText(TextFormField, 'Jumlah awal (opsional)'),
        '-1',
      );
      await t.scrollUntilVisible(
        find.text('Simpan Batch'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await t.ensureVisible(find.text('Simpan Batch'));
      await t.pumpAndSettle();
      await t.tap(find.text('Simpan Batch'));
      await t.pumpAndSettle();
      expect(batches.createCalls, 0);
      expect(find.textContaining('Gagal menyimpan:'), findsOneWidget);
      await t.ensureVisible(
        find.widgetWithText(TextFormField, 'Jumlah awal (opsional)'),
      );
      await t.enterText(
        find.widgetWithText(TextFormField, 'Jumlah awal (opsional)'),
        '500',
      );
      await t.enterText(
        find.widgetWithText(TextFormField, 'Unit jumlah awal'),
        'ekor',
      );
      await t.ensureVisible(find.text('Simpan Batch'));
      await t.ensureVisible(find.text('Simpan Batch'));
      await t.pumpAndSettle();
      await t.tap(find.text('Simpan Batch'));
      await t.pump();
      expect(batches.createCalls, 1);
      final button = t.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Menyimpan...'),
      );
      expect(button.onPressed, isNull);
      await t.pumpWidget(const MaterialApp(home: SizedBox()));
      pending.complete('SAVED');
      await t.pumpAndSettle();
    },
  );
  testWidgets(
    'detail status action completes cycle without stock or harvest writes',
    (t) async {
      db.documents['batches/KOLAM-A'] = batchDoc('KOLAM-A');
      await pump(
        t,
        BatchDetailScreen(
          batchId: 'KOLAM-A',
          service: batches,
          logbookService: logbooks,
          userId: 'field',
          canManage: true,
        ),
      );
      await t.ensureVisible(find.text('Ubah ke Selesai'));
      await t.tap(find.text('Ubah ke Selesai'));
      await t.pumpAndSettle();
      await t.tap(find.text('Ubah Status'));
      await t.pumpAndSettle();
      expect(find.text('Status: Selesai'), findsOneWidget);
      expect(db.documents['batches/KOLAM-A']!['completedAt'], isA<Timestamp>());
      expect(
        db.documents.keys.where(
          (k) =>
              k.startsWith('inventory/') || k.startsWith('production_results/'),
        ),
        isEmpty,
      );
    },
  );
  testWidgets(
    'activity pagination and detail navigation use actual logbook ID',
    (t) async {
      db.documents['batches/KOLAM-A'] = batchDoc('KOLAM-A');
      for (var n = 0; n < 21; n++) {
        db.documents['logbooks/entry-$n'] = {
          'id': 'entry-$n',
          'batchId': 'KOLAM-A',
          'title': 'Aktivitas $n',
          'moduleType': 'lele',
          'activityDate': Timestamp.fromDate(day),
          'notes': 'Pengamatan',
          'details': {},
          'isDeleted': false,
        };
      }
      await pump(
        t,
        BatchDetailScreen(
          batchId: 'KOLAM-A',
          service: batches,
          logbookService: logbooks,
          userId: 'field',
          canManage: false,
        ),
      );
      await t.scrollUntilVisible(
        find.text('Muat aktivitas berikutnya'),
        500,
        scrollable: find.byType(Scrollable).first,
      );
      await t.ensureVisible(find.text('Muat aktivitas berikutnya'));
      await t.pumpAndSettle();
      await t.tap(find.text('Muat aktivitas berikutnya'));
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        find.text('Seluruh halaman aktivitas telah dimuat.'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.text('Seluruh halaman aktivitas telah dimuat.'),
        findsOneWidget,
      );
      await t.ensureVisible(find.text('Lihat Detail Logbook').last);
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Lihat Detail Logbook').last);
      await t.pumpAndSettle();
      await t.tap(find.text('Lihat Detail Logbook').last);
      await t.pumpAndSettle();
      expect(find.text('Detail Logbook'), findsOneWidget);
      expect(find.text('Batch: KOLAM-A'), findsOneWidget);
      expect(find.text('Belum terhubung ke batch'), findsNothing);
    },
  );
  for (final width in [320.0, 1280.0]) {
    for (final page in ['list', 'detail', 'form']) {
      testWidgets('$page fits $width at text scale 1.4', (t) async {
        db.documents['batches/KOLAM-A'] = batchDoc('KOLAM-A');
        final boundary = GlobalKey();
        final widget = switch (page) {
          'list' => list(),
          'detail' => BatchDetailScreen(
            batchId: 'KOLAM-A',
            service: batches,
            logbookService: logbooks,
            userId: 'field',
            canManage: true,
          ),
          _ => BatchFormScreen(
            service: batches,
            userId: 'field',
            initialModule: 'lele',
          ),
        };
        await pump(
          t,
          RepaintBoundary(key: boundary, child: widget),
          width: width,
          scale: 1.4,
        );
        expect(t.takeException(), isNull);
        if (capture) {
          await t.runAsync(() async {
            final img =
                await (boundary.currentContext!.findRenderObject()
                        as RenderRepaintBoundary)
                    .toImage(pixelRatio: 1);
            final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
            final file = File('build/phase03/$page-${width.toInt()}.png');
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes!.buffer.asUint8List());
            img.dispose();
          });
        }
        await t.drag(find.byType(ListView).first, const Offset(0, -600));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
      });
    }
  }
}
