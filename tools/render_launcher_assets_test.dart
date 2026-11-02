// Run with: flutter test tools/render_launcher_assets_test.dart
// Deterministic Android resource rendering of the unchanged Kebun Sei logo.
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('render original mark into Android launcher resources', () async {
    final codec = await ui.instantiateImageCodec(
      File('lib/assets/logo.png').readAsBytesSync(),
    );
    final source = (await codec.getNextFrame()).image;
    final pixels = (await source.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!;
    var left = source.width, top = source.height, right = 0, bottom = 0;
    for (var y = 0; y < source.height; y++) {
      for (var x = 0; x < source.width; x++) {
        if (pixels.getUint8((y * source.width + x) * 4 + 3) == 0) continue;
        left = math.min(left, x);
        top = math.min(top, y);
        right = math.max(right, x + 1);
        bottom = math.max(bottom, y + 1);
      }
    }
    expect(right > left && bottom > top, isTrue);
    final bounds = ui.Rect.fromLTRB(
      left.toDouble(),
      top.toDouble(),
      right.toDouble(),
      bottom.toDouble(),
    );
    Future<void> render(
      String path,
      int size,
      double fraction, {
      bool white = true,
      bool monochrome = false,
    }) async {
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      if (white) canvas.drawColor(const ui.Color(0xffffffff), ui.BlendMode.src);
      final scale = size * fraction / math.max(bounds.width, bounds.height);
      final width = bounds.width * scale, height = bounds.height * scale;
      canvas.drawImageRect(
        source,
        bounds,
        ui.Rect.fromLTWH(
          (size - width) / 2,
          (size - height) / 2,
          width,
          height,
        ),
        ui.Paint()
          ..filterQuality = ui.FilterQuality.high
          ..isAntiAlias = true
          ..colorFilter = monochrome
              ? const ui.ColorFilter.mode(ui.Color(0xffffffff), ui.BlendMode.srcIn)
              : null,
      );
      final picture = recorder.endRecording();
      final rendered = await picture.toImage(size, size);
      final bytes = await rendered.toByteData(format: ui.ImageByteFormat.png);
      final file = File(path)..parent.createSync(recursive: true);
      file.writeAsBytesSync(bytes!.buffer.asUint8List());
      rendered.dispose();
      picture.dispose();
    }

    for (final entry in {
      'mdpi': 48,
      'hdpi': 72,
      'xhdpi': 96,
      'xxhdpi': 144,
      'xxxhdpi': 192,
    }.entries) {
      await render(
        'android/app/src/main/res/mipmap-${entry.key}/ic_launcher.png',
        entry.value,
        .84,
      );
    }
    // Android adaptive foreground uses a 108dp canvas; the whole mark stays
    // inside a centered 64dp square, within the documented 66dp safe zone.
    await render(
      'android/app/src/main/res/drawable-nodpi/ic_launcher_foreground.png',
      432,
      64 / 108,
      white: false,
    );
    await render(
      'android/app/src/main/res/drawable-nodpi/ic_stat_seicycle.png',
      96,
      .8,
      white: false,
      monochrome: true,
    );
    source.dispose();
    codec.dispose();
  });
}
