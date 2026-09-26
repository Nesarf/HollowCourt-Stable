import '../units/quantity.dart';
import '../units/rational.dart';
import 'item_role.dart';

/// How a drink is assembled.
///
/// The method matters to arithmetic rather than only to instructions: it is
/// what decides how much ice melts into the glass, and section 5.5 is blunt
/// that ignoring that gets the strength of the drink wrong.
enum Method {
  /// Stirred over ice.
  stirred,

  /// Shaken with ice.
  shaken,

  /// Built in the glass over ice.
  built,

  /// Poured without ice.
  poured,

  /// Blended with ice.
  blended,
}

/// One measured line of a drink.
///
/// Carries its own alcohol figure rather than pointing at an ingredient,
/// because the domain layer's arithmetic should not need a catalogue to run.
/// Anything that can look up an ingredient can build one of these.
final class Component {
  const Component({
    required this.volume,
    this.abvPercent,
    this.role = ItemRole.base,
  });

  /// The amount, as the recipe stores it: whole microlitres.
  ///
  /// Whole, because section 5.1 makes the microlitre the base and a recipe is
  /// written down once. Scaling multiplies this exactly, so the only rounding
  /// in a resized drink is the one that was already in the recipe.
  final Volume volume;

  /// Alcohol by volume as a percentage, where 40 means 40% ABV.
  ///
  /// Null for anything without alcohol. Deliberately not `0`: a drink does not
  /// have a component of unknown strength, and a missing figure should be a
  /// missing figure rather than a convenient zero that quietly weakens the
  /// answer.
  final Rational? abvPercent;

  final ItemRole role;

  bool get isAlcoholic => abvPercent != null && abvPercent!.isZero == false;

  /// The alcohol in this component, as a volume.
  ///
  /// Exact: `volume * abv / 100`, with no rounding until something asks for a
  /// whole number of microlitres.
  Rational alcoholMicrolitres() =>
      abvPercent == null
          ? Rational.zero
          : volume.toRational() * abvPercent! / Rational.fromInt(100);

  /// This component scaled by [factor], exactly.
  Component scaledBy(Rational factor) => Component(
    volume: Volume.fromMicrolitres(
      (volume.toRational() * factor).roundHalfUpToBigInt().toInt(),
    ),
    abvPercent: abvPercent,
    role: role,
  );

  @override
  String toString() {
    final strength = abvPercent == null ? '' : ' @$abvPercent%';
    return '${role.name} ${volume.microlitres}ul$strength';
  }
}

/// A drink, as the dosing arithmetic sees it.
///
/// Just the measured lines and the method. Names, glassware and the rest
/// belong to the recipe entity and to the layer that displays it; nothing here
/// needs them, and leaving them out is what keeps this testable on its own.
final class Drink {
  const Drink({required this.components, required this.method});

  final List<Component> components;
  final Method method;

  /// The total volume in the mixing vessel, before any ice has melted.
  Volume get undilutedVolume =>
      components.fold(Volume.zero, (sum, component) => sum + component.volume);

  /// The alcohol that will be in the glass, before dilution.
  Rational alcoholMicrolitres() => components.fold(
    Rational.zero,
    (sum, component) => sum + component.alcoholMicrolitres(),
  );

  /// Drinkable lines: everything that is actually part of the liquid.
  ///
  /// Garnishes are excluded. A twist of peel is not in the glass, and counting
  /// its (zero) volume would be harmless but counting a garnish that happens
  /// to carry alcohol -- a cherry in syrup, say -- would not.
  Iterable<Component> get liquidComponents =>
      components.where((component) => component.role != ItemRole.garnish);

  Drink scaledBy(Rational factor) => Drink(
    components: [
      for (final component in components) component.scaledBy(factor),
    ],
    method: method,
  );
}
