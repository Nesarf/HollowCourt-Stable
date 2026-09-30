import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../domain/pricing/price.dart';

/// What the reader has told the application about the bar's money.
///
/// **Both fields are things only the reader knows.** Everything else on the cashflow view is derived from the
/// event log -- what was spent, over four windows -- but the till's starting point and what is in it now are
/// facts from outside the application, so they are stored rather than computed. `CashReconciliation` says what
/// the difference between them means; this says what the two numbers are.
///
/// **Stored per currency, and that is not over-engineering.** A reader who buys in two currencies has two
/// tills, and a single deposit figure would silently be in whichever currency happened to be written first.
/// The map is keyed by currency code, so the arithmetic never has to guess.
///
/// **The counted amount carries its date.** "What is in the till" is a statement about a moment: a count from
/// three weeks ago is not wrong, but presenting it as today's answer would be. `countedAtMillis` is null when
/// the reader has not counted, which is different from a count of zero -- the same distinction `Money?` carries
/// everywhere else in this project.
final class CashSettings {
  const CashSettings({
    this.deposits = const <String, int>{},
    this.counted = const <String, int>{},
    this.countedAtMillis,
  });

  /// What the bar started with, by currency code, in minor units.
  final Map<String, int> deposits;

  /// What the reader last counted in the till, by currency code, in minor units.
  final Map<String, int> counted;

  /// When [counted] was entered, or null when nothing has been counted.
  final int? countedAtMillis;

  bool get hasCounted => countedAtMillis != null && counted.isNotEmpty;

  /// What was put in to start with, in [currency], or null when the reader has not said.
  Money? depositIn(Currency currency) {
    final minor = deposits[currency.code];
    return minor == null ? null : Money.fromMinorUnits(minor, currency);
  }

  /// What the reader counted, in [currency], or null when they have not counted.
  Money? countedIn(Currency currency) {
    if (!hasCounted) return null;
    final minor = counted[currency.code];
    return minor == null ? null : Money.fromMinorUnits(minor, currency);
  }

  CashSettings withDeposit(Currency currency, int minorUnits) => CashSettings(
    deposits: {...deposits, currency.code: minorUnits},
    counted: counted,
    countedAtMillis: countedAtMillis,
  );

  CashSettings withCounted(Currency currency, int minorUnits, int atMillis) => CashSettings(
    deposits: deposits,
    counted: {...counted, currency.code: minorUnits},
    countedAtMillis: atMillis,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'deposits': deposits,
    'counted': counted,
    'countedAtMillis': countedAtMillis,
  };

  /// Reads a stored file back, **falling back per field rather than failing whole** -- the rule
  /// `DisplaySettings.fromJson` and `CellarPreferences.fromJson` both follow, and for the same reason: a
  /// setting must never be able to stop the application from opening.
  factory CashSettings.fromJson(Object? json) {
    if (json is! Map<String, Object?>) return const CashSettings();
    int? asMinor(Object? value) => value is int ? value : null;
    Map<String, int> asMap(Object? value) {
      if (value is! Map) return const <String, int>{};
      final out = <String, int>{};
      for (final entry in value.entries) {
        final minor = asMinor(entry.value);
        final code = entry.key;
        if (minor != null && code is String && code.isNotEmpty) out[code] = minor;
      }
      return out;
    }

    return CashSettings(
      deposits: asMap(json['deposits']),
      counted: asMap(json['counted']),
      countedAtMillis: asMinor(json['countedAtMillis']),
    );
  }
}

/// The file the bar's money settings live in, handed in rather than found.
///
/// The same shape every other store in this project uses: it never asks the platform where anything is, so a
/// test hands it a file in a temporary directory and exercises the real read and write paths.
final class CashSettingsStore {
  const CashSettingsStore(this.file);

  final File file;

  Future<CashSettings?> read() async {
    try {
      if (!await file.exists()) return null;
      final text = await file.readAsString();
      if (text.trim().isEmpty) return null;
      return CashSettings.fromJson(jsonDecode(text));
    } catch (_) {
      // Deliberately silent, for the reason the other stores give: a preference is the least important byte
      // in the application and the only one that could stop it from opening.
      return null;
    }
  }

  Future<void> write(CashSettings settings) async {
    try {
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode(settings.toJson()));
    } catch (_) {
      // Deliberately silent: the screen has already changed, and a failed write costs the reader their entry
      // next launch rather than this one.
    }
  }
}

/// Where the bar's money settings go, resolved once.
final cashSettingsFileProvider = FutureProvider<File>((Ref ref) async {
  final directory = await getApplicationSupportDirectory();
  return File('${directory.path}${Platform.pathSeparator}cash.json');
});

/// The reader's deposit and their last count.
final cashSettingsProvider = NotifierProvider<CashSettingsNotifier, CashSettings>(
  CashSettingsNotifier.new,
);

class CashSettingsNotifier extends Notifier<CashSettings> {
  CashSettingsStore? _store;

  @override
  CashSettings build() {
    unawaited(_restore());
    return const CashSettings();
  }

  Future<void> _restore() async {
    // **The whole read is guarded, not just the file's own**, for the reason `display_providers.dart` records:
    // `getApplicationSupportDirectory` goes through a platform channel, and a channel that is not there -- a
    // widget test, or a platform whose plugin failed to register -- throws rather than returning null.
    try {
      final file = await ref.read(cashSettingsFileProvider.future);
      final store = CashSettingsStore(file);
      _store = store;
      final stored = await store.read();
      if (stored != null) state = stored;
    } catch (_) {
      // Deliberately silent: the defaults are already the state.
    }
  }

  Future<void> setDeposit(Currency currency, int minorUnits) async {
    state = state.withDeposit(currency, minorUnits);
    await _store?.write(state);
  }

  /// Records a count, and **stamps it with the moment it was taken.** The timestamp is the point: a count is
  /// an observation of a specific time, and the comparison is only meaningful while the reader can see how old
  /// it is.
  Future<void> setCounted(Currency currency, int minorUnits, int atMillis) async {
    state = state.withCounted(currency, minorUnits, atMillis);
    await _store?.write(state);
  }
}
