/// The choices section 12.4 puts in settings, and the one check that keeps them
/// from contradicting each other.
///
/// **This is the settings key the document named as missing.** `dual_copy_text.dart`
/// has said since it was written that the value it reads is fixed *"rather than left
/// implicit"*, and that *"when the key arrives, it overrides this provider and
/// nothing else in the tree changes"*. This is the key. The leaf that reads it did
/// not change.
///
/// **No imports, deliberately** -- the same discipline as `dual_copy.dart`, and for
/// the same reason: this is the file that has to be testable on the plain Dart VM,
/// and a settings model that reached for Flutter could not be.
library;

import 'locale_catalogue.dart';

/// What a reader has chosen about language, as opposed to what the system reports.
///
/// The three fields are exactly section 12.4's three rows, in its order: the primary
/// is *"the reader's locale, always. Not a choice made here"*; the secondary is
/// *"one reference language, defaulting to English, itself a setting"*; and the guard
/// is *"the reference language must not be the primary. One check, at one place"*.
final class LocaleSettings {
  const LocaleSettings({
    required this.primaryTag,
    required this.secondaryTag,
    required this.dualCopy,
  });

  /// The line the reader reads. Always a shipped locale, never a raw system tag.
  final String primaryTag;

  /// The line drawn under it, when [dualCopy] is on.
  final String secondaryTag;

  /// Whether the second language is drawn at all.
  ///
  /// **On, and deliberately not off.** The instruction was 中英文方面的相互影响可以采用双字幕
  /// 的类型，也就是中英文同时实现 -- both languages present at once -- so a build that
  /// shipped with them switched off would not have implemented it. Section 2.7's "a
  /// reader who wants one language should not be made to read two" is served by this
  /// switch, not by the default.
  final bool dualCopy;

  /// What a first run looks like on a machine reporting [systemTag].
  ///
  /// The system locale decides the primary and nothing else. `systemTag` may be null,
  /// may be a language this build does not carry, and may be a bare `zh`; all three
  /// are [resolveLocaleTag]'s job, and by the time a value reaches here it is a
  /// shipped tag.
  factory LocaleSettings.initial(String? systemTag) => LocaleSettings(
        primaryTag: resolveLocaleTag(systemTag),
        secondaryTag: referenceTag,
        dualCopy: true,
      ).guarded();

  /// [decision] The guard, applied -- section 12.4 says *one check, at one place*,
  /// and this is the place.
  ///
  /// Two settings can contradict each other: the reader can point the primary at the
  /// language the secondary is already using. Something has to give, and it must not
  /// be the primary, because the primary is the line a reader actually reads. So the
  /// **secondary** moves -- to [fallbackTag] if the primary has taken [referenceTag],
  /// and to [referenceTag] otherwise. That keeps the pair valid in both directions
  /// and needs no third state to describe "paired with itself".
  ///
  /// It is a method rather than a constructor so that every mutator can end in it and
  /// no caller has to remember. A `LocaleSettings` obtained from any of the `with…`
  /// methods below has already been through here.
  LocaleSettings guarded() {
    if (secondaryTag != primaryTag) return this;
    return LocaleSettings(
      primaryTag: primaryTag,
      secondaryTag: primaryTag == referenceTag ? fallbackTag : referenceTag,
      dualCopy: dualCopy,
    );
  }

  /// A tag this build does not ship is refused rather than stored.
  ///
  /// A picker can only offer [shippedLocales], so an unshipped tag arriving here is a
  /// caller's mistake and not a reader's -- and the one place it *is* legitimate, a
  /// raw system tag, has a function of its own: [resolveLocaleTag]. Refusing keeps
  /// [primaryTag] an invariant other code can rely on instead of a string to be
  /// re-validated at each screen.
  LocaleSettings withPrimary(String tag) => LocaleSettings(
        primaryTag: byTag(tag)?.tag ?? primaryTag,
        secondaryTag: secondaryTag,
        dualCopy: dualCopy,
      ).guarded();

  /// Same refusal as [withPrimary], for the same reason.
  LocaleSettings withSecondary(String tag) => LocaleSettings(
        primaryTag: primaryTag,
        secondaryTag: byTag(tag)?.tag ?? secondaryTag,
        dualCopy: dualCopy,
      ).guarded();

  LocaleSettings withDualCopy(bool value) => LocaleSettings(
        primaryTag: primaryTag,
        secondaryTag: secondaryTag,
        dualCopy: value,
      ).guarded();

  /// The second line to draw, or null when there is not one.
  ///
  /// A leaf asks this instead of reading [secondaryTag] and [dualCopy] separately,
  /// so that "the reader turned it off" and "there is no second language" produce the
  /// same single answer. [guarded] means the other case -- secondary equal to primary
  /// -- cannot reach here, and this getter does not defensively repeat its check.
  String? get secondaryOrNull => dualCopy ? secondaryTag : null;

  @override
  bool operator ==(Object other) =>
      other is LocaleSettings &&
      other.primaryTag == primaryTag &&
      other.secondaryTag == secondaryTag &&
      other.dualCopy == dualCopy;

  @override
  int get hashCode => Object.hash(primaryTag, secondaryTag, dualCopy);

  @override
  String toString() =>
      'LocaleSettings($primaryTag, $secondaryTag, dualCopy: $dualCopy)';
}
