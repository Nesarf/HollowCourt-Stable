// Draws every theme to a PNG, offscreen, so the look can be looked at.
//
// **Not an assertion -- a tool that needs a test binding.** Nothing here compares anything; the four
// files land in the cache directory and a person looks at them. It exists because the obvious way to
// review a theme is a screenshot of a running window, and on this machine that stopped working: two
// platforms both came back blank because their windows were never composited while another
// application held the foreground. `RenderRepaintBoundary.toImage` does not care about the desktop
// session at all.
//
//     flutter test test/render_themes_test.dart
//     # -> E:/DaShaoHuo/cache/shot-<theme>.png
//
// **TEXT IS DRAWN AS BOXES**, because `flutter test` uses a placeholder font and this application
// bundles none. Colour, spacing and the ornament are what these files can show; typography is not,
// and a reviewer should not read anything into the shapes.
//
// The whole application is not pumped: its settings providers read a file through a platform channel
// that a test does not have, and Riverpod throws when such a provider is disposed while loading. So
// what is rendered is the shell's composition -- ornament, headings, a numeric line, two buttons, the
// tab bar -- which is the part a palette decides.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hollow_court/ui/l10n/dual_copy_text.dart';
import 'package:hollow_court/ui/ornament.dart';
import 'package:hollow_court/ui/theme.dart';

void main() {
  for (final value in HollowPaletteValue.all) {
    testWidgets('render ${value.name}', (tester) async {
      tester.view.physicalSize = const Size(1000, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      HollowPalette.use(value);

      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: ProviderScope(
            child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: HollowTheme.build(),
            home: Scaffold(
              body: Stack(
                children: [
                  const Positioned.fill(child: OrnamentBackdrop()),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 40, 24, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        DualCopyText(Copy.stockTitle, style: HollowType.display),
                        const SizedBox(height: 6),
                        DualCopyText(Copy.stockEmpty, style: HollowType.body),
                        const SizedBox(height: 22),
                        DualCopyText(Copy.cellarValue, style: HollowType.heading),
                        const SizedBox(height: 8),
                        Text('1280.00 CNY', style: HollowType.numeric),
                        Text('700 ml', style: HollowType.caption),
                        const SizedBox(height: 16),
                        TextButton(onPressed: () {}, child: const Text('a button')),
                        OutlinedButton(onPressed: () {}, child: const Text('another')),
                      ],
                    ),
                  ),
                ],
              ),
              bottomNavigationBar: NavigationBar(
                selectedIndex: 0,
                destinations: const [
                  NavigationDestination(icon: Icon(Icons.inventory_2), label: 'one'),
                  NavigationDestination(icon: Icon(Icons.grid_view), label: 'two'),
                  NavigationDestination(icon: Icon(Icons.local_bar), label: 'three'),
                  NavigationDestination(icon: Icon(Icons.insights), label: 'four'),
                  NavigationDestination(icon: Icon(Icons.settings), label: 'five'),
                ],
              ),
            ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 60));

      await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        File('E:/DaShaoHuo/cache/shot-${value.name}.png')
            .writeAsBytesSync(bytes!.buffer.asUint8List());
        image.dispose();
      });
    });
  }
}
