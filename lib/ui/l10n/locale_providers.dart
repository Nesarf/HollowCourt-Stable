/// Where the language settings live, and the file they survive in.
///
/// **This is the layer `dual_copy_text.dart` said would arrive.** Its `dualCopyProvider`
/// has read a fixed `true` since it was written, with the reason stated: *"the
/// setting does not exist yet, and this is where it lands."* It now derives from
/// [localeSettingsProvider] instead, and the leaf that watches it is unchanged --
/// which is what that file promised would happen.
///
/// **Synchronous, on purpose.** The stored value has to be read from disk, but the
/// provider's surface is not asynchronous, because a `DualCopyText` is drawn inside
/// widgets that have one frame to draw in and section 2.7's "a reader who wants one
/// language should not be made to read two" is not worth a spinner. The first value
/// is therefore **the platform's own locale**, which is the honest answer to "what
/// does this reader want" before anything has been read, and the stored value
/// replaces it a microtask later if it differs. Screens render the state they are
/// actually in -- `main.dart` already says that about the drink library and the log,
/// and the same rule applies here rather than an exception being made for settings.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'locale_catalogue.dart';
import 'locale_settings.dart';

/// The settings file, as a plain [File] the store is handed.
///
/// **Injected rather than found**, the same shape `event_store.dart` uses: the store
/// never asks the platform where anything is, so a test can hand it a file in a
/// temporary directory and exercise the real read and write paths.
final class LocaleSettingsStore {
  const LocaleSettingsStore(this.file);

  final File file;

  /// The stored settings, or null when there is nothing usable to read.
  ///
  /// **A file that cannot be read is a first run, not an error.** It may be absent,
  /// empty, truncated by a kill during a write, or hand-edited into something that is
  /// not the shape expected. None of those is a condition a language setting is worth
  /// refusing to start over, so every one of them returns null and the caller keeps
  /// the platform-derived default. The one thing this must not do is throw: a settings
  /// file is the least important byte in the application and the only one that can
  /// stop it from opening.
  ///
  /// Keys are ASCII and English, per section 12.4's first rule -- a stored key is
  /// something a person never reads, even though the value beside it is a language a
  /// person chose.
  Future<LocaleSettings?> read() async {
    try {
      if (!await file.exists()) return null;
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return null;

      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;

      // A stored tag is re-resolved rather than trusted: an older build may have
      // written one this build no longer ships, and section 12.4's list is "settled"
      // for now rather than forever.
      return LocaleSettings(
        primaryTag: resolveLocaleTag(decoded['primary'] as String?),
        secondaryTag: byTag(decoded['secondary'] as String?)?.tag ?? referenceTag,
        dualCopy: decoded['dualCopy'] as bool? ?? true,
      ).guarded();
    } catch (_) {
      return null;
    }
  }

  /// Writes the settings out. A failure is swallowed for the reason in [read]:
  /// losing a preference is survivable and interrupting the reader is not.
  Future<void> write(LocaleSettings settings) async {
    try {
      await file.parent.create(recursive: true);
      await file.writeAsString(
        jsonEncode(<String, Object?>{
          'primary': settings.primaryTag,
          'secondary': settings.secondaryTag,
          'dualCopy': settings.dualCopy,
        }),
      );
    } catch (_) {
      // Deliberately silent: see read().
    }
  }
}

/// Where the settings file goes, resolved once.
final localeSettingsFileProvider = FutureProvider<File>((Ref ref) async {
  final directory = await getApplicationSupportDirectory();
  return File('${directory.path}${Platform.pathSeparator}locale.json');
});

/// The reader's language settings. Synchronous, seeded from the platform.
final localeSettingsProvider =
    NotifierProvider<LocaleSettingsNotifier, LocaleSettings>(
  LocaleSettingsNotifier.new,
);

class LocaleSettingsNotifier extends Notifier<LocaleSettings> {
  LocaleSettingsStore? _store;

  @override
  LocaleSettings build() {
    // The first value is the platform's, which is section 12.4's own default
    // ("locale choice belongs in settings, defaulting to the system locale"), and
    // is also the only value available without waiting for a file.
    final platform = PlatformDispatcher.instance.locale.toLanguageTag();
    final seeded = LocaleSettings.initial(platform);

    // Then the stored value, if there is one, replaces it. Scheduled rather than
    // awaited so that build() stays synchronous.
    unawaited(_restore());

    return seeded;
  }

  Future<void> _restore() async {
    final store = await _resolveStore();
    if (store == null) return;
    final stored = await store.read();
    if (stored == null) return;
    // A stored value equal to what is already shown is not a change, and assigning
    // it anyway would rebuild every listener for nothing.
    if (stored == state) return;
    state = stored;
  }

  Future<LocaleSettingsStore?> _resolveStore() async {
    if (_store != null) return _store;
    try {
      final file = await ref.read(localeSettingsFileProvider.future);
      return _store = LocaleSettingsStore(file);
    } catch (_) {
      // No writable directory: the settings still work, they just do not survive
      // the process. Same reasoning as read().
      return null;
    }
  }

  Future<void> _commit(LocaleSettings next) async {
    if (next == state) return;
    state = next;
    final store = await _resolveStore();
    await store?.write(next);
  }

  /// Point the primary line at a shipped language. The guard is applied inside
  /// [LocaleSettings.withPrimary], so the secondary moves if it has to.
  Future<void> setPrimary(String tag) => _commit(state.withPrimary(tag));

  /// Point the reference line at a shipped language, subject to the same guard.
  Future<void> setSecondary(String tag) => _commit(state.withSecondary(tag));

  /// Draw the second language, or stop drawing it.
  Future<void> setDualCopy(bool value) => _commit(state.withDualCopy(value));
}
