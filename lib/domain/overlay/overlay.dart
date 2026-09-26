import '../events/event.dart';
import '../events/hlc.dart';
import '../events/overlay.dart';
import 'overlay_key.dart';
import 'synonyms.dart';

/// One field's value, and when it was last set.
final class OverlayEntry {
  const OverlayEntry({required this.key, required this.value, required this.setAt});

  final OverlayKey key;

  /// The user's own text. Never empty: [Overlay] does not hold an entry for a
  /// field that was set to nothing, because a reader cannot tell that state apart
  /// from a field that is not there.
  final String value;

  /// The reading of the `set` that won.
  ///
  /// Kept because "why does it say that" is a question an overlay gets asked, and
  /// a value with no clock cannot answer it.
  final Hlc setAt;

  @override
  String toString() => '${key.toString()} = "$value"';
}

/// The overlay layer, folded from the log.
///
/// Section 8's separation, made mechanical: the seed is replaced wholesale on
/// update and this is not, so a user's note, alias or correction outlives every
/// rebuild of the library. It holds no reference to the seed at all -- an entry
/// names a key and nothing else -- which is what makes "the overlay never gets
/// lost" a property of the type rather than a promise about the update code.
///
/// **Field-level last-writer-wins, which is what section 10.4 asks for**: stock
/// goes through the op-log, "other fields use field-level LWW". So two devices
/// that each edited different fields of the same entity both keep their edit, and
/// two that edited the same field resolve by clock rather than by arrival.
///
/// ## Why there is no tombstone in the state
///
/// A removal is applied by *removing the entry*, and the usual objection to that
/// is a real one in the usual setting: if a peer still holds the `set` you
/// cleared, merging its state would resurrect the value you threw away. That is
/// why a state-based store has to keep the clear around as a tombstone.
///
/// **This store merges logs, not states.** Section 10.4 reduces a sync to
/// "exchanging events the other side is missing", and [of] sorts the whole log by
/// clock before applying anything -- so a clear and an older `set` are always
/// applied in the order that makes the clear win, whatever order they arrived in.
/// A tombstone would be a second copy of a fact the sorted log already carries.
///
/// **What would break that, written down because it is a real future temptation.**
/// Compacting the log: dropping an old `set` and the `clear` that superseded it
/// together is safe only while nothing older can still arrive, and "nothing older
/// can arrive" is a claim about sync rather than about the file. A compacted log
/// would need the tombstone kept, and the day someone adds compaction is the day
/// this paragraph stops being true.
final class Overlay {
  Overlay._(
    this._entries, {
    required List<OverlayFieldSet> emptySets,
    required int applied,
    required int ignored,
  }) : emptySets = List.unmodifiable(emptySets),
       appliedEvents = applied,
       ignoredEvents = ignored;

  final Map<OverlayKey, OverlayEntry> _entries;

  /// Sets that arrived carrying an empty value.
  ///
  /// **Surfaced rather than dropped, and it should always be empty.** `fieldSet`
  /// refuses an empty value and points the caller at `fieldCleared`, so an empty
  /// one in the log can only have been written by another build -- which is
  /// worth seeing rather than smoothing over.
  ///
  /// They are read as removals, because that is the only thing an empty value can
  /// mean to a reader, and the alternative is a screen drawing a blank line where
  /// a note used to be and calling it a value.
  final List<OverlayFieldSet> emptySets;

  /// How many events this fold actually reduced.
  final int appliedEvents;

  /// How many it could not read, which is normal when a log carries events
  /// written by a newer build.
  final int ignoredEvents;

  /// Folds [events] into an overlay.
  ///
  /// Applies them in clock order and applies each clock reading at most once,
  /// both for the same reasons the stock ledger does: clock order because LWW is
  /// defined by the clock, and deduplication because a sync sends everything the
  /// other side is missing and a device missing a stretch of the log will happily
  /// send one event twice.
  ///
  /// **The fold is a pure function of the *set* of events**, which is the
  /// property that makes two devices agree: shuffling the input produces the same
  /// overlay, because the sort is what decides and not the order of the argument.
  factory Overlay.of(Iterable<Event> events) {
    final ordered = events.toList()..sort((a, b) => a.hlc.compareTo(b.hlc));

    final entries = <OverlayKey, OverlayEntry>{};
    final empty = <OverlayFieldSet>[];
    final seen = <Hlc>{};
    var applied = 0;
    var ignored = 0;

    for (final event in ordered) {
      if (!seen.add(event.hlc)) continue; // already applied, or a duplicate
      final op = OverlayOp.tryParse(event);
      if (op == null) {
        ignored++;
        continue;
      }
      applied++;

      switch (op) {
        case OverlayFieldSet():
          if (op.value.isEmpty) {
            empty.add(op);
            entries.remove(op.key);
            continue;
          }
          entries[op.key] = OverlayEntry(
            key: op.key,
            value: op.value,
            setAt: op.hlc,
          );
        case OverlayFieldCleared():
          entries.remove(op.key);
      }
    }

    return Overlay._(entries, emptySets: empty, applied: applied, ignored: ignored);
  }

  /// Every field that is set, keyed by what it is attached to.
  Map<OverlayKey, OverlayEntry> get entries => Map.unmodifiable(_entries);

  bool get isEmpty => _entries.isEmpty;

  int get length => _entries.length;

  bool has(OverlayKey key) => _entries.containsKey(key);

  /// What [key] holds, or null when nothing does.
  ///
  /// **Null is a result and not a failure.** A field nobody has set is a field
  /// with no value in it, and the seed's own value belongs to the seed: this layer
  /// only ever answers for what a person put on top of it.
  String? value(OverlayKey key) => _entries[key]?.value;

  /// The whole of one entity's overlay, by field name.
  ///
  /// Used for a screen that wants to draw "everything this person changed about
  /// this thing" without knowing the field names in advance -- which is section
  /// 8's `extras`, and is why the field part of a key allows dots.
  Map<String, String> fieldsOf(String kind, String id) => {
    for (final MapEntry(key: key, value: stored) in _entries.entries)
      if (key.kind == kind && key.id == id) key.field: stored.value,
  };

  /// Section 8's `extras: Map<String, String>`, with the prefix taken off.
  ///
  /// The prefix is in the key rather than in a separate table so that an extra is
  /// an ordinary overlay field: it syncs, it merges and it is cleared by the same
  /// two events as everything else, and there is no third path to get wrong.
  Map<String, String> extrasOf(String kind, String id) => {
    for (final MapEntry(key: key, value: stored) in _entries.entries)
      if (key.kind == kind &&
          key.id == id &&
          key.field.startsWith(_extraPrefix))
        key.field.substring(_extraPrefix.length): stored.value,
  };

  /// A note somebody wrote on a recipe, or null.
  String? recipeNote(String recipeId) => value(OverlayKey.recipe(recipeId));

  /// The reader's dictionary of equivalent names, as the block of text the editor holds, or empty.
  String get synonymBlock => value(OverlayKey.synonymTable) ?? '';

  /// The table, parsed. Parsing on every read is deliberate: the block is a few lines and the parse is a
  /// split, while a cache would be a second copy of the reader's words to keep in step with the first.
  List<SynonymGroup> get synonymGroups => parseSynonymBlock(synonymBlock).groups;

  /// What somebody calls this bottle, or null when they have not renamed it.
  String? bottleName(String bottleId) => value(OverlayKey.bottle(bottleId));

  /// What somebody calls an ingredient, or null when they call it what the seed
  /// calls it.
  String? ingredientAlias(String ingredientId) =>
      value(OverlayKey.ingredient(ingredientId));

  static const _extraPrefix = 'extras.';
}
