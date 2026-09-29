import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'l10n/voice.dart';
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
    this.voice = Voice.plain,
  });

  final TextSize textSize;

  /// Which of the palettes the whole interface is drawn in.
  ///
  /// **Stored by name, not by index.** An index would shift the day a theme is inserted in the middle
  /// of the list, and a reader's choice would silently become a different one -- the same reason
  /// units and currencies are stored by id.
  final HollowPaletteValue theme;

  /// **How the application speaks, as opposed to what language it speaks.** Stored by name like the theme, and
  /// [Voice.plain] is the default: a reader who has not chosen a voice reads exactly what they read before the
  /// axis existed. See `dual_copy.dart` for what a voice is and for the rule about which language it answers in.
  final Voice voice;

  DisplaySettings withTextSize(TextSize size) =>
      DisplaySettings(textSize: size, theme: theme, voice: voice);

  DisplaySettings withTheme(HollowPaletteValue value) =>
      DisplaySettings(textSize: textSize, theme: value, voice: voice);

  DisplaySettings withVoice(Voice value) =>
      DisplaySettings(textSize: textSize, theme: theme, voice: value);

  Map<String, Object?> toJson() => <String, Object?>{
    'textSize': textSize.name,
    'theme': theme.name,
    'voice': voice.name,
  };

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
      // A voice this build does not carry is a setting from another build, not an error: it reads plain.
      voice: Voice.byName(json['voice'] as String?),
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
  /// Switching how the application speaks.
  ///
  /// **Its own method rather than a parameter on [setTheme].** They are independent choices -- a reader may want
  /// the winter world *and* a permanent secretary -- and a combined setter would make one of them implicit in the
  /// other's call.
  Future<void> setVoice(Voice value) async {
    state = state.withVoice(value);
    await _store?.write(state);
  }

  Future<void> setTheme(HollowPaletteValue value) async {
    state = state.withTheme(value);
    HollowPalette.use(value);
    await _store?.write(state);
  }
}
