import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sei_cycle/features/dashboard/models/dashboard_summary.dart';
import 'package:sei_cycle/features/dashboard/models/productivity_point.dart';
import 'package:sei_cycle/features/dashboard/screen/dashboard_screen.dart';
import 'package:sei_cycle/theme/app_theme.dart';
import 'phase05_dashboard_test.dart' show user;

void main() {
  setUpAll(() => initializeDateFormatting('id_ID'));
  for (final width in [320.0, 360.0, 768.0, 1280.0]) {
    testWidgets(
      'partial Dashboard at $width and text scale 1.4 has no overflow or false zero',
      (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.4)),
              child: child!,
            ),
            home: Scaffold(
              body: DashboardScreen(
                profile: user('operator_lapangan'),
                summaryLoader: ({required includeFinance}) async {
                  expect(includeFinance, isFalse);
                  return const DashboardSummary(
                    activeModuleCount: 5,
                    todayLogCount: 1,
                    todayScheduleCount: 0,
                    lowStockCount: null,
                    outOfStockCount: null,
                    monthlyIncome: 0,
                    monthlyExpense: 0,
                    monthlyProfit: 0,
                    recentActivities: [],
                    revenueItems: [],
                    circularFlows: [],
                    lowStockPreview: [],
                    financeVisible: false,
                    samplesExcluded: true,
                    sectionErrors: {
                      'inventory': FormatException('private details'),
                    },
                  );
                },
                productivityLoader: (_, _, _) async =>
                    const ProductivityReport(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        for (var i = 0; i < 13; i++) {
          expect(tester.takeException(), isNull);
          await tester.drag(
            find.byType(SingleChildScrollView).first,
            const Offset(0, -400),
          );
          await tester.pumpAndSettle();
        }
        expect(find.textContaining('Belum dapat dihitung'), findsWidgets);
        expect(find.textContaining('private details'), findsNothing);
        expect(find.text('null'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
