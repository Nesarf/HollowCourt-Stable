import '../pricing/price.dart';
import '../units/measure_set.dart';
import '../units/unit.dart';
import '../units/unit_system.dart';
import 'choice_set.dart';

/// What the reader has changed about units and money.
///
/// **A default is not a restriction, so the defaults need somewhere to be replaced.**
/// `locale_defaults.dart` decides what a fresh cellar offers; this is what it offers
/// once somebody has disagreed with it. 都可替换，都不可重复: the replacement is per
/// state of matter, because the reader who wants grams for solids has not thereby
/// asked for grams for liquids.
///
/// **Three axes and one value, because they are stored together.** A separate file per
/// axis would be three things to lose and three chances for the money on a screen to
/// come from a different generation than the units beside it.
final class CellarPreferences {
  const CellarPreferences({required this.measures, required this.currencies});

  /// The measuring system, by matter state.
  ///
  /// A plain map rather than a field per state, so that adding a fourth state is a
  /// table change and not a schema change. A state with no entry keeps whatever the
  /// locale table offered.
  final Map<MatterState, ChoiceSet<Unit>> measures;

  /// The reader's currency slots, primary first, at most one plus three.
  final ChoiceSet<Currency> currencies;

  /// What this reader measures [state] in, if they have said.
  ChoiceSet<Unit>? measuresFor(MatterState state) => measures[state];

  CellarPreferences withMeasures(MatterState state, ChoiceSet<Unit> units) =>
      CellarPreferences(
        measures: {...measures, state: units},
        currencies: currencies,
      );

  CellarPreferences withCurrencies(ChoiceSet<Currency> next) =>
      CellarPreferences(measures: measures, currencies: next);

  /// Writes the choices out as JSON.
  ///
  /// By unit **id** and currency **code**, never by symbol or display name: those are
  /// what a person reads, and a file written with them would break the first time a
  /// symbol was corrected. The ids are the same wire format the events use.
  Map<String, Object?> toJson() => <String, Object?>{
    'measures': <String, Object?>{
      for (final entry in measures.entries)
        entry.key.name: <String, Object?>{
          'primary': entry.value.primary.id,
          'secondary': [for (final unit in entry.value.secondary) unit.id],
        },
    },
    'currencies': <String, Object?>{
      'primary': currencies.primary.code,
      'secondary': [for (final currency in currencies.secondary) currency.code],
    },
  };

  /// Reads the choices back, **re-resolving every id and refusing what it cannot**.
  ///
  /// **Falling back per axis rather than failing whole.** A file written by a build
  /// that shipped a unit this one does not would otherwise lose the reader's money too,
  /// and the two have nothing to do with each other. So a unit id that does not resolve
  /// leaves the seed for that state in place and the currencies are still read.
  ///
  /// [seedMeasures] and [seedCurrencies] are what the locale table offers, which is
  /// also the answer for anything missing or unreadable.
  factory CellarPreferences.fromJson(
    Object? json, {
    required Map<MatterState, ChoiceSet<Unit>> seedMeasures,
    required ChoiceSet<Currency> seedCurrencies,
  }) {
    if (json is! Map<String, Object?>) {
      return CellarPreferences(
        measures: seedMeasures,
        currencies: seedCurrencies,
      );
    }

    final measures = <MatterState, ChoiceSet<Unit>>{...seedMeasures};
    final rawMeasures = json['measures'];
    if (rawMeasures is Map<String, Object?>) {
      for (final entry in rawMeasures.entries) {
        final state = MatterState.values
            .where((candidate) => candidate.name == entry.key)
            .firstOrNull;
        if (state == null) continue;
        final decoded = _choiceSetFromJson(
          entry.value,
          lookUp: (id) =>
              UnitSystem.all.where((unit) => unit.id == id).firstOrNull,
        );
        if (decoded != null) measures[state] = decoded;
      }
    }

    final currencies = _choiceSetFromJson(
          json['currencies'],
          lookUp: Currency.byCode,
        ) ??
        seedCurrencies;

    return CellarPreferences(measures: measures, currencies: currencies);
  }
}

/// One choice set, read from one JSON object, or null when it cannot be read.
///
/// Refuses rather than repairs: a set whose primary does not resolve is not a set with
/// a missing primary, and picking a different one for the reader would be inventing a
/// choice they did not make. The caller keeps its seed instead.
ChoiceSet<T>? _choiceSetFromJson<T>(
  Object? json, {
  required T? Function(String) lookUp,
}) {
  if (json is! Map<String, Object?>) return null;
  final primary = json['primary'];
  if (primary is! String) return null;
  final resolvedPrimary = lookUp(primary);
  if (resolvedPrimary == null) return null;

  final secondary = <T>[];
  final raw = json['secondary'];
  if (raw is List) {
    for (final item in raw) {
      if (item is! String) continue;
      final resolved = lookUp(item);
      // A secondary that does not resolve is dropped rather than refused, and that
      // asymmetry with the primary is deliberate: the primary is what a number is
      // read in and cannot be guessed, while a secondary is an offer beside it. Losing
      // one offer is better than losing the reader's whole set over a unit this build
      // no longer ships.
      if (resolved != null) secondary.add(resolved);
    }
  }

  try {
    return ChoiceSet<T>(primary: resolvedPrimary, secondary: secondary);
  } on Object {
    // More secondaries than the set allows, or a duplicate the table produced. The
    // seed is the safer answer than a truncated set that silently drops what the
    // reader chose.
    return null;
  }
}
