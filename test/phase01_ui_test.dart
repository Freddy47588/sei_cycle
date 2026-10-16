import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sei_cycle/app/app_shell.dart';
import 'package:sei_cycle/features/dashboard/models/dashboard_summary.dart';
import 'package:sei_cycle/features/dashboard/screen/dashboard_screen.dart';
import 'package:sei_cycle/features/dashboard/services/dashboard_service.dart';
import 'package:sei_cycle/features/education/models/education_content.dart';
import 'package:sei_cycle/features/education/screen/education_screen.dart';
import 'package:sei_cycle/features/inventory/services/inventory_service.dart';
import 'package:sei_cycle/features/logbook/screen/logbook_screen.dart';
import 'package:sei_cycle/features/logbook/services/logbook_service.dart';
import 'package:sei_cycle/features/notification/models/app_notification.dart';
import 'package:sei_cycle/features/notification/screen/notification_screen.dart';
import 'package:sei_cycle/features/profile/models/app_user.dart';
import 'package:sei_cycle/theme/app_theme.dart';

const _capture = bool.fromEnvironment('CAPTURE_UI');
final _boundary = GlobalKey();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await initializeDateFormatting('id_ID');
    if (_capture) {
      final flutterRoot = Platform.environment['FLUTTER_ROOT'];
      if (flutterRoot != null) {
        final font = File(
          '$flutterRoot/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
        );
        if (font.existsSync()) {
          final loader = FontLoader('Roboto')
            ..addFont(
              Future.value(ByteData.sublistView(font.readAsBytesSync())),
            );
          await loader.load();
          final fallbackFont = FontLoader('Ahem')
            ..addFont(
              Future.value(ByteData.sublistView(font.readAsBytesSync())),
            );
          await fallbackFont.load();
          final icons = File(
            '$flutterRoot/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
          );
          final iconLoader = FontLoader('MaterialIcons')
            ..addFont(
              Future.value(ByteData.sublistView(icons.readAsBytesSync())),
            );
          await iconLoader.load();
        }
      }
    }
  });

  test(
    'empty Firestore results do not become demo activities or revenue',
    () async {
      final database = _EmptyFirestore();
      final summary = await DashboardService(
        firestore: database,
      ).load(includeFinance: false);
      expect(summary.activeModuleCount, 0);
      expect(summary.recentActivities, isEmpty);
      expect(summary.revenueItems, isEmpty);
      expect(summary.circularFlows, isEmpty);
      expect(summary.financeVisible, isFalse);
      expect(database.collections, isNot(contains('finance_transactions')));
    },
  );

  for (final width in [320.0, 600.0, 768.0, 1280.0]) {
    for (final role in ['admin', 'operator_lapangan', 'operator_keuangan']) {
      testWidgets(
        'navigation $role at $width retains allowed destinations and badge',
        (tester) async {
          await _pump(
            tester,
            AppShell(
              profile: _user(role),
              unreadCountStream: Stream.value(7),
              pageBuilder: (label) => Center(child: Text('Halaman $label')),
            ),
            width: width,
          );
          expect(find.text('7'), findsOneWidget);
          for (final label in [
            'Dashboard',
            'Logbook',
            'Edukasi',
            'Notifikasi',
          ]) {
            expect(find.text(label), findsWidgets);
          }
          if (width < AppBreakpoints.desktop) {
            await tester.tap(find.text('Lainnya'));
            await tester.pumpAndSettle();
          }
          expect(
            find.text('Keuangan'),
            role == 'operator_lapangan' ? findsNothing : findsOneWidget,
          );
          for (final label in [
            'Inventaris',
            'Jadwal',
            'Rekomendasi',
            'Laporan',
            'Profil',
          ]) {
            expect(find.text(label), findsOneWidget);
          }
          await tester.ensureVisible(find.text('Laporan'));
          await tester.tap(find.text('Laporan'));
          await tester.pumpAndSettle();
          expect(find.text('Halaman Laporan'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'dashboard loading and errors never present demo values or Live',
    (tester) async {
      final pending = Completer<DashboardSummary>();
      await _pump(
        tester,
        DashboardScreen(
          profile: _user('admin'),
          summaryLoader: ({required includeFinance}) => pending.future,
        ),
        settle: false,
      );
      expect(find.text('Memuat'), findsOneWidget);
      expect(find.text('Live'), findsNothing);
      expect(find.textContaining('Rp 20'), findsNothing);
      pending.completeError(StateError('offline'));
      await tester.pumpAndSettle();
      expect(find.text('Gagal'), findsOneWidget);
      expect(find.text('Coba lagi'), findsOneWidget);
      expect(find.text('Live'), findsNothing);
      expect(find.text('0'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'finance summary stays hidden for field operators even if supplied',
    (tester) async {
      bool? requestedFinance;
      await _pump(
        tester,
        DashboardScreen(
          profile: _user('operator_lapangan'),
          summaryLoader: ({required includeFinance}) async {
            requestedFinance = includeFinance;
            return _summary;
          },
        ),
      );
      expect(requestedFinance, isFalse);
      expect(find.textContaining('Rincian Omset'), findsNothing);
      expect(find.textContaining('Rp '), findsNothing);
      expect(find.text('Belum ada aktivitas hari ini'), findsOneWidget);
    },
  );

  for (final module in ['Ayam', 'Maggot', 'Cacing', 'Tanaman', 'Lele']) {
    testWidgets(
      '$module form keeps inputs and sends observations through save',
      (tester) async {
        final service = _RecordingLogbookService();
        await _pump(
          tester,
          LogbookScreen(profile: _user('admin'), service: service),
          width: 320,
        );
        await tester.ensureVisible(find.text('Modul $module').first);
        await tester.tap(find.text('Modul $module').first);
        await tester.pumpAndSettle();
        final fields = find.byType(TextFormField);
        expect(fields, findsWidgets);
        for (final field in tester.widgetList<TextFormField>(fields)) {
          expect(field.initialValue, isEmpty);
        }
        await tester.enterText(
          fields.first,
          module == 'Tanaman' ? 'Kangkung uji' : '7',
        );
        FocusManager.instance.primaryFocus?.unfocus();
        tester.testTextInput.hide();
        await tester.pump();
        await tester.ensureVisible(find.text('Simpan Catatan'));
        await tester.tap(find.text('Simpan Catatan'));
        await tester.pumpAndSettle();
        expect(
          service.savedModule,
          {
            'Ayam': 'ayam_kampung',
            'Maggot': 'maggot_bsf',
            'Cacing': 'cacing_tanah',
            'Tanaman': 'tanaman',
            'Lele': 'lele',
          }[module],
        );
        expect(
          service.savedDetails!.values,
          contains(module == 'Tanaman' ? 'Kangkung uji' : 7.0),
        );
        expect(service.savedDetails!['fase_larva_hari'], isNull);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('read only logbook role cannot save', (tester) async {
    await _pump(
      tester,
      LogbookScreen(profile: _user('operator_keuangan')),
      width: 320,
    );
    await tester.ensureVisible(find.text('Simpan Catatan'));
    final button = tester.widget<ElevatedButton>(
      find.ancestor(
        of: find.text('Simpan Catatan'),
        matching: find.byType(ElevatedButton),
      ),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('empty form cannot create an unobserved logbook entry', (
    tester,
  ) async {
    final service = _RecordingLogbookService();
    await _pump(
      tester,
      LogbookScreen(profile: _user('admin'), service: service),
      width: 320,
    );
    await tester.ensureVisible(find.text('Simpan Catatan'));
    await tester.tap(find.text('Simpan Catatan'));
    await tester.pumpAndSettle();
    expect(service.savedDetails, isNull);
    expect(
      find.text('Isi hasil pengamatan sebelum menyimpan catatan.'),
      findsOneWidget,
    );
  });

  testWidgets('logbook save remains reachable above the keyboard', (
    tester,
  ) async {
    await _pump(tester, LogbookScreen(profile: _user('admin')), width: 320);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Simpan Catatan'));
    await tester.pumpAndSettle();
    expect(
      tester.getRect(find.text('Simpan Catatan')).bottom,
      lessThanOrEqualTo(600),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'education search filters supplied content and retains thumbnails',
    (tester) async {
      await _pump(
        tester,
        EducationScreen(
          profile: _user('operator_lapangan'),
          contents: Stream.value([
            _education('Ayam uji'),
            _education('Maggot uji'),
          ]),
        ),
      );
      await tester.enterText(find.byType(TextField).first, '  ayam  ');
      await tester.pumpAndSettle();
      expect(find.text('Ayam uji'), findsOneWidget);
      expect(find.text('Maggot uji'), findsNothing);
      await tester.enterText(find.byType(TextField).first, 'tidak ditemukan');
      await tester.pumpAndSettle();
      expect(find.text('Materi tidak ditemukan'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final page in ['education', 'notification']) {
    testWidgets('$page shows honest loading, empty, and error states', (
      tester,
    ) async {
      final contents = StreamController<List<EducationContent>>();
      final notifications = StreamController<List<AppNotification>>();
      await _pump(
        tester,
        page == 'education'
            ? EducationScreen(
                profile: _user('operator_lapangan'),
                contents: contents.stream,
              )
            : NotificationScreen(
                profile: _user('operator_lapangan'),
                notifications: notifications.stream,
              ),
        settle: false,
      );
      expect(find.text('Memuat data...'), findsOneWidget);
      contents.add([]);
      notifications.add([]);
      await tester.pumpAndSettle();
      expect(
        find.text(
          page == 'education'
              ? 'Belum ada materi edukasi'
              : 'Belum ada notifikasi',
        ),
        findsOneWidget,
      );
      if (page == 'education') {
        contents.addError(StateError('offline'));
      } else {
        notifications.addError(StateError('offline'));
      }
      await tester.pumpAndSettle();
      expect(find.text('Data belum dapat dimuat'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      if (page == 'education') {
        unawaited(contents.close());
      } else {
        unawaited(notifications.close());
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('read notification exposes read indicator', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pump(
      tester,
      NotificationScreen(
        profile: _user('operator_lapangan'),
        notifications: Stream.value([_notification]),
      ),
    );
    expect(find.bySemanticsLabel(RegExp('Sudah dibaca')), findsOneWidget);
    expect(find.text('Jadwal Terlewat'), findsOneWidget);
    semantics.dispose();
  });

  for (final width in [320.0, 600.0, 768.0, 1280.0]) {
    testWidgets('main pages fit $width and produce review captures', (
      tester,
    ) async {
      final profile = _user('admin');
      final pages = <String, Widget>{
        'dashboard': DashboardScreen(
          profile: profile,
          summaryLoader: ({required includeFinance}) async => _summary,
        ),
        'logbook': LogbookScreen(profile: profile),
        'education': EducationScreen(
          profile: profile,
          contents: Stream.value([
            _education('Panduan budidaya ayam'),
            _education('SOP pakan harian'),
          ]),
        ),
        'notification': NotificationScreen(
          profile: profile,
          notifications: Stream.value([_notification]),
        ),
      };
      for (final page in pages.entries) {
        final labels = {
          'dashboard': 'Dashboard',
          'logbook': 'Logbook',
          'education': 'Edukasi',
          'notification': 'Notifikasi',
        };
        await _pump(
          tester,
          AppShell(
            profile: profile,
            unreadCountStream: Stream.value(0),
            pageBuilder: (_) => page.value,
          ),
          width: width,
        );
        final navigation = width < AppBreakpoints.desktop
            ? find.byType(NavigationBar)
            : find.byType(ListView).first;
        await tester.tap(
          find
              .descendant(
                of: navigation,
                matching: find.text(labels[page.key]!),
              )
              .first,
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: page.key);
        if (_capture) {
          await _saveCapture(tester, '${page.key}-${width.toInt()}');
          if (page.key == 'dashboard') {
            await tester.drag(
              find.byType(SingleChildScrollView).first,
              const Offset(0, -1600),
            );
            await tester.pumpAndSettle();
            await _saveCapture(tester, 'dashboard-bottom-${width.toInt()}');
          }
          if (page.key == 'logbook') {
            await tester.ensureVisible(find.text('Modul Tanaman').first);
            await tester.tap(find.text('Modul Tanaman').first);
            await tester.pumpAndSettle();
            await _saveCapture(tester, 'logbook-tanaman-${width.toInt()}');
          }
        }
      }
    });
  }

  testWidgets('main content fits narrow screens with enlarged text', (
    tester,
  ) async {
    final profile = _user('operator_lapangan');
    for (final page in <Widget>[
      DashboardScreen(
        profile: profile,
        summaryLoader: ({required includeFinance}) async => _summary,
      ),
      LogbookScreen(profile: profile),
      EducationScreen(
        profile: profile,
        contents: Stream.value([_education('Panduan uji')]),
      ),
      NotificationScreen(
        profile: profile,
        notifications: Stream.value([_notification]),
      ),
    ]) {
      await _pump(tester, page, width: 320, textScale: 1.4);
      expect(tester.takeException(), isNull, reason: '${page.runtimeType}');
    }
  });
}

Future<void> _pump(
  WidgetTester tester,
  Widget page, {
  double width = 390,
  bool settle = true,
  double textScale = 1,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      theme: AppTheme.lightTheme.copyWith(
        textTheme: AppTheme.lightTheme.textTheme.apply(
          fontFamily: _capture ? 'Roboto' : null,
        ),
      ),
      home: RepaintBoundary(
        key: _boundary,
        child: Scaffold(body: page),
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

Future<void> _saveCapture(WidgetTester tester, String name) async {
  final boundary =
      _boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final originalShadows = debugDisableShadows;
  debugDisableShadows = false;
  boundary.markNeedsPaint();
  await tester.pump();
  try {
    await tester.runAsync(() async {
      final rendered = await boundary.toImage();
      final data = await rendered.toByteData(format: ui.ImageByteFormat.png);
      final dir = Directory('build/phase01')..createSync(recursive: true);
      File(
        '${dir.path}/$name.png',
      ).writeAsBytesSync(data!.buffer.asUint8List());
      rendered.dispose();
    });
  } finally {
    debugDisableShadows = originalShadows;
    boundary.markNeedsPaint();
    await tester.pump();
  }
}

AppUser _user(String role) => AppUser(
  uid: 'ui-test',
  name: 'Pengguna Uji',
  email: 'test@example.invalid',
  photoUrl: '',
  role: role,
  isActive: true,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);
const _summary = DashboardSummary(
  activeModuleCount: 0,
  todayLogCount: 0,
  todayScheduleCount: 0,
  lowStockCount: 0,
  monthlyIncome: 0,
  monthlyExpense: 0,
  monthlyProfit: 0,
  recentActivities: [],
  revenueItems: [],
  circularFlows: [],
  lowStockPreview: [],
  financeVisible: true,
);
EducationContent _education(String title) => EducationContent(
  id: title,
  title: title,
  type: EducationType.sop,
  status: EducationStatus.published,
  moduleType: 'ayam_kampung',
  category: '',
  tags: [],
  authorId: 'ui-test',
  createdBy: 'ui-test',
  updatedBy: 'ui-test',
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  isDeleted: false,
  summary: 'Materi uji lokal untuk memeriksa kartu, gambar, dan pencarian.',
);
final _notification = AppNotification(
  id: 'ui-test',
  title: 'Pengingat uji lokal',
  body: 'Contoh khusus pengujian widget, tidak berasal dari database.',
  type: 'system',
  targetRole: 'all',
  userId: '',
  relatedCollection: '',
  relatedId: '',
  isRead: true,
  createdAt: DateTime(2026),
  scheduledAt: null,
  isDeleted: false,
);

class _EmptyFirestore implements FirebaseFirestore {
  final collections = <String>[];
  @override
  CollectionReference<Map<String, dynamic>> collection(String path) {
    collections.add(path);
    return _EmptyCollection();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// A query double is deliberately confined to this test; no Firebase is accessed.
// ignore: subtype_of_sealed_class
class _EmptyCollection implements CollectionReference<Map<String, dynamic>> {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #get) {
      return Future<QuerySnapshot<Map<String, dynamic>>>.value(
        _EmptySnapshot(),
      );
    }
    if ([#where, #orderBy, #limit].contains(invocation.memberName)) return this;
    return super.noSuchMethod(invocation);
  }
}

class _EmptySnapshot implements QuerySnapshot<Map<String, dynamic>> {
  @override
  List<QueryDocumentSnapshot<Map<String, dynamic>>> get docs => [];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RecordingLogbookService extends LogbookService {
  _RecordingLogbookService() : super(firestore: _EmptyFirestore());
  String? savedModule;
  Map<String, dynamic>? savedDetails;
  @override
  Future<List<InventoryStockWarning>> previewInventoryStockWarnings({
    required String moduleType,
    required Map<String, dynamic> details,
  }) async => [];
  @override
  Future<void> createDailyEntry({
    required String moduleType,
    required String title,
    required String activityType,
    required double? quantity,
    required String? unit,
    required String? notes,
    required Map<String, dynamic> details,
    required String userId,
  }) async {
    savedModule = moduleType;
    savedDetails = details;
  }
}
