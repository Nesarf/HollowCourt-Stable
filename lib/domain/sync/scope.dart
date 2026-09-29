import 'dart:convert';

import '../events/event.dart';
import '../events/hlc.dart';
import '../events/overlay.dart';
import '../events/price.dart';
import '../events/shelf.dart';
import '../events/stock.dart';
import 'exchange.dart';

/// Which part of a cellar a share may carry.
///
/// **Section 10.3's last promise: "sharing can be scoped to exactly which Bar, not the whole
/// library."** Everything else in that section is about who may talk to this device; this is about
/// what this device says when it does. A sync sends everything the other side is missing, so without a
/// scope, pairing your phone with a friend's laptop hands over your whole cellar -- and the design's
/// promise is that it need not.
///
/// THE RULE, STATED EXACTLY, BECAUSE A FILTER NOBODY CAN DESCRIBE IS A FILTER THAT DROPS THINGS.
///
/// A share scoped to shelf S carries:
///
/// 1. **Every placement on S** -- the events that say what stood there.
/// 2. **Every stock operation for a bottle that has ever stood on S** -- added, consumed, discarded,
///    recounted, removed. "Ever", not "currently": a bottle that was on this shelf and then moved is
///    part of this shelf's story, and a rule based on where it is *now* would drop the pours that
///    happened while it was here, which is the half of the history a bar cares about.
/// 3. **Every price observation for the ingredients those bottles are of.** A price point carries a
///    sku and not a bottle, so the sku set is derived from the scoped bottles. Without this a shared
///    shelf would show bottles with no prices, and section 7's cost per glass would silently read zero.
/// 4. **Overlay values about those bottles or those ingredients** -- a name somebody gave this bottle,
///    or this word. Recipe notes do not travel: they are the reader's own jottings about drinks, not
///    facts about the shelf being shared.
///
/// Everything else stays. The scope is a whitelist and not a blacklist on purpose: a new event type
/// added later is *not* shared until somebody decides it belongs in a scoped share, which is the
/// failure that leaks nothing rather than the one that leaks everything.
/// What a share may carry, by **content** rather than by place.
///
/// The owner asked for this in the same breath as discovery: *"默认只同步酒单，可在设置选择想要同步什么"* --
/// by default a share carries the list of what is in the cellar, and what else travels is a setting.
///
/// **The kinds are the log's own event families, because that is what there is to send.** The log holds
/// exactly three: `stock.bottle.*` (what is on the shelf and what happened to it), `price.paid` (what was
/// paid), and `overlay.*` (what the reader named things). Note what is *not* here: **a recipe is not an
/// event.** The 502 recipes are shipped seed data (section 15), identical on every install, so there is
/// nothing of a recipe to synchronise -- only the reader's own notes about one, which travel as
/// [notes]. A kind for recipes would be a switch that moved nothing.
enum SyncKind {
  /// The bottles: added, poured, discarded, recounted, retracted, and where they stand.
  stock,

  /// What was paid, and when.
  prices,

  /// The reader's own overlay: what they call an ingredient, what they named a bottle, notes on a recipe.
  notes;

  /// The kind an event belongs to, or null for an event that is not shareable by kind.
  static SyncKind? of(String eventType) {
    if (eventType.startsWith('stock.')) return SyncKind.stock;
    if (eventType.startsWith('price.')) return SyncKind.prices;
    if (eventType.startsWith('overlay.')) return SyncKind.notes;
    return null;
  }
}

/// **The default a share carries when nobody has chosen**: the cellar list, and nothing else.
///
/// Deliberately not "everything". A first sync between two devices that have just met should hand over
/// what is in the cupboard -- that is what the owner asked for and what the feature is for -- while prices
/// (which say something about somebody's finances) and notes (which are their own jottings) wait to be
/// asked for. A default that shipped them would be a default nobody chose.
const Set<SyncKind> defaultSyncKinds = {SyncKind.stock};

final class SyncScope {
  /// The whole library, of every kind. What every share was before scoping existed, and what an older
  /// caller still means by it.
  const SyncScope.everything() : shelfId = null, kinds = null;

  /// One shelf's history, by its id, of every kind.
  const SyncScope.shelf(String this.shelfId) : kinds = null;

  /// A share limited by place, by content, or by both. Null on either axis means "no limit on this one".
  const SyncScope.of({this.shelfId, this.kinds});

  /// The shelf this share is limited to, or null for the whole cellar.
  final String? shelfId;

  /// The kinds this share may carry, or **null for every kind**.
  ///
  /// Null rather than `SyncKind.values` so that "no opinion" and "all of them, listed" stay different
  /// things: the first follows a kind added later and the second does not, and a default that silently
  /// stopped carrying a new kind would be a bug nobody could see.
  final Set<SyncKind>? kinds;

  bool get isEverything => shelfId == null && kinds == null;

  /// A name for a screen: the shelf's id, or a word for "all of it".
  String get describe => shelfId ?? 'everything';

  /// The clock readings that may travel, derived from the whole log.
  ///
  /// **Derived once per share rather than tested per event**, because the rule needs the whole history:
  /// a bottle's membership of a shelf is decided by a placement that may be far from the operation
  /// being filtered, and a per-event predicate would have to re-scan the log to answer.
  Set<Hlc> allowedClocks(Iterable<Event> events) {
    if (isEverything) return {for (final event in events) event.hlc};

    // The kinds axis is checked first because it is the cheaper question and the one a share most often
    // sets: a request for the cellar list alone should not depend on which shelf a bottle stood on.
    final byKind = kinds == null
        ? events
        : events.where((event) {
            final kind = SyncKind.of(event.type);
            return kind != null && kinds!.contains(kind);
          });

    if (shelfId == null) return {for (final event in byKind) event.hlc};

    // ---- who has ever stood on this shelf, and what happened there ----------------
    //
    // Read straight off the payload rather than through a parsed op, because the shelf events do not
    // have one: `ShelfLayout` reads the same four fields for the same reason, and inventing a second
    // reader for them would be a second thing to keep in step with the wire format.
    final scoped = byKind.toList();
    final bottles = <String>{};
    for (final event in scoped) {
      if (event.type != ShelfEvent.bottlePlaced) continue;
      if (event.optional<String>('shelfId') != shelfId) continue;
      final bottleId = event.optional<String>('bottleId');
      if (bottleId != null && bottleId.isNotEmpty) bottles.add(bottleId);
    }

    // ---- which ingredients those bottles are of ----------------------------------
    final skus = <String>{};
    for (final event in scoped) {
      final op = StockOp.tryParse(event);
      if (op is BottleAdded && bottles.contains(op.bottleId)) skus.add(op.sku);
    }

    // ---- and the whitelist itself ------------------------------------------------
    final allowed = <Hlc>{};
    for (final event in scoped) {
      if (_isScoped(event, shelfId: shelfId, bottles: bottles, skus: skus)) {
        allowed.add(event.hlc);
      }
    }
    return allowed;
  }

  static bool _isScoped(
    Event event, {
    required String? shelfId,
    required Set<String> bottles,
    required Set<String> skus,
  }) {
    // 1. a placement on the shelf
    if (event.type == ShelfEvent.bottlePlaced) {
      return event.optional<String>('shelfId') == shelfId;
    }

    // 2. a stock operation for a bottle that has stood there
    final stock = StockOp.tryParse(event);
    if (stock != null) return bottles.contains(stock.bottleId);

    // 3. a price observation for an ingredient those bottles are of
    final price = PriceOp.tryParse(event);
    if (price is PricePaid) return skus.contains(price.sku);

    // 4. a name about those bottles or those ingredients
    final overlay = OverlayOp.tryParse(event);
    if (overlay != null &&
        (overlay is OverlayFieldSet || overlay is OverlayFieldCleared)) {
      // `key` is on the base class, so both an assignment and a removal answer the same question:
      // what is this about?
      final key = overlay.key;
      return switch (key.kind) {
        'bottle' => bottles.contains(key.id),
        'ingredient' => skus.contains(key.id),
        // Everything else -- a recipe note, a correction to a shipped string -- is about the reader's
        // own use of the application rather than about the shelf, and a scoped share is about a shelf.
        _ => false,
      };
    }

    return false;
  }
}

/// A cellar's events, filtered to what a scope allows.
///
/// **A wrapper rather than a change to `EventLog`.** The scope is a property of *one share* -- the same
/// cellar may be shared wholesale with a phone and shelf-by-shelf with a friend -- so it belongs to the
/// thing doing the sharing, not to the log. `SyncSource` is already the interface an exchange reads
/// through, which is why this is three methods and not a refactor.
final class ScopedSyncSource implements SyncSource {
  ScopedSyncSource({
    required this.inner,
    required this.scope,
    required Iterable<Event> events,
  }) : _allowed = scope.allowedClocks(events);

  final SyncSource inner;
  final SyncScope scope;
  final Set<Hlc> _allowed;

  /// **The scoped readings, not the whole cellar's.** This is what an exchange turns into the digest
  /// it sends first -- a summary of what the other side is being offered -- and a digest of the whole
  /// log would tell a peer how much it is *not* being given.
  @override
  Set<Hlc> get clocks => {
    for (final clock in inner.clocks)
      if (_allowed.contains(clock)) clock,
  };

  @override
  List<Event> missingFrom(Set<Hlc> theirClocks) => [
    for (final event in inner.missingFrom(theirClocks))
      if (_allowed.contains(event.hlc)) event,
  ];

  /// Merging is not scoped, and that is deliberate: a scope says what this device *gives out*.
  /// Refusing to accept what the peer sends because it is outside our scope would make a scoped share
  /// a one-way street, and the peer's own scope is the peer's business.
  @override
  Future<List<Event>> merge(Iterable<Event> incoming) => inner.merge(incoming);
}

/// The JSON a scope round-trips through, for a stored share.
String encodeScope(SyncScope scope) =>
    jsonEncode({'shelfId': scope.shelfId});

SyncScope decodeScope(String text) {
  try {
    final decoded = jsonDecode(text);
    if (decoded is! Map<String, Object?>) return const SyncScope.everything();
    final shelfId = decoded['shelfId'];
    if (shelfId is! String || shelfId.isEmpty) return const SyncScope.everything();
    return SyncScope.shelf(shelfId);
  } on FormatException {
    return const SyncScope.everything();
  }
}
