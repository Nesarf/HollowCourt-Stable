import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'display_providers.dart';
import 'l10n/dual_copy.dart';
import 'l10n/locale_providers.dart';
import 'l10n/dual_copy_text.dart';
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
        // say 銅鳴 / 宇宙拿铁 / 群青 -- and each chip carries a swatch of the world it offers, which is the only
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
                  Copy.themeLabelFor(value).textFor(locale.primaryTag),
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
      ],
    );
  }

  /// **Five worlds, and the switch is written so a sixth cannot lie about itself.**
  ///
  /// **The fallback is the id, and it has a history.** The first version returned one fixed name for anything it did
  /// not recognise, so a new world called itself an old one's name -- a chip that lied rather than a chip that was
  /// missing. The second returned the id, which is honest and useless. **The third is what is here**, and it is the
  /// one that matters because of a defect found on 2026-10-11:
  ///
  /// `docs/memo-themes.md` settled on **2026-10-01** that 白庭 was deleted and `CL` took its place. The palette value
  /// was renamed to `cosmicLatte`; **`Copy.themeWhiteCourt` was not touched**, and this switch kept matching
  /// `'whiteCourt'`. So for ten days the light world fell through to the id fallback and its chip in 设置 read
  /// **`cosmicLatte`** -- a camelCase key, in no language, with no case to it. **A copy line outlived the theme it
  /// named**, which is the failure mode a switch keyed on strings cannot see.
  ///
  /// `theme_label_test.dart` is the guard, and it is deliberately not a list of names: **it walks `HollowPalette.all`
  /// and refuses the fallback for every one of them**, so a world added tomorrow fails the test rather than shipping
  /// an id.
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
