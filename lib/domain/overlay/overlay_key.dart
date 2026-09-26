/// What an overlay value is attached to.
///
/// **The key is the whole reason section 8 works.** The seed is replaced
/// wholesale on update and the overlay never is, so a key that moves when the
/// seed moves loses the user's data on the one occasion the layer exists to
/// survive. That rules out every key derived from the seed's *contents*: an
/// index, a position, a display name, a title. What is left is an id the seed
/// promises not to renumber.
///
/// Section 4.4 already made that promise, and made it against this section by
/// name. `recipe_id.dart` records why the digits are hashed rather than counted:
/// a running index "would have been simpler and wrong: adding a recipe to the
/// source would renumber everything after it, and section 8 keeps user data
/// pointing at recipe ids". So a key here is built from the same ids the seed
/// layer mints, and the two layers agree because section 4.4 said they would.
///
/// ## Three parts
///
/// | part | example | who chooses it |
/// | --- | --- | --- |
/// | [kind] | `recipe`, `ingredient`, `copy` | this project |
/// | [id] | `dry_manhattan17517`, `gin`, `stockEmptyHint` | this project, or the seed |
/// | [field] | `note`, `alias`, `extras.glass` | this project |
///
/// **An id is minted; a name is a value.** That is the rule that lets all three
/// parts be validated: a user never mints a key. A custom category of the user's
/// own gets an id this project assigns, and the words they typed for it are a
/// *value* stored under that id. So [OverlayKey] may refuse a key and throw,
/// while a value is the user's text and is never refused -- which is the
/// division of authority the whole layer rests on.
///
/// ## Why [kind] is an open string and not an enum
///
/// The same reason [Event.type] is: two versions of the app meet during a sync,
/// and the older one must carry the newer one's entries across without
/// understanding them. A closed set would force it to drop what it does not
/// recognise, and in an op-log dropping an event loses a real operation -- here,
/// a note somebody wrote. Validation is therefore about *shape* and not about
/// membership: a kind this build has never heard of is a valid key.
final class OverlayKey {
  const OverlayKey._(this.kind, this.id, this.field);

  /// Validates, then builds.
  ///
  /// **A factory and not a public const constructor**, which costs the ability to
  /// write a key as a compile-time constant and buys validation on every way in.
  /// The trade is deliberate: a key that fails the charset is a bug that would
  /// otherwise surface as an entry nobody can look up again, and there is
  /// nothing in this layer that needs a `const` key -- every real key carries a
  /// seed id that is only known at run time.
  factory OverlayKey(String kind, String id, String field) {
    if (!_kindPattern.hasMatch(kind)) {
      throw FormatException('overlay kind is not a lowercase name: "$kind"');
    }
    if (!_idPattern.hasMatch(id)) {
      // Colons and dots are excluded rather than merely discouraged: they are the
      // two separators in [toString], so allowing them here would make that form
      // ambiguous and there would be no inverse of it.
      throw FormatException('overlay id has a reserved character: "$id"');
    }
    if (!_fieldPattern.hasMatch(field)) {
      throw FormatException('overlay field is not a name: "$field"');
    }
    return OverlayKey._(kind, id, field);
  }

  /// What sort of thing this is about: `recipe`, `ingredient`, `copy`.
  ///
  /// Lower snake case, so it reads as a namespace and sorts as one.
  final String kind;

  /// The stable id of the thing. Never a name and never a position.
  final String id;

  /// Which of the thing's fields. Dots are allowed so that section 8's
  /// `extras: Map<String, String>` is expressible as `extras.<name>`.
  final String field;

  static final RegExp _kindPattern = RegExp(r'^[a-z][a-z0-9_]*$');
  static final RegExp _idPattern = RegExp(r'^[A-Za-z0-9_-]+$');
  static final RegExp _fieldPattern = RegExp(r'^[A-Za-z][A-Za-z0-9_.-]*$');

  /// A note on a recipe. Section 8's first personalizable thing after `extras`.
  static OverlayKey recipe(String recipeId, [String field = 'note']) =>
      OverlayKey('recipe', recipeId, field);

  /// What this project's user calls an ingredient: section 8's "I call it gin",
  /// and the same machinery section 12.4 cites when it refuses 自定义中文 as a
  /// fifteenth locale -- "it would put a user's own words into the shipped seed
  /// data instead of on top of it", which is this, but on top.
  static OverlayKey ingredient(String ingredientId, [String field = 'alias']) =>
      OverlayKey('ingredient', ingredientId, field);

  /// **What this bottle is called, as opposed to what its ingredient is called.**
  ///
  /// Section 8 gives an `ingredient` alias for renaming a *word* -- "I call it gin" -- and this is the
  /// other half of the same question: the reader who wants the bottle in front of them relabelled
  /// without every other bottle of gin in the cellar changing too. Both are wanted, and they are
  /// different sentences: one is about the vocabulary, the other about this object.
  ///
  /// Keyed on the **bottle id** and not on the sku, because that is the thing being named. A bottle id
  /// is already what stock operations use, so a name written here follows the bottle through a recount
  /// or a pour without anything having to keep the two in step.
  static OverlayKey bottle(String bottleId, [String field = 'name']) =>
      OverlayKey('bottle', bottleId, field);

  /// A correction to a shipped display string.
  ///
  /// **The field is a language tag, and that is the design rather than a
  /// convenience.** The proposal's 4.2(b) puts a generated translation and the
  /// user's correction in the same place, keyed by the string's key -- and a
  /// string can be corrected in more than one language, so the language has to
  /// be part of the key or one correction would overwrite another. Keying on a
  /// locale tag rather than on "primary"/"secondary" also means the correction
  /// survives the reader changing which language is which.
  ///
  /// Nothing writes one yet: no translation is generated, because section 12.4's
  /// locale layer is not built. The scheme is here so that the layer, when it
  /// arrives, has a decided place to put things instead of inventing one.
  static OverlayKey copy(String copyKey, {String language = 'en'}) =>
      OverlayKey('copy', copyKey, language);

  /// The key an entity's own custom field lives under: `extras.<name>`.
  static OverlayKey extra(String kind, String id, String name) =>
      OverlayKey(kind, id, 'extras.$name');

  /// The inverse of [toString].
  ///
  /// Total, and that is what the two reserved characters in [id] are for: the
  /// first colon ends the kind and the first dot after it ends the id, so every
  /// string this class produces parses back to the key that produced it. The
  /// parts are still stored separately in an event's payload -- this form is for
  /// a log line, a settings key and a test, and never the thing that is read
  /// back on the wire.
  static OverlayKey parse(String packed) {
    final colon = packed.indexOf(':');
    if (colon <= 0) {
      throw FormatException('overlay key has no kind: "$packed"');
    }
    final dot = packed.indexOf('.', colon + 1);
    if (dot <= colon + 1 || dot == packed.length - 1) {
      throw FormatException('overlay key has no id or no field: "$packed"');
    }
    return OverlayKey(
      packed.substring(0, colon),
      packed.substring(colon + 1, dot),
      packed.substring(dot + 1),
    );
  }

  /// `kind:id.field`, which [parse] accepts.
  ///
  /// Deliberately not a dotted path all the way through (`recipe.note.<id>`):
  /// the entity is one thing and its id may contain underscores and hyphens, so
  /// keeping the three parts visible is worth more than a single uniform
  /// separator.

  @override
  String toString() => '$kind:$id.$field';

  /// **The reader's dictionary of equivalent names, as one block of text.**
  ///
  /// One value rather than one key per group, and the reason is this class's own grammar: the id is ASCII
  /// only, while a canonical name here is 金酒 or 安高天娜. It also matches the interaction the owner asked
  /// for -- "批量自定义" -- where somebody pastes many lines at once and saves them together.
  ///
  /// **The cost, stated rather than discovered later**: the whole table is one value, so two devices that
  /// both edit it while apart resolve it last-writer-wins, losing groups together. Acceptable for a personal
  /// dictionary, and not for the cellar -- which is why the cellar's operations are events and this is field.
  static OverlayKey get synonymTable => OverlayKey('synonym', 'table', 'block');

  @override
  bool operator ==(Object other) =>
      other is OverlayKey &&
      other.kind == kind &&
      other.id == id &&
      other.field == field;

  @override
  int get hashCode => Object.hash(kind, id, field);
}
