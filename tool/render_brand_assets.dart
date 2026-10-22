// Renders the eRefill launcher icon and splash images from the same painter
// the app uses (ERefillMarkPainter), so app UI, icon and splash always match.
//
//   flutter test tool/render_brand_assets.dart
//   dart run flutter_launcher_icons
//   dart run flutter_native_splash:create
//
// Set BRAND_OUT to write somewhere other than the asset folders (previews).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:erefill/core/widgets/brand/erefill_mark.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _font = 'BrandJakarta';

Future<void> _loadFont() async {
  final bytes = await File('assets/fonts/PlusJakartaSans.ttf').readAsBytes();
  final loader = FontLoader(_font)
    ..addFont(Future.value(ByteData.view(bytes.buffer)));
  await loader.load();
}

Future<void> _save(
  String path,
  int w,
  int h,
  void Function(Canvas canvas) draw,
) async {
  final recorder = ui.PictureRecorder();
  draw(Canvas(recorder));
  final image = await recorder.endRecording().toImage(w, h);
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  final file = File(path)..parent.createSync(recursive: true);
  await file.writeAsBytes(png!.buffer.asUint8List());
  // ignore: avoid_print
  print('wrote $path (${w}x$h)');
}

void _mark(Canvas canvas, Offset origin, double size, {Color? color}) {
  canvas.save();
  canvas.translate(origin.dx, origin.dy);
  ERefillMarkPainter(color: color).paint(canvas, Size.square(size));
  canvas.restore();
}

ui.Paragraph _text(
  String text,
  double fontSize,
  Color color, {
  double weight = 800,
  double letterSpacing = 0,
}) {
  final builder =
      ui.ParagraphBuilder(ui.ParagraphStyle(fontFamily: _font))
        ..pushStyle(
          ui.TextStyle(
            color: color,
            fontFamily: _font,
            fontSize: fontSize,
            fontWeight: FontWeight.values[(weight / 100).round() - 1],
            fontVariations: [ui.FontVariation('wght', weight)],
            letterSpacing: letterSpacing,
          ),
        )
        ..addText(text);
  return builder.build()
    ..layout(const ui.ParagraphConstraints(width: double.infinity));
}

/// Mark + "eRefill" (+ tagline), laid out exactly like `ERefillLogo`:
/// gap 0.16 × mark, wordmark at 0.62 × mark, block centred on the mark.
/// Returns the canvas size that fits it with no padding.
({Size size, void Function(Canvas) draw}) _lockup(
  double markSize, {
  required Color word,
  Color? tagline,
}) {
  final fontSize = markSize * 0.62;
  final name = _text(
    'eRefill',
    fontSize,
    word,
    letterSpacing: -fontSize * 0.02,
  );
  final tag = tagline == null
      ? null
      : _text(
          BrandColors.tagline,
          (fontSize * 0.2).clamp(9, 72).toDouble(),
          tagline,
          weight: 600,
          letterSpacing: fontSize * 0.055,
        );
  final textX = markSize * 1.16;
  final blockH = name.height + (tag == null ? 0 : fontSize * 0.08 + tag.height);
  final textW = [
    name.maxIntrinsicWidth,
    if (tag != null) tag.maxIntrinsicWidth,
  ].reduce((a, b) => a > b ? a : b);
  final height = blockH > markSize ? blockH : markSize;
  return (
    size: Size((textX + textW).ceilToDouble(), height.ceilToDouble()),
    draw: (canvas) {
      _mark(canvas, Offset(0, (height - markSize) / 2), markSize);
      final y = (height - blockH) / 2;
      canvas.drawParagraph(name, Offset(textX, y));
      if (tag != null) {
        canvas.drawParagraph(
          tag,
          Offset(textX, y + name.height + fontSize * 0.08),
        );
      }
    },
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final out = Platform.environment['BRAND_OUT'];
  String icon(String name) => out == null ? 'assets/icon/$name' : '$out/$name';
  String image(String name) =>
      out == null ? 'assets/images/$name' : '$out/$name';

  test('render brand assets', () async {
    await _loadFont();

    // App icon (iOS, legacy Android, web, Windows): mark on a white tile.
    await _save(icon('app-icon.png'), 1024, 1024, (canvas) {
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, 1024, 1024),
        Paint()..color = const Color(0xFFFFFFFF),
      );
      _mark(canvas, const Offset(132, 132), 760);
    });

    // Android adaptive foreground: mark inside the 66% safe zone.
    await _save(icon('app-icon-foreground.png'), 1024, 1024, (canvas) {
      _mark(canvas, const Offset(142, 142), 740);
    });

    // Android 12+ splash icon: shown inside a circle on the navy background.
    await _save(image('splash_icon_android12.png'), 1152, 1152, (canvas) {
      _mark(canvas, const Offset(336, 336), 480);
    });

    // Native splash lockup (iOS, web, Android < 12). flutter_native_splash
    // treats it as 4x, so a 250px mark shows at 62.5dp: the same size the
    // in-app splash draws, for a seamless handoff. The tagline is left to
    // the in-app splash, which fades it in.
    final splash = _lockup(250, word: const Color(0xFFFFFFFF));
    await _save(
      image('splash_wordmark.png'),
      splash.size.width.toInt(),
      splash.size.height.toInt(),
      splash.draw,
    );

    // Light-background lockup with tagline, for receipts and documents.
    final light = _lockup(
      250,
      word: BrandColors.navy,
      tagline: BrandColors.slate,
    );
    await _save(
      image('brand_lockup_light.png'),
      light.size.width.toInt(),
      light.size.height.toInt(),
      light.draw,
    );

    // Android notification icon: white silhouette on transparent, 24dp.
    const densities = {
      'mdpi': 24,
      'hdpi': 36,
      'xhdpi': 48,
      'xxhdpi': 72,
      'xxxhdpi': 96,
    };
    for (final entry in densities.entries) {
      final px = entry.value;
      final dir = out == null
          ? 'android/app/src/main/res/drawable-${entry.key}'
          : '$out/drawable-${entry.key}';
      await _save('$dir/ic_stat_erefill.png', px, px, (canvas) {
        _mark(
          canvas,
          Offset.zero,
          px.toDouble(),
          color: const Color(0xFFFFFFFF),
        );
      });
    }
  });
}
