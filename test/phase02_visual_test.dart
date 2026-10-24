import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sei_cycle/features/logbook/models/logbook_page.dart';
import 'package:sei_cycle/features/logbook/screen/logbook_list_screen.dart';
import 'package:sei_cycle/features/logbook/screen/logbook_detail_screen.dart';
import 'package:sei_cycle/theme/app_theme.dart';
import 'phase02_logbook_test.dart' as fixtures;

const capture = bool.fromEnvironment('CAPTURE_UI');
void main() {
  setUpAll(() async {
    await initializeDateFormatting('id_ID');
    if (capture) {
      final root = Platform.environment['FLUTTER_ROOT'];
      if (root == null) return;
      for (final family in ['Roboto', 'Ahem', 'MaterialIcons']) {
        final path = family == 'MaterialIcons'
            ? 'materialicons-regular.otf'
            : 'Roboto-Regular.ttf';
        final file = File('$root/bin/cache/artifacts/material_fonts/$path');
        if (file.existsSync()) {
          await (FontLoader(family)..addFont(
                Future.value(ByteData.sublistView(file.readAsBytesSync())),
              ))
              .load();
        }
      }
    }
  });
  for (final width in [320.0, 360.0, 393.0, 768.0, 1280.0]) {
    for (final detail in [false, true]) {
      testWidgets('${detail ? 'detail' : 'list'} fits $width at text scale 1.4', (
        tester,
      ) async {
        final boundary = GlobalKey();
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final service = fixtures.FakeLogbook()
          ..actual = fixtures.entry('visual')
          ..pages = [
            LogbookPage(entries: [fixtures.entry('visual')], hasMore: false),
          ];
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: MaterialApp(
              theme: AppTheme.lightTheme,
              debugShowCheckedModeBanner: false,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(1.4)),
                child: child!,
              ),
              home: detail
                  ? LogbookDetailScreen(
                      service: service,
                      entryId: 'visual',
                      userId: 'user',
                      canEdit: true,
                    )
                  : LogbookListScreen(
                      service: service,
                      userId: 'user',
                      canEdit: true,
                      initialModuleId: 'ayam_kampung',
                    ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (capture) {
          await tester.runAsync(() async {
            final image =
                await (boundary.currentContext!.findRenderObject()
                        as RenderRepaintBoundary)
                    .toImage(pixelRatio: 1);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final file = File(
              'build/phase02/${detail ? 'detail' : 'list'}-${width.toInt()}.png',
            );
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
      });
    }
  }
}
