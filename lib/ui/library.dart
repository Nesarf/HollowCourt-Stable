import 'archive_providers.dart';
import '../domain/units/unit.dart';
import '../domain/units/matter_inference.dart';
import 'dart:io';

import 'package:flutter/foundation.dart' show FlutterError;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../data/archive_package.dart';
import '../data/folder_styles.dart';
import '../data/event_log.dart';
import '../data/seed/seed_codec.dart';
import '../data/seed/seed_repository.dart';
import '../domain/events/event.dart';
import '../domain/events/hlc.dart';
import '../domain/events/overlay.dart';
import '../domain/events/price.dart';
import '../domain/events/court_pack.dart';
import '../domain/events/ingredient_authoring.dart';
import '../domain/events/recipe_authoring.dart';
import '../domain/events/recipe_collection.dart';
import '../domain/events/shelf.dart';
import '../domain/events/stock.dart';
import '../domain/matching/match_score.dart';
import '../domain/model/recipe.dart';
import '../domain/model/ingredient_book.dart';
import '../domain/model/recipe_book.dart';
import '../domain/model/pack_book.dart';
import '../domain/model/recipe_collections.dart';
import '../domain/overlay/overlay.dart';
import '../domain/overlay/overlay_key.dart';
import '../domain/pricing/price.dart';
import '../domain/units/quantity.dart';

/// The drink library, or null when this build has none.
///
/// **Null is a state the screens render, not an error they swallow.** Section
/// 15 keeps the seed out of git, so a clone that has not run
/// `dart run tools/build_seed.dart` genuinely has no library -- and showing an
/// empty shelf would say the cellar is bare when the truth is that the shelf was
/// never built. Section 20.6 asks the same of a missing Pro pack: degrade to
/// nothing rather than to a placeholder.
final seedProvider = AsyncNotifierProvider<SeedNotifier, SeedRepository?>(
  SeedNotifier.new,
);

class SeedNotifier extends AsyncNotifier<SeedRepository?> {
  /// Where pubspec declares the directory.
  // **Our own library, assembled from `data/drinks/library.json`.** It replaced `assets/seed/seed.json` on
  // 2026-09-22, when the harvested another source and one source data was deleted at the owner's instruction: their
  // recipe names and measures were each author's own, so the application now ships a list referenced
  // against the IBA's official one, with our instruction text and our translations.
  static const assetPath = 'assets/drinks/library.json';

  @override
  Future<SeedRepository?> build() async {
    final String source;
    try {
      source = await rootBundle.loadString(assetPath);
    } on FlutterError {
      // The asset is not in the bundle. That is the fresh-clone case rather than
      // a fault, so it resolves to null rather than to an error state.
      return null;
    } catch (_) {
      return null;
    }
    try {
      return SeedRepository.fromJson(source);
    } on SeedFormatException {
      // A seed that cannot be read is different from one that is absent, but the
      // screen has the same thing to say either way: there is no library. The
      // difference belongs in a diagnostic, not in a person's way.
      return null;
    }
  }
}

/// The event log and the ledger folded from it.
///
/// Held together because they are never useful apart: the ledger is a pure
/// function of the log, so a write and a re-fold are one operation.
final class Cellar {
  const Cellar({
    required this.log,
    required this.stock,
    required this.overlay,
    required this.shelf,
    required this.authoredRecipes,
    required this.authoredIngredients,
    required this.collections,
    required this.packs,
    required this.archivedEvents,
  });

  /// **How many of the events these folds read came out of the reader's packages.**
  ///
  /// Carried so that a screen can say so, and it is not a decoration: **a consumption curve drawn from three years of
  /// log and one drawn from ten years of log plus two archives look identical**, and only one of them is the whole
  /// history. This is the number that tells them apart.
  final int archivedEvents;

  /// Whether any of what is folded here came from a package.
  bool get readsArchives => archivedEvents > 0;

  /// Both folds of one log, taken together.
  ///
  /// A factory rather than three arguments at every site, because the two folds
  /// have to be of the *same* log: a caller that folded one of them from a stale
  /// list would produce a screen where the shelf and the notes disagree about
  /// what has happened, and the disagreement would be invisible.
  ///
  /// **[archived] is the events a reader attached from their own packages**, and `docs/archival.md` is why they are
  /// merged here rather than folded separately: **history cannot be folded in two halves and combined.** Every fold
  /// sorts by clock and applies in that order, so a bottle added in a package and poured in the log would fold as *a
  /// pour of nothing, then an unopened bottle*. Merging first is the only order that works, and it is the same one a
  /// merge from a peer already uses.
  ///
  /// **And the line this does not cross**: [log]'s `digest` and `missingFrom` are about *the working log* and keep
  /// reading it alone. **Archives travel by their own frame rather than by the event difference** -- if a peer's clock
  /// set described events this machine has moved out of the log, the two would agree about a history neither of them
  /// can send.
  factory Cellar.of(EventLog log, {List<Event> archived = const []}) {
    // **Nothing archived is the ordinary case, and it costs nothing**: not one fold is recomputed, so a cellar whose
    // history fits in the log behaves exactly as it did before this parameter existed.
    if (archived.isEmpty) {
      return Cellar(
        log: log,
        stock: log.stock,
        overlay: log.overlay,
        shelf: log.shelf,
        authoredRecipes: log.authoredRecipes,
        authoredIngredients: log.authoredIngredients,
        collections: log.collections,
        packs: log.packs,
        archivedEvents: 0,
      );
    }
    final all = [...archived, ...log.events]..sort((a, b) => a.hlc.compareTo(b.hlc));
    return Cellar(
      log: log,
      stock: StockLedger.of(all),
      overlay: Overlay.of(all),
      shelf: ShelfLayout.of(all),
      authoredRecipes: RecipeBook.of(all),
      authoredIngredients: IngredientBook.of(all),
      collections: RecipeCollections.of(all),
      packs: PackBook.of(all),
      archivedEvents: archived.length,
    );
  }

  final EventLog log;
  final StockLedger stock;

  /// Section 8's overlay: everything a person has put on top of the seed.
  final Overlay overlay;

  /// Where the bottles physically stand, folded from the same events.
  ///
  /// Held here rather than fetched by the page, because the arrangement and the
  /// quantities have to be of the *same* log: a Bar tab drawing stale positions
  /// over a fresh shelf would show a bottle that has been poured away.
  final ShelfLayout shelf;

  /// The recipes the reader wrote, folded from the same log.
  ///
  /// **Here rather than fetched by the page, for the reason the shelf is here**: the recipes a reader has written
  /// and the bottles they hold have to be of *the same* log, or a recipe would read as unmakable against a shelf
  /// that has since changed. A reader's own recipe and a shipped one are the same record shape -- see `RecipeBook` --
  /// so a screen holds both in one list and only has to ask `isMine` when it decides whether to offer a delete.
  final RecipeBook authoredRecipes;

  /// The ingredients the reader added, folded from the same log.
  ///
  /// **Beside the recipes rather than inside the catalogue**, because the two are different kinds of thing: the
  /// catalogue is what ships, and this is what somebody typed. `IngredientBook` argues the split; what matters here
  /// is that a screen holding both can ask one question -- is this id the reader's? -- and get an answer that
  /// decides whether a delete button belongs on the row.
  final IngredientBook authoredIngredients;

  /// The collections the reader made, and the derived folders they hid.
  ///
  /// **Here for the reason every other fold is here**: a collection names recipes and members, and a screen joining
  /// it against a stale recipe list would show a collection containing drinks that no longer exist -- or, worse,
  /// hide drinks that do. Folded from the same log, that cannot happen.
  final RecipeCollections collections;

  /// The packs the reader defined, folded from the same log.
  ///
  /// **Beside the collections and not inside them.** A collection is a reader saying *these belong together*, and a
  /// pack is *where this recipe came from* -- so a recipe is in exactly one pack and may be in many collections, which
  /// is why one is a field on the recipe and the other is a list of members.
  final PackBook packs;

  /// A bottle is on the shelf when its sku has remaining volume.
  ///
  /// The join between the seed and the shelf is this one comparison. A recipe
  /// item names an ingredient id; a bottle carries a sku. Nothing else about the
  /// two layers has to agree, which is why the ids had to be made canonical
  /// before any of this could work.
  bool has(String ingredientId) => stock.bottles.any(
    (bottle) => bottle.sku == ingredientId && bottle.remaining.microlitres > 0,
  );

  /// Section 9's score, for one recipe against this shelf.
  MatchScore scoreOf(Recipe recipe) => MatchScore.of([
    for (final item in recipe.items)
      Requirement(
        id: item.ingredientId,
        role: item.role,
        available: has(item.ingredientId),
      ),
  ]);
}

/// **How each ingredient in the library is measured, worked out from the drinks themselves.**
///
/// The owner asked for this on 2026-09-22 (*"落实固体、液体、组合等对应默认计量单位的智能识别"*), and the
/// domain rule lives in `domain/units/matter_inference.dart`: what every drink pours is a liquid, what every
/// drink weighs is a solid, what the drinks do both ways is *either*, and what they count is neither -- with
/// the library's own `defaultUnit` outranking the statistics where somebody wrote one down.
///
/// **A provider rather than a call at the point of use**, because the answer is a fact about the loaded
/// library: it is computed once, and the entry form and anything else that asks get the same readings rather
/// than two computations that could drift.
final matterReadingsProvider = Provider<Map<String, MatterReading>>((ref) {
  final repository = ref.watch(seedProvider).value;
  if (repository == null) return const {};

  // **A line with no unit is not evidence about how a thing is measured** -- it is a drink that counts or
  // describes it -- so it is left out rather than guessed at, and `MatterEvidence` already keeps counted
  // instances apart from measurable ones for the same reason.
  final lines = <({String ingredientId, Unit unit})>[
    for (final recipe in repository.recipes)
      for (final item in recipe.items)
        if (item.unit != null) (ingredientId: item.ingredientId, unit: item.unit!),
  ];
  final evidence = gatherEvidence(lines);

  return {
    for (final ingredient in repository.ingredients)
      ingredient.id: inferMatter(
        evidence: evidence[ingredient.id] ?? const MatterEvidence(),
        statedDefault: ingredient.defaultUnit,
        // The owner's three inputs, in the order that keeps each one honest: a statement about this
        // ingredient, then what the drinks do, then what its group is like.
        category: ingredient.category?.name,
      ),
  };
});

final cellarProvider = AsyncNotifierProvider<CellarNotifier, Cellar>(
  CellarNotifier.new,
);

/// The price history of one ingredient, folded from the same log as the shelf.
///
/// **A family rather than one series**, because section 7's metrics are per item: a cost
/// per glass is the cost of *this* bottle, and a chart of the whole cellar mixed together
/// would be a number with no meaning. The fold is taken from the same log the shelf is
/// folded from -- `Cellar.of` exists precisely so that two folds cannot be taken from
/// different lists and quietly disagree.
///
/// A cellar that has not loaded yet answers with an **empty series rather than null**,
/// because there is nothing a chart can say about "not yet" that it cannot say about
/// "nothing recorded", and inventing a third state for it would give the screen a
/// distinction it has no words for.
final priceSeriesForProvider = Provider.family<PriceSeries, String>((ref, sku) {
  final cellar = ref.watch(cellarProvider).value;
  if (cellar == null) return PriceSeries(const <PricePoint>[]);
  // **The retractions the shelf was built from, handed to the price fold.** The two folds read the
  // same log and only one of them knows that a line can be withdrawn; without this a bottle removed
  // by mistake would keep its purchase in the chart, and the chart would look like data.
  return priceSeriesOf(
    cellar.log.events,
    sku: sku,
    removedBottles: cellar.stock.removedBottleIds,
  );
});

class CellarNotifier extends AsyncNotifier<Cellar> {
  /// The identity this device writes events under.
  ///
  /// A constant for now. Section 10 gives every device its own node id so that
  /// two cellars can merge, and that work has not been done -- so this says so
  /// rather than pretending to be per-device.
  static const nodeId = 'local';

  EventLog? _log;
  int _clock = DateTime.now().millisecondsSinceEpoch;

  @override
  Future<Cellar> build() async {
    final log = _log ?? await _open();
    _log = log;
    await _migrateFolderStylesOnce(log);
    return Cellar.of(log, archived: await _attachedEvents());
  }

  /// **The events of the packages the reader has attached, and nothing else.**
  ///
  /// `docs/archival.md`: no package is read unless it was chosen. **Watched rather than read**, so that ticking a
  /// package on the 归档 section re-folds every projection in the application -- which is the whole point of attaching
  /// one, and would otherwise be a control that changes a list and nothing else.
  ///
  /// **A package that cannot be read is skipped rather than fatal**, the same rule `CellarHistory` follows and for the
  /// same reason: one damaged file out of several must not cost the reader their library. `archiveCatalogProvider`
  /// has already read each one's manifest, so a package reaching this point is one this build could parse a moment
  /// ago; the second read is the price of not holding every package's events in memory for a section nobody has open.
  Future<List<Event>> _attachedEvents() async {
    final selection = ref.watch(archiveSelectionProvider);
    if (selection.isEmpty) return const [];
    final catalog = await ref.watch(archiveCatalogProvider.future);
    final events = <Event>[];
    for (final entry in catalog) {
      if (!entry.isUsable || !selection.contains(entry.fileName)) continue;
      try {
        events.addAll((await ArchivePackage.read(entry.file)).events);
      } on Object {
        continue;
      }
    }
    return events;
  }

  /// **Reads the old folder-style file into the log, once.**
  ///
  /// Until 2026-10-01 a reader's own name for a folder lived in `folder_styles.json`, a file beside the cellar -- so
  /// it never synced while every other kind of reader-written thing did. The recipes page now reads the log instead,
  /// which fixes that going forward and **would silently drop the names already in that file** if nothing read them.
  ///
  /// **It runs only when the log holds no packs at all**, which is what makes it idempotent without a flag: once
  /// anything has been migrated the fold is no longer empty, and a reader who deletes every pack on purpose does not
  /// get their old ones resurrected from a file they cannot see. **The file is left on disk on purpose** -- it is the
  /// only copy of those names until this has run at least once, and a migration that deletes its source has no
  /// second chance.
  ///
  /// A failure here is swallowed: an unreadable style file means there was nothing to migrate, and refusing to open
  /// the cellar over it would trade folder names for the whole library.
  Future<void> _migrateFolderStylesOnce(EventLog log) async {
    if (log.packs.isNotEmpty) return;
    try {
      final directory = await getApplicationSupportDirectory();
      final file = File('${directory.path}${Platform.pathSeparator}folder_styles.json');
      if (!file.existsSync()) return;
      final styles = await FolderStyleStore(file).read();
      for (final entry in styles.entries) {
        final pack = PackBook.packFromStyle(entry.key, entry.value);
        await log.record((hlc) => CourtPackEvents.set(hlc: hlc, pack: pack));
      }
    } on Object {
      // Nothing to migrate, or nothing readable. See above.
    }
  }

  Future<EventLog> _open() async {
    final directory = await getApplicationDocumentsDirectory();
    return EventLog.open(
      file: File('${directory.path}${Platform.pathSeparator}cellar.ndjson'),
      nodeId: nodeId,
      nowMillis: () => _clock++,
    );
  }

  // ---------------------------------------------------------------- correcting a bottle
  //
  // **The verbs section 6 has always had and no screen ever reached.** `BottleRecounted`,
  // `BottleDiscarded`, `BottleRemoved` and `PricePaid` are operations the fold reduces and events
  // nothing wrote -- the model was ahead of the interface, which is this project's most repeated
  // failure. These are the writers, and the shape of each is decided here rather than in a sheet:
  // a screen that decided for itself what a correction meant could decide it differently.

  /// Renames one bottle, leaving every other bottle of the same ingredient alone.
  ///
  /// The overlay's `bottle` key, so this is a fact about the overlay layer rather than about the log:
  /// a name is not an event in the cellar's history, it is what somebody calls the thing. Clearing it
  /// -- an empty name -- puts the seed's word back rather than leaving a blank.
  Future<void> renameBottle(String bottleId, String name) =>
      editOverlay(OverlayKey.bottle(bottleId), name);

  /// Renames an ingredient for every bottle of it.
  ///
  /// Section 8's other half of the same question: "I call it gin" is a statement about the vocabulary
  /// and applies to the shelf, where [renameBottle] applies to the object.
  Future<void> renameIngredient(String ingredientId, String name) =>
      editOverlay(OverlayKey.ingredient(ingredientId), name);

  /// Sets what is actually left in a bottle, from somebody looking at it.
  ///
  /// **A recount is not a correction to a number, it is an observation**, which is why it replaces the
  /// remaining volume instead of adjusting it: the person read the level off the bottle, so nothing
  /// that happened before it needs to be added up again. Zero is refused -- an empty bottle is
  /// discarded, not recounted, and the two are different facts about a cellar.
  Future<void> recountBottle(String bottleId, Volume volume) async {
    if (volume.isZero || volume.isNegative) return;
    final current = state.value;
    if (current == null) return;
    await current.log.record(
      (hlc) => StockEvents.bottleRecounted(
        hlc: hlc,
        bottleId: bottleId,
        volume: volume,
      ),
    );
    state = AsyncData(Cellar.of(current.log));
  }

  /// Pours the rest of a bottle away, or records that it broke.
  ///
  /// Separate from a pour on purpose -- section 6 is explicit that both reduce the shelf and only one
  /// of them was a drink -- so the consumption curve does not gain a glass nobody drank.
  Future<void> discardBottle(String bottleId, Volume volume) async {
    if (volume.isZero || volume.isNegative) return;
    final current = state.value;
    if (current == null) return;
    await current.log.record(
      (hlc) => StockEvents.bottleDiscarded(
        hlc: hlc,
        bottleId: bottleId,
        volume: volume,
      ),
    );
    state = AsyncData(Cellar.of(current.log));
  }

  /// Adds an observation of what this bottle cost, by hand.
  ///
  /// **A price is a series and not a field** (section 7), so a correction is a *new point* rather than
  /// an edit: the old observation stays, dated, and the chart shows both. That is the whole reason the
  /// price fold exists, and a screen that overwrote the last number would destroy the only thing the
  /// series is for.
  Future<void> recordPrice({
    required String sku,
    required Money price,
    String? bottleId,
    int? atMillis,
  }) async {
    final current = state.value;
    if (current == null) return;
    await current.log.record(
      (hlc) => PriceEvents.paid(
        hlc: hlc,
        sku: sku,
        minorUnits: price.minorUnits,
        currency: price.currency,
        // The bottle's own volume when the caller has it, so the new point is comparable with the
        // others: section 7's per-glass figure needs an amount, not just a price.
        microlitres: bottleId == null
            ? 0
            : (current.stock.bottle(bottleId)?.added.microlitres ?? 0),
        purchasedAtMillis: atMillis,
        source: PriceSource.manual,
      ),
    );
    state = AsyncData(Cellar.of(current.log));
  }

  /// Retracts a line that should never have been written.
  ///
  /// **[decision] Refused once anything has been poured or discarded against the bottle**, and the
  /// refusal is here rather than in the fold for the reason `stock.bottle.removed` gives: a fold's job
  /// is to reduce what it is given, and a removal may arrive from another device after a pour this one
  /// recorded. What the guard buys is that the **consumption curve cannot be made to lie** by deleting
  /// the bottle a drink came from -- the pours stay in the log with nothing left to belong to.
  ///
  /// Returns whether it was retracted, so a screen can say which happened instead of guessing.
  Future<bool> removeBottle(String bottleId) async {
    final current = state.value;
    if (current == null) return false;
    final bottle = current.stock.bottle(bottleId);
    if (bottle == null) return false;
    if (!bottle.consumed.isZero || !bottle.discarded.isZero) return false;

    await current.log.record(
      (hlc) => StockEvents.bottleRemoved(hlc: hlc, bottleId: bottleId),
    );
    state = AsyncData(Cellar.of(current.log));
    return true;
  }

  /// Records a bottle, then re-folds. **Enter a bottle, from the P1 criterion.**
  ///
  /// **A [Volume] rather than a whole number of millilitres, which is what it used to take.**
  /// The event this writes has always carried microlitres (`volumeMicrolitres`), so the
  /// millilitre-shaped door was the one place that narrowed the exact base -- harmless while
  /// the entry form could only say millilitres, and wrong the moment a reader may type
  /// `0.5 oz` and mean it. This system's fluid ounce is the exact 29.5735295625 ml, so that
  /// pour is 14 787 µl, and a door that wanted millilitres would have stored 14 000.
  Future<void> addBottle({
    required String sku,
    required Volume volume,
    String? name,
    Money? price,
    int? purchasedAtMillis,
  }) async {
    final current = state.value;
    if (current == null) return;
    await current.log.record(
      (hlc) => StockEvents.bottleAdded(
        hlc: hlc,
        // The sku is the identity the shelf matches on, so it is the natural
        // bottle id too: one bottle per line the shelf can answer for, for now.
        bottleId: 'bottle-$sku-${_clock++}',
        sku: sku,
        volume: volume,
        // **The denomination travels with the number.** This used to take an `int? priceMinor`
        // and write no currency, which is what left the price fold naming one for every price
        // this form recorded -- and a price whose denomination is silently substituted is a
        // number that means something else with nothing on screen to say so. The event has
        // always had the field; the form now fills it.
        priceMinor: price?.minorUnits,
        currency: price?.currency.code,
        // **The day it was bought, when the form knows it.** Section 7's series is dated
        // by the purchase and not by the keystroke -- a cellar entered in one sitting has
        // every event inside the same second, so a chart bucketed by the log's clock would
        // draw one candle for a decade of buying. Null means the clock reading is the best
        // answer available, which is honest for a bottle recorded as it is put away.
        purchasedAtMillis: purchasedAtMillis,
        note: name,
      ),
    );
    state = AsyncData(Cellar.of(current.log));
  }

  /// Takes a drink off the shelf. **Mix a drink and decrement stock.**
  ///
  /// One event per bottle, because section 6 puts the operation in the log
  /// rather than the resulting state: if two devices each pour a drink while
  /// apart, the answer is the sum of both pours and last-write-wins would lose
  /// one of them.
  Future<void> pour(Map<String, int> microlitresBySku, {String? batchId}) async {
    final current = state.value;
    if (current == null) return;
    final builders = <Event Function(Hlc)>[];
    for (final entry in microlitresBySku.entries) {
      if (entry.value <= 0) continue;
      final bottle = current.stock.bottles
          .where((b) => b.sku == entry.key && b.remaining.microlitres > 0)
          .firstOrNull;
      if (bottle == null) continue;
      builders.add(
        (hlc) => StockEvents.bottleConsumed(
          hlc: hlc,
          bottleId: bottle.bottleId,
          volume: Volume.fromMicrolitres(entry.value),
          batchId: batchId,
        ),
      );
    }
    if (builders.isEmpty) return;
    await current.log.recordAll(builders);
    state = AsyncData(Cellar.of(current.log));
  }

  /// Stands a bottle somewhere on a shelf, or moves it, and re-folds.
  ///
  /// **A move and a placement are the same write**, which is why there is no
  /// `moveBottle`: the fold takes the latest clock reading, so writing a second
  /// placement *is* the move. Adding a `move` method would create a second path
  /// to the same event that could drift from this one.
  ///
  /// Positions arrive in per-mille rather than as fractions, and the conversion
  /// happens at the caller -- a page that computes a fraction from a pixel offset
  /// knows the resolution it has, and this layer would only be guessing at it.
  Future<void> placeBottle({
    required String bottleId,
    required String shelfId,
    required int posXPermille,
    required int posYPermille,
  }) async {
    final current = state.value;
    if (current == null) return;
    // Refused here rather than written and folded away. The event builder
    // asserts, and an assert in release is nothing -- so the range is checked
    // before an event exists, and a caller that passed a position off the shelf
    // gets nothing written rather than a log entry that every device will
    // silently drop.
    if (posXPermille < 0 ||
        posXPermille > 1000 ||
        posYPermille < 0 ||
        posYPermille > 1000) {
      return;
    }
    await current.log.record(
      (hlc) => ShelfEvents.bottlePlaced(
        hlc: hlc,
        bottleId: bottleId,
        shelfId: shelfId,
        posXPermille: posXPermille,
        posYPermille: posYPermille,
      ),
    );
    state = AsyncData(Cellar.of(current.log));
  }

  /// Re-reads the log from disk. For a pull to refresh, and for the case where
  /// the same file was appended to by something else.
  Future<void> reload() async {
    _log = await _open();
    state = AsyncData(Cellar.of(_log!));
  }

  /// Puts a value into the overlay and re-folds.
  ///
  /// Section 8's write path, and it is deliberately the same shape as [addBottle]:
  /// an operation is appended and the state is whatever the operations add up to.
  /// There is no `setOverlay` that mutates a map in memory, because an edit that
  /// was not written down is not an edit -- the next fold would not have it, and
  /// the screen that showed it would have been lying.
  ///
  /// [value] may not be empty: [OverlayEvents.fieldSet] refuses that and points at
  /// [clearOverlay], so a caller that means "the user emptied the field" has to
  /// say so rather than passing a string that reads as a value and is not one.
  Future<void> setOverlay(OverlayKey key, String value) async {
    final current = state.value;
    if (current == null) return;
    await current.log.record(
      (hlc) => OverlayEvents.fieldSet(hlc: hlc, key: key, value: value),
    );
    state = AsyncData(Cellar.of(current.log));
  }

  /// Writes a recipe the reader composed, and re-folds.
  ///
  /// **The write path `docs/proposal-recipes-and-packs.md` §2 was missing**, and it is deliberately the same shape as
  /// [setOverlay] and [addBottle]: an operation is appended and the state is whatever the operations add up to.
  ///
  /// **The record is stored whole, including an id the caller supplied.** A recipe being edited keeps its id, which
  /// is what makes an edit an edit rather than a second recipe -- and [RecipeAuthoredId.from] derives a new one for
  /// a recipe being written for the first time. Handing the id in rather than minting it here is what lets a screen
  /// hold a draft, and it is safe because [RecipeAuthoredId.isMine] is the only thing that decides whether one of
  /// these may later be removed.
  ///
  /// **Nothing is validated here.** `validateAuthored` exists and belongs to the form, which can say *which* line
  /// names an ingredient this build does not know; a store that refused a record could only say that it refused it.
  /// [recipe] may carry an id minted by its composer, which is what an edit does; when [id] is absent a new one is
  /// derived from [AuthoredRecipe.name] and a reading off **this log's own clock**. The clock is here rather than in
  /// the form because taking a reading is a thing the log does, not a thing a widget does -- and a form that reached
  /// for one would be consuming the identity of an event it is not creating.
  Future<void> authorRecipe(AuthoredRecipe recipe, {String? id}) async {
    final current = state.value;
    if (current == null) return;
    final withId = id == null
        ? AuthoredRecipe(
            id: AuthoredRecipeId.from(recipe.name, current.log.clock.next()),
            name: recipe.name,
            items: recipe.items,
            subtitle: recipe.subtitle,
            folder: recipe.folder,
            description: recipe.description,
            method: recipe.method,
            glass: recipe.glass,
            ice: recipe.ice,
            garnish: recipe.garnish,
          )
        : recipe;
    await current.log.record(
      (hlc) => RecipeAuthoredEvents.set(hlc: hlc, recipe: withId),
    );
    state = AsyncData(Cellar.of(current.log));
  }

  /// Adds or replaces an ingredient the reader described, and re-folds.
  ///
  /// **The write path ③ needs**, and it is deliberately the same shape as [authorRecipe]: an operation is appended
  /// and the state is whatever the operations add up to. The id is minted here from the log's own clock when the
  /// caller has none, because taking a reading is the log's business rather than a widget's -- and a form that
  /// reached for one would be consuming the identity of an event it is not creating.
  ///
  /// **Nothing is validated here.** `validateAuthoredIngredient` exists and belongs to the form, which can say
  /// *which* thing is wrong; a store that refused a record could only report that it refused it.
  Future<void> authorIngredient(AuthoredIngredient ingredient, {String? id}) async {
    final current = state.value;
    if (current == null) return;
    final withId = id == null
        ? AuthoredIngredient(
            id: AuthoredIngredientId.from(ingredient.name, current.log.clock.next()),
            name: ingredient.name,
            category: ingredient.category,
            aliases: ingredient.aliases,
            note: ingredient.note,
          )
        : ingredient;
    await current.log.record(
      (hlc) => IngredientAuthoredEvents.set(hlc: hlc, ingredient: withId),
    );
    state = AsyncData(Cellar.of(current.log));
  }

  /// Removes an ingredient the reader added.
  ///
  /// Recorded rather than forgotten, like [removeAuthoredRecipe] and for the same reason: a removal that left no
  /// event would be undone by the next sync. `IngredientAuthoredEvents.removed` refuses an id that is not the
  /// reader's own, so the catalogue cannot be edited by calling this -- the refusal is in the domain layer so no
  /// caller can get it wrong.
  Future<void> removeAuthoredIngredient(String id) async {
    final current = state.value;
    if (current == null) return;
    await current.log.record(
      (hlc) => IngredientAuthoredEvents.removed(hlc: hlc, id: id),
    );
    state = AsyncData(Cellar.of(current.log));
  }

  /// Creates or replaces a collection, and re-folds.
  ///
  /// **The cycle check happens here, before the event is written**, which is what `checkMembership` argues for at
  /// length: a collection that contains itself is not a rendering problem a screen can dodge, because the fold
  /// listing its contents would recurse until the stack ran out -- and by then the bad event is in the log and in
  /// every synced copy of it. Refusing at the door costs a message; refusing later costs a migration.
  ///
  /// **The whole membership is written rather than a change to it**, so a device folding the log arrives at a state
  /// instead of at a state that depends on whether it saw every earlier event.
  ///
  /// Returns the problem when the membership is refused, and null when the collection was written -- so a screen can
  /// say which thing was wrong rather than only that something was.
  Future<CollectionProblem?> setCollection({
    required String id,
    required String name,
    required Iterable<CollectionMember> members,
  }) async {
    final current = state.value;
    if (current == null) return null;
    final memberList = members.toList(growable: false);
    final problem = checkMembership(
      id: id,
      members: memberList,
      existing: current.collections,
    );
    if (problem != null) return problem;
    await current.log.record(
      (hlc) => RecipeCollectionEvents.set(
        hlc: hlc,
        id: id,
        name: name,
        members: memberList,
      ),
    );
    state = AsyncData(Cellar.of(current.log));
    return null;
  }

  /// Deletes a collection.
  ///
  /// **Cleared rather than emptied, because "deleted" and "empty" are different things to a reader** -- the fold
  /// argues it and the screen depends on it: an emptied collection still exists to be filled again, and a cleared
  /// one is gone from the list.
  Future<void> clearCollection(String id) async {
    final current = state.value;
    if (current == null) return;
    await current.log.record(
      (hlc) => RecipeCollectionEvents.cleared(hlc: hlc, id: id),
    );
    state = AsyncData(Cellar.of(current.log));
  }

  /// Hides a folder the application derives from the drinks themselves.
  ///
  /// A derived folder cannot be deleted -- it is a fact about the recipes, not a record -- so the most a reader can
  /// say about one is "not on my screen", which is what this records.
  Future<void> hideDerivedFolder(String folderKey) async {
    final current = state.value;
    if (current == null) return;
    await current.log.record(
      (hlc) => RecipeCollectionEvents.folderHidden(hlc: hlc, folderKey: folderKey),
    );
    state = AsyncData(Cellar.of(current.log));
  }

  /// Shows a hidden derived folder again.
  Future<void> showDerivedFolder(String folderKey) async {
    final current = state.value;
    if (current == null) return;
    await current.log.record(
      (hlc) => RecipeCollectionEvents.folderShown(hlc: hlc, folderKey: folderKey),
    );
    state = AsyncData(Cellar.of(current.log));
  }

  /// Defines a pack, and re-folds.
  ///
  /// **The write path `docs/proposal-recipes-and-packs.md` §1 asked for**, and it is deliberately the same shape as
  /// [authorRecipe], [authorIngredient] and [setCollection]: an operation is appended and the state is whatever the
  /// operations add up to.
  ///
  /// **The whole record is written rather than a change to it**, so a device folding the log arrives at a state
  /// instead of at a state that depends on whether it saw every earlier event -- which is what makes a rename travel
  /// between devices, and is the point of the family existing at all.
  ///
  /// Returns the problem when the pack is refused, and null when it was written, so a screen can say which thing was
  /// wrong. `official` is refused here because it ships with the build.
  Future<PackProblem?> definePack(CourtPack pack) async {
    final current = state.value;
    if (current == null) return null;
    final problems = validatePack(pack);
    if (problems.isNotEmpty) return problems.first;
    await current.log.record((hlc) => CourtPackEvents.set(hlc: hlc, pack: pack));
    state = AsyncData(Cellar.of(current.log));
    return null;
  }

  /// Removes a pack the reader defined.
  ///
  /// **Recorded rather than forgotten**, like the other removals: one that left no event would be undone by the next
  /// sync. `CourtPackEvents.removed` refuses `official`, so the shipped pack cannot be deleted by calling this.
  ///
  /// **What happens to the recipes in it is the caller's decision, not this method's.** The proposal asks that
  /// deleting a pack *"asks what happens to its recipes rather than silently orphaning them"*, and a store cannot ask
  /// -- so this removes the pack and the screen is where the question is put.
  Future<void> removePack(String id) async {
    final current = state.value;
    if (current == null) return;
    await current.log.record((hlc) => CourtPackEvents.removed(hlc: hlc, id: id));
    state = AsyncData(Cellar.of(current.log));
  }

  /// Removes a recipe the reader wrote.
  ///
  /// **Recorded rather than forgotten**, like [clearOverlay] and for the same reason: a removal that left no event
  /// would be undone by the next sync, because a peer still holding the older write would hand it straight back.
  ///
  /// `RecipeAuthoredEvents.removed` refuses an id that is not the reader's own, so a shipped recipe cannot be
  /// deleted by calling this -- the refusal is in the domain layer rather than here, so no caller can get it wrong.
  Future<void> removeAuthoredRecipe(String id) async {
    final current = state.value;
    if (current == null) return;
    await current.log.record(
      (hlc) => RecipeAuthoredEvents.removed(hlc: hlc, id: id),
    );
    state = AsyncData(Cellar.of(current.log));
  }

  /// Takes a value back out of the overlay.
  ///
  /// Recorded rather than forgotten. A removal that left no event would be undone
  /// by the next sync, because a peer still holding the older `set` would hand it
  /// straight back -- so this is an operation with a clock, and it wins like one.
  Future<void> clearOverlay(OverlayKey key) async {
    final current = state.value;
    if (current == null) return;
    await current.log.record(
      (hlc) => OverlayEvents.fieldCleared(hlc: hlc, key: key),
    );
    state = AsyncData(Cellar.of(current.log));
  }

  /// Writes what a person typed into a field: a value, or a removal.
  ///
  /// **One entry point, because two rules have to hold on every screen with a text
  /// field and neither should be decided twice.**
  ///
  /// * **An emptied field is a removal.** `setOverlay` refuses an empty value and
  ///   points here, so a caller that skipped this branch would fail loudly rather
  ///   than writing a note nobody can see -- and the branch belongs beside the
  ///   refusal that makes it necessary, not in each screen that owns a `TextField`.
  /// * **The value is trimmed here and nowhere else.** The domain does not trim,
  ///   because an overlay value is the user's own text and the fold does not edit
  ///   it; whitespace around a note is not something anybody meant to say, so the
  ///   boundary is where a person decided it, and the boundary is this method.
  Future<void> editOverlay(OverlayKey key, String typed) async {
    final text = typed.trim();
    if (text.isEmpty) return clearOverlay(key);
    return setOverlay(key, text);
  }
}
