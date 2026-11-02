import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sei_cycle/features/profile/models/app_user.dart';
import 'package:sei_cycle/features/reports/models/analytics_model.dart';
import 'package:sei_cycle/features/reports/models/report_filter.dart';
import 'package:sei_cycle/features/reports/screens/report_screen.dart';
import 'package:sei_cycle/features/reports/services/report_service.dart';
import 'package:sei_cycle/theme/app_theme.dart';

import 'support/memory_firestore.dart';

class _Reports extends ReportService {
  _Reports(MemoryFirestore db) : super(firestore: db);
  final filters = <ReportFilter>[];

  @override
  Future<AnalyticsModel> generateReport(
    ReportFilter filter, {
    bool includeFinance = false,
    AppUser? profile,
  }) {
    filters.add(filter);
    return super.generateReport(
      filter,
      includeFinance: includeFinance,
      profile: profile,
    );
  }
}

void main() {
  for (final hasInventory in [false, true]) {
    testWidgets('report empty state respects healthy inventory: $hasInventory', (
      tester,
    ) async {
      final db = MemoryFirestore();
      if (hasInventory) {
        db.documents['inventory/healthy'] = {
          'name': 'Persediaan aktual',
          'unit': 'kg',
          'currentStock': 10,
          'minStock': 2,
          'createdBy': 'fixture-admin',
          'isDeleted': false,
        };
      }
      final date = DateTime(2026, 10, 17);
      final service = _Reports(db);
      final profile = AppUser(
        uid: 'fixture-admin',
        name: 'Admin Uji',
        email: '',
        photoUrl: '',
        role: 'admin',
        isActive: true,
        createdAt: date,
        updatedAt: date,
      );
      tester.view.physicalSize = const Size(393, 1100);
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
            body: ReportScreen(profile: profile, service: service),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final filter = service.filters.single;
      expect(filter.endDate, DateUtils.dateOnly(filter.endDate));
      expect(
        filter.startDate,
        DateTime(
          filter.endDate.year,
          filter.endDate.month,
          filter.endDate.day - 29,
        ),
      );
      expect(
        find.text(
          'Laporan akan tersedia setelah data logbook, inventaris, atau transaksi terkumpul.',
        ),
        hasInventory ? findsNothing : findsOneWidget,
      );
      // Healthy stock is valid report data without becoming a low-stock item.
      await tester.scrollUntilVisible(
        find.text('Item stok rendah'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('Tidak ada stok kritis'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
