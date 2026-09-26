import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'display_providers.dart';
import 'l10n/dual_copy.dart';
import 'l10n/locale_providers.dart';
import 'l10n/dual_copy_text.dart';
import 'l10n/voice.dart';
import 'theme.dart';

/// How the application looks: the text size, and nothing else yet.
///
/// **One control, and the reason there is only one is worth stating on the screen's behalf.** An
/// accent colour or a light palette would each be a change to `HollowPalette`, which is a table of
/// constants that every widget in the interface reads directly -- a setting that could not be
/// applied everywhere would make two screens disagree about the colour of the same thing. Text size
/// is applied in exactly one place, the `MediaQuery` the whole tree is built under, so it is the one
/// style setting that cannot be half-applied.
class DisplaySection extends ConsumerWidget {
  const DisplaySection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(displaySettingsProvider);
    final locale = ref.watch(localeSettingsProvider);
    final notifier = ref.read(displaySettingsProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DualCopyText(Copy.displayHeading, style: HollowType.heading),
        const SizedBox(height: 10),
        DualCopyText(Copy.displayTextSize, style: HollowType.caption),
        const SizedBox(height: 8),
        SegmentedButton<TextSize>(
          key: const ValueKey('text-size'),
          segments: [
            for (final size in TextSize.values)
              ButtonSegment<TextSize>(
                value: size,
                label: Text(_label(size).primary.text, style: HollowType.caption),
              ),
          ],
          selected: {settings.textSize},
          showSelectedIcon: false,
          onSelectionChanged: (chosen) => notifier.setTextSize(chosen.first),
        ),
        const SizedBox(height: 8),
        DualCopyText(Copy.displayTextSizeNote, style: HollowType.caption),
        const SizedBox(height: 20),
        DualCopyText(Copy.displayTheme, style: HollowType.caption),
        const SizedBox(height: 8),
        // **Named by what they look like rather than by their ids.** A reader is choosing a mood, so the chips
        // say 琥珀庭 / 白庭 / 冬庭 -- and each chip carries a swatch of the world it offers, which is the only
        // honest way to label
        // a colour scheme. This is the one place in the interface where a palette other than the
        // current one is drawn.
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final value in HollowPalette.all)
              ChoiceChip(
                key: ValueKey('theme-${value.name}'),
                label: Text(
                  _themeLabel(value).textFor(locale.primaryTag),
                  style: HollowType.caption,
                ),
                selected: settings.theme.name == value.name,
                onSelected: (_) => notifier.setTheme(value),
                avatar: _Swatch(value: value),
                backgroundColor: HollowPalette.surfaceRaised,
                side: BorderSide(color: HollowPalette.line),
              ),
          ],
        ),
        const SizedBox(height: 20),
        DualCopyText(Copy.displayVoice, style: HollowType.caption),
        const SizedBox(height: 8),
        // **The voices, laid out exactly like the worlds above them**, because they are the same kind of choice:
        // a register rather than a language, defaulting to the one the application has always spoken. A voice
        // with nothing written for a line simply leaves that line alone, which is why the plain option is a real
        // option and not a reset.
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final voice in Voice.values)
              ChoiceChip(
                key: ValueKey('voice-${voice.name}'),
                label: Text(
                  voice.isPlain ? Copy.voicePlain.textFor(locale.primaryTag) : voice.label,
                  style: HollowType.caption,
                ),
                selected: settings.voice == voice,
                onSelected: (_) => notifier.setVoice(voice),
                backgroundColor: HollowPalette.surfaceRaised,
                side: BorderSide(color: HollowPalette.line),
              ),
          ],
        ),
      ],
    );
  }

  /// **Three worlds, and the switch used to name the four that were deleted this morning** -- so every chip read
  /// 琥珀庭, including the two it was not describing. Found while adding the voice row above it, which is the
  /// pattern this whole day has followed: the thing next to the thing you are changing is where the staleness is.
  static CopyLine _themeLabel(HollowPaletteValue value) => switch (value.name) {
    'whiteCourt' => Copy.themeWhiteCourt,
    'winter' => Copy.themeWinter,
    _ => Copy.themeAmber,
  };

  static CopyLine _label(TextSize size) => switch (size) {
    TextSize.small => Copy.textSizeSmall,
    TextSize.standard => Copy.textSizeStandard,
    TextSize.large => Copy.textSizeLarge,
    TextSize.extraLarge => Copy.textSizeExtraLarge,
  };
}

/// Two colours of a theme, as a small square.
///
/// A chip labelled only with a word asks a reader to try four themes to find out what they are; a chip
/// carrying its own ground and accent answers the question before the tap.
class _Swatch extends StatelessWidget {
  const _Swatch({required this.value});

  final HollowPaletteValue value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        color: value.ground,
        border: Border.all(color: value.rose, width: 3),
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }
}
