import 'package:hollow_court/domain/events/event.dart';
import 'package:hollow_court/domain/events/hlc.dart';
import 'package:hollow_court/domain/events/overlay.dart';
import 'package:hollow_court/domain/overlay/overlay_key.dart';
import 'package:hollow_court/domain/events/price.dart';
import 'package:hollow_court/domain/events/shelf.dart';
import 'package:hollow_court/domain/events/stock.dart';
import 'package:hollow_court/domain/pricing/price.dart';
import 'package:hollow_court/domain/sync/exchange.dart';
import 'package:hollow_court/domain/sync/scope.dart';
import 'package:hollow_court/domain/units/quantity.dart';
import 'package:test/test.dart';

/// Scoping a share to one shelf: section 10.3's last promise, and the only one of the five that is a
/// rule rather than a mechanism.
///
/// **A filter is the one kind of code where a quiet mistake is worse than a loud one.** A share that
/// sends too little looks like a sync that did not work; a share that sends too much looks like one
/// that did, and nobody finds out. So every part of the rule below is asserted twice where it matters:
/// what travels, and what does not.
void main() {
  var clock = 1000;
  Hlc at() => Hlc(physicalMillis: clock++, counter: 0, nodeId: 'phone');

  Event added(String bottleId, String sku) => StockEvents.bottleAdded(
    hlc: at(),
    bottleId: bottleId,
    sku: sku,
    volume: Volume.fromMillilitres(700),
  );

  Event placed(String bottleId, String shelfId) => ShelfEvents.bottlePlaced(
    hlc: at(),
    bottleId: bottleId,
    shelfId: shelfId,
    posXPermille: 100,
    posYPermille: 200,
  );

  Event poured(String bottleId, int millilitres) => StockEvents.bottleConsumed(
    hlc: at(),
    bottleId: bottleId,
    volume: Volume.fromMillilitres(millilitres),
  );

  Event priced(String sku) => PriceEvents.paid(
    hlc: at(),
    sku: sku,
    minorUnits: 12000,
    currency: Currency.cny,
    microlitres: 700000,
    source: PriceSource.manual,
  );

  Event named(String kind, String id, String value) =>
      OverlayEvents.fieldSet(hlc: at(), key: OverlayKey(kind, id, 'name'), value: value);

  /// Two shelves, two bottles on the bar shelf and one on the back shelf, plus the things that are
  /// about one of them only.
  List<Event> cellar() {
    final gin = added('gin1', 'gin');
    final rye = added('rye1', 'rye');
    final wine = added('wine1', 'wine');
    return [
      gin,
      placed('gin1', 'bar'),
      poured('gin1', 45),
      priced('gin'),
      named('bottle', 'gin1', 'the good one'),
      rye,
      placed('rye1', 'bar'),
      priced('rye'),
      // ---- and the back shelf, which a share of the bar must not carry ----
      wine,
      placed('wine1', 'back'),
      priced('wine'),
      named('bottle', 'wine1', 'cooking wine'),
      // ---- and something that is about neither shelf ----
      OverlayEvents.fieldSet(
        hlc: at(),
        key: OverlayKey.recipe('negroni', 'note'),
        value: 'too much campari',
      ),
    ];
  }

  Set<Hlc> allowed(SyncScope scope, List<Event> events) => scope.allowedClocks(events);

  group('a share of one shelf carries that shelf and nothing else', () {
    test('the bar shelf brings its own bottles, their pours, their prices and their names', () {
      final events = cellar();
      final bar = allowed(const SyncScope.shelf('bar'), events);
      final back = allowed(const SyncScope.shelf('back'), events);

      Event find(bool Function(Event) test) => events.firstWhere(test);

      expect(bar, contains(find((e) => e.optional<String>('bottleId') == 'gin1' && e.type == StockEvent.bottleAdded).hlc));
      expect(bar, contains(find((e) => e.type == StockEvent.bottleConsumed).hlc));
      expect(bar, contains(find((e) => e.type == ShelfEvent.bottlePlaced && e.optional<String>('bottleId') == 'gin1').hlc));
      expect(bar, contains(find((e) => e.type == PriceEventTypes.paid && e.optional<String>('sku') == 'gin').hlc));
      expect(
        bar,
        contains(
          find((e) =>
              e.type == OverlayEvent.fieldSet &&
              e.optional<String>('kind') == 'bottle' &&
              e.optional<String>('id') == 'gin1').hlc,
        ),
      );

      // ---- and the back shelf's things are absent, which is the whole point ----
      expect(back, isNot(contains(find((e) => e.optional<String>('bottleId') == 'gin1' && e.type == StockEvent.bottleAdded).hlc)));
      expect(bar, isNot(contains(find((e) => e.optional<String>('bottleId') == 'wine1' && e.type == StockEvent.bottleAdded).hlc)));
      expect(bar, isNot(contains(find((e) => e.type == PriceEventTypes.paid && e.optional<String>('sku') == 'wine').hlc)));
      expect(
        bar,
        isNot(contains(
          find((e) =>
              e.type == OverlayEvent.fieldSet &&
              e.optional<String>('kind') == 'bottle' &&
              e.optional<String>('id') == 'wine1').hlc,
        )),
      );
      expect(
        back,
        hasLength(4),
        reason: 'wine: added, placed, priced, and its name -- the fourth is the one I forgot when '
            'first writing this, which is why the counts are asserted rather than the shape',
      );
    });

    test('a recipe note never travels, on any shelf', () {
      // The one thing that is about the reader's own use of the application rather than about a shelf.
      // A scoped share is a share of a shelf.
      final events = cellar();
      final noteHlc = events
          .firstWhere((e) => e.optional<String>('kind') == 'recipe')
          .hlc;

      expect(allowed(const SyncScope.shelf('bar'), events), isNot(contains(noteHlc)));
      expect(allowed(const SyncScope.shelf('back'), events), isNot(contains(noteHlc)));
      expect(
        allowed(const SyncScope.everything(), events),
        contains(noteHlc),
        reason: 'and the whole cellar still carries everything',
      );
    });

    test('everything means everything, which is what a share was before scoping existed', () {
      final events = cellar();
      expect(allowed(const SyncScope.everything(), events), hasLength(events.length));
    });

    test('a shelf nothing has ever stood on carries nothing at all', () {
      // Not an error: a bar with no bottles is a real state, and a share of it is an empty share
      // rather than a failure to describe one.
      expect(allowed(const SyncScope.shelf('the cellar we have not built'), cellar()), isEmpty);
    });
  });

  group('membership is decided by where a bottle has EVER stood', () {
    test('a bottle that moved away still belongs to the shelf it was on', () {
      // **The rule that would quietly drop a bar's history.** A bottle standing on the back shelf now
      // was on the bar last week, and the pour it contributed happened while it was there. A rule
      // based on where it is *now* answers the wrong question, and the symptom would be a shared
      // shelf whose consumption curve is missing a drink.
      var tick = 2000;
      Hlc stamp() => Hlc(physicalMillis: tick++, counter: 0, nodeId: 'phone');

      final events = <Event>[
        StockEvents.bottleAdded(
          hlc: stamp(),
          bottleId: 'moved',
          sku: 'gin',
          volume: Volume.fromMillilitres(700),
        ),
        ShelfEvents.bottlePlaced(
          hlc: stamp(),
          bottleId: 'moved',
          shelfId: 'bar',
          posXPermille: 100,
          posYPermille: 100,
        ),
        StockEvents.bottleConsumed(
          hlc: stamp(),
          bottleId: 'moved',
          volume: Volume.fromMillilitres(45),
        ),
        // ... and then it was moved to the back.
        ShelfEvents.bottlePlaced(
          hlc: stamp(),
          bottleId: 'moved',
          shelfId: 'back',
          posXPermille: 300,
          posYPermille: 100,
        ),
      ];

      final bar = allowed(const SyncScope.shelf('bar'), events);
      expect(bar, hasLength(3), reason: 'added, the bar placement, and the pour');
      expect(
        allowed(const SyncScope.shelf('back'), events).length,
        3,
        reason: 'and the back shelf has it too -- added, the pour, and its own placement',
      );
    });
  });

  group('the scoped source is what an exchange actually reads', () {
    test('it offers only the scope, and its digest is the scope', () {
      // **The digest is the first thing an exchange sends**, and it is a summary of what this device
      // holds. A digest of the whole cellar would tell a peer how much it is *not* being given, which
      // is a leak of exactly the shape the scope exists to prevent.
      final events = cellar();
      final inner = _Source(events);
      final scoped = ScopedSyncSource(
        inner: inner,
        scope: const SyncScope.shelf('bar'),
        events: events,
      );

      // Eight: gin1 added, placed, poured and named; rye1 added and placed; and the price of each --
      // which is the arithmetic the rule in the class comment exists to make checkable.
      expect(scoped.clocks, hasLength(8));
      expect(
        scoped.clocks,
        isNot(containsAll(inner.clocks)),
        reason: 'and it is a smaller set than the cellar',
      );

      final offered = scoped.missingFrom(const {});
      expect(offered, hasLength(scoped.clocks.length));
      expect(
        offered.any((e) => e.optional<String>('bottleId') == 'wine1'),
        isFalse,
        reason: 'the back shelf is not on offer',
      );
    });

    test('but it accepts everything it is given', () async {
      // A scope says what this device *gives out*. Refusing to merge what the peer sends because it
      // falls outside our scope would make a scoped share a one-way street.
      final events = cellar();
      final scoped = ScopedSyncSource(
        inner: _Source(const []),
        scope: const SyncScope.shelf('bar'),
        events: events,
      );

      final merged = await scoped.merge(events);
      expect(merged, isNotEmpty);
    });
  });

  group('what a share carries is chosen by content, and the cellar list is the default', () {
    test('the default is the bottles and nothing else', () {
      // **The owner asked for exactly this**: a first sync hands over what is in the cupboard.
      // Prices say something about somebody's finances and notes are their own jottings, so neither
      // travels until it is asked for -- a default that shipped them would be a default nobody chose.
      expect(defaultSyncKinds, {SyncKind.stock});
    });

    test('a share carrying only the cellar list leaves prices and notes behind', () {
      final events = cellar();
      final stockOnly = SyncScope.of(kinds: defaultSyncKinds);
      final allowed = stockOnly.allowedClocks(events);

      Event find(bool Function(Event) test) => events.firstWhere(test);

      expect(
        allowed,
        contains(find((e) => e.type == StockEvent.bottleAdded).hlc),
        reason: 'the bottles travel',
      );
      expect(
        allowed,
        contains(find((e) => e.type == ShelfEvent.bottlePlaced).hlc),
        reason: 'and where they stand, which is part of the list',
      );
      expect(
        allowed,
        isNot(contains(find((e) => e.type == PriceEventTypes.paid).hlc)),
        reason: 'what somebody paid does not',
      );
      expect(
        allowed,
        isNot(contains(find((e) => e.type == OverlayEvent.fieldSet).hlc)),
        reason: 'and neither do their own names for things',
      );
    });

    test('asking for the notes brings exactly the notes', () {
      final events = cellar();
      final allowed = SyncScope.of(kinds: const {SyncKind.notes}).allowedClocks(events);
      final overlay = events
          .where((e) => e.type == OverlayEvent.fieldSet || e.type == OverlayEvent.fieldCleared)
          .map((e) => e.hlc)
          .toSet();

      expect(allowed, overlay);
      expect(allowed, isNotEmpty, reason: 'the fixture has notes, so this is not vacuously true');
    });

    test('the two axes compose: one shelf AND one kind', () {
      final events = cellar();
      final allowed = SyncScope.of(
        shelfId: 'bar',
        kinds: const {SyncKind.stock},
      ).allowedClocks(events);

      // Everything allowed must be a stock event on the bar shelf -- checked from the events themselves
      // rather than from a count, because a count would pass for the wrong set.
      for (final event in events.where((e) => allowed.contains(e.hlc))) {
        expect(SyncKind.of(event.type), SyncKind.stock, reason: event.type);
        expect(
          event.type != ShelfEvent.bottlePlaced ||
              event.optional<String>('shelfId') == 'bar',
          isTrue,
        );
      }
      expect(allowed, isNotEmpty);
    });

    test('a share of nothing is a legitimate request, and carries nothing', () {
      expect(SyncScope.of(kinds: const <SyncKind>{}).allowedClocks(cellar()), isEmpty);
    });

    test('no opinion means every kind, including one added later', () {
      // Null rather than a listed set, and the difference matters: a listed set would stop carrying a
      // kind added in a later version, silently, on every caller that had asked for "everything".
      final everything = SyncScope.everything().allowedClocks(cellar());
      expect(everything, hasLength(cellar().length));
      expect(SyncScope.of().kinds, isNull);
    });

    test('every event the log can hold belongs to a kind, or is deliberately unshareable', () {
      // The list is short and closed on purpose: an event whose kind is null can never be shared by a
      // kind-scoped request, so a new event family that nobody classified is dropped rather than leaked.
      const known = [
        'stock.bottle.added',
        'stock.bottle.consumed',
        'stock.bottle.discarded',
        'stock.bottle.recounted',
        'stock.bottle.removed',
        'stock.bottle.placed',
        'price.paid',
        'overlay.field.set',
        'overlay.field.cleared',
      ];
      for (final type in known) {
        expect(SyncKind.of(type), isNotNull, reason: type);
      }
      expect(SyncKind.of('recipe.authored'), isNull);
      expect(SyncKind.of(''), isNull);
    });
  });

  test('a scope round-trips through a stored string', () {
    expect(decodeScope(encodeScope(const SyncScope.everything())).isEverything, isTrue);
    expect(decodeScope(encodeScope(const SyncScope.shelf('bar'))).shelfId, 'bar');
    // A stored value this build cannot read is the whole cellar rather than an error, which is the
    // same rule the units and the themes follow.
    expect(decodeScope('not json').isEverything, isTrue);
    expect(decodeScope('{"shelfId":""}').isEverything, isTrue);
  });
}

/// The three methods an exchange reads, over a plain list.
final class _Source implements SyncSource {
  _Source(this._events);

  final List<Event> _events;

  @override
  Set<Hlc> get clocks => {for (final event in _events) event.hlc};

  @override
  List<Event> missingFrom(Set<Hlc> theirClocks) =>
      [for (final event in _events) if (!theirClocks.contains(event.hlc)) event];

  @override
  Future<List<Event>> merge(Iterable<Event> incoming) async => [...incoming];
}
