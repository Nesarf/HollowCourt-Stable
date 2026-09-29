import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:hollow_court/ui/prism.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hollow_court/ui/materials.dart';
import 'package:hollow_court/ui/ornament.dart';
import 'package:hollow_court/ui/theme.dart';

/// Paints one sheet per world and writes it to disk: the ground, the instrument, the palette and the five
/// materials, side by side so that "three worlds, not three recolours" can be looked at rather than argued about.
///
/// **Why this exists instead of a screenshot.** Capturing the running application means capturing the desktop,
/// and the desktop belongs to whoever is using the machine -- two rounds of captures came back with the browser
/// on them, and a third with the task switcher, because a person was working while they were taken. This draws
/// the same evidence out of the same painters with no window involved at all: deterministic, repeatable, and
/// nobody's screen is touched.
///
/// **Text is deliberately absent.** A widget test has no real font, so any label would render as boxes and make
/// the sheets look broken. What is being checked here is the art -- ground, instrument, palette, materials --
/// and none of it is text.
void main() {
  const sheetWidth = 1180.0;
  const sheetHeight = 420.0;

  /// **One world per test, because two `toImage` calls in one test do not both return.** The first version
  /// painted all three in a loop and hung for ten minutes after writing the first file; a sheet per test costs
  /// three test names and cannot deadlock.
  Future<void> sheet(WidgetTester tester, HollowPaletteValue world) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, sheetWidth, sheetHeight));
    canvas.drawRect(Rect.fromLTWH(0, 0, sheetWidth, sheetHeight), Paint()..color = world.ground);

    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, sheetWidth, sheetHeight));
    PrismWashPainter(color: world.line, alpha: 0.34, cell: 96, texture: world.texture)
        .paint(canvas, Size(sheetWidth, sheetHeight));

    // **The instrument at full strength, unlike on a page.** A page draws it at a third so it stays a
    // background; a sheet drawn to *review* the instrument has to show the instrument, or there is nothing to
    // look at. The strength is the page's business and the shape is this sheet's.
    HollowOrnamentPainter(ornament: world.ornament, strength: 0.9, color: world.hairline)
        .paint(canvas, Size(sheetWidth, sheetHeight));
    canvas.restore();

    final swatches = <Color>[
      world.ground, world.surface, world.surfaceRaised, world.line, world.hairline,
      world.ink, world.inkSoft, world.inkFaint, world.rose, world.gold, world.onAccent, world.absent,
    ];
    final swatchWidth = sheetWidth / swatches.length;
    for (var i = 0; i < swatches.length; i++) {
      canvas.drawRect(Rect.fromLTWH(i * swatchWidth, sheetHeight - 34, swatchWidth, 34),
          Paint()..color = swatches[i]);
    }

    final rooms = RoomMaterial.values;
    final roomWidth = sheetWidth / rooms.length;
    for (var i = 0; i < rooms.length; i++) {
      canvas.drawRect(Rect.fromLTWH(i * roomWidth, sheetHeight - 104, roomWidth, 66),
          Paint()..color = rooms[i].surface(world));
      canvas.drawRect(Rect.fromLTWH(i * roomWidth, sheetHeight - 108, roomWidth, 4),
          Paint()..color = rooms[i].rule(world));
    }

    final image = await recorder.endRecording().toImage(sheetWidth.toInt(), sheetHeight.toInt());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    File('E:/DaShaoHuo/downloads/world-sheet-${world.name}.png')
        .writeAsBytesSync(bytes!.buffer.asUint8List());
    image.dispose();
  }

  for (final world in HollowPaletteValue.all) {
    testWidgets('sheet: ${world.name} (${world.texture.name}, ${world.ornament.name})', (tester) async {
      // **`runAsync`, or nothing ever finishes.** `toImage` is real asynchronous work rather than a scheduled
      // frame, and a widget test's fake clock never advances past it -- the first version of this file hung for
      // ten minutes per world, which is exactly what that looks like from the outside.
      await tester.runAsync(() => sheet(tester, world));
    });
  }
}
