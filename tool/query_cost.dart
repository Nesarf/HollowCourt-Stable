// What the folds cost, and the answer to stage ⑤'s question.
//
//     dart run tool/query_cost.dart
//
// **Stage ⑤ of `docs/catalogue-and-stock.md` is "a database, if ever, last"**, and it names its own gate: *what a
// database would eventually fix is query cost -- which is measurable*. This is the measurement. `docs/query-cost.md`
// records what it said and what was decided; this file is kept so that the question can be asked again with a number
// rather than an opinion, which is the only way "measure before claiming" is a rule rather than a slogan.
//
// **A script rather than a test.** It asserts nothing: a timing assertion fails on a loaded machine, and this
// project has already recorded two tests that failed for exactly that reason. What it produces is a table a person
// reads, and the reading is the point.
//
// Nothing here writes anything, opens a file or touches the network. It builds events in memory and folds them.
//
// **The `print` suppression is the one this file is for.** `avoid_print` is on for the whole project and the config
// says a single line or a whole file may suppress it; a script whose entire output is a table has nothing else to do
// with its results, and `tool/` already holds scripts that print for the same reason.
// ignore_for_file: avoid_print
import 'package:hollow_court/domain/events/event.dart';
import 'package:hollow_court/domain/events/hlc.dart';
import 'package:hollow_court/domain/events/overlay.dart';
import 'package:hollow_court/domain/events/recipe_authoring.dart';
import 'package:hollow_court/domain/events/shelf.dart';
import 'package:hollow_court/domain/events/shelf_authoring.dart';
import 'package:hollow_court/domain/events/stock.dart';
import 'package:hollow_court/domain/model/ingredient_book.dart';
import 'package:hollow_court/domain/model/pack_book.dart';
import 'package:hollow_court/domain/model/recipe_book.dart';
import 'package:hollow_court/domain/model/recipe_collections.dart';
import 'package:hollow_court/domain/model/shelf_book.dart';
import 'package:hollow_court/domain/overlay/overlay.dart';
import 'package:hollow_court/domain/overlay/overlay_key.dart';
import 'package:hollow_court/domain/units/quantity.dart';

var _seq = 0;

Hlc _tick() => Hlc(physicalMillis: 1000000 + (_seq ~/ 4), counter: _seq++ % 4, nodeId: 'cost');

/// A cellar of [bottles] bottles, each poured from [poursEach] times.
///
/// **The shape matters as much as the count**, because the folds are filters over an event list and a list of one
/// event type would measure the cheapest case. So each bottle contributes four events of three kinds, and the
/// reader's own material -- recipes and shelves -- is laid on top: this is a log a real cellar would produce.
List<Event> _generate(int bottles, int poursEach) {
  final events = <Event>[];
  for (var b = 0; b < bottles; b++) {
    final id = 'b$b';
    events.add(
      StockEvents.bottleAdded(
        hlc: _tick(),
        bottleId: id,
        sku: 'sku${b % 189}',
        volume: Volume.fromMillilitres(700),
      ),
    );
    for (var p = 0; p < poursEach; p++) {
      events.add(
        StockEvents.bottleConsumed(
          hlc: _tick(),
          bottleId: id,
          volume: Volume.fromMillilitres(25),
        ),
      );
    }
    events.add(
      ShelfEvents.bottlePlaced(
        hlc: _tick(),
        bottleId: id,
        shelfId: 'bar',
        posXPermille: b % 1000,
        posYPermille: 0,
      ),
    );
    events.add(
      OverlayEvents.fieldSet(
        hlc: _tick(),
        key: OverlayKey.bottle(id),
        value: 'note $b',
      ),
    );
  }
  for (var r = 0; r < bottles ~/ 4; r++) {
    events.add(
      RecipeAuthoredEvents.set(
        hlc: _tick(),
        recipe: AuthoredRecipe(
          id: 'own.r$r',
          name: 'Drink $r',
          items: [AuthoredItem(ingredientId: 'sku${r % 189}', amount: '30')],
        ),
      ),
    );
  }
  for (var s = 0; s < 4; s++) {
    events.add(
      ShelfAuthoredEvents.declared(
        hlc: _tick(),
        shelf: AuthoredShelf(id: 'own.s$s-1-0', name: 'Shelf $s'),
      ),
    );
  }
  return events;
}

/// Every fold `Cellar.of` builds, in the order the constructor builds them.
///
/// **Eight of them, and that is the number that matters.** Each is a filter over the whole event list followed by a
/// sort of what it kept, so a read of the cellar filters and sorts the same list eight times.
void _foldAll(List<Event> events) {
  StockLedger.of(events);
  Overlay.of(events);
  ShelfLayout.of(events);
  RecipeBook.of(events);
  IngredientBook.of(events);
  RecipeCollections.of(events);
  PackBook.of(events);
  ShelfBook.of(events);
}

double _millis(void Function() body) {
  final watch = Stopwatch()..start();
  body();
  watch.stop();
  return watch.elapsedMicroseconds / 1000;
}

void main() {
  print('SCALING -- all eight folds, as `Cellar.of` builds them');
  print('  events   total ms   per fold ms');
  // **The sizes are chosen around the two that matter**: the cellar this application actually has (single digits,
  // measured at 8 events after three weeks) and the one it would have after a decade of daily use.
  for (final bottles in [1, 5, 50, 200, 1000, 5000]) {
    final events = _generate(bottles, 4);
    // Warm first. The very first run in a process pays for JIT and reads about 10 ms for eleven events, which is a
    // number about the virtual machine rather than about the folds.
    _foldAll(events);
    final ms = _millis(() => _foldAll(events));
    print(
      '  ${events.length.toString().padLeft(6)}   '
      '${ms.toStringAsFixed(2).padLeft(8)}   '
      '${(ms / 8).toStringAsFixed(2).padLeft(11)}',
    );
  }

  final big = _generate(5000, 4);
  print('');
  print('AT ${big.length} EVENTS -- one fold at a time');
  for (final (name, body) in <(String, void Function())>[
    ('StockLedger.of', () => StockLedger.of(big)),
    ('Overlay.of', () => Overlay.of(big)),
    ('ShelfLayout.of', () => ShelfLayout.of(big)),
    ('RecipeBook.of', () => RecipeBook.of(big)),
    ('IngredientBook.of', () => IngredientBook.of(big)),
    ('RecipeCollections.of', () => RecipeCollections.of(big)),
    ('PackBook.of', () => PackBook.of(big)),
    ('ShelfBook.of', () => ShelfBook.of(big)),
  ]) {
    body();
    print('  ${name.padRight(22)} ${_millis(body).toStringAsFixed(2).padLeft(7)} ms');
  }

  print('');
  print('WHERE A FOLD GOES -- one fold\'s filter against its sort, at ${big.length} events');
  final ordered = big.toList()..sort((a, b) => a.hlc.compareTo(b.hlc));
  bool stock(Event e) => e.type.startsWith('stock.');
  print(
    '  ${'filter, then sort'.padRight(30)} '
    '${_millis(() => big.where(stock).toList()..sort((a, b) => a.hlc.compareTo(b.hlc))).toStringAsFixed(2).padLeft(7)} ms',
  );
  print(
    '  ${'filter only'.padRight(30)} ${_millis(() => big.where(stock).toList()).toStringAsFixed(2).padLeft(7)} ms',
  );
  print(
    '  ${'sort once, filter eight'.padRight(30)} '
    '${_millis(() {
      final once = big.toList()..sort((a, b) => a.hlc.compareTo(b.hlc));
      for (var i = 0; i < 8; i++) {
        once.where(stock).toList();
      }
    }).toStringAsFixed(2).padLeft(7)} ms',
  );
  print('');
  print('`ordered` is built above and deliberately unused by the folds: they sort their own input, and that is an');
  print('invariant rather than an oversight. See docs/query-cost.md.');
  // Kept referenced so the linter does not call the pre-sorted list dead while the point is that it is unused.
  assert(ordered.length == big.length);
}
