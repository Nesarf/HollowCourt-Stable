import '../units/quantity.dart';
import '../units/rational.dart';
import '../units/unit.dart';
import '../units/unit_system.dart';

/// What a written ingredient line turned out to be able to say.
///
/// Four outcomes rather than one, because the sources genuinely contain four
/// kinds of line and collapsing them would mean inventing amounts. Section 5.3
/// and the reverse-engineering record between them settle the rule: the parser
/// **may do something when it meets an unfamiliar phrase, but it must never
/// guess silently.** So an outcome that could not be measured says so and says
/// why, and [UnparsedIngredient] exists so that "I do not understand this" is a
/// result rather than an exception somebody swallows.
sealed class ParsedIngredient {
  const ParsedIngredient({required this.ingredient});

  /// The ingredient, with the amount and the unit stripped off.
  final String ingredient;
}

/// A number with a unit that has a size: `2 oz of rye whiskey`.
final class MeasuredIngredient extends ParsedIngredient {
  const MeasuredIngredient({
    required super.ingredient,
    required this.amount,
    required this.unit,
    required this.volume,
    required this.isEstimate,
  });

  /// As written, before conversion.
  final Rational amount;

  /// The unit as written, kept because section 4.4 says a recipe item preserves
  /// the unit it arrived in -- a bartender reads `2 oz`, not `59147 ul`.
  final Unit unit;

  /// The exact amount, rounded once, here.
  final Volume volume;

  /// True when the unit's size is a convention rather than a standard.
  ///
  /// A caller that shows the number has to decide what to do about this; a
  /// caller that does not look cannot present a guess as arithmetic.
  final bool isEstimate;
}

/// A number of whole things: `1 twist of lemon`, `4 of mint leaf`.
final class CountedIngredient extends ParsedIngredient {
  const CountedIngredient({
    required super.ingredient,
    required this.count,
    required this.unit,
  });

  final Rational count;

  /// A discrete unit -- `twist`, `leaf`, `wedge` -- or [UnitSystem.each] when
  /// the source gave a number and no unit word at all.
  final Unit unit;
}

/// A line that says how to use something without saying how much.
///
/// `rim of bar sugar`, `rinse of absinthe`, `grated of nutmeg`. These are real
/// instructions and they are not amounts. Inventing a number for them -- a
/// teaspoon of sugar, a dash of absinthe -- would put a fabricated quantity
/// into a stock ledger, where it would then be deducted from a real bottle.
final class UnmeasuredIngredient extends ParsedIngredient {
  const UnmeasuredIngredient({
    required super.ingredient,
    required this.use,
    required this.why,
  });

  /// The word that displaced the amount: `rim`, `rinse`, `grated`. Null when
  /// the line carried no such word either (`of salt`).
  final String? use;

  final String why;
}

/// A line this parser does not understand.
///
/// Deliberately not an exception. An importer meeting an unfamiliar spelling
/// wants to finish the run, collect every one of them, and report the list --
/// which is more useful than dying on the first, and far more useful than
/// guessing and reporting nothing.
final class UnparsedIngredient extends ParsedIngredient {
  const UnparsedIngredient({
    required super.ingredient,
    required this.raw,
    required this.why,
  });

  final String raw;
  final String why;
}

/// Parses the human-readable ingredient lines the sources actually contain.
///
/// The grammar below is not invented; it is read off the 390 lines in the another source
/// harvest, which between them use exactly four shapes:
///
/// ```
/// <number> <unit> of <ingredient>     356   2 oz of rye whiskey
/// <number> of <ingredient>             28   1 of cherry
/// <word> of <ingredient>                4   rim of bar sugar
/// of <ingredient>                       2   of egg
/// ```
///
/// That is the whole of it. Anything else is reported rather than absorbed.
///
/// This lives in the domain layer because it is not import machinery: a person
/// typing a recipe into the app writes the same kind of line, and the same
/// question -- how much is a dash, and was that even an amount? -- has to be
/// answered the same way there.
abstract final class IngredientPhrase {
  /// Words that describe a use, not a size.
  ///
  /// Kept as a closed set. An unfamiliar word in that position is reported as
  /// unparsed rather than accepted as a preparation, because accepting anything
  /// there is how `2 glugs of gin` would become a measurement.
  static const Set<String> uses = {'rim', 'rinse', 'grated', 'muddled', 'flamed'};

  static final RegExp _leadingNumber = RegExp(r'^(\d+(?:[.,]\d+)?)\s+(.*)$');
  static final RegExp _wordThenOf = RegExp(r'^(\S+)\s+of\s+(.+)$');
  static final RegExp _ofOnly = RegExp(r'^of\s+(.+)$');

  /// Parses [raw], resolving unit words against [units].
  ///
  /// Defaults to a standard [UnitSystem]; pass a calibrated one to have dashes
  /// and pinches come out at the size this particular bar measures.
  static ParsedIngredient parse(String raw, {UnitSystem? units}) {
    final system = units ?? UnitSystem.standard();
    final text = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (text.isEmpty) {
      return const UnparsedIngredient(
        ingredient: '',
        raw: '',
        why: 'the line is empty',
      );
    }

    // --- a leading number, if there is one -------------------------------
    Rational? number;
    var rest = text;
    final leading = _leadingNumber.firstMatch(text);
    if (leading != null) {
      number = Rational.parse(leading.group(1)!.replaceAll(',', '.'));
      rest = leading.group(2)!.trim();
    }

    // --- `<number> of <ingredient>`: a count with no unit word -----------
    if (number != null) {
      final ofOnly = _ofOnly.firstMatch(rest);
      if (ofOnly != null) {
        final ingredient = ofOnly.group(1)!.trim();
        if (ingredient.isEmpty) {
          return UnparsedIngredient(
            ingredient: '',
            raw: raw,
            why: 'a number and "of", but nothing after it',
          );
        }
        return CountedIngredient(
          ingredient: ingredient,
          count: number,
          unit: UnitSystem.each,
        );
      }
    }

    // --- `<word> of <ingredient>` ----------------------------------------
    final wordThenOf = _wordThenOf.firstMatch(rest);
    if (wordThenOf != null) {
      final word = wordThenOf.group(1)!.toLowerCase();
      final ingredient = wordThenOf.group(2)!.trim();
      final unit = _unitFor(word, system);

      if (number != null) {
        // `<number> <unit> of <ingredient>` -- the common case.
        if (ingredient.isEmpty) {
          return UnparsedIngredient(
            ingredient: '',
            raw: raw,
            why: 'nothing after "of"',
          );
        }
        if (unit != null && unit.kind != UnitKind.discrete) {
          return MeasuredIngredient(
            ingredient: ingredient,
            amount: number,
            unit: unit,
            volume: system.volumeOf(number, unit),
            isEstimate: system.isEstimate(unit),
          );
        }
        if (unit != null) {
          return CountedIngredient(
            ingredient: ingredient,
            count: number,
            unit: unit,
          );
        }
        // A word that is neither a unit nor a use, in a numbered line.
        if (uses.contains(word)) {
          return UnmeasuredIngredient(
            ingredient: ingredient,
            use: word,
            why: '"$word" describes how to use it, not how much',
          );
        }
        return UnparsedIngredient(
          ingredient: ingredient,
          raw: raw,
          why: '"$word" is not a unit this system knows',
        );
      }

      // No number: `<use> of <ingredient>`, or a broken unit.
      if (unit != null) {
        return UnparsedIngredient(
          ingredient: ingredient,
          raw: raw,
          why: 'the unit "$word" has no number in front of it',
        );
      }
      return UnmeasuredIngredient(
        ingredient: ingredient,
        use: uses.contains(word) ? word : null,
        why: uses.contains(word)
            ? '"$word" describes how to use it, not how much'
            : 'no amount is given, and "$word" is not a unit',
      );
    }

    // --- `of <ingredient>`: nothing but a name ----------------------------
    final ofOnly = _ofOnly.firstMatch(rest);
    if (ofOnly != null && number == null) {
      final ingredient = ofOnly.group(1)!.trim();
      if (ingredient.isEmpty) {
        return UnparsedIngredient(
          ingredient: '',
          raw: raw,
          why: 'nothing after "of"',
        );
      }
      return UnmeasuredIngredient(
        ingredient: ingredient,
        use: null,
        why: 'no amount is given at all',
      );
    }

    return UnparsedIngredient(
      ingredient: rest,
      raw: raw,
      why: 'does not match any shape the sources use',
    );
  }

  static Unit? _unitFor(String word, UnitSystem system) {
    for (final unit in UnitSystem.all) {
      if (unit.id == word) return unit;
    }
    return null;
  }
}
