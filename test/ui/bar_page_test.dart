import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hollow_court/data/event_log.dart';
import 'package:hollow_court/domain/events/event.dart';
import 'package:hollow_court/domain/events/hlc.dart';
import 'package:hollow_court/domain/events/shelf.dart';
import 'package:hollow_court/domain/events/stock.dart';
import 'package:hollow_court/domain/units/quantity.dart';
import 'package:hollow_court/ui/bar_page.dart';
import 'package:hollow_court/ui/library.dart';
import 'package:hollow_court/ui/theme.dart';

/// The cellar, built OUTSIDE the test's fake clock.
///
/// **`tester.runAsync` is not optional here.** `testWidgets` runs in a FakeAsync
/// zone where a real file read never completes, so the first version of this file
/// hung on its first test for five minutes with no failure and no output. The log
/// is a real file and the write path is the thing under test, so the I/O has to
/// happen on the real clock.
Future<Cellar> _cellarFor(WidgetTester tester, List<Event> events) async =>
    (await tester.runAsync(() => _cellarWith(events)))!;

/// A cellar the page can be handed without a documents directory.
///
/// **The page is built on a real [EventLog] in a temporary file, not on a fake
/// list**, because the thing under test is the path from a drop to an appended
/// event. A stub that collected placements into a `List` would pass while the
/// real write path was broken, which is the only part of this worth testing.
Future<Cellar> _cellarWith(List<Event> events) async {
  final dir = Directory.systemTemp.createTempSync('hollow_bar_test');
  var clock = 1000;
  final log = await EventLog.open(
    file: File('${dir.path}${Platform.pathSeparator}cellar.ndjson'),
    nodeId: 'test',
    nowMillis: () => clock++,
  );
  // One at a time through `record`, with a builder that hands back the event
  // already built: the clock readings here are chosen by the test so that
  // ordering is explicit, rather than minted from the log's own counter.
  for (final event in events) {
    await log.record((_) => event);
  }
  return Cellar.of(log);
}

/// What the page asked to be written.
typedef PlacementCall = ({String bottleId, String shelfId, int x, int y});

/// Hands the page a prepared cellar and REMEMBERS the calls it makes.
///
/// **It does not write through the real log, and the reason is not laziness.**
/// `testWidgets` runs in a FakeAsync zone where a real file write never completes,
/// so a stub that awaited `log.record` made the drop tests hang with no event and
/// no error -- the same trap that made `_cellarFor` need `runAsync`, met from the
/// other side. So this records the call and the real write path is exercised in a
/// plain `test` below, where the clock is real.
///
/// The split is also the honest one: converting a drop point into whole per-mille
/// and naming the bottle and shelf is the page's job, and appending the event is
/// the notifier's. Each is tested where it lives.
class _SeededCellar extends CellarNotifier {
  _SeededCellar(this._initial);

  final Cellar _initial;

  /// Every `placeBottle` the page called, in order.
  final List<PlacementCall> calls = [];

  @override
  Future<Cellar> build() async => _initial;

  @override
  Future<void> placeBottle({
    required String bottleId,
    required String shelfId,
    required int posXPermille,
    required int posYPermille,
  }) async {
    calls.add((
      bottleId: bottleId,
      shelfId: shelfId,
      x: posXPermille,
      y: posYPermille,
    ));
  }
}

Event _added(String id, String sku, int millilitres, {int millis = 1}) =>
    StockEvents.bottleAdded(
      hlc: Hlc(physicalMillis: millis, counter: 0, nodeId: 'test'),
      bottleId: id,
      sku: sku,
      volume: Volume.fromMillilitres(millilitres),
    );

Event _placed(String id, int x, int y, {int millis = 5}) =>
    ShelfEvents.bottlePlaced(
      hlc: Hlc(physicalMillis: millis, counter: 0, nodeId: 'test'),
      bottleId: id,
      shelfId: BarPage.defaultShelfId,
      posXPermille: x,
      posYPermille: y,
    );


/// Picks a bottle up and puts it down at [target].
///
/// The manual gesture sequence rather than `tester.drag`, because the pick-up is a
/// long press: a plain drag is delivered to the ListView's scroll recogniser and
/// no drop is ever produced. Writing the gesture out is what makes this test
/// exercise the same path a finger does.
Future<void> _pickUpAndDrop(WidgetTester tester, Key bottle, Offset target) async {
  final gesture = await tester.startGesture(tester.getCenter(find.byKey(bottle)));
  await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
  await gesture.moveTo(target);
  await tester.pump();
  await gesture.up();
  await tester.pump();
}

/// The notifier the last [_pumpBar] built, so a test can read its calls.
late _SeededCellar _notifier;

Future<void> _pumpBar(WidgetTester tester, Cellar cellar) async {
  // A tall surface, because this page is taller than the 800x600 default and the
  // box a bottle is picked up from sits below the shelf. At the default size the
  // drop tests began their gesture outside the viewport, so nothing was hit and no
  // event was written -- a failure that looks like a broken drag and is a viewport
  // that is too short.
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        cellarProvider.overrideWith(() {
          _notifier = _SeededCellar(cellar);
          return _notifier;
        }),
      ],
      child: const MaterialApp(home: Scaffold(body: BarPage())),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('a bottle with stock and no position is still in the box',
      (tester) async {
    final cellar = await _cellarFor(tester, [_added('b1', 'gin', 700)]);

    await _pumpBar(tester, cellar);

    expect(find.text(Copy.barInTheBox.primary.text), findsOneWidget);
    expect(
      find.byKey(const ValueKey('bottle-b1')),
      findsOneWidget,
      reason: 'it has stock, so it is somewhere on this page',
    );
    expect(find.text(Copy.barShelfEmpty.primary.text), findsOneWidget);
  });

  testWidgets('a placed bottle is drawn on the shelf and not in the box',
      (tester) async {
    final cellar = await _cellarFor(tester, [
      _added('b1', 'gin', 700),
      _placed('b1', 250, 500),
    ]);

    await _pumpBar(tester, cellar);

    expect(find.byKey(const ValueKey('bottle-b1')), findsOneWidget);
    expect(find.text(Copy.barShelfEmpty.primary.text), findsNothing);
    // Not in the box either: the bottle is one thing and it is on the shelf, so
    // drawing it in both places would show two bottles.
    expect(find.byKey(const ValueKey('bottle-b1')), findsOneWidget);
  });

  testWidgets('a position whose bottle is empty is named, not drawn',
      (tester) async {
    // The cross-check this page exists to make. The bottle was recorded, poured
    // away and its position stayed in the log; standing it on the shelf would put
    // a bottle there that nobody can pour.
    final cellar = await _cellarFor(tester, [
      _added('b1', 'gin', 700, millis: 1),
      _placed('b1', 400, 400, millis: 2),
      StockEvents.bottleConsumed(
        hlc: const Hlc(physicalMillis: 3, counter: 0, nodeId: 'test'),
        bottleId: 'b1',
        volume: Volume.fromMillilitres(700),
      ),
    ]);

    await _pumpBar(tester, cellar);

    expect(find.byKey(const ValueKey('bottle-b1')), findsNothing);
    expect(find.text(Copy.barPlacedButEmpty.primary.text), findsOneWidget);
  });

  testWidgets('dropping a bottle on the shelf writes where it landed',
      (tester) async {
    final cellar = await _cellarFor(tester, [_added('b1', 'gin', 700)]);
    await _pumpBar(tester, cellar);

    final shelf = tester.getRect(find.byType(DragTarget<DraggedBottle>));
    // Aim at a point a quarter across and a third down the board.
    final target = Offset(
      shelf.left + shelf.width * 0.25,
      shelf.top + shelf.height * 0.33,
    );

    await _pickUpAndDrop(tester, const ValueKey('bottle-b1'), target);

    expect(_notifier.calls, hasLength(1), reason: 'the drop is the write');
    final call = _notifier.calls.single;
    expect(call.bottleId, 'b1');
    expect(call.shelfId, BarPage.defaultShelfId);
    // Within a few per-mille of where the finger was, rather than a fixed
    // expected pair: the drop point is a pixel and the stored value is whole, and
    // pinning the exact number would make this fail on a layout change instead of
    // on a behaviour change.
    expect((call.x - 250).abs(), lessThan(40));
    expect((call.y - 333).abs(), lessThan(40));
  });

  testWidgets('a drop in the last pixel of the surface lands on the edge',
      (tester) async {
    // **The clamp guards a boundary, not a wild drop.** A `DragTarget` only
    // accepts inside its own hit area, so a release far outside it is never
    // delivered at all and there is nothing for the write path to refuse. What
    // the clamp is for is the last pixel: a person aiming at the corner is still
    // aiming at the shelf, and `placeBottle` refuses anything outside 0..1000, so
    // an unclamped offset would produce no log entry and a bottle that snaps back.
    final cellar = await _cellarFor(tester, [_added('b1', 'gin', 700)]);
    await _pumpBar(tester, cellar);

    final shelf = tester.getRect(find.byType(DragTarget<DraggedBottle>));
    // One pixel inside the bottom-right corner.
    final target = Offset(shelf.right - 1, shelf.bottom - 1);

    await _pickUpAndDrop(tester, const ValueKey('bottle-b1'), target);

    expect(_notifier.calls, hasLength(1));
    final call = _notifier.calls.single;
    expect(call.x, greaterThan(970));
    expect(call.y, greaterThan(970));
  });

  testWidgets('the page draws one named shelf, and does not offer a choice',
      (tester) async {
    // Section 12.3 asks this tab to let a person choose which Bar is being worked
    // on. One shelf with a chooser over it would be furniture, so the page names
    // the shelf and offers nothing -- and this asserts the absence, because an
    // absence that is not tested is an absence that quietly becomes a dropdown.
    final cellar = await _cellarFor(tester, [_added('b1', 'gin', 700)]);

    await _pumpBar(tester, cellar);

    expect(find.text(Copy.barShelfMain.primary.text), findsOneWidget);
    expect(find.byType(DropdownButton<Object>), findsNothing);
  });
}
