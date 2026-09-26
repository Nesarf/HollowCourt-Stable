import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../domain/preferences/cellar_preferences.dart';
import '../domain/preferences/choice_set.dart';
import '../domain/pricing/price.dart';
import '../domain/units/measure_set.dart';
import '../domain/units/unit.dart';
import '../domain/units/unit_system.dart';
import 'l10n/locale_defaults.dart';
import 'l10n/locale_providers.dart';

/// Reads and writes the reader's unit and money choices.
///
/// The same shape as `LocaleSettingsStore`, and for the same reasons: a missing or
/// unreadable file is a preference lost rather than an error shown, because the reader
/// asked to mix a drink and not to debug a settings screen.
///
/// **Per axis, unlike the locale store.** That one has three fields that belong
/// together; this has two that do not, and `CellarPreferences.fromJson` already falls
/// back per axis. So this only has to hand it the seeds.
final class PreferencesStore {
  const PreferencesStore(this.file);

  final File file;

  /// Reads what is there, or null when nothing usable is.
  Future<CellarPreferences?> read({
    required Map<MatterState, ChoiceSet<Unit>> seedMeasures,
    required ChoiceSet<Currency> seedCurrencies,
  }) async {
    try {
      if (!await file.exists()) return null;
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return null;
      return CellarPreferences.fromJson(
        jsonDecode(raw),
        seedMeasures: seedMeasures,
        seedCurrencies: seedCurrencies,
      );
    } catch (_) {
      return null;
    }
  }

  /// Writes the choices out. A failure is swallowed for the reason in [read].
  Future<void> write(CellarPreferences preferences) async {
    try {
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode(preferences.toJson()));
    } catch (_) {
      // Deliberately silent: see read().
    }
  }
}

/// Where the preferences file goes, resolved once.
final preferencesFileProvider = FutureProvider<File>((Ref ref) async {
  final directory = await getApplicationSupportDirectory();
  return File('${directory.path}${Platform.pathSeparator}preferences.json');
});

/// The reader's units and money, seeded from their language and then from the file.
///
/// **Seeded once, at startup, and not re-seeded when the language changes.** A reader
/// who switches the interface to English has not asked for their bottles to start
/// reading in ounces, and re-seeding would silently overwrite a choice they made. The
/// language decides what a *fresh* cellar offers; after that the two are independent.
final preferencesProvider =
    NotifierProvider<PreferencesNotifier, CellarPreferences>(
  PreferencesNotifier.new,
);

class PreferencesNotifier extends Notifier<CellarPreferences> {
  PreferencesStore? _store;

  @override
  CellarPreferences build() {
    final seeded = _seedFromLocale(ref.read(localeSettingsProvider).primaryTag);
    unawaited(_restore(seeded));
    return seeded;
  }

  /// What the locale table offers, as a preference value.
  static CellarPreferences _seedFromLocale(String tag) {
    final measures = measuresFor(tag);
    return CellarPreferences(
      measures: {
        for (final state in MatterState.values)
          if (measures.forState(state) != null)
            state: measures.forState(state)!.units,
      },
      currencies: currenciesFor(tag),
    );
  }

  Future<void> _restore(CellarPreferences seeded) async {
    final store = _store ??= PreferencesStore(
      await ref.read(preferencesFileProvider.future),
    );
    final stored = await store.read(
      seedMeasures: seeded.measures,
      seedCurrencies: seeded.currencies,
    );
    if (stored != null) state = stored;
  }

  Future<void> _commit(CellarPreferences next) async {
    state = next;
    final store = _store ??= PreferencesStore(
      await ref.read(preferencesFileProvider.future),
    );
    await store.write(next);
  }

  /// Replaces the units for one state of matter.
  Future<void> setMeasures(MatterState state, ChoiceSet<Unit> units) =>
      _commit(this.state.withMeasures(state, units));

  /// Replaces the currency slots.
  Future<void> setCurrencies(ChoiceSet<Currency> currencies) =>
      _commit(state.withCurrencies(currencies));

  /// The unit this reader measures [state] in.
  ///
  /// **`either` answers with the liquid unit, which is the useful answer to "what do I
  /// pour this in".** The `either` set exists precisely to offer both, and the
  /// instruction settles its default as volume -- so a caller asking about a syrup gets
  /// the unit they would actually pour it in rather than a set's own primary, which
  /// happens to be the same thing until somebody edits it.
  ///
  /// Falls back to the locale's own default rather than to a constant, because that is
  /// what this notifier was seeded from and the two answers should agree.
  Unit unitFor(MatterState matter) {
    final key = matter == MatterState.either ? MatterState.liquid : matter;
    final chosen = state.measuresFor(key);
    if (chosen != null) return chosen.primary;

    final byLocale = measuresFor(ref.read(localeSettingsProvider).primaryTag);
    return byLocale.forState(key)?.primary ?? UnitSystem.millilitre;
  }
}
