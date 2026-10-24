import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sei_cycle/features/dashboard/models/dashboard_filter.dart';
import 'package:sei_cycle/features/dashboard/models/productivity_point.dart';
import 'package:sei_cycle/features/dashboard/widgets/productivity_chart.dart';

void main() {
  setUpAll(() => initializeDateFormatting('id_ID'));
  Future<void> pumpChart(
    WidgetTester tester, {
    required List<ProductivityPoint> points,
    bool additive = true,
    int days = 90,
    double width = 320,
    double scale = 1.4,
  }) async {
    tester.view.physicalSize = Size(width, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: ProductivityChart(
                filter: DashboardFilter.days(days, now: DateTime(2026, 10, 17)),
                series: ProductivitySeries(
                  label: 'Panen aktual',
                  unit: 'kg',
                  additive: additive,
                  points: points,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  testWidgets(
    'sparse 90-day bars use observed dates and exact tooltips without invented groups',
    (tester) async {
      await pumpChart(
        tester,
        points: [
          ProductivityPoint(DateTime(2026, 10, 17), 2.125),
          ProductivityPoint(DateTime(2026, 8, 1), 0),
        ],
      );
      final data = tester.widget<BarChart>(find.byType(BarChart)).data;
      expect(data.barGroups, hasLength(2));
      expect(data.barGroups.map((g) => g.barRods.single.toY), [0, 2.125]);
      expect(data.barGroups.every((g) => g.barRods.single.width >= 12), isTrue);
      expect(find.text('1/8'), findsOneWidget);
      expect(find.text('17/10'), findsOneWidget);
      final group = data.barGroups.last;
      final tip = data.barTouchData.touchTooltipData.getTooltipItem(
        group,
        1,
        group.barRods.single,
        0,
      )!;
      expect(tip.text, '17/10\n2,125 kg');
    },
  );

  for (final days in [1, 7, 30, 90, 366]) {
    for (final width in [320.0, 360.0, 393.0, 768.0, 1280.0]) {
      testWidgets('$days-day dense bars readable at $width and 2x text', (
        tester,
      ) async {
        await pumpChart(
          tester,
          days: days,
          width: width,
          scale: 2,
          points: [
            for (var i = days - 1; i >= 0; i--)
              ProductivityPoint(DateTime(2026, 10, 17 - i), i.toDouble()),
          ],
        );
        final chart = tester.widget<BarChart>(find.byType(BarChart));
        expect(chart.data.barGroups, hasLength(days));
        expect(
          chart.data.barGroups.every((g) => g.barRods.single.width == 14),
          isTrue,
        );
        if (days * 32 + 128 > width - 32) {
          final scroll = find.byWidgetPredicate(
            (w) =>
                w is SingleChildScrollView &&
                w.scrollDirection == Axis.horizontal,
          );
          expect(scroll, findsOneWidget);
          await tester.drag(scroll, const Offset(-5000, 0));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
      });
    }
  }

  testWidgets(
    'sparse lines remain on actual day offsets with gaps and no interpolation',
    (tester) async {
      await pumpChart(
        tester,
        additive: false,
        days: 30,
        points: [
          ProductivityPoint(DateTime(2026, 10, 17), 7),
          ProductivityPoint(DateTime(2026, 10, 1), 6),
          ProductivityPoint(DateTime(2026, 10, 2), 6.5),
        ],
      );
      final data = tester.widget<LineChart>(find.byType(LineChart)).data;
      expect(data.lineBarsData.map((line) => line.spots.length), [2, 1]);
      expect(data.lineBarsData.first.spots.map((spot) => spot.x), [13, 14]);
      expect(data.lineBarsData.last.spots.single.x, 29);
      expect(data.lineBarsData.every((line) => !line.isCurved), isTrue);
    },
  );

  testWidgets(
    'empty, invalid and out of range observations do not become zero bars',
    (tester) async {
      await pumpChart(
        tester,
        days: 7,
        points: [
          ProductivityPoint(DateTime(2026, 10, 17), double.nan),
          ProductivityPoint(DateTime(2026, 10, 17), -1),
          ProductivityPoint(DateTime(2025), 5),
        ],
      );
      expect(find.byType(BarChart), findsNothing);
      expect(find.textContaining('Belum ada data'), findsOneWidget);
    },
  );
}
