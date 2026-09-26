import '../model/item_role.dart';
import '../units/rational.dart';

/// One thing a recipe needs, and whether the bar has it.
///
/// Deliberately not an ingredient: the score needs a role and a yes or no, and
/// nothing else. That keeps this file free of the catalogue, so it can be
/// tested by writing down a list rather than by building a bar.
final class Requirement {
  const Requirement({
    required this.id,
    required this.role,
    required this.available,
  });

  /// Whatever identifies the ingredient in the caller's world.
  final String id;

  final ItemRole role;
  final bool available;
}

/// How much of a recipe a bar can actually make (design section 9).
///
/// Section 9 is explicit that this is not a yes-or-no question: a drink one
/// ingredient short is a different proposition from a drink three short, and a
/// drink short only of its garnish is not short at all.
final class MatchScore {
  const MatchScore({
    required this.main,
    required this.garnish,
    required this.missing,
  });

  /// The weighted fraction of the drink itself that is on hand.
  ///
  /// A fraction rather than a percentage, so that arithmetic on it stays exact
  /// and the display layer is the one that multiplies by a hundred.
  final Rational main;

  /// The same for the garnish, scored apart.
  ///
  /// Section 9 keeps these separate for a concrete reason: a missing twist of
  /// peel should not turn a Negroni from "makeable" into "impossible". Both
  /// numbers are reported and neither is folded into the other.
  final Rational garnish;

  /// The ingredients that are not on hand, in the order they were given.
  final List<Requirement> missing;

  /// How much each role counts for.
  ///
  /// Garnish weighs nothing here because it is scored in [garnish] instead.
  /// Giving it a weight as well would count it twice.
  static Rational weightOf(ItemRole role) => switch (role) {
    ItemRole.base => Rational.one,
    ItemRole.modifier => Rational.of(8, 10),
    ItemRole.optional => Rational.of(3, 10),
    ItemRole.garnish => Rational.zero,
  };

  /// Scores [requirements].
  ///
  /// A recipe with nothing but a garnish -- or with no garnish at all -- scores
  /// one on the part that has nothing in it. There is nothing missing from an
  /// empty list, and reporting zero would say the opposite.
  factory MatchScore.of(List<Requirement> requirements) {
    var mainAvailable = Rational.zero;
    var mainTotal = Rational.zero;
    var garnishAvailable = Rational.zero;
    var garnishTotal = Rational.zero;
    final missing = <Requirement>[];

    for (final requirement in requirements) {
      if (!requirement.available) missing.add(requirement);

      if (requirement.role == ItemRole.garnish) {
        // Counted at one each, not by [weightOf]. That method returns zero for
        // a garnish because a garnish must not count toward the main score --
        // and using the same zero here would make this total zero as well, so
        // that a *missing* garnish scored a perfect one. The two tallies need
        // different weights for the same role, which is the whole reason the
        // two tallies exist.
        garnishTotal = garnishTotal + Rational.one;
        if (requirement.available) {
          garnishAvailable = garnishAvailable + Rational.one;
        }
      } else {
        final weight = weightOf(requirement.role);
        mainTotal = mainTotal + weight;
        if (requirement.available) mainAvailable = mainAvailable + weight;
      }
    }

    return MatchScore(
      main: mainTotal.isZero ? Rational.one : mainAvailable / mainTotal,
      garnish: garnishTotal.isZero ? Rational.one : garnishAvailable / garnishTotal,
      missing: List.unmodifiable(missing),
    );
  }

  /// What the main score means, in the bands section 9 sets out.
  MatchVerdict get verdict {
    if (main >= Rational.of(95, 100)) return MatchVerdict.makeable;
    if (main >= Rational.of(70, 100)) return MatchVerdict.close;
    return MatchVerdict.insufficient;
  }

  /// Whether the garnish is all there.
  bool get garnishComplete => garnish >= Rational.one;

  /// The main score as a percentage, for display.
  ///
  /// Rounded, and labelled as a display value by being the only method here
  /// that leaves exact arithmetic.
  int get mainPercent => (main * Rational.fromInt(100)).roundHalfUpToBigInt().toInt();

  /// The garnish score as a percentage.
  int get garnishPercent =>
      (garnish * Rational.fromInt(100)).roundHalfUpToBigInt().toInt();

  @override
  String toString() =>
      'MatchScore(main: $mainPercent%, garnish: $garnishPercent%, '
      'missing: ${missing.length})';
}

/// What a score means to somebody deciding what to drink.
enum MatchVerdict {
  /// Ninety-five percent or better: the drink can be made.
  makeable,

  /// Seventy to ninety-four: close, and worth showing what is missing.
  close,

  /// Below seventy: not tonight.
  insufficient,
}
