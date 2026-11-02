import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sei_cycle/core/constants/app_roles.dart';
import 'package:sei_cycle/core/constants/farm_modules.dart';
import 'package:sei_cycle/core/widgets/app_ui.dart';
import 'package:sei_cycle/core/widgets/async_state_widgets.dart';
import 'package:sei_cycle/core/widgets/feature_page.dart';
import 'package:sei_cycle/features/auth/screen/widgets/auth_frame.dart';
import 'package:sei_cycle/features/finance/models/finance_record.dart';
import 'package:sei_cycle/features/finance/services/finance_service.dart';
import 'package:sei_cycle/features/inventory/models/inventory_item.dart';
import 'package:sei_cycle/features/logbook/models/logbook_entry.dart';
import 'package:sei_cycle/features/profile/models/app_user.dart';
import 'package:sei_cycle/features/reports/models/analytics_model.dart';
import 'package:sei_cycle/features/recommendations/services/recommendation_service.dart';
import 'package:sei_cycle/features/schedule/models/schedule_item.dart';
import 'package:sei_cycle/theme/app_theme.dart';

void main() {
  test('five default farm modules are available', () {
    expect(FarmModules.values, hasLength(5));
    expect(FarmModules.values.map((module) => module.id), contains('lele'));
  });

  test('async snapshot errors are shown instead of loading forever', () {
    final snapshot = AsyncSnapshot<List<String>>.withError(
      ConnectionState.active,
      StateError('permission denied'),
    );

    final state = asyncSnapshotState(snapshot);

    expect(state, isA<ErrorState>());
    expect((state! as ErrorState).message, contains('permission denied'));
  });

  test('async snapshot without data shows loading state', () {
    const snapshot = AsyncSnapshot<List<String>>.nothing();

    expect(asyncSnapshotState(snapshot), isA<LoadingState>());
  });

  test('async snapshot with data leaves rendering to the caller', () {
    final snapshot = AsyncSnapshot.withData(ConnectionState.active, <String>[]);

    expect(asyncSnapshotState(snapshot), isNull);
  });

  test('async snapshot can treat an emitted null as loaded data', () {
    const snapshot = AsyncSnapshot<String?>.withData(
      ConnectionState.active,
      null,
    );

    expect(asyncSnapshotState(snapshot, allowNullData: true), isNull);
  });

  test('seicycle role capabilities match the current brief', () {
    final admin = _userWithRole(AppRoles.admin);
    final operatorLapangan = _userWithRole(AppRoles.operatorLapangan);
    final operatorKeuangan = _userWithRole(AppRoles.operatorKeuangan);

    expect(admin.canManageLogbooks, isTrue);
    expect(admin.canManageFinance, isTrue);
    expect(admin.canDeleteLogbooks, isTrue);
    expect(admin.canDeleteInventory, isTrue);
    expect(admin.canDeleteSchedules, isTrue);
    expect(admin.canDeleteFinance, isTrue);
    expect(admin.canDeleteEducation, isTrue);
    expect(_userWithRole(' Admin ').isAdmin, isTrue);
    expect(_userWithRole('ADMIN').canManageFinance, isTrue);
    expect(_userWithRole('ADMIN').canDeleteFinance, isTrue);

    for (final user in [admin, operatorLapangan, operatorKeuangan]) {
      expect(user.canViewLogbooks, isTrue);
      expect(user.canViewInventory, isTrue);
      expect(user.canViewSchedules, isTrue);
      expect(user.canViewFinance, user.isAdmin || user.isOperatorKeuangan);
      expect(user.canViewRecommendations, isTrue);
      expect(user.canViewReports, isTrue);
    }

    expect(operatorLapangan.canManageLogbooks, isTrue);
    expect(operatorLapangan.canManageInventory, isTrue);
    expect(operatorLapangan.canManageSchedules, isTrue);
    expect(operatorLapangan.canManageFinance, isFalse);
    expect(operatorLapangan.canDeleteLogbooks, isFalse);
    expect(operatorLapangan.canDeleteInventory, isFalse);
    expect(operatorLapangan.canDeleteSchedules, isFalse);

    expect(operatorKeuangan.canManageLogbooks, isFalse);
    expect(operatorKeuangan.canManageInventory, isFalse);
    expect(operatorKeuangan.canManageSchedules, isFalse);
    expect(operatorKeuangan.canManageFinance, isTrue);
    expect(operatorKeuangan.canDeleteFinance, isTrue);
    expect(operatorKeuangan.canViewFinanceDashboard, isTrue);
  });

  test('legacy roles stay migration-safe', () {
    final legacyOperator = _userWithRole(AppRoles.legacyOperator);
    final legacyMitra = _userWithRole(AppRoles.legacyMitra);
    final pesertaEdukasi = _userWithRole(AppRoles.legacyPesertaEdukasi);

    expect(legacyOperator.effectiveRole, AppRoles.operatorLapangan);
    expect(legacyOperator.canManageLogbooks, isTrue);

    for (final user in [legacyMitra, pesertaEdukasi]) {
      expect(user.canViewDashboard, isTrue);
      expect(user.canViewEducation, isTrue);
      expect(user.canViewLogbooks, isTrue);
      expect(user.canViewInventory, isTrue);
      expect(user.canViewSchedules, isTrue);
      expect(user.canViewFinance, user.isAdmin || user.isOperatorKeuangan);
      expect(user.canViewRecommendations, isTrue);
      expect(user.canViewReports, isTrue);
      expect(user.canManageLogbooks, isFalse);
      expect(user.canManageInventory, isFalse);
      expect(user.canManageSchedules, isFalse);
      expect(user.canManageFinance, isFalse);
      expect(user.canDeleteLogbooks, isFalse);
      expect(user.canDeleteInventory, isFalse);
      expect(user.canDeleteSchedules, isFalse);
      expect(user.canDeleteFinance, isFalse);
    }
  });

  test('finance summary calculates monthly profit loss and categories', () {
    final records = [
      _financeRecord(
        id: 'income-1',
        type: 'income',
        category: 'Panen telur',
        amount: 150000,
        date: DateTime(2026, 6, 5),
      ),
      _financeRecord(
        id: 'expense-1',
        type: 'expense',
        category: 'Pakan',
        amount: 50000,
        date: DateTime(2026, 6, 6),
      ),
      _financeRecord(
        id: 'income-old',
        type: 'income',
        category: 'Panen telur',
        amount: 999000,
        date: DateTime(2026, 5, 31),
      ),
      _financeRecord(
        id: 'deleted',
        type: 'expense',
        category: 'Pakan',
        amount: 25000,
        date: DateTime(2026, 6, 7),
        isDeleted: true,
      ),
    ];

    final summary = FinanceService.monthlyProfitLoss(
      records,
      month: DateTime(2026, 6, 15),
    );

    expect(summary.totalIncome, 150000);
    expect(summary.totalExpense, 50000);
    expect(summary.netProfit, 100000);
    expect(summary.transactions, hasLength(2));
    expect(summary.byCategory['Panen telur']?.income, 150000);
    expect(summary.byCategory['Pakan']?.expense, 50000);
  });

  test('rule based recommendations detect core operational risks', () {
    final now = DateTime(2026, 6, 28);
    final recommendations = RecommendationService.generateFromData(
      logbooks: [
        _logbook(
          id: 'lele-start',
          moduleId: FarmModules.lele.id,
          activityType: 'Tebar benih',
          date: DateTime(2026, 3, 31),
          quantity: 100,
          unit: 'ekor',
        ),
        _logbook(
          id: 'lele-feed',
          moduleId: FarmModules.lele.id,
          activityType: 'Pakan harian',
          date: DateTime(2026, 6, 27),
          quantity: 3,
          unit: 'kg',
        ),
        _logbook(
          id: 'lele-panen',
          moduleId: FarmModules.lele.id,
          activityType: 'Cek pertumbuhan',
          date: DateTime(2026, 6, 26),
          quantity: 8,
          unit: 'cm',
        ),
      ],
      lowStockItems: [
        _inventoryItem(
          id: 'feed',
          name: 'Pakan lele',
          currentStock: 2,
          minStock: 5,
          unit: 'kg',
        ),
      ],
      overdueSchedules: [
        _scheduleItem(
          id: 'water-check',
          title: 'Cek kualitas air',
          moduleId: FarmModules.lele.id,
          date: DateTime(2026, 6, 26),
        ),
      ],
      financeRecords: [
        _financeRecord(
          id: 'income',
          type: 'income',
          category: 'Penjualan',
          amount: 100000,
          date: now,
        ),
        _financeRecord(
          id: 'expense',
          type: 'expense',
          category: 'Pakan',
          amount: 150000,
          date: now,
        ),
      ],
      includeFinance: true,
      now: now,
    );

    expect(
      recommendations.map((recommendation) => recommendation.type),
      containsAll(['inventory', 'schedule', 'finance']),
    );
    expect(
      recommendations.any(
        (recommendation) => recommendation.type == 'harvest_prediction',
      ),
      isFalse,
    );
  });

  test('rule based recommendations stay safe with minimal data', () {
    final recommendations = RecommendationService.generateFromData(
      logbooks: const [],
      lowStockItems: const [],
      overdueSchedules: const [],
      financeRecords: const [],
      includeFinance: true,
      now: DateTime(2026, 6, 28),
    );

    expect(recommendations, isNotEmpty);
    expect(recommendations.first.priority, 'low');
  });

  test('report analytics handles empty datasets', () {
    final analytics = AnalyticsModel(
      logbooks: const [],
      inventoryItems: const [],
      financeRecords: const [],
      startDate: DateTime(2026, 6),
      endDate: DateTime(2026, 7),
    );

    expect(analytics.logbooksPerModule, isEmpty);
    expect(analytics.lowStockItems, isEmpty);
    expect(analytics.totalIncome, 0);
    expect(analytics.totalExpense, 0);
    expect(analytics.profitLoss, 0);
  });

  testWidgets('auth layout fits a compact Android viewport', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: const AuthFrame(
          title: 'Masuk ke SeiCycle',
          subtitle: 'Lanjutkan pencatatan operasional Kebun Sei.',
          child: Column(
            children: [
              TextField(decoration: InputDecoration(labelText: 'Email')),
              SizedBox(height: 12),
              TextField(decoration: InputDecoration(labelText: 'Password')),
              SizedBox(height: 20),
              FilledButton(onPressed: null, child: Text('Masuk')),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Masuk ke SeiCycle'), findsOneWidget);
  });

  testWidgets('feature page and form row avoid overflow on a small screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: FeaturePage(
            title: 'Logbook Operasional',
            subtitle: 'Catatan harian Kebun Sei.',
            actions: const [
              FilledButton(onPressed: null, child: Text('Tambah')),
            ],
            child: ListView(
              children: const [
                AppCard(
                  child: ResponsiveFormRow(
                    children: [
                      TextField(
                        decoration: InputDecoration(labelText: 'Jumlah'),
                      ),
                      TextField(
                        decoration: InputDecoration(labelText: 'Satuan'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Logbook Operasional'), findsOneWidget);
  });
}

FinanceRecord _financeRecord({
  required String id,
  required String type,
  required String category,
  required double amount,
  required DateTime date,
  bool isDeleted = false,
}) {
  return FinanceRecord(
    id: id,
    type: type,
    category: category,
    amount: amount,
    date: date,
    notes: '',
    paymentMethod: '',
    moduleType: '',
    createdBy: 'tester',
    updatedBy: 'tester',
    createdAt: date,
    updatedAt: date,
    isDeleted: isDeleted,
  );
}

LogbookEntry _logbook({
  required String id,
  required String moduleId,
  required String activityType,
  required DateTime date,
  required double quantity,
  required String unit,
}) {
  return LogbookEntry(
    id: id,
    moduleId: moduleId,
    activityType: activityType,
    activityDate: date,
    quantity: quantity,
    unit: unit,
    condition: 'normal',
    note: '',
    createdBy: 'tester',
    updatedBy: 'tester',
    createdAt: date,
    updatedAt: date,
    isDeleted: false,
  );
}

InventoryItem _inventoryItem({
  required String id,
  required String name,
  required double currentStock,
  required double minStock,
  required String unit,
}) {
  final now = DateTime(2026);
  return InventoryItem(
    id: id,
    name: name,
    category: 'Pakan',
    unit: unit,
    currentStock: currentStock,
    minStock: minStock,
    isLowStock: true,
    createdBy: 'tester',
    updatedBy: 'tester',
    createdAt: now,
    updatedAt: now,
    isDeleted: false,
  );
}

ScheduleItem _scheduleItem({
  required String id,
  required String title,
  required String moduleId,
  required DateTime date,
}) {
  return ScheduleItem(
    id: id,
    title: title,
    moduleId: moduleId,
    scheduleType: 'maintenance',
    scheduledAt: date,
    status: 'pending',
    note: '',
    createdBy: 'tester',
    updatedBy: 'tester',
    createdAt: date,
    updatedAt: date,
    isDeleted: false,
  );
}

AppUser _userWithRole(String role) {
  final now = DateTime(2026);
  return AppUser(
    uid: 'uid-$role',
    name: 'Pengguna $role',
    email: '$role@example.com',
    photoUrl: '',
    role: role,
    isActive: true,
    createdAt: now,
    updatedAt: now,
  );
}
