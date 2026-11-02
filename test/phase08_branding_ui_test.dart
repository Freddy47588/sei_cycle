import 'dart:io';
import 'dart:ui' as ui;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sei_cycle/app/app_shell.dart';
import 'package:sei_cycle/core/widgets/kebun_sei_logo.dart';
import 'package:sei_cycle/features/auth/screen/login_screen.dart';
import 'package:sei_cycle/features/auth/services/auth_service.dart';
import 'package:sei_cycle/features/dashboard/models/dashboard_summary.dart';
import 'package:sei_cycle/features/dashboard/screen/dashboard_screen.dart';
import 'package:sei_cycle/features/profile/models/app_user.dart';
import 'package:sei_cycle/features/profile/services/user_profile_service.dart';
import 'package:sei_cycle/theme/app_theme.dart';

import 'support/memory_firestore.dart';

const _capture = bool.fromEnvironment('CAPTURE_UI');
final _boundary = GlobalKey();

class _Auth implements FirebaseAuth {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _profile = AppUser(
  uid: 'branding-fixture',
  name: 'Tim Kebun Sei',
  email: '',
  photoUrl: '',
  role: 'admin',
  isActive: true,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);
final _summary = DashboardSummary(
  activeModuleCount: 0,
  todayLogCount: 0,
  todayScheduleCount: 0,
  lowStockCount: 0,
  monthlyIncome: 0,
  monthlyExpense: 0,
  monthlyProfit: 0,
  recentActivities: const [],
  revenueItems: const [],
  circularFlows: const [],
  lowStockPreview: const [],
  financeVisible: false,
  updatedAt: DateTime(2026),
);

Future<void> _pump(
  WidgetTester tester,
  Widget page,
  double width,
  double scale,
) async {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.lightTheme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: RepaintBoundary(key: _boundary, child: page),
    ),
  );
  // Asset decoding uses real asynchronous work; complete it before inspecting
  // the artwork so captures never pass with an empty Image placeholder.
  await tester.runAsync(
    () => precacheImage(
      const AssetImage('lib/assets/logo.png'),
      _boundary.currentContext!,
    ),
  );
  await tester.pumpAndSettle();
  for (final element in find.byType(KebunSeiLogo).evaluate()) {
    final image = find.descendant(
      of: find.byWidget(element.widget),
      matching: find.byType(RawImage),
    );
    expect(tester.widget<RawImage>(image).image, isNotNull);
  }
}

Future<void> _saveCapture(WidgetTester tester, String name) async {
  if (!_capture) return;
  await tester.runAsync(() async {
    final boundary =
        _boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final rendered = await boundary.toImage();
    final bytes = await rendered.toByteData(format: ui.ImageByteFormat.png);
    final directory = Directory('build/phase08/branding')
      ..createSync(recursive: true);
    File(
      '${directory.path}/$name.png',
    ).writeAsBytesSync(bytes!.buffer.asUint8List());
    rendered.dispose();
  });
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('id_ID');
    if (_capture) {
      final flutterRoot = Platform.environment['FLUTTER_ROOT'];
      if (flutterRoot == null) {
        throw StateError('Set FLUTTER_ROOT for readable captures.');
      }
      final font = File(
        '$flutterRoot/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
      );
      final icons = File(
        '$flutterRoot/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
      );
      for (final family in ['Roboto', 'Ahem']) {
        await (FontLoader(family)..addFont(
              Future.value(ByteData.sublistView(font.readAsBytesSync())),
            ))
            .load();
      }
      await (FontLoader('MaterialIcons')..addFont(
            Future.value(ByteData.sublistView(icons.readAsBytesSync())),
          ))
          .load();
    }
  });

  for (final width in [320.0, 393.0, 768.0, 1280.0]) {
    for (final scale in [1.0, 1.4]) {
      testWidgets(
        'original logo stays visible and navigation usable at $width text $scale',
        (tester) async {
          final semantics = tester.ensureSemantics();
          try {
            await _pump(
              tester,
              LoginScreen(
                authService: AuthService(
                  auth: _Auth(),
                  userProfileService: UserProfileService(
                    firestore: MemoryFirestore(),
                  ),
                ),
              ),
              width,
              scale,
            );
            expect(find.byType(KebunSeiLogo), findsOneWidget);
            expect(find.bySemanticsLabel('Logo Kebun Sei'), findsOneWidget);
            expect(tester.takeException(), isNull);
            await _saveCapture(tester, 'login-${width.toInt()}-$scale');
            await tester.ensureVisible(find.text('Masuk').last);
            expect(find.text('Masuk').last.hitTestable(), findsOneWidget);

            await _pump(
              tester,
              AppShell(
                profile: _profile,
                unreadCountStream: Stream.value(0),
                pageBuilder: (label) => label == 'Dashboard'
                    ? DashboardScreen(
                        profile: _profile,
                        summaryLoader: ({required includeFinance}) async =>
                            _summary,
                      )
                    : Center(child: Text('Halaman $label')),
              ),
              width,
              scale,
            );
            expect(find.byType(KebunSeiLogo), findsNWidgets(2));
            final title = tester.getRect(find.text('Dashboard SeiCycle'));
            final heroLogo = tester.getRect(find.byType(KebunSeiLogo).last);
            expect(title.overlaps(heroLogo), false);
            expect(
              find.text('Dashboard SeiCycle').hitTestable(),
              findsOneWidget,
            );
            expect(tester.takeException(), isNull);
            await _saveCapture(tester, 'dashboard-${width.toInt()}-$scale');
            await tester.tap(find.text('Notifikasi').last);
            await tester.pumpAndSettle();
            expect(find.text('Halaman Notifikasi'), findsOneWidget);
            expect(tester.takeException(), isNull);
          } finally {
            semantics.dispose();
          }
        },
      );
    }
  }
}
