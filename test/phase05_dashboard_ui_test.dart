import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sei_cycle/features/batches/models/cultivation_batch.dart';
import 'package:sei_cycle/features/dashboard/models/dashboard_filter.dart';
import 'package:sei_cycle/features/dashboard/models/dashboard_summary.dart';
import 'package:sei_cycle/features/dashboard/models/productivity_point.dart';
import 'package:sei_cycle/features/dashboard/screen/dashboard_screen.dart';
import 'package:sei_cycle/features/dashboard/widgets/module_monitoring_section.dart';
import 'package:sei_cycle/features/dashboard/widgets/productivity_chart.dart';
import 'package:sei_cycle/theme/app_theme.dart';
import 'phase05_dashboard_test.dart' show user, now;

const capture = bool.fromEnvironment('CAPTURE_UI');
final boundary = GlobalKey();

DashboardSummary summary({int modules = 5, Object? error}) => DashboardSummary(
  activeModuleCount: modules,
  todayLogCount: 3,
  todayScheduleCount: 3,
  lowStockCount: 1,
  monthlyIncome: 100,
  monthlyExpense: 150,
  monthlyProfit: -50,
  recentActivities: const [],
  revenueItems: const [],
  circularFlows: const [],
  lowStockPreview: const [],
  financeVisible: true,
  financeError: error,
  updatedAt: now,
  pendingScheduleCount: 1,
  doneScheduleCount: 1,
  skippedScheduleCount: 1,
);
final period = DashboardFilter.days(7, now: now);
ProductivityReport report(String label) => ProductivityReport(
  logCount: 1,
  series: [
    ProductivitySeries(
      label: label,
      unit: 'pH',
      points: [ProductivityPoint(now, 7)],
    ),
  ],
);
Future<void> pump(
  WidgetTester tester,
  Widget widget, {
  double width = 360,
  double scale = 1.4,
  bool settle = true,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.lightTheme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: RepaintBoundary(
        key: boundary,
        child: Scaffold(
          body: widget is DashboardScreen
              ? widget
              : SingleChildScrollView(child: widget),
        ),
      ),
    ),
  );
  if (settle) await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('id_ID');
    final flutterRoot = Platform.environment['FLUTTER_ROOT'];
    if (capture && flutterRoot != null) {
      final font = File(
        '$flutterRoot/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
      );
      final iconFont = File(
        '$flutterRoot/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
      );
      if (iconFont.existsSync()) {
        await (FontLoader('MaterialIcons')..addFont(
              Future.value(ByteData.sublistView(iconFont.readAsBytesSync())),
            ))
            .load();
      }
      if (font.existsSync()) {
        for (final family in ['Roboto', 'Ahem']) {
          await (FontLoader(family)..addFont(
                Future.value(ByteData.sublistView(font.readAsBytesSync())),
              ))
              .load();
        }
      }
    }
  });
  for (final width in [320.0, 360.0, 393.0, 768.0, 1280.0]) {
    for (final additive in [false, true]) {
      testWidgets(
        'dashboard and ${additive ? 'bar' : 'line'} chart fit $width at text scale 1.4',
        (tester) async {
          await pump(
            tester,
            DashboardScreen(
              profile: user('admin'),
              summaryLoader: ({required includeFinance}) async => summary(),
              productivityLoader: (filter, module, batch) async =>
                  ProductivityReport(
                    logCount: 1,
                    series: [
                      ProductivitySeries(
                        label: 'Pengamatan dengan satu titik',
                        unit: 'kg',
                        additive: additive,
                        points: [ProductivityPoint(DateTime.now(), 20)],
                      ),
                    ],
                  ),
            ),
            width: width,
          );
          expect(tester.takeException(), isNull);
          await tester.ensureVisible(find.byType(ProductivityChart));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(
            find.textContaining('Pengamatan dengan satu titik'),
            findsWidgets,
          );
          if (capture) {
            await tester.runAsync(() async {
              final rendered =
                  await (boundary.currentContext!.findRenderObject()!
                          as RenderRepaintBoundary)
                      .toImage();
              final data = await rendered.toByteData(
                format: ui.ImageByteFormat.png,
              );
              Directory('build/phase05').createSync(recursive: true);
              File(
                'build/phase05/chart-${additive ? 'bar' : 'line'}-${width.toInt()}.png',
              ).writeAsBytesSync(data!.buffer.asUint8List());
              rendered.dispose();
            });
          }
        },
      );
    }
  }
  testWidgets('empty and non finite chart data have an honest no data state', (
    tester,
  ) async {
    await pump(
      tester,
      ProductivityChart(
        filter: period,
        series: ProductivitySeries(
          label: 'x',
          unit: 'kg',
          points: [ProductivityPoint(now, double.nan)],
        ),
      ),
    );
    expect(
      find.text('Belum ada data produktivitas pada periode ini.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('old module response cannot replace newer response', (
    tester,
  ) async {
    final old = Completer<ProductivityReport>();
    var calls = 0;
    await pump(
      tester,
      ModuleMonitoringSection(
        filter: period,
        offline: true,
        onBatchDetail: (_) {},
        loader: (_, module, _) {
          calls++;
          return module == 'ayam_kampung'
              ? old.future
              : Future.value(report('DATA MAGGOT TERBARU'));
        },
      ),
      settle: false,
    );
    await tester.tap(find.text('Maggot BSF'));
    await tester.pumpAndSettle();
    expect(find.text('DATA MAGGOT TERBARU'), findsWidgets);
    old.complete(report('DATA AYAM LAMA'));
    await tester.pumpAndSettle();
    expect(find.text('DATA AYAM LAMA'), findsNothing);
    expect(calls, 2);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'period changes discard pending old summary, refresh starts a new request',
    (tester) async {
      final old = Completer<DashboardSummary>();
      var requests = 0;
      await pump(
        tester,
        DashboardScreen(
          profile: user('admin'),
          periodSummaryLoader: (_) {
            requests++;
            return requests == 1
                ? old.future
                : Future.value(summary(modules: 77));
          },
        ),
        settle: false,
      );
      await tester.ensureVisible(find.text('30 Hari Terakhir'));
      await tester.tap(find.text('30 Hari Terakhir'));
      await tester.pumpAndSettle();
      expect(find.text('77'), findsOneWidget);
      old.complete(summary(modules: 99));
      await tester.pumpAndSettle();
      expect(find.text('99'), findsNothing);
      await tester.ensureVisible(find.text('Refresh'));
      await tester.tap(find.text('Refresh'));
      await tester.pumpAndSettle();
      expect(requests, 3);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'finance error is shown without currency zero and operational KPI remains',
    (tester) async {
      await pump(
        tester,
        DashboardScreen(
          profile: user('admin'),
          summaryLoader: ({required includeFinance}) async =>
              summary(error: StateError('offline')),
        ),
      );
      expect(find.text('Modul Aktif'), findsOneWidget);
      await tester.ensureVisible(find.text('Ringkasan Arus Kas'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Rp '), findsNothing);
      expect(find.text('Coba lagi'), findsOneWidget);
    },
  );
  testWidgets('error and retry load operational summary successfully', (
    tester,
  ) async {
    var calls = 0;
    await pump(
      tester,
      DashboardScreen(
        profile: user('operator_lapangan'),
        summaryLoader: ({required includeFinance}) async {
          if (++calls == 1) throw StateError('offline');
          return summary();
        },
      ),
    );
    await tester.ensureVisible(find.text('Coba lagi'));
    await tester.tap(find.text('Coba lagi'));
    await tester.pumpAndSettle();
    expect(find.text('Modul Aktif'), findsOneWidget);
    expect(find.text('Ringkasan Arus Kas'), findsNothing);
  });
  testWidgets(
    'completed batch loads independently and opens existing detail callback',
    (tester) async {
      final historical = CultivationBatch(
        id: 'HIST',
        status: 'completed',
        createdBy: 'admin',
        updatedBy: 'admin',
        input: BatchInput(
          moduleType: 'ayam_kampung',
          name: 'Siklus Selesai',
          code: 'HIST',
          locationName: 'A',
          startedAt: DateTime(2025),
          expectedHarvestAt: DateTime(2025, 12, 31),
        ),
      );
      final requested = <String?>[];
      String? opened;
      await pump(
        tester,
        ModuleMonitoringSection(
          filter: period,
          offline: true,
          onBatchDetail: (id) => opened = id,
          loader: (_, _, batch) async {
            requested.add(batch);
            return report('BATCH ${batch ?? 'SEMUA'}');
          },
          batchLoader: (_, _) async =>
              BatchPage(entries: [historical], hasMore: false),
        ),
      );
      await tester.ensureVisible(find.byType(DropdownButtonFormField<String>));
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Siklus Selesai · Selesai').last);
      await tester.pumpAndSettle();
      expect(requested, [null, 'HIST']);
      expect(find.text('BATCH HIST'), findsWidgets);
      await tester.ensureVisible(find.text('Lihat Detail Batch'));
      await tester.tap(find.text('Lihat Detail Batch'));
      expect(opened, 'HIST');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('timeline logbook schedule and batch actions preserve identity', (
    tester,
  ) async {
    final clicked = <String>[];
    final activities = [
      for (final source in ['logbook', 'schedule'])
        DashboardActivity(
          id: source,
          source: source,
          moduleType: 'lele',
          title: 'Buka $source',
          time: '12:00',
          icon: Icons.water_drop,
          color: Colors.green,
          done: false,
          batchId: 'B1',
        ),
    ];
    final data = DashboardSummary(
      activeModuleCount: 0,
      todayLogCount: 0,
      todayScheduleCount: 0,
      lowStockCount: 0,
      monthlyIncome: 0,
      monthlyExpense: 0,
      monthlyProfit: 0,
      recentActivities: activities,
      revenueItems: const [],
      circularFlows: const [],
      lowStockPreview: const [],
      financeVisible: false,
    );
    await pump(
      tester,
      DashboardScreen(
        profile: user('operator_lapangan'),
        summaryLoader: ({required includeFinance}) async => data,
        onActivity: (a) => clicked.add(a.id),
        onBatchDetail: (id) => clicked.add(id),
        onBatches: () => clicked.add('list'),
      ),
    );
    for (final source in ['logbook', 'schedule']) {
      await tester.ensureVisible(find.text('Buka $source'));
      await tester.tap(find.text('Buka $source'));
      await tester.pump();
    }
    await tester.ensureVisible(find.text('Batch B1').first);
    await tester.tap(find.text('Batch B1').first);
    await tester.ensureVisible(find.text('Batch Aktif'));
    await tester.tap(find.text('Batch Aktif'));
    expect(clicked, ['logbook', 'schedule', 'B1', 'list']);
  });
  testWidgets('monitoring error retry recovers to honest empty data', (
    tester,
  ) async {
    var calls = 0;
    await pump(
      tester,
      ModuleMonitoringSection(
        filter: period,
        offline: true,
        onBatchDetail: (_) {},
        loader: (_, _, _) async {
          if (++calls == 1) throw StateError('offline');
          return const ProductivityReport();
        },
      ),
    );
    await tester.ensureVisible(find.text('Coba lagi'));
    await tester.tap(find.text('Coba lagi'));
    await tester.pumpAndSettle();
    expect(
      find.text('Belum ada data produktivitas pada periode ini.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'mixed invalid chart values do not leak Infinity into summaries',
    (tester) async {
      await pump(
        tester,
        ProductivityChart(
          filter: period,
          series: ProductivitySeries(
            label: 'Finite only',
            unit: 'kg',
            additive: true,
            points: [
              ProductivityPoint(now, 3),
              ProductivityPoint(now, double.infinity),
            ],
          ),
        ),
      );
      expect(find.text('Total tercatat: 3 kg'), findsOneWidget);
      expect(find.textContaining('Infinity'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('old batch response cannot overwrite a newer selected batch', (
    tester,
  ) async {
    final old = Completer<ProductivityReport>();
    CultivationBatch batch(String id) => CultivationBatch(
      id: id,
      status: 'active',
      createdBy: 'admin',
      updatedBy: 'admin',
      input: BatchInput(
        moduleType: 'ayam_kampung',
        name: id,
        code: id,
        locationName: 'A',
        startedAt: now,
      ),
    );
    await pump(
      tester,
      ModuleMonitoringSection(
        filter: period,
        offline: true,
        onBatchDetail: (_) {},
        batchLoader: (_, _) async => BatchPage(
          entries: [batch('BATCH1'), batch('BATCH2')],
          hasMore: false,
        ),
        loader: (_, _, id) => id == 'BATCH1'
            ? old.future
            : Future.value(
                report(id == 'BATCH2' ? 'NEW BATCH TWO' : 'ALL BATCHES'),
              ),
      ),
    );
    final picker = find.byType(DropdownButtonFormField<String>);
    await tester.ensureVisible(picker);
    await tester.tap(picker);
    await tester.pumpAndSettle();
    await tester.tap(find.text('BATCH1 · Aktif').last);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.ensureVisible(picker);
    await tester.tap(picker);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('BATCH2 · Aktif').last);
    await tester.pumpAndSettle();
    expect(find.text('NEW BATCH TWO'), findsWidgets);
    old.complete(report('OLD BATCH ONE'));
    await tester.pumpAndSettle();
    expect(find.text('OLD BATCH ONE'), findsNothing);
    expect(find.text('NEW BATCH TWO'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
