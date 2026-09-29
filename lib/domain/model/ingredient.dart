import '../units/rational.dart';
import '../units/unit.dart';
import 'ingredient_category.dart';

/// An ingredient, as section 4.1 defines it.
///
/// One field departs from the section's own listing on purpose.
/// **`abvPercent`, `sugarGPerL` and `densityGPerMl` are [Rational] here, not
/// `double`.** Section 4.1 writes them as `Double?`, and that contradicts
/// section 3 and section 5.1, which between them forbid floating point
/// anywhere in the domain layer -- a density is multiplied into a volume by
/// `DensityBridge.massOf`, which takes a [Rational], and a `double` arriving
/// here would have to be converted at that boundary by exactly the kind of
/// implicit conversion section 2 chose a strongly typed language to avoid.
///
/// The design document is the authority; this is the one place it contradicts
/// itself, and the arithmetic rule wins because it is the rule with a reason
/// attached.
final class Ingredient {
  const Ingredient({
    required this.id,
    required this.name,
    this.category,
    this.aliases = const [],
    this.abvPercent,
    this.sugarGPerL,
    this.densityGPerMl,
    this.defaultUnit,
    this.bottleSizesMillilitres = const [],
    this.sourceBucket,
    this.isCommon = false,
    this.note,
    this.extras = const {},
  });

  /// The stable identifier, in the prefix scheme section 4.1 asks for:
  /// `juiceLime`, `ginPlymouth`.
  ///
  /// Built from a category prefix and the name rather than from a number,
  /// because a recipe written by hand is far easier to read when the item it
  /// points at is recognisable in the text.
  final String id;

  /// What a person sees.
  final String name;

  /// What it is, from section 4.2. Null when nobody has said.
  ///
  /// Nullable rather than defaulted. The another source harvest carries 139 ingredient
  /// entries and **none of them has a category** -- the taxonomy in section 4.2
  /// was observed from the site, but the per-ingredient assignment was not part
  /// of what was captured. Guessing one from the name would be exactly the
  /// silent guess the reverse-engineering record forbids, so the field stays
  /// empty and a report counts how many are empty.
  final IngredientCategory? category;

  /// Other names this ingredient answers to.
  final List<String> aliases;

  /// Alcohol by volume as a percentage, where 40 means 40%.
  final Rational? abvPercent;

  /// Sugar, in grams per litre.
  final Rational? sugarGPerL;

  /// Density in grams per millilitre: the bridge of section 5.4.
  final Rational? densityGPerMl;

  /// The unit this ingredient is normally measured in.
  final Unit? defaultUnit;

  /// Common bottle sizes, in millilitres, as whole numbers.
  final List<int> bottleSizesMillilitres;

  /// Which of the source's buckets it came from, kept as provenance.
  ///
  /// Beside [category] rather than folded into it: the two taxonomies do not
  /// line up, and section 18's warning is precisely about an enum that was
  /// defined and then quietly made to fit whatever arrived.
  final SourceBucket? sourceBucket;

  /// True when the source marked this as a commonly used ingredient.
  final bool isCommon;

  /// A description, where the source carried one.
  final String? note;

  /// Everything that does not deserve a column (section 8).
  final Map<String, String> extras;

  /// A copy of this ingredient with fields replaced.
  Ingredient copyWith({
    String? id,
    String? name,
    IngredientCategory? category,
    List<String>? aliases,
    Rational? abvPercent,
    Rational? sugarGPerL,
    Rational? densityGPerMl,
    Unit? defaultUnit,
    List<int>? bottleSizesMillilitres,
    SourceBucket? sourceBucket,
    bool? isCommon,
    String? note,
    Map<String, String>? extras,
  }) => Ingredient(
    id: id ?? this.id,
    name: name ?? this.name,
    category: category ?? this.category,
    aliases: aliases ?? this.aliases,
    abvPercent: abvPercent ?? this.abvPercent,
    sugarGPerL: sugarGPerL ?? this.sugarGPerL,
    densityGPerMl: densityGPerMl ?? this.densityGPerMl,
    defaultUnit: defaultUnit ?? this.defaultUnit,
    bottleSizesMillilitres: bottleSizesMillilitres ?? this.bottleSizesMillilitres,
    sourceBucket: sourceBucket ?? this.sourceBucket,
    isCommon: isCommon ?? this.isCommon,
    note: note ?? this.note,
    extras: extras ?? this.extras,
  );

  /// Problems that make this ingredient unusable, empty when it is sound.
  ///
  /// Section 18 asks for schema validation at write time and on import, so this
  /// is called from both. It answers with sentences rather than throwing: a
  /// spreadsheet with forty bad rows should produce forty lines, not forty
  /// runs, and an exception can only carry one.
  List<String> validate() {
    final problems = <String>[];

    if (id.trim().isEmpty) {
      problems.add('id is empty');
    } else if (!RegExp(r'^[a-z][A-Za-z0-9]*$').hasMatch(id)) {
      problems.add('id "$id" is not lowerCamelCase starting with a letter');
    }

    if (name.trim().isEmpty) problems.add('name is empty');

    for (final alias in aliases) {
      if (alias.trim().isEmpty) problems.add('an alias is empty');
    }

    if (abvPercent != null) {
      if (abvPercent!.isNegative || abvPercent! > Rational.fromInt(100)) {
        problems.add('abvPercent $abvPercent is outside 0 to 100');
      }
    }

    if (sugarGPerL != null && sugarGPerL!.isNegative) {
      problems.add('sugarGPerL $sugarGPerL is negative');
    }

    if (densityGPerMl != null) {
      if (densityGPerMl!.isNegative || densityGPerMl!.isZero) {
        problems.add('densityGPerMl $densityGPerMl is not a positive density');
      }
    }

    for (final size in bottleSizesMillilitres) {
      if (size <= 0) problems.add('bottle size $size ml is not positive');
    }

    return problems;
  }

  @override
  String toString() => '$id ($name)';
}
