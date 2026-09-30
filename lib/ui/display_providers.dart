// **One deprecation is suppressed for this file, and only one.** `TextScaler` declares
// `textScaleFactor` and deprecates it in the same breath, so `ScaledTextScaler` has to implement it and
// the analyzer reports it on every build. There is no third option -- leaving it out does not compile --
// and the deprecation is aimed at CALLERS who read a linear assumption out of a scaler that may be
// curved, which is not what this file does: `scale()` is the method that matters and it consults the
// platform's scaler through `scale()` too.
// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'theme.dart';

/// How large the interface's text is drawn.
///
/// **Four steps and not a continuous slider.** Every string in this application is drawn in one of
/// a handful of styles -- a display heading, a heading, body, a caption, a numeric line -- and a
/// slider would produce hundreds of sizes no screen was laid out for. Four steps are the sizes that
/// were looked at.
///
/// **This is not the same control as the platform's own text scale.** A reader who has already
/// turned their system font up has that applied on top: this multiplies what the platform hands
/// over, and `standard` is exactly what the platform asked for rather than an override of it. So
/// the setting can only ever make the text larger or smaller than the reader's own baseline, which
/// is what a reader of this app would expect from a setting *inside* it.
enum TextSize {
  small(0.9),
  standard(1.0),
  large(1.15),
  extraLarge(1.3);

  const TextSize(this.scale);

  /// The multiplier applied to the platform's own text scale.
  final double scale;

  /// The stored name, which is the enum's own: a wire format by identity, as `Unit.id` is.
  static TextSize byName(String? name) => TextSize.values.firstWhere(
    (size) => size.name == name,
    orElse: () => TextSize.standard,
  );
}

/// The application's own text size, **multiplied onto whatever the platform already applies**.
///
/// This is the thing the setting above was always meant to be, and until 2026-09-30 it did not exist:
/// the four steps were stored, drawn, and read by nothing, so choosing one changed the file and not the
/// screen. The `MediaQuery` the whole tree is built under is the one place a text scale can be applied
/// without half of the interface disagreeing with the other half, which is what the comment above says
/// and what this now does.
///
/// **A subclass rather than `TextScaler.linear(platform * mine)`.** Reading the platform's factor back
/// out is only correct while the platform is linear, and a platform is free not to be: the API exists to
/// express a curve. Multiplying through `scale()` is right for any scaler, including a curved one, and
/// costs one multiplication per string.
///
/// **The reader's own system setting is not overridden, and cannot be.** A reader who has already turned
/// the system font up gets that baseline, and this steps up or down from it -- so `standard` is exactly
/// what the platform asked for rather than a reset of it, which is what someone opening a size control
/// inside an application expects.
final class ScaledTextScaler extends TextScaler {
  const ScaledTextScaler(this.base, this.multiplier);

  /// What the platform handed over, untouched.
  final TextScaler base;

  /// The application's own step, from [TextSize.scale].
  final double multiplier;

  @override
  double scale(double fontSize) => base.scale(fontSize) * multiplier;

  @override
  double get textScaleFactor => base.textScaleFactor * multiplier;

  // Equality by value, for the reason `DisplaySettings` compares by value: a rebuild that changes
  // nothing must not look like a change, or every frame would invalidate the whole tree.
  @override
  bool operator ==(Object other) =>
      other is ScaledTextScaler && other.base == base && other.multiplier == multiplier;

  @override
  int get hashCode => Object.hash(base, multiplier);

  @override
  String toString() => 'ScaledTextScaler($base x$multiplier)';
}

/// What the reader has changed about how this application looks.
///
/// One field, and it is not a placeholder for the others: an accent colour or a light palette would
/// each be a change to `HollowPalette`, which is a table of constants the whole interface reads
/// directly. A setting that cannot be applied everywhere is a setting that makes two screens
/// disagree, so the one control here is the one that is applied in exactly one place -- the
/// `MediaQuery` the whole tree is built under.
final class DisplaySettings {
  const DisplaySettings({
    this.textSize = TextSize.standard,
    this.theme = HollowPaletteValue.honeyed,
  });

  final TextSize textSize;

  /// Which of the palettes the whole interface is drawn in.
  ///
  /// **Stored by name, not by index.** An index would shift the day a theme is inserted in the middle
  /// of the list, and a reader's choice would silently become a different one -- the same reason
  /// units and currencies are stored by id.
  final HollowPaletteValue theme;

  /// **How the application speaks, as opposed to what language it speaks.** Stored by name like the theme, and

  DisplaySettings withTextSize(TextSize size) =>
      DisplaySettings(textSize: size, theme: theme);

  DisplaySettings withTheme(HollowPaletteValue value) =>
      DisplaySettings(textSize: textSize, theme: value);
  Map<String, Object?> toJson() => <String, Object?>{
    'textSize': textSize.name,
    'theme': theme.name  };

  /// Reads a stored file back, **falling back per field rather than failing whole.**
  ///
  /// A file written by a build that knew a size this one does not loses that setting and keeps the
  /// rest, which is the same rule `CellarPreferences.fromJson` follows and for the same reason: the
  /// alternative is a display setting that can stop the application from opening.
  factory DisplaySettings.fromJson(Object? json) {
    if (json is! Map<String, Object?>) return const DisplaySettings();
    return DisplaySettings(
      textSize: TextSize.byName(json['textSize'] as String?),
      // A name this build does not carry falls back to the theme the application was designed
      // around rather than to an error, which is the rule a missing unit follows too.
      theme: HollowPaletteValue.byName(json['theme'] as String?),
    );
  }
}

/// The file the display settings live in, handed in rather than found.
///
/// The same shape `LocaleSettingsStore` uses: the store never asks the platform where anything is,
/// so a test hands it a file in a temporary directory and exercises the real read and write paths.
final class DisplaySettingsStore {
  const DisplaySettingsStore(this.file);

  final File file;

  /// What is stored, or null when there is nothing usable to read.
  ///
  /// **A file that cannot be read is a first run, not an error.** Absent, empty, truncated by a kill
  /// during a write, or hand-edited into something else -- none of those is a condition worth
  /// refusing to start over, and the one thing this must not do is throw.
  Future<DisplaySettings?> read() async {
    try {
      if (!await file.exists()) return null;
      final text = await file.readAsString();
      if (text.trim().isEmpty) return null;
      return DisplaySettings.fromJson(jsonDecode(text));
    } catch (_) {
      // Deliberately silent: a display setting is the least important byte in the application and
      // the only one that could stop it from opening.
      return null;
    }
  }

  Future<void> write(DisplaySettings settings) async {
    try {
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode(settings.toJson()));
    } catch (_) {
      // Deliberately silent, for the reason above: the screen has already changed, and a write that
      // failed costs the reader their choice next launch rather than this one.
    }
  }
}

/// Where the display settings file goes, resolved once.
final displaySettingsFileProvider = FutureProvider<File>((Ref ref) async {
  final directory = await getApplicationSupportDirectory();
  return File('${directory.path}${Platform.pathSeparator}display.json');
});

/// The reader's display settings, defaulted and then read from the file.
final displaySettingsProvider =
    NotifierProvider<DisplaySettingsNotifier, DisplaySettings>(
  DisplaySettingsNotifier.new,
);

class DisplaySettingsNotifier extends Notifier<DisplaySettings> {
  DisplaySettingsStore? _store;

  @override
  DisplaySettings build() {
    unawaited(_restore());
    return const DisplaySettings();
  }

  Future<void> _restore() async {
    // **The whole read is guarded, not just the file's own.** `getApplicationSupportDirectory` goes
    // through a platform channel, and a channel that is not there -- a widget test, or a platform
    // whose plugin failed to register -- throws rather than returning null. A display setting is the
    // least important byte in the application; it must not be able to take the screen with it.
    try {
      final file = await ref.read(displaySettingsFileProvider.future);
      final store = DisplaySettingsStore(file);
      _store = store;
      final stored = await store.read();
      if (stored != null) {
        state = stored;
        // **Applied here as well as at the root**, because this is the only place that knows a theme
        // was ever stored: the root paints before the file has been read, so it starts on the default
        // and this corrects it the moment the setting arrives.
        HollowPalette.use(stored.theme);
      }
    } catch (_) {
      // Deliberately silent: the defaults are already the state.
    }
  }

  Future<void> setTextSize(TextSize size) async {
    state = state.withTextSize(size);
    await _store?.write(state);
  }

  /// Switches the appearance, and tells the palette in the same breath.
  ///
  /// **The two happen together because they are one change.** Writing the setting without applying it
  /// would leave the screen in the old theme until something else rebuilt the tree, and applying it
  /// without writing it would lose the choice on the next launch.
  Future<void> setTheme(HollowPaletteValue value) async {
    state = state.withTheme(value);
    HollowPalette.use(value);
    await _store?.write(state);
  }
}
