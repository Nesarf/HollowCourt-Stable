import '../../data/folder_styles.dart';
import '../events/court_pack.dart';
import '../events/event.dart';

/// The packs the reader defined, folded from the log.
///
/// **The fold that makes a folder name survive a sync.** A recipe already carried a `packId`, and the reader's own
/// name for that folder lived in `folder_styles.json` -- **a file beside the cellar**, outside the log. So everything
/// else in this application travelled between devices and the folder names did not, which is the inconsistency
/// `docs/proposal-recipes-and-packs.md` §1 is about: a pack is *where a recipe came from*, and it should be a thing
/// the reader owns in the same way their recipes and their ingredients are.
///
/// **Beside the shelf rather than inside the seed**, for the reason the other four folds are: a reader's own
/// additions must not be shipped to anybody else, and `SeedRepository` is an asset that is identical on every
/// install.
final class PackBook {
  const PackBook(this.packs);

  /// Every pack the reader defined and has not removed, by id.
  ///
  /// **`official` is not in here.** It ships with the build, so it has no event and cannot be removed; a screen that
  /// lists folders shows it first and reads its name from the build. What this holds is what somebody typed.
  final Map<String, CourtPack> packs;

  static const PackBook none = PackBook({});

  bool get isEmpty => packs.isEmpty;
  bool get isNotEmpty => packs.isNotEmpty;
  int get length => packs.length;

  /// The reader's packs, in the order they were written.
  List<CourtPack> get all => packs.values.toList(growable: false);

  CourtPack? operator [](String id) => packs[id];

  /// Whether [id] names a pack the reader made, as opposed to one the build ships.
  bool isMine(String id) => packs.containsKey(id);

  /// The folds in a stable order: **the reader's own first, then the shipped one.**
  ///
  /// The order a screen lists folders in, and the reason it is here rather than in the page is that two screens
  /// listing the same packs differently is a disagreement about the reader's own library.
  List<CourtPack> get ordered {
    final out = all;
    out.sort((a, b) {
      final ao = a.order;
      final bo = b.order;
      if (ao == null && bo == null) return 0;
      if (ao == null) return 1;
      if (bo == null) return -1;
      return ao.compareTo(bo);
    });
    return out;
  }

  /// **One entry of the old style file, as a pack.**
  ///
  /// The mapping the one-time migration runs, pulled out as a pure function so that **the part with a decision in
  /// it can be tested without a file system or a cellar**: the store's `name` is optional and a pack's is not.
  ///
  /// **A style with no name becomes a pack named after its key**, and that is the only defensible choice rather than
  /// an arbitrary one: the key is `source/category` -- what the folder is called on screen today -- so the migrated
  /// pack keeps the name the reader is already looking at instead of arriving blank or being dropped. **Dropping it
  /// would be the quiet failure**, because a style with only an `order` or only an `accent` is a real thing a reader
  /// can have, and losing it would mean their folder silently reordered.
  static CourtPack packFromStyle(String key, FolderStyle style) => CourtPack(
    id: key,
    name: style.name ?? key,
    note: style.note,
    accent: style.accent,
    order: style.order,
  );

  /// **The packs as the folder styles the recipes page already knows how to draw.**
  ///
  /// The migration `docs/proposal-recipes-and-packs.md` §1 asks for, done in one place: the page reads a folder's
  /// name, note, colour and order, and it has always read them from `folder_styles.json`. **`CourtPack` carries the
  /// same four fields**, so this is a view rather than a second record -- and it is what makes a renamed folder
  /// travel between devices, because the data now comes off the log.
  ///
  /// **A view rather than a rename of `FolderStyle`**, because the page's own model is a *style* -- an optional
  /// override on a derived folder -- while a pack is a *record* the reader owns. Collapsing the two would force the
  /// page to decide what a missing pack means, which is the question the override shape already answers with null.
  ///
  /// **It lives here rather than in the page** so that the day the page stops needing `FolderStyle` entirely, the
  /// only thing to delete is this method and its import.
  Map<String, FolderStyle> get asFolderStyles => {
    for (final pack in packs.values)
      pack.id: FolderStyle(
        name: pack.name,
        note: pack.note,
        order: pack.order,
        accent: pack.accent,
      ),
  };

  /// Folds every pack event in [events].
  ///
  /// **Sorted by clock rather than read in file order**, the rule every fold here follows: a merged log holds a
  /// peer's events interleaved with local ones, and a write that replaced a pack has to be applied after the write
  /// it replaced however the arrivals happened to land. Two devices folding the same set therefore agree.
  factory PackBook.of(Iterable<Event> events) {
    final ordered = events.where((event) => CourtPackEvent.all.contains(event.type)).toList()
      ..sort((a, b) => a.hlc.compareTo(b.hlc));

    final out = <String, CourtPack>{};
    for (final event in ordered) {
      if (event.type == CourtPackEvent.removed) {
        // A removal of something never seen is not an error: it is what a device that has just been sent a deletion
        // sees, and the fold's answer -- that this pack is not held -- is right either way.
        final id = CourtPackOp.removedId(event);
        if (id != null) out.remove(id);
        continue;
      }
      if (event.type != CourtPackEvent.set) continue;
      final pack = CourtPackOp.tryParse(event)?.pack;
      // A malformed payload of a known type throws inside `tryParse` rather than arriving null, so null here means
      // the event was not one of ours after all -- skipped rather than guessed at.
      if (pack == null) continue;
      out[pack.id] = pack;
    }
    return PackBook(out);
  }
}
