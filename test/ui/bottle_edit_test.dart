import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hollow_court/data/event_log.dart';
import 'package:hollow_court/domain/overlay/overlay.dart' as domain;
import 'package:hollow_court/domain/pricing/price.dart';
import 'package:hollow_court/domain/units/quantity.dart';
import 'package:hollow_court/ui/library.dart';

/// Correcting a bottle that is already on the shelf.
///
/// **The verbs existed and nothing wrote them**, which is what this file is here to stop happening
/// again: `BottleRecounted`, `BottleDiscarded`, `BottleRemoved` and the `price.paid` writer were all
/// present in the domain -- reduced by the fold, parsed from the log -- with no caller anywhere. A
/// domain test cannot catch that; a test that goes through the *notifier* can, because the notifier is
/// what a screen talks to.
void main() {
  late Directory home;

  setUp(() => home = Directory.systemTemp.createTempSync('hollow-edit-bottle'));
  tearDown(() {
    if (home.existsSync()) home.deleteSync(recursive: true);
  });

  /// A container holding one cellar, with a bottle on the shelf.
  ///
  /// The container is built rather than pumped: these are actions on a notifier, and the only thing a
  /// widget would add is the sheet in front of them -- which has its own test below, for the one thing
  /// a widget can show that a notifier cannot: the sentence a refusal puts on screen.
  Future<(ProviderContainer, CellarNotifier)> openCellar({
    Volume? bottleVolume,
  }) async {
    var clock = 1000;
    final log = await EventLog.open(
      file: File('${home.path}${Platform.pathSeparator}cellar.ndjson'),
      nodeId: 'test',
      nowMillis: () => clock++,
    );
    final cellar = Cellar.of(log);
    final container = ProviderContainer(
      overrides: [cellarProvider.overrideWith(() => _Seeded(cellar))],
    );
    addTearDown(container.dispose);
    final notifier = container.read(cellarProvider.notifier);

    // **Awaited before anything is recorded.** An `AsyncNotifier`'s `state.value` is null until its
    // future completes, and every action on this notifier starts by reading it and returning early if
    // it is not there -- so a test that calls one immediately records nothing at all, silently. That
    // is the same shape as the button that did nothing in the sync section, and it cost the same ten
    // minutes to see: the symptom was an empty shelf, not an exception.
    await container.read(cellarProvider.future);

    if (bottleVolume != null) {
      await notifier.addBottle(
        sku: 'gin',
        volume: bottleVolume,
        name: 'Tanqueray',
      );
    }
    return (container, notifier);
  }

  group('a name is a label, and there are two of them', () {
    test('renaming a bottle changes that bottle and not the vocabulary', () async {
      final (container, notifier) = await openCellar(bottleVolume: Volume.fromMillilitres(700));
      final bottleId = container.read(cellarProvider).value!.stock.bottles.first.bottleId;

      await notifier.renameBottle(bottleId, 'the good one');

      final cellar = container.read(cellarProvider).value!;
      expect(cellar.overlay.bottleName(bottleId), 'the good one');
      expect(
        cellar.overlay.ingredientAlias('gin'),
        isNull,
        reason: 'section 8 keeps the two sentences apart: this was about one object',
      );
    });

    test('renaming the ingredient changes every bottle of it and no bottle name', () async {
      final (container, notifier) = await openCellar(bottleVolume: Volume.fromMillilitres(700));
      final bottleId = container.read(cellarProvider).value!.stock.bottles.first.bottleId;

      await notifier.renameIngredient('gin', '杜松子酒');

      final cellar = container.read(cellarProvider).value!;
      expect(cellar.overlay.ingredientAlias('gin'), '杜松子酒');
      expect(cellar.overlay.bottleName(bottleId), isNull);
    });

    test('an emptied name puts the seed word back rather than leaving a blank', () async {
      // `editOverlay` treats an empty value as a removal, which is the only sensible reading of
      // "clear this name": the seed's word is what an unnamed ingredient is called.
      final (container, notifier) = await openCellar(bottleVolume: Volume.fromMillilitres(700));
      final bottleId = container.read(cellarProvider).value!.stock.bottles.first.bottleId;

      await notifier.renameBottle(bottleId, 'the good one');
      await notifier.renameBottle(bottleId, '   ');

      expect(container.read(cellarProvider).value!.overlay.bottleName(bottleId), isNull);
    });
  });

  group('a quantity is an observation', () {
    test('a recount replaces what is left and counts the pour that came before', () async {
      final (container, notifier) = await openCellar(bottleVolume: Volume.fromMillilitres(700));
      final bottleId = container.read(cellarProvider).value!.stock.bottles.first.bottleId;

      await notifier.pour({'gin': 45000});
      expect(
        container.read(cellarProvider).value!.stock.bottle(bottleId)!.remaining,
        Volume.fromMillilitres(655),
      );

      await notifier.recountBottle(bottleId, Volume.fromMillilitres(600));

      final bottle = container.read(cellarProvider).value!.stock.bottle(bottleId)!;
      expect(bottle.remaining, Volume.fromMillilitres(600));
      expect(
        bottle.consumed,
        Volume.fromMillilitres(45),
        reason: 'the pour still happened -- a recount says what is left, not what was drunk',
      );
    });

    test('a discard does not become a drink', () async {
      // Section 6 is explicit that both reduce the shelf and only one of them was a drink, and the
      // consumption curve is the thing that would lie if this were a pour.
      final (container, notifier) = await openCellar(bottleVolume: Volume.fromMillilitres(700));
      final bottleId = container.read(cellarProvider).value!.stock.bottles.first.bottleId;

      await notifier.discardBottle(bottleId, Volume.fromMillilitres(50));

      final bottle = container.read(cellarProvider).value!.stock.bottle(bottleId)!;
      expect(bottle.discarded, Volume.fromMillilitres(50));
      expect(bottle.consumed, Volume.zero, reason: 'nobody drank it');
      expect(bottle.remaining, Volume.fromMillilitres(650));
    });

    test('a recount of nothing is refused, because an empty bottle is discarded', () async {
      final (container, notifier) = await openCellar(bottleVolume: Volume.fromMillilitres(700));
      final bottleId = container.read(cellarProvider).value!.stock.bottles.first.bottleId;

      await notifier.recountBottle(bottleId, Volume.zero);

      expect(
        container.read(cellarProvider).value!.stock.bottle(bottleId)!.recounts,
        0,
        reason: 'no event was written',
      );
    });
  });

  group('a price is a series and not a field', () {
    test('recording a price adds a point and keeps the one that was there', () async {
      final (container, notifier) = await openCellar(bottleVolume: Volume.fromMillilitres(700));

      await notifier.recordPrice(
        sku: 'gin',
        price: Money.fromMinorUnits(12000, Currency.cny),
      );
      await notifier.recordPrice(
        sku: 'gin',
        price: Money.fromMinorUnits(13500, Currency.cny),
      );

      final points = container.read(cellarProvider).value!.log.events.length;
      expect(points, greaterThan(2), reason: 'two bottles-worth plus two price events');
      // And the correction is visible as a *second* observation rather than a replacement, which is
      // the only reason section 7 keeps a series.
      final prices = container
          .read(cellarProvider)
          .value!
          .log
          .events
          .where((event) => event.type == 'price.paid')
          .length;
      expect(prices, 2);
    });
  });

  group('a line that was a mistake can be retracted, once', () {
    test('a bottle nobody has poured from is retracted', () async {
      final (container, notifier) = await openCellar(bottleVolume: Volume.fromMillilitres(700));
      final bottleId = container.read(cellarProvider).value!.stock.bottles.first.bottleId;

      final removed = await notifier.removeBottle(bottleId);

      expect(removed, isTrue);
      final cellar = container.read(cellarProvider).value!;
      expect(cellar.stock.bottle(bottleId), isNull);
      expect(cellar.stock.removedBottleIds, {bottleId});
    });

    test('and one that has been poured from is NOT, because the curve would lie', () async {
      // **The guard, and the reason it is in the writer rather than in the fold.** The pour is in the
      // log; deleting the bottle it came from would leave a drink with nothing to belong to, and the
      // consumption curve would report a glass from nowhere. What such a bottle needs is a discard.
      final (container, notifier) = await openCellar(bottleVolume: Volume.fromMillilitres(700));
      final bottleId = container.read(cellarProvider).value!.stock.bottles.first.bottleId;
      await notifier.pour({'gin': 45000});

      final removed = await notifier.removeBottle(bottleId);

      expect(removed, isFalse);
      expect(
        container.read(cellarProvider).value!.stock.bottle(bottleId),
        isNotNull,
        reason: 'and the bottle is still on the shelf',
      );
    });
  });

  group('the two overlay names resolve in the order section 8 implies', () {
    test('the bottle wins, then the ingredient, then the seed', () async {
      // What the shelf reads, asserted where the rule lives rather than through a screen: the more
      // specific answer is the one a person gave about *this* object.
      final (container, notifier) = await openCellar(bottleVolume: Volume.fromMillilitres(700));
      final bottleId = container.read(cellarProvider).value!.stock.bottles.first.bottleId;

      domain.Overlay overlay() => container.read(cellarProvider).value!.overlay;

      expect(overlay().bottleName(bottleId), isNull);
      expect(overlay().ingredientAlias('gin'), isNull);

      await notifier.renameIngredient('gin', '杜松子酒');
      expect(overlay().bottleName(bottleId) ?? overlay().ingredientAlias('gin'), '杜松子酒');

      await notifier.renameBottle(bottleId, 'the good one');
      expect(overlay().bottleName(bottleId) ?? overlay().ingredientAlias('gin'), 'the good one');
    });
  });
}

/// A cellar handed straight to the notifier, so no file is opened through a platform channel.
class _Seeded extends CellarNotifier {
  _Seeded(this._initial);

  final Cellar _initial;

  @override
  Future<Cellar> build() async => _initial;
}
