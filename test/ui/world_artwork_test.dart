import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hollow_court/ui/display_providers.dart';
import 'package:hollow_court/ui/ornament.dart';
import 'package:hollow_court/ui/theme.dart';

/// The fourth world's picture, and the three worlds that must not have one.
///
/// **Both halves of this are worth asserting.** The owner's instruction was that the two traced pieces
/// 「只限定于 miku 主题里出现」-- so a world that draws it and a world that does not are each a claim, and the
/// second is the one that would break quietly: a picture that leaked into every theme would look like a feature.
class _FixedWorld extends DisplaySettingsNotifier {
  _FixedWorld(this._world);

  final HollowPaletteValue _world;

  @override
  DisplaySettings build() => DisplaySettings(theme: _world);
}

void main() {
  Future<void> pumpWorld(WidgetTester tester, HollowPaletteValue world, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // **Loaded on the real clock, and this is the fault the first attempt hit.** A widget test's zone does not
    // advance real file I/O, so the asset is still resolving when the frame is captured -- the render came out
    // with the texture and no picture, which reads exactly like "the feature is not wired up". `runAsync` is what
    // lets the loader finish; without it the test would sit until its timeout and then report nothing useful.
    if (world.artwork case final artwork?) {
      await tester.runAsync(() async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [displaySettingsProvider.overrideWith(() => _FixedWorld(world))],
            child: const MaterialApp(home: SizedBox()),
          ),
        );
        for (final asset in [artwork.tall, artwork.wide]) {
          await precacheImage(AssetImage(asset), tester.element(find.byType(SizedBox)));
        }
      });
    }

    await tester.pumpWidget(
      ProviderScope(
        overrides: [displaySettingsProvider.overrideWith(() => _FixedWorld(world))],
        child: MaterialApp(
          home: Stack(children: [Positioned.fill(child: Container(color: world.ground)), const OrnamentBackdrop()]),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('**the world with a picture draws the shape its window asks for**', (tester) async {
    // 竖版用于安卓, 横版用于 windows 和 linux -- the owner's split. What produces it is the window's own
    // proportions rather than a `Platform` check, which is why a tall box in a test is an honest stand-in for a
    // phone and a wide one for a desktop window.
    await pumpWorld(tester, HollowPaletteValue.eternalDiva, const Size(500, 1000));
    expect(
      find.byWidgetPredicate((w) => w is Image && (w.image as AssetImage).assetName.endsWith('diva-tall.png')),
      findsOneWidget,
      reason: 'a window taller than it is wide gets the upright drawing',
    );

    await pumpWorld(tester, HollowPaletteValue.eternalDiva, const Size(1200, 600));
    expect(
      find.byWidgetPredicate((w) => w is Image && (w.image as AssetImage).assetName.endsWith('diva-wide.png')),
      findsOneWidget,
      reason: 'a window wider than it is tall gets the landscape one',
    );
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets('**no other world draws a picture**', (tester) async {
    for (final world in HollowPaletteValue.all) {
      if (world.artwork != null) continue;
      await pumpWorld(tester, world, const Size(900, 600));
      expect(
        find.byType(Image),
        findsNothing,
        reason: '${world.name} has no picture, and one appearing there is the leak this asserts against',
      );
    }
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets('**the picture is drawn under the interface**', (tester) async {
    // It is a material rather than a subject: anything the reader can press or read is above it, and it takes no
    // taps. Both would be reasons not to ship it if they were wrong, and neither is visible in a screenshot.
    await pumpWorld(tester, HollowPaletteValue.eternalDiva, const Size(900, 600));
    final picture = tester.getTopLeft(find.byType(Image));
    final ornament = tester.getTopLeft(find.byType(CustomPaint).last);
    expect(picture, ornament, reason: 'both fill the same box');
    expect(find.byType(IgnorePointer), findsWidgets);
  }, timeout: const Timeout(Duration(seconds: 30)));
}
