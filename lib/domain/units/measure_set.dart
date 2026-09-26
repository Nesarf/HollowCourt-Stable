import '../preferences/choice_set.dart';
import 'unit.dart';
import 'unit_system.dart';

/// Which state of matter a measure set is for.
///
/// 固体用克、液体用毫升. The third member is not a state of matter -- it is the
/// admission that some things are measured either way, and the instruction says so
/// with 糖浆/蜂蜜: a syrup can be weighed or poured, and a set that had to choose one
/// would be wrong for half the bottles in the cupboard.
enum MatterState {
  /// Measured by mass: a solid, or anything that is scooped.
  solid,

  /// Measured by volume: anything that is poured.
  liquid,

  /// Either, and the reader picks. Defaulted to volume, because a syrup is poured
  /// far more often than it is weighed -- and the grams are still offered, so the
  /// default is a starting point rather than a rule.
  either,
}

/// The units one locale offers for one state of matter.
///
/// **One primary and up to three secondaries, and no repetition** -- the same shape
/// as the money axis, which is why both are a [ChoiceSet] rather than two types with
/// two copies of the uniqueness rule.
///
/// The units themselves are not locale-specific; which ones are *offered first* is.
/// A millilitre is a millilitre everywhere, and what changes is whether somebody
/// reaches for it or for a fluid ounce.
final class MeasureSet {
  const MeasureSet._(this.state, this.units);

  /// Builds a set from unit ids, **refusing one this system does not carry**.
  ///
  /// A refusal rather than a silent skip, for the reason `Unit`'s own equality gives:
  /// these ids are a wire format and a table of them is data. A typo that quietly
  /// dropped a unit would produce a locale offering three units where it meant four,
  /// and nothing on any screen would say so.
  factory MeasureSet.fromIds(
    MatterState state, {
    required String primary,
    List<String> secondary = const [],
  }) {
    Unit lookUp(String id) {
      final unit = UnitSystem.all.where((unit) => unit.id == id).firstOrNull;
      if (unit == null) {
        throw ArgumentError.value(id, 'unit id', 'this system carries no such unit');
      }
      return unit;
    }

    return MeasureSet._(
      state,
      ChoiceSet<Unit>(
        primary: lookUp(primary),
        secondary: [for (final id in secondary) lookUp(id)],
      ),
    );
  }

  final MatterState state;
  final ChoiceSet<Unit> units;

  Unit get primary => units.primary;

  /// The units in order, primary first.
  List<Unit> get all => units.all;

  /// The dimension of the primary, which is the unit a number is read in.
  UnitDimension get dimension => primary.dimension;

  /// Whether the set carries units of more than one dimension.
  ///
  /// **Not an error by itself, and that took a correction to see.** 糖浆/蜂蜜 are
  /// measured either way and the instruction is explicit that the default is volume
  /// with grams beside it -- so an `either` set mixing ml and g is exactly what was
  /// asked for. What is an error is mixing them for a *stated* state: a `liquid` set
  /// offering grams answers a question nobody asked, and would look perfectly fine on
  /// a screen. Hence [isLegal] rather than a blanket refusal.
  bool get isMixed => all.any((unit) => unit.dimension != dimension);

  /// Whether this set is allowed to be what it is.
  bool get isLegal => state == MatterState.either || !isMixed;

  @override
  String toString() => 'MeasureSet(${state.name}: ${all.map((u) => u.id).join(', ')})';
}

/// The measure sets a locale offers, and the one a fresh cellar starts with.
///
/// **The order is the point of a locale default.** A set is not a restriction -- a
/// reader can replace every unit in it -- it is what the app reaches for when nobody
/// has said. So this holds a list and a designated default rather than one set, and a
/// locale that measures solids in grams and liquids in millilitres, or one that
/// reaches for ounces, are the same type with different data.
final class LocaleMeasures {
  const LocaleMeasures({required this.sets});

  /// The sets this locale offers, in the order a screen should show them.
  final List<MeasureSet> sets;

  /// The set for [state], or null when this locale offers none.
  ///
  /// Null rather than a fallback set: a locale table that forgot solids should be
  /// visible as a gap, not masked by inventing a metric default. The caller that
  /// wants a fallback says so.
  MeasureSet? forState(MatterState state) =>
      sets.where((set) => set.state == state).firstOrNull;

  /// The sets that are mixed while claiming a single state.
  ///
  /// Called by the table's own test rather than at every construction, because it is
  /// a property of the table and not of a value. Empty is the healthy answer.
  List<String> illegalSets() => [
    for (final set in sets)
      if (!set.isLegal) set.toString(),
  ];
}
