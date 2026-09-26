import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme.dart';
import 'dual_copy.dart';
import 'locale_providers.dart';
import '../display_providers.dart';

/// Whether the reader wants the second language under the first.
///
/// **The setting arrived, and this is where it landed.** This provider used to return
/// a fixed `true` with the reason written down beside it -- *"when the key arrives, it
/// overrides this provider and nothing else in the tree changes"*. `locale_providers.dart`
/// is that key, and nothing else in the tree changed: [DualCopyText] still watches this
/// and still has no idea where the value came from.
///
/// **It stays a `bool` and not a `LocaleSettings` on purpose.** A leaf needs one bit,
/// and handing it the whole settings object would rebuild every widget that draws a
/// line whenever an unrelated language choice changed.
///
/// **On, and deliberately not off.** The instruction was 中英文方面的相互影响可以采用双字幕
/// 的类型，也就是中英文同时实现 -- both languages present at once -- so a build that
/// shipped with them switched off would not have implemented it. Section 2.7's "a
/// reader who wants one language should not be made to read two" is served by the
/// *setting*, not by the default -- and the default now lives in
/// `LocaleSettings.initial`, beside the guard that has to agree with it.
final dualCopyProvider = Provider<bool>(
  (ref) => ref.watch(localeSettingsProvider).dualCopy,
);

/// Draws a [CopyLine]: the reader's language, and the reference language under it.
///
/// **This widget is why section 4.2(a) can claim no boolean is threaded through the
/// widget tree.** The decision about whether a string may be paired lives in the
/// type; the *setting* is read here, at the leaf, from [dualCopyProvider]. So a call
/// site passes a `CopyLine` and nothing else, and no screen above it has to know
/// that a second language exists.
///
/// **The secondary is smaller and dimmer, which is why this is a widget and not
/// `line.joined(' · ')`.** Section 2.7 asks for a second level of type rather than a
/// suffix, and section 12.4 notes that CJK and Latin do not share metrics -- so the
/// pair is two `Text`s in a column, and a paired line is genuinely taller than an
/// unpaired one rather than a longer string.
///
/// **[maxLines] and [textAlign] go to both lines**, because a caller that has room
/// for one line has room for one line: a two-line string in a one-line slot would
/// overflow rather than degrade. A caller in that position should pass
/// `roomForSecondary: false` to `CopyLine.present` and draw the primary itself.
class DualCopyText extends ConsumerWidget {
  const DualCopyText(
    this.line, {
    super.key,
    this.style,
    this.textAlign,
    this.maxLines,
  });

  /// The line, in both languages, with the origin of each.
  final CopyLine line;

  /// The primary's style. The secondary is derived from it.
  final TextStyle? style;

  final TextAlign? textAlign;
  final int? maxLines;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // **Two watches, and each is the narrowest provider for what it supplies.** The languages come from
    // the settings; the dual-copy *mode* comes from `dualCopyProvider`, which derives from those same
    // settings but is the seam a screen (and a test) overrides on its own. Collapsing them into one read
    // was the first version of this change, and it quietly broke every caller that overrode the mode
    // alone -- which is exactly what a seam is for, and why removing one is not a simplification.
    final settings = ref.watch(localeSettingsProvider);
    // **A narrow watch: this rebuilds when the voice changes and not when anything else about the display
    // does.** Every text widget in the application goes through here, so a broad watch would repaint the whole
    // interface for a font-size change that only touches half of it.
    final voice = ref.watch(displaySettingsProvider.select((settings) => settings.voice));
    final shown = line.present(
      locale: settings.primaryTag,
      secondLocale: settings.secondaryTag,
      dualCopy: ref.watch(dualCopyProvider),
      voice: voice,
    );
    final primary = Text(
      shown.primary,
      style: style,
      textAlign: textAlign,
      maxLines: maxLines,
    );
    if (!shown.isPaired) return primary;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: switch (textAlign) {
        TextAlign.center => CrossAxisAlignment.center,
        TextAlign.end || TextAlign.right => CrossAxisAlignment.end,
        _ => CrossAxisAlignment.start,
      },
      children: [
        primary,
        Text(
          _secondaryText(shown.secondary!),
          style: secondary(style),
          textAlign: textAlign,
          maxLines: maxLines,
        ),
      ],
    );
  }

  /// The second line's text, marked if it is a machine's and nobody has read it.
  ///
  /// A tribute to the ambient style of writing in this app: the secondary that
  /// ships is hand-written, so the branch never fires today, and it exists because
  /// the day it fires is the day a screen would otherwise present a machine's guess
  /// as this project's own words.
  String _secondaryText(String text) {
    if (!line.secondaryNeedsReviewMark) return text;
    return line.secondary!.asReviewMarked(Copy.machineMark).text;
  }

  /// The subtitle's type: the primary's, one step down and one step back.
  ///
  /// **Derived rather than passed, so that a pair cannot be drawn at the primary's
  /// size by accident.** A second language at the same weight and colour does not
  /// read as a subtitle, it reads as a repetition -- which is exactly the mistake
  /// section 2.7 describes when it says two languages in one place is not one
  /// string with a newline in it.
  ///
  /// The dimming is an alpha on the primary's own colour rather than a fixed
  /// palette entry, because call sites use the palette to carry meaning: a rose
  /// error line and a gold verdict keep their colour in the second language, and
  /// only lose emphasis.
  @visibleForTesting
  static TextStyle? secondary(TextStyle? base) {
    final colour = base?.color ?? HollowPalette.inkSoft;
    return (base ?? const TextStyle()).copyWith(
      fontSize: (base?.fontSize ?? 14) * 0.86,
      color: colour.withValues(alpha: colour.a * 0.66),
    );
  }
}
