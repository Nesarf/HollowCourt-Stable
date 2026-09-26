import 'dart:convert';

import '../../domain/model/flavor.dart';
import '../../domain/model/glass.dart';
import '../../domain/model/ice.dart';
import '../../domain/model/ingredient.dart';
import '../../domain/model/ingredient_category.dart';
import '../../domain/model/item_role.dart';
import '../../domain/model/liquid_visual.dart';
import '../../domain/model/recipe.dart';
import '../../domain/units/rational.dart';
import '../../domain/units/unit.dart';
import '../../domain/units/unit_system.dart';

/// Raised when a seed document is not one this code can read.
///
/// A separate type from a JSON syntax error, because the two mean different
/// things: malformed JSON is a broken file, and this is a file that is not a
/// seed, or is a seed from a version this build does not know.
final class SeedFormatException implements Exception {
  const SeedFormatException(this.reason);
  final String reason;
  @override
  String toString() => 'SeedFormatException: $reason';
}

/// A seed as it lives on disk, with no file system involved.
///
/// **Encoding and decoding are separated from reading and writing on purpose.**
/// The app loads the seed from wherever it can -- an asset bundle, a file beside
/// the executable, a string in a test -- and none of those is this class's
/// business. Keeping `dart:io` out of here is also what lets the round trip be
/// tested without touching a disk.
abstract final class SeedCodec {
  /// The format's own name and version, on the first two fields.
  ///
  /// Section 4.4's lesson from the an earlier seed beatmap format, applied to a file of
  /// this project's own: **a format that states which format it is survives its
  /// own evolution**, because the reader branches on the statement instead of
  /// guessing from what it finds. `osu file format v14` has loaded beside v4
  /// files for a decade for exactly this reason.
  /// **The format's own name, and it changed on 2026-09-22 with the data it describes.** It read
  /// `hollow-court-seed` while the library was a build artifact of harvested sources; those sources were
  /// deleted at the owner's instruction, so the document the application loads is now our own list and the
  /// marker says whose it is. A file carrying the old marker is refused rather than read, which is the
  /// behaviour this check exists for: an application that guessed at a document it does not recognise would
  /// show a person a library that is not theirs.
  static const String formatName = 'hollow-court-library';
  static const int formatVersion = 1;

  /// Encodes a seed. [pretty] is for a person reading the artifact while
  /// debugging; the shipped form is compact.
  static String encode({
    required List<Ingredient> ingredients,
    required List<Recipe> recipes,
    bool pretty = false,
  }) {
    final document = <String, Object?>{
      'format': formatName,
      'version': formatVersion,
      'counts': {
        'ingredients': ingredients.length,
        'recipes': recipes.length,
        'items': recipes.fold<int>(0, (sum, r) => sum + r.items.length),
      },
      'ingredients': [for (final i in ingredients) _ingredientToJson(i)],
      'recipes': [for (final r in recipes) _recipeToJson(r)],
    };
    return pretty
        ? const JsonEncoder.withIndent('  ').convert(document)
        : jsonEncode(document);
  }

  /// Decodes a seed, or throws [SeedFormatException] saying why not.
  ///
  /// Strict about the version and lenient about everything absent: a field this
  /// build does not know is ignored rather than refused, and an enum value it
  /// cannot read is reported by name rather than silently becoming null. The
  /// two are different: an unknown *field* is a newer writer, and an unknown
  /// *value* is a writer this build cannot honestly interpret.
  static ({List<Ingredient> ingredients, List<Recipe> recipes}) decode(
    String source,
  ) {
    final Object? parsed;
    try {
      parsed = jsonDecode(source);
    } on FormatException catch (error) {
      throw SeedFormatException('not JSON: ${error.message}');
    }
    if (parsed is! Map<String, Object?>) {
      throw const SeedFormatException('the top level is not an object');
    }

    final format = parsed['format'];
    if (format != formatName) {
      throw SeedFormatException(
        'this is not a $formatName document (format is ${jsonEncode(format)})',
      );
    }
    final version = parsed['version'];
    if (version is! int) {
      throw const SeedFormatException('version is missing or is not a number');
    }
    if (version > formatVersion) {
      throw SeedFormatException(
        'the seed is version $version and this build reads up to $formatVersion',
      );
    }

    return (
      ingredients: [
        for (final entry in (parsed['ingredients'] as List? ?? const []))
          _ingredientFromJson(_object(entry, 'ingredient')),
      ],
      recipes: [
        for (final entry in (parsed['recipes'] as List? ?? const []))
          _recipeFromJson(_object(entry, 'recipe')),
      ],
    );
  }

  // --- ingredients ------------------------------------------------------

  static Map<String, Object?> _ingredientToJson(Ingredient ingredient) => {
    'id': ingredient.id,
    'name': ingredient.name,
    if (ingredient.category != null) 'category': ingredient.category!.name,
    if (ingredient.aliases.isNotEmpty) 'aliases': ingredient.aliases,
    if (ingredient.abvPercent != null)
      'abvPercent': _rationalToJson(ingredient.abvPercent!),
    if (ingredient.sugarGPerL != null)
      'sugarGPerL': _rationalToJson(ingredient.sugarGPerL!),
    if (ingredient.densityGPerMl != null)
      'densityGPerMl': _rationalToJson(ingredient.densityGPerMl!),
    if (ingredient.defaultUnit != null) 'defaultUnit': ingredient.defaultUnit!.id,
    if (ingredient.bottleSizesMillilitres.isNotEmpty)
      'bottleSizesMillilitres': ingredient.bottleSizesMillilitres,
    if (ingredient.sourceBucket != null)
      'sourceBucket': ingredient.sourceBucket!.name,
    if (ingredient.isCommon) 'isCommon': true,
    if (ingredient.note != null) 'note': ingredient.note,
    if (ingredient.extras.isNotEmpty) 'extras': ingredient.extras,
  };

  static Ingredient _ingredientFromJson(Map<String, Object?> json) => Ingredient(
    id: _string(json['id'], 'ingredient id'),
    name: _string(json['name'], 'ingredient name'),
    category: _enumByName(IngredientCategory.values, json['category']),
    aliases: _strings(json['aliases']),
    abvPercent: _rationalOrNull(json['abvPercent']),
    sugarGPerL: _rationalOrNull(json['sugarGPerL']),
    densityGPerMl: _rationalOrNull(json['densityGPerMl']),
    defaultUnit: _unitById(json['defaultUnit']),
    bottleSizesMillilitres: [
      for (final size in (json['bottleSizesMillilitres'] as List? ?? const []))
        if (size is int) size,
    ],
    sourceBucket: _enumByName(SourceBucket.values, json['sourceBucket']),
    isCommon: json['isCommon'] == true,
    note: json['note'] as String?,
    extras: _stringMap(json['extras']),
  );

  // --- recipes ----------------------------------------------------------

  static Map<String, Object?> _recipeToJson(Recipe recipe) => {
    'id': recipe.id,
    'name': recipe.name,
    if (recipe.subtitle != null) 'subtitle': recipe.subtitle,
    if (recipe.packId != null) 'packId': recipe.packId,
    if (recipe.description != null) 'description': recipe.description,
    if (recipe.origin != null) 'origin': recipe.origin,
    if (recipe.glass != null) 'glass': recipe.glass!.name,
    if (recipe.ice != null) 'ice': recipe.ice!.name,
    if (recipe.method != null) 'method': recipe.method!.name,
    if (recipe.methodSteps.isNotEmpty) 'methodSteps': recipe.methodSteps,
    if (recipe.liquid != null) 'liquid': _liquidToJson(recipe.liquid!),
    'flavors': _flavorsToJson(recipe.flavors),
    if (recipe.rating != null)
      'rating': {
        'value': _rationalToJson(recipe.rating!.value),
        if (recipe.rating!.count != null) 'count': recipe.rating!.count,
      },
    if (!recipe.isSeed) 'isSeed': false,
    if (recipe.extras.isNotEmpty) 'extras': recipe.extras,
    'items': [for (final item in recipe.items) _itemToJson(item)],
  };

  static Recipe _recipeFromJson(Map<String, Object?> json) => Recipe(
    id: _string(json['id'], 'recipe id'),
    name: _string(json['name'], 'recipe name'),
    subtitle: json['subtitle'] as String?,
    packId: json['packId'] as String?,
    description: json['description'] as String?,
    origin: json['origin'] as String?,
    glass: _enumByName(Glass.values, json['glass']),
    ice: _enumByName(IceKind.values, json['ice']),
    method: _enumByName(Method.values, json['method']),
    methodSteps: _strings(json['methodSteps']),
    liquid: json['liquid'] == null
        ? null
        : _liquidFromJson(_object(json['liquid'], 'liquid')),
    flavors: _flavorsFromJson(json['flavors']),
    rating: json['rating'] == null
        ? null
        : _ratingFromJson(_object(json['rating'], 'rating')),
    isSeed: json['isSeed'] != false,
    extras: _stringMap(json['extras']),
    items: [
      for (final entry in (json['items'] as List? ?? const []))
        _itemFromJson(_object(entry, 'item')),
    ],
  );

  static Map<String, Object?> _itemToJson(RecipeItem item) => {
    'ingredientId': item.ingredientId,
    'amount': item.amount,
    if (item.count != null) 'count': _rationalToJson(item.count!),
    if (item.unit != null) 'unit': item.unit!.id,
    'role': item.role.name,
    if (item.originalText != null) 'originalText': item.originalText,
    if (item.note != null) 'note': item.note,
    if (item.substitutes.isNotEmpty) 'substitutes': item.substitutes,
  };

  static RecipeItem _itemFromJson(Map<String, Object?> json) => RecipeItem(
    ingredientId: _string(json['ingredientId'], 'item ingredientId'),
    amount: (json['amount'] as num?)?.toInt() ?? 0,
    count: _rationalOrNull(json['count']),
    unit: _unitById(json['unit']),
    role: _enumByName(ItemRole.values, json['role']) ?? ItemRole.base,
    originalText: json['originalText'] as String?,
    note: json['note'] as String?,
    substitutes: _strings(json['substitutes']),
  );

  static Map<String, Object?> _liquidToJson(LiquidVisual liquid) => {
    'colour': liquid.colour.sourceName,
    'opacity': liquid.opacityPercent,
    if (liquid.colourSecondary != null)
      'colourSecondary': liquid.colourSecondary!.sourceName,
    if (liquid.opacitySecondary != null) 'opacitySecondary': liquid.opacitySecondary,
    if (liquid.layered) 'layered': true,
  };

  static LiquidVisual _liquidFromJson(Map<String, Object?> json) => LiquidVisual(
    colour: LiquidColour.fromSource(_string(json['colour'], 'liquid colour'))!,
    colourSecondary: json['colourSecondary'] == null
        ? null
        : LiquidColour.fromSource(json['colourSecondary']! as String),
    opacityPercent: (json['opacity'] as num?)?.toInt() ?? 0,
    opacitySecondary: (json['opacitySecondary'] as num?)?.toInt(),
    layered: json['layered'] == true,
  );

  static Map<String, Object?> _flavorsToJson(FlavorProfile profile) => {
    if (profile.primary != null) 'primary': profile.primary!.name,
    if (profile.secondary != null) 'secondary': profile.secondary!.name,
    if (profile.tertiary != null) 'tertiary': profile.tertiary!.name,
  };

  static FlavorProfile _flavorsFromJson(Object? raw) {
    if (raw is! Map<String, Object?>) return const FlavorProfile();
    return FlavorProfile(
      primary: _enumByName(Flavor.values, raw['primary']),
      secondary: _enumByName(Flavor.values, raw['secondary']),
      tertiary: _enumByName(Flavor.values, raw['tertiary']),
    );
  }

  static Rating _ratingFromJson(Map<String, Object?> json) => Rating(
    value: _rationalOrNull(json['value']) ?? Rational.zero,
    count: (json['count'] as num?)?.toInt(),
  );

  // --- the four primitives that need care -------------------------------

  /// A [Rational] as an exact string: `6`, or `9/2` for a fraction.
  ///
  /// **Not [Rational.toString], because that does not round-trip.** `toString`
  /// gives `9/2` and `Rational.parse` reads only decimals, so a value written
  /// with one cannot be read by the other -- and 4.5 written as `"4.5"` and
  /// read back through a floating point would not be 4.5. This form is exact,
  /// reads back through [Rational.of], and is unambiguous about which of the
  /// two it is.
  static String _rationalToJson(Rational value) => value.isInteger
      ? '${value.numerator}'
      : '${value.numerator}/${value.denominator}';

  static Rational? _rationalOrNull(Object? raw) {
    if (raw == null) return null;
    if (raw is! String) {
      throw SeedFormatException('a number is written as ${jsonEncode(raw)}, '
          'which is not a string');
    }
    final slash = raw.indexOf('/');
    if (slash < 0) {
      final whole = BigInt.tryParse(raw);
      if (whole == null) throw SeedFormatException('"$raw" is not a number');
      return Rational.fromBigInt(whole);
    }
    final numerator = BigInt.tryParse(raw.substring(0, slash));
    final denominator = BigInt.tryParse(raw.substring(slash + 1));
    if (numerator == null || denominator == null || denominator == BigInt.zero) {
      throw SeedFormatException('"$raw" is not a fraction');
    }
    return Rational(numerator, denominator);
  }

  /// A unit by its id, or null.
  ///
  /// Null rather than a throw for an id this build does not know: a unit is a
  /// display choice and an unknown one costs readability, not correctness. The
  /// amount is already in microlitres and stays exact either way.
  static Unit? _unitById(Object? raw) {
    if (raw is! String) return null;
    for (final unit in UnitSystem.all) {
      if (unit.id == raw) return unit;
    }
    return null;
  }

  /// An enum by name: null when the field is absent, **a throw when the name is
  /// present and this build does not know it.**
  ///
  /// The two are different facts and are treated differently on purpose. An
  /// absent field is a seed that does not carry the value -- `Recipe.glass` is
  /// nullable for exactly that reason. A value this build cannot read is a
  /// newer seed, or a corrupted one, and reading it as null would turn "a glass
  /// this build cannot draw" into "no glass", which is a lie the caller cannot
  /// detect. So it stops the load and says what it saw.
  static T? _enumByName<T extends Enum>(List<T> values, Object? raw) {
    if (raw == null) return null;
    if (raw is! String) {
      throw SeedFormatException('an enum value is ${jsonEncode(raw)}, not a name');
    }
    for (final value in values) {
      if (value.name == raw) return value;
    }
    throw SeedFormatException(
      '"$raw" is not one of ${values.map((v) => v.name).join(", ")}',
    );
  }

  static Map<String, Object?> _object(Object? raw, String what) {
    if (raw is! Map<String, Object?>) {
      throw SeedFormatException('an entry in $what is not an object');
    }
    return raw;
  }

  static String _string(Object? raw, String what) {
    if (raw is! String || raw.isEmpty) {
      throw SeedFormatException('$what is missing or empty');
    }
    return raw;
  }

  static List<String> _strings(Object? raw) => [
    for (final entry in (raw as List? ?? const []))
      if (entry is String) entry,
  ];

  static Map<String, String> _stringMap(Object? raw) {
    if (raw is! Map) return const {};
    final result = <String, String>{};
    raw.forEach((key, value) {
      if (key is String && value is String) result[key] = value;
    });
    return result;
  }
}
