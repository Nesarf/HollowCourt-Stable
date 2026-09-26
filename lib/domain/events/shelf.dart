import 'event.dart';
import 'hlc.dart';

/// Shelf placement: where a bottle physically stands.
///
/// **Why this is not a [StockOp].** `StockOp.tryParse` refuses any event without
/// a `volumeMicrolitres`, because every stock operation is arithmetic on a
/// quantity. Placement is not: standing a bottle on a shelf moves nothing and
/// pours nothing. Forcing it into that family would have meant giving a
/// position a volume it does not have, which is the kind of field that looks
/// like data and means nothing. So placement is a **second fold over the same
/// log** rather than a fifth member of the quantity family.
///
/// **Why it belongs to the log at all**, rather than to the overlay layer of
/// section 8: the arrangement of a real cupboard is a fact about the cupboard,
/// not a personal opinion about it. Two devices that hold the same events should
/// show the same shelf, which is exactly what section 12.2 asks for when it puts
/// `posX` / `posY` / `shelfId` on the bottle.
abstract final class ShelfEvent {
  /// A bottle was stood at a position on a shelf, or moved to another one.
  ///
  /// **One event for both**, because a move is a placement whose clock reading
  /// is later. A separate `moved` type would carry the same payload and would
  /// have to be folded by the same rule, so the distinction would live only in
  /// the name.
  static const bottlePlaced = 'stock.bottle.placed';

  /// Every type this build knows how to reduce.
  static const all = {bottlePlaced};
}

/// Builders for the shelf events.
///
/// The clock reading is passed in rather than read here, for the same reason as
/// [StockEvents]: an event's contents have to be assertable exactly in a test.
abstract final class ShelfEvents {
  /// Stands [bottleId] on [shelfId] at a position, or moves it there.
  ///
  /// **Positions are integer per-mille, not fractions.** 0..1000 along each
  /// axis, so 500 is the middle of a shelf. Two reasons, and the first is not
  /// the obvious one: a fraction cannot be asserted exactly in a test, so a
  /// rounding difference between two devices would be invisible until it
  /// accumulated -- which is the same argument that put the volume base at
  /// integer microlitres. The second is that the shelf is laid out to a
  /// resolution, and saying which resolution is better than implying infinite
  /// precision the layout does not have.
  static Event bottlePlaced({
    required Hlc hlc,
    required String bottleId,
    required String shelfId,
    required int posXPermille,
    required int posYPermille,
  }) {
    assert(bottleId != '', 'a placement without a bottle is not a placement');
    assert(shelfId != '', 'a placement without a shelf is not a placement');
    assert(
      posXPermille >= 0 && posXPermille <= _permilleFull,
      'posXPermille is 0..$_permilleFull, and $posXPermille is outside it',
    );
    assert(
      posYPermille >= 0 && posYPermille <= _permilleFull,
      'posYPermille is 0..$_permilleFull, and $posYPermille is outside it',
    );
    return Event(
      hlc: hlc,
      type: ShelfEvent.bottlePlaced,
      data: {
        'bottleId': bottleId,
        'shelfId': shelfId,
        'posXPermille': posXPermille,
        'posYPermille': posYPermille,
      },
    );
  }
}

/// The full extent of one axis, in per-mille.
const int _permilleFull = 1000;

/// Where one bottle stands.
final class BottlePlacement {
  const BottlePlacement({
    required this.bottleId,
    required this.shelfId,
    required this.posXPermille,
    required this.posYPermille,
    required this.hlc,
  });

  final String bottleId;
  final String shelfId;
  final int posXPermille;
  final int posYPermille;

  /// The reading that produced this placement, kept so that a later move can be
  /// told from an earlier one without consulting the log again.
  final Hlc hlc;

  /// The position as a fraction of the shelf, for a layout that works in
  /// fractions. Only the *display* side converts; the stored value stays whole.
  double get x => posXPermille / _permilleFull;

  double get y => posYPermille / _permilleFull;

  @override
  String toString() =>
      'BottlePlacement($bottleId at $shelfId $posXPermille/$posYPermille)';

  @override
  bool operator ==(Object other) =>
      other is BottlePlacement &&
      other.bottleId == bottleId &&
      other.shelfId == shelfId &&
      other.posXPermille == posXPermille &&
      other.posYPermille == posYPermille &&
      other.hlc == hlc;

  @override
  int get hashCode =>
      Object.hash(bottleId, shelfId, posXPermille, posYPermille, hlc);
}

/// The fold from shelf events to where everything stands.
///
/// Pure, like [StockLedger] and for the same reason: two devices holding the
/// same events hold the same arrangement, in whatever order they arrived.
final class ShelfLayout {
  const ShelfLayout._(
    this._byBottle, {
    required int placed,
    required int duplicates,
    required int malformed,
    required int ignored,
  }) : placedEvents = placed,
       duplicateEvents = duplicates,
       malformedEvents = malformed,
       ignoredEvents = ignored;

  /// Reads a whole log, keeping only what this fold understands.
  ///
  /// Events are ordered by their own clock reading, not by the order they were
  /// given, because a sync delivers them in whatever order the network
  /// produced. Ties cannot happen: [Hlc] compares by physical time, then
  /// counter, then node id, so the order is total.
  factory ShelfLayout.of(Iterable<Event> events) {
    final seen = <Hlc>{};
    var duplicates = 0;
    var malformed = 0;
    var ignored = 0;
    final ordered = <Event>[];
    for (final event in events) {
      if (!ShelfEvent.all.contains(event.type)) {
        ignored++;
        continue;
      }
      if (!seen.add(event.hlc)) {
        duplicates++;
        continue;
      }
      ordered.add(event);
    }
    ordered.sort((a, b) => a.hlc.compareTo(b.hlc));

    final byBottle = <String, BottlePlacement>{};
    var placed = 0;
    for (final event in ordered) {
      final bottleId = event.optional<String>('bottleId');
      final shelfId = event.optional<String>('shelfId');
      final x = event.optional<int>('posXPermille');
      final y = event.optional<int>('posYPermille');
      if (bottleId == null ||
          bottleId.isEmpty ||
          shelfId == null ||
          shelfId.isEmpty ||
          x == null ||
          y == null) {
        malformed++;
        continue;
      }
      if (x < 0 || x > _permilleFull || y < 0 || y > _permilleFull) {
        // Reported rather than clamped. A position outside the shelf is a real
        // disagreement between two builds -- a different resolution, a bad
        // write -- and pinning it to the edge would hide the only evidence.
        malformed++;
        continue;
      }
      // Later wins, which is what makes a move a move. An earlier placement is
      // not an error and is not counted as one.
      byBottle[bottleId] = BottlePlacement(
        bottleId: bottleId,
        shelfId: shelfId,
        posXPermille: x,
        posYPermille: y,
        hlc: event.hlc,
      );
      placed++;
    }
    return ShelfLayout._(
      byBottle,
      placed: placed,
      duplicates: duplicates,
      malformed: malformed,
      ignored: ignored,
    );
  }

  final Map<String, BottlePlacement> _byBottle;

  /// How many placement events were applied. A move counts twice here, because
  /// two placements were applied; [placed] is a count of events, not of bottles.
  final int placedEvents;

  /// Events already seen, which a sync may send again.
  final int duplicateEvents;

  /// Events that claimed to be placements and were not usable.
  final int malformedEvents;

  /// Events of other types, which this fold does not reduce.
  final int ignoredEvents;

  /// Where [bottleId] stands, or null when nothing has been recorded.
  ///
  /// **Null is not a default position.** A bottle with no placement has not been
  /// put anywhere yet, and placing it at the origin would say somebody put it
  /// against the left wall. The distinction is the same one `library.dart` makes
  /// between an empty shelf and a bare cellar.
  BottlePlacement? placementOf(String bottleId) => _byBottle[bottleId];

  /// Whether anything has been recorded for [bottleId].
  bool isPlaced(String bottleId) => _byBottle.containsKey(bottleId);

  /// Everything standing on one shelf, ordered left to right and then front to
  /// back, so a caller that draws them in order gets a stable picture rather
  /// than one that depends on map iteration.
  List<BottlePlacement> onShelf(String shelfId) {
    final found = _byBottle.values.where((p) => p.shelfId == shelfId).toList()
      ..sort((a, b) {
        final byX = a.posXPermille.compareTo(b.posXPermille);
        if (byX != 0) return byX;
        final byY = a.posYPermille.compareTo(b.posYPermille);
        if (byY != 0) return byY;
        return a.bottleId.compareTo(b.bottleId);
      });
    return List.unmodifiable(found);
  }

  /// Every shelf that holds something.
  Set<String> get shelves =>
      Set.unmodifiable({for (final p in _byBottle.values) p.shelfId});

  /// How many bottles have a recorded position.
  int get placedCount => _byBottle.length;

  /// How many bottles in [bottleIds] have never been placed.
  ///
  /// Takes the bottles rather than reading the stock ledger, so that this fold
  /// stays independent of the quantity family: a caller that wants "which of my
  /// bottles are still in the box" has both lists and can ask.
  List<String> unplacedAmong(Iterable<String> bottleIds) =>
      List.unmodifiable(bottleIds.where((id) => !_byBottle.containsKey(id)));
}
