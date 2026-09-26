import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hollow_court/data/event_log.dart';
import 'package:hollow_court/domain/events/event.dart';
import 'package:hollow_court/domain/events/hlc.dart';
import 'package:hollow_court/domain/events/shelf.dart';
import 'package:hollow_court/domain/events/stock.dart';
import 'package:hollow_court/domain/units/quantity.dart';
import 'package:hollow_court/ui/library.dart';

/// The notifier's half of placing a bottle, on the real clock.
///
/// **A plain `test` and not a `testWidgets`, and that is the point.** The page's
/// tests stub `placeBottle` because a real file write cannot complete inside a
/// widget test's FakeAsync zone; this file is where the write path itself is
/// exercised, and it has to run outside that zone to be able to await anything.
///
/// Only `build` is replaced -- so the page does not go looking for a documents
/// directory -- which means `placeBottle` below is the shipping implementation.
class _Seeded extends CellarNotifier {
  _Seeded(this._initial);

  final Cellar _initial;

  @override
  Future<Cellar> build() async => _initial;
}

Future<(Cellar, ProviderContainer)> _open(List<Event> seed) async {
  final dir = Directory.systemTemp.createTempSync('hollow_placement_test');
  var clock = 1000;
  final log = await EventLog.open(
    file: File('${dir.path}${Platform.pathSeparator}cellar.ndjson'),
    nodeId: 'test',
    nowMillis: () => clock++,
  );
  for (final event in seed) {
    await log.record((_) => event);
  }
  final cellar = Cellar.of(log);
  final container = ProviderContainer(
    overrides: [cellarProvider.overrideWith(() => _Seeded(cellar))],
  );
  addTearDown(container.dispose);
  await container.read(cellarProvider.future);
  return (cellar, container);
}

Event _added(String id, String sku, int millilitres) => StockEvents.bottleAdded(
  hlc: const Hlc(physicalMillis: 1, counter: 0, nodeId: 'test'),
  bottleId: id,
  sku: sku,
  volume: Volume.fromMillilitres(millilitres),
);

Iterable<Event> _placements(Cellar cellar) =>
    cellar.log.events.where((e) => e.type == ShelfEvent.bottlePlaced);

void main() {
  test('placing a bottle appends one event and re-folds', () async {
    final (cellar, container) = await _open([_added('b1', 'gin', 700)]);

    await container
        .read(cellarProvider.notifier)
        .placeBottle(
          bottleId: 'b1',
          shelfId: 'bar',
          posXPermille: 250,
          posYPermille: 500,
        );

    expect(_placements(cellar), hasLength(1));
    // Read back through the fold the state now carries, not from the event's
    // payload: the point of placing is that the shelf shows it.
    final state = container.read(cellarProvider).value!;
    final placement = state.shelf.placementOf('b1')!;
    expect(placement.shelfId, 'bar');
    expect(placement.posXPermille, 250);
    expect(placement.posYPermille, 500);
  });

  test('moving a bottle is a second placement, and the later one stands',
      () async {
    final (cellar, container) = await _open([_added('b1', 'gin', 700)]);
    final notifier = container.read(cellarProvider.notifier);

    await notifier.placeBottle(
      bottleId: 'b1',
      shelfId: 'bar',
      posXPermille: 100,
      posYPermille: 100,
    );
    await notifier.placeBottle(
      bottleId: 'b1',
      shelfId: 'fridge',
      posXPermille: 900,
      posYPermille: 100,
    );

    // Two events and one bottle. That is what a move is, and it is why there is
    // no `moveBottle`: a separate method would be a second path to the same
    // write, and the two could drift.
    expect(_placements(cellar), hasLength(2));
    final placement = container.read(cellarProvider).value!.shelf.placementOf('b1')!;
    expect(placement.shelfId, 'fridge');
    expect(placement.posXPermille, 900);
  });

  test('a position off the shelf is refused rather than written', () async {
    // The event builder asserts and an assert is nothing in release, so this has
    // to be a check and not an assert. A caller that passed 1001 gets no log
    // entry, rather than one that every device reading the log will drop.
    final (cellar, container) = await _open([_added('b1', 'gin', 700)]);
    final notifier = container.read(cellarProvider.notifier);

    await notifier.placeBottle(
      bottleId: 'b1',
      shelfId: 'bar',
      posXPermille: 1001,
      posYPermille: 500,
    );
    await notifier.placeBottle(
      bottleId: 'b1',
      shelfId: 'bar',
      posXPermille: 500,
      posYPermille: -1,
    );

    expect(_placements(cellar), isEmpty);
    expect(container.read(cellarProvider).value!.shelf.placementOf('b1'), isNull);
  });

  test('the edges are inside the shelf, and they are written', () async {
    // The boundary belongs to the shelf rather than to the refusal: 0 and 1000
    // are positions a drop can produce, and a check that rejected them would
    // refuse the corner of the board.
    final (cellar, container) = await _open([_added('b1', 'gin', 700)]);
    final notifier = container.read(cellarProvider.notifier);

    await notifier.placeBottle(
      bottleId: 'b1',
      shelfId: 'bar',
      posXPermille: 0,
      posYPermille: 1000,
    );

    expect(_placements(cellar), hasLength(1));
    final placement = container.read(cellarProvider).value!.shelf.placementOf('b1')!;
    expect(placement.posXPermille, 0);
    expect(placement.posYPermille, 1000);
  });
}
