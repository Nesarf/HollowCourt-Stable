import '../units/rational.dart';
import '../units/unit.dart';
import 'drink.dart';
import 'flavor.dart';
import 'glass.dart';
import 'ice.dart';
import 'item_role.dart';
import 'liquid_visual.dart';

/// [Method] belongs to the dosing arithmetic, which already reads it to decide
/// how much ice melts (section 5.5). It is re-exported here rather than declared
/// again, because two enums with one name would eventually disagree -- and the
/// import above is what lets this file use it as well as hand it on.
export 'drink.dart' show Method;

/// A score from a source, and how many people gave it.
///
/// Section 4.4 lists `rating: Double?`; this is a [Rational] and a count, for
/// the same reason section 4.1's percentages are. A rating is a number the
/// domain layer carries, and the rule in section 3 has no exception for
/// numbers that "are only displayed" -- every float that has ever been called
/// display-only has eventually been compared to another one.
///
/// The count is kept because another source gives one and a 4.1 from 489 people is a
/// different fact from a 4.1 from three. A source that gives no count leaves
/// it null rather than zero.
final class Rating {
  const Rating({required this.value, this.count});

  final Rational value;
  final int? count;

  List<String> validate() {
    final problems = <String>[];
    if (value.isNegative || value > Rational.fromInt(5)) {
      problems.add('rating $value is outside 0 to 5');
    }
    if (count != null && count! < 0) {
      problems.add('rating count $count is negative');
    }
    return problems;
  }

  @override
  String toString() => count == null ? '$value' : '$value ($count)';
}

/// One measured line of a recipe, as section 4.4 defines it.
final class RecipeItem {
  const RecipeItem({
    required this.ingredientId,
    required this.amount,
    this.count,
    this.unit,
    this.role = ItemRole.base,
    this.originalText,
    this.note,
    this.substitutes = const [],
  });

  /// Points at an [Ingredient] by id.
  final String ingredientId;

  /// The amount in whole microlitres, as section 5.1 requires.
  ///
  /// Zero is a legal amount and not a missing one: a rinse or a rim genuinely
  /// measures nothing, and [role] is where that is said. A *missing* amount is
  /// a different thing and has no representation here on purpose -- an item
  /// that says "some sugar" cannot be deducted from a bottle, so it does not
  /// become an item.
  final int amount;

  /// How many whole things, for a line that counts rather than measures.
  ///
  /// **A second numeric field, and it is not redundant with [amount].** A
  /// garnishing line says `4 of mint leaf` and four mint leaves are not a
  /// volume -- section 5.2 files that under [UnitKind.discrete] and says why,
  /// and the arithmetic follows: four cherries doubled is eight cherries in the
  /// spec, not eight in the glass. Without this field that quantity has nowhere
  /// to live, and the importer would have had to drop it or bury it in
  /// [originalText] as prose -- which is the silent loss this project's records
  /// exist to prevent.
  ///
  /// A [Rational] rather than an int, for the same reason every other number in
  /// the domain layer is: `1,5` appears in the data, and a half a leaf that
  /// becomes a `1` is a wrong number rather than a rounded one.
  ///
  /// Null for a measured line. Zero is not a legal count -- a line that counts
  /// nothing is not a line.
  final Rational? count;

  /// The unit the line arrived in, preserved as section 4.4 requires.
  ///
  /// A bartender reads `2 oz`, not `59147 ul`. Null when the source gave a bare
  /// count.
  final Unit? unit;

  final ItemRole role;

  /// The line as it was written, kept verbatim.
  ///
  /// This is what makes the importer's work reviewable: when a parsed amount
  /// looks wrong, the original sentence is right there next to it.
  final String? originalText;

  final String? note;
  final List<String> substitutes;

  List<String> validate() {
    final problems = <String>[];
    if (ingredientId.trim().isEmpty) problems.add('ingredientId is empty');
    if (amount < 0) problems.add('amount $amount ul is negative');
    if (count != null) {
      if (count!.isNegative || count!.isZero) {
        problems.add('count $count is not a positive number of things');
      }
      // A line cannot both measure and count. One of the two is the quantity
      // and the other is noise, and a reader cannot tell which.
      if (amount != 0) {
        problems.add('has both an amount ($amount ul) and a count ($count)');
      }
    }
    for (final substitute in substitutes) {
      if (substitute.trim().isEmpty) problems.add('a substitute is empty');
    }
    return problems;
  }

  @override
  String toString() => count != null
      ? '$count x $ingredientId (${role.name})'
      : '$amount ul $ingredientId (${role.name})';
}

/// A recipe, as section 4.4 defines it.
///
/// The same type covers the seed library and a recipe the user writes, which is
/// what [isSeed] is for. Section 8 keeps the two apart by where they live
/// rather than by their shape: the seed is replaced wholesale on an update and
/// the overlay never is.
final class Recipe {
  const Recipe({
    required this.id,
    required this.name,
    required this.items,
    this.glass,
    this.ice,
    this.method,
    this.liquid,
    this.subtitle,
    this.packId,
    this.description,
    this.origin,
    this.flavors = const FlavorProfile(),
    this.methodSteps = const [],
    this.rating,
    this.isSeed = true,
    this.extras = const {},
  });

  /// `<slug><5 digits>`, as section 4.4 asks.
  ///
  /// Neither source supplies one. one source numbers its recipes `"0"` through
  /// `"413"` and another source uses a URL path like `/r/dry_manhattan`, so the importer
  /// has to mint these -- which is exactly why the format is checked here
  /// rather than assumed.
  final String id;

  final String name;
  final String? subtitle;

  /// Which content pack this arrived in. one source fills it (`free`, `premium`);
  /// another source does not.
  final String? packId;

  final String? description;

  /// Where the recipe came from: "Travel Finds, Casoni Bar, Italy, 1919".
  final String? origin;

  final FlavorProfile flavors;
  /// What it is served in, or null when the source named a glass this project
  /// cannot draw.
  ///
  /// **The fourth field of the same shape as [ice], [method] and [liquid], and
  /// it was the last one to be made honest.** Six of another source's 88 recipes are
  /// served in an Irish coffee glass, a copper mule mug, a snifter or a
  /// tropical, and those four are deliberately outside [Glass] -- mapping them
  /// onto the nearest of the eight would be a drawing decision taken by an
  /// importer. Null is what is actually known.
  final Glass? glass;

  /// Whether there is ice in it, or null when the source did not say.
  ///
  /// one source omits it on 3 of its 414 recipes; **another source has no ice field at all**,
  /// so null covers the whole of that source. A missing ice is a fact about the
  /// data, and the alternative -- assuming none -- is a claim nobody made.
  final IceKind? ice;

  /// How the drink is built, or null when the source did not say.
  ///
  /// **Nullable on purpose, and the reason is arithmetic rather than taste.**
  /// Section 5.5 reads the method to decide how much ice melts, so a null
  /// method means the dilution of that drink cannot be computed -- which is a
  /// real consequence and exactly why this is not simply defaulted to
  /// [Method.stirred]. one source omits it on 5 of 414 recipes, and another source encodes it
  /// only as a hashtag inside the steps, so a large part of the seed has none.
  ///
  /// A missing method is a fact about the data. Picking one would put a
  /// fabricated dilution into a stock ledger.
  final Method? method;

  /// How it looks in the glass (section 12.1), or null when unknown.
  ///
  /// one source supplies this for all but 18 of its recipes -- the ones whose colour
  /// is one section 12.1 cannot express -- while **another source supplies it for none
  /// of its 88**, having neither a colour nor an opacity field. Null is
  /// therefore the common case for one half of the seed rather than an edge
  /// case, and a renderer needs an answer for it that is not a guess.
  final LiquidVisual? liquid;

  final List<String> methodSteps;

  final List<RecipeItem> items;
  final Rating? rating;
  final bool isSeed;
  final Map<String, String> extras;

  /// The pattern section 4.4 specifies: a slug, then five digits.
  static final RegExp idPattern = RegExp(r'^[a-z][a-z0-9_]*\d{5}$');

  /// Total liquid, in microlitres, before any ice has melted.
  int get undilutedMicrolitres =>
      items.fold(0, (sum, item) => sum + item.amount);

  List<String> validate() {
    final problems = <String>[];

    if (!idPattern.hasMatch(id)) {
      problems.add('id "$id" is not a slug followed by five digits');
    }
    if (name.trim().isEmpty) problems.add('name is empty');

    if (items.isEmpty) {
      problems.add('a recipe with no items cannot be mixed');
    }
    for (final item in items) {
      for (final problem in item.validate()) {
        problems.add('item ${item.ingredientId}: $problem');
      }
    }

    // Two items with the same ingredient and the same role used to be reported,
    // on the reading that somebody had duplicated a line.
    //
    // **Aliasing turned that into a false positive and this is where it showed
    // up.** A Mai Tai really does call for two rums, and the seed resolves
    // `aged Jamaican rum` and `aged rum, Pref. Martinique` to one canonical id,
    // so both lines became items with the same id and role. A mojito genuinely
    // has mint muddled into it and mint as a garnish. Neither is a duplicated
    // line, and reporting them made the validator cry wolf on source data that
    // was correct.
    //
    // So a duplicate now means an *identical* line: same ingredient, role,
    // amount, count, unit and original text. That is what a line somebody
    // copied actually looks like, and it is the only case where nothing is lost
    // by collapsing it.
    final seen = <String>{};
    for (final item in items) {
      final key = [
        item.ingredientId,
        item.role.name,
        item.amount,
        item.count?.toString() ?? '',
        item.unit?.id ?? '',
        item.originalText ?? '',
      ].join('|');
      if (!seen.add(key)) {
        problems.add(
          '${item.ingredientId} appears twice as ${item.role.name}, identically',
        );
      }
    }

    for (final problem in flavors.validate()) {
      problems.add('flavours: $problem');
    }
    // Absent is not a problem. Section 4.4 asks for these three and half the
    // seed does not carry them, so reporting them would produce a report with
    // every another source recipe in it and a reader would stop reading it.
    if (liquid != null) {
      for (final problem in liquid!.validate()) {
        problems.add('liquid: $problem');
      }
    }
    if (rating != null) {
      for (final problem in rating!.validate()) {
        problems.add('rating: $problem');
      }
    }

    return problems;
  }

  @override
  String toString() => '$id ($name)';
}
