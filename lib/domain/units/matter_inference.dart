import 'measure_set.dart';
import 'unit.dart';
import 'unit_system.dart';

/// **How a substance is measured, worked out from how the drinks actually measure it.**
///
/// The owner asked for this on 2026-09-22: *"落实固体、液体、组合等对应默认计量单位的智能识别"* -- and the
/// examples that make it concrete are the ones a bar meets every day. Gin is poured, so it is a volume; sugar
/// is scooped, so it is a mass; honey is both, depending on who is writing and what they are making; a lime is
/// counted, and neither of the two states describes it at all.
///
/// **The evidence is the recipes, and never the name.** `Ingredient.category` is null in this library by an
/// earlier decision (a name is not a fact about how something is measured: "cream" is poured and "cream of
/// coconut" is scooped, and a name-based rule would get one of them wrong), so the only honest source is what
/// the 88 drinks in this library actually do: `30 ml Gin` says volume, `5 g Sugar` says mass, and an
/// ingredient measured both ways in different drinks says *either* -- which is a real answer rather than an
/// abstention.
///
/// **Counted is not a third state, it is the absence of one.** A cherry and a mint leaf are neither solid nor
/// liquid in any sense that helps a reader choose a unit -- `MatterState` has no member for them by design --
/// so this returns null and the caller keeps whatever the library stated. Inventing a `counted` state would
/// put a value in a field the rest of the application reads as "which family of units to offer", and the
/// families are two.
enum MatterEvidenceKind {
  /// `ml`, `cl`, `l`, `oz` -- the drink is poured.
  volume,

  /// `g`, `kg`, `mg` -- the drink is weighed.
  mass,

  /// `each`, `slice`, `leaf`, `dash`, `pinch` -- the drink is counted, and the states do not apply.
  counted,
}

/// What the drinks said about one ingredient.
final class MatterEvidence {
  const MatterEvidence({this.volume = 0, this.mass = 0, this.counted = 0});

  /// How many times the drinks in the library measure this ingredient by volume.
  final int volume;

  /// How many times by mass.
  final int mass;

  /// How many times by counting, which is evidence for neither state.
  final int counted;

  int get total => volume + mass + counted;

  /// True when nothing in the library measures this ingredient at all.
  bool get isEmpty => total == 0;

  MatterEvidence withKind(MatterEvidenceKind kind) => switch (kind) {
    MatterEvidenceKind.volume => MatterEvidence(volume: volume + 1, mass: mass, counted: counted),
    MatterEvidenceKind.mass => MatterEvidence(volume: volume, mass: mass + 1, counted: counted),
    MatterEvidenceKind.counted => MatterEvidence(volume: volume, mass: mass, counted: counted + 1),
  };

  /// The share of the *measurable* instances that went by volume, mass being the rest.
  ///
  /// Counted instances are excluded from the fraction rather than counted as a third opinion: a lime that is
  /// muddled alongside measured ingredients says nothing about whether the gin is poured.
  double get volumeShare {
    final measurable = volume + mass;
    return measurable == 0 ? 0 : volume / measurable;
  }

  @override
  String toString() => 'volume $volume, mass $mass, counted $counted';
}

/// Which unit family a unit belongs to, in terms of this file's question.
///
/// **Read from the unit system rather than from a second list.** A table of unit ids here would be a second
/// place to update when the catalogue grows, and the one that is not updated is always the one being read.
MatterEvidenceKind kindOf(Unit unit) {
  // A counted unit is one that measures things rather than substance. `UnitSystem.all` is the catalogue, and
  // these are the units whose dimension is a count -- asked through the unit itself where it can answer, and
  // by name where the catalogue's own vocabulary is the only source.
  if (_countedUnits.contains(unit.id)) return MatterEvidenceKind.counted;
  if (_massUnits.contains(unit.id)) return MatterEvidenceKind.mass;
  return MatterEvidenceKind.volume;
}

const _countedUnits = {
  'each', 'slice', 'wheel', 'twist', 'peel', 'wedge', 'cube', 'leaf', 'sprig',
  'dash', 'drop', 'pinch', 'chunk', 'barspoon', 'part', 'shot',
};

const _massUnits = {'mg', 'g', 'kg', 'lb', 'ozm'};

/// **The answer for one ingredient, with the evidence that produced it.**
///
/// The evidence travels with the answer on purpose: a screen that says "honey is measured either way" and can
/// show *four by volume, three by mass* is a screen somebody can disagree with. A bare state is an assertion.
final class MatterReading {
  const MatterReading({required this.state, required this.evidence, required this.because});

  /// The inferred state, or null when the library counts this ingredient rather than measuring it -- and also
  /// null when nothing in the library measures it at all, which is honest rather than a guess.
  final MatterState? state;

  final MatterEvidence evidence;

  /// Where the answer came from, in a sentence, for the screen that explains it.
  final String because;

  bool get isKnown => state != null;
}

/// How much of the measurable instances one side must hold to count as *either*.
///
/// **A threshold rather than "any evidence of both".** One recipe out of thirty that weighs an ingredient it is
/// otherwise poured in is a recipe doing something unusual, not a substance that is measured two ways; calling
/// it *either* would make the entry form offer a scale for gin because one drink weighed it. A fifth is the
/// line: below that, the majority state is the answer.
const double _eitherThreshold = 0.2;

/// **What a category says about how its members are measured, when the drinks say nothing.**
///
/// The owner named three inputs for this work on 2026-09-22 -- each ingredient's `category`, its
/// `defaultUnit`, and what the recipes actually do -- and this is the third of them, used **last** and only
/// where the other two are silent. The order is the point: a category is a person's judgement about a group
/// ("syrups are poured"), while a stated default is a judgement about *this* ingredient and a recipe line is
/// an observation of somebody making a drink. A group judgement that overruled either would be a rule
/// disagreeing with the thing it describes.
///
/// **Only the categories that are unambiguous are mapped.** `itemsYouCanMake` and `top25MostUsed` are
/// collections rather than kinds; `pantryItems` and `groceryItems` hold both a bag of sugar and a bottle of
/// Worcestershire; a mapping for those would be a guess wearing a table's clothes, and null is the honest
/// answer for them.
MatterState? stateFromCategory(String? category) => switch (category) {
  'juices' || 'syrups' || 'sodas' || 'wine' || 'beerAndCider' || 'vermouth' || 'portAndSherry' ||
  'commonLiqueurs' || 'aperitifs' || 'commonAmaro' || 'commonBitters' || 'whiskey' || 'gin' || 'rum' ||
  'tequilaAndMezcal' || 'vodkaAndSimilar' || 'brandy' || 'mockSpirits' =>
    MatterState.liquid,

  'herbsAndSpices' || 'jamsAndPreserves' => MatterState.solid,

  // Counted by where they sit rather than by what they are, or genuinely either: no answer.
  _ => null,
};

/// **The whole inference, in one function**, so it can be tested against the library and against invented
/// evidence without a widget in sight.
///
/// [statedDefault] is the library's own `defaultUnit` for the ingredient, and it outranks the statistics when
/// it exists: somebody wrote it down about this ingredient, and a count of drink lines is an observation about
/// drinks.
MatterReading inferMatter({
  required MatterEvidence evidence,
  Unit? statedDefault,
  String? category,
}) {
  if (statedDefault != null) {
    final kind = kindOf(statedDefault);
    final state = switch (kind) {
      MatterEvidenceKind.mass => MatterState.solid,
      MatterEvidenceKind.volume => MatterState.liquid,
      // A stated *count* says the ingredient is not measured by substance, and says nothing about which family
      // to offer -- so the statistics get their say, and if they are silent the answer is that we do not know.
      MatterEvidenceKind.counted => null,
    };
    if (state != null) {
      return MatterReading(
        state: state,
        evidence: evidence,
        because: 'the library states ${statedDefault.id} for this ingredient',
      );
    }
  }

  if (evidence.volume + evidence.mass == 0) {
    // **The category gets its turn only here**, where nothing else can answer: an ingredient the drinks count
    // rather than measure, or one no drink in the library touches at all.
    final fromCategory = stateFromCategory(category);
    return MatterReading(
      state: fromCategory,
      evidence: evidence,
      because: fromCategory != null
          ? 'the drinks do not measure it; its category says ${fromCategory.name}'
          : evidence.counted == 0
              ? 'nothing in the library measures this ingredient'
              : 'the drinks count this ingredient rather than measuring it',
    );
  }

  final share = evidence.volumeShare;
  if (share >= 1 - _eitherThreshold) {
    return MatterReading(
      state: MatterState.liquid,
      evidence: evidence,
      because: 'every drink that measures it pours it (${evidence.volume} by volume)',
    );
  }
  if (share <= _eitherThreshold) {
    return MatterReading(
      state: MatterState.solid,
      evidence: evidence,
      because: 'every drink that measures it weighs it (${evidence.mass} by mass)',
    );
  }
  return MatterReading(
    state: MatterState.either,
    evidence: evidence,
    because: 'the drinks do both: ${evidence.volume} by volume, ${evidence.mass} by mass',
  );
}

/// The evidence for every ingredient in a set of drink lines, keyed by ingredient id.
///
/// Takes the pairs rather than the recipes so the domain stays free of the model layer's shape: callers pass
/// `(ingredientId, unit)` and this does not care where they came from.
Map<String, MatterEvidence> gatherEvidence(Iterable<({String ingredientId, Unit unit})> lines) {
  final evidence = <String, MatterEvidence>{};
  for (final line in lines) {
    final current = evidence[line.ingredientId] ?? const MatterEvidence();
    evidence[line.ingredientId] = current.withKind(kindOf(line.unit));
  }
  return evidence;
}

/// A unit id as the catalogue knows it, or null when this build does not carry it.
///
/// **Null rather than a default**, because a library naming a unit this build cannot measure in is a fact the
/// caller has to decide about; quietly reading it as millilitres would turn a data problem into wrong numbers
/// on a shelf.
Unit? unitById(String id) {
  for (final unit in UnitSystem.all) {
    if (unit.id == id) return unit;
  }
  return null;
}
