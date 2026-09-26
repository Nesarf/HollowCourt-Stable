/// Two languages in one place, and who is answerable for each.
///
/// The instruction this implements: 中英文方面的相互影响可以采用双字幕的类型，也就是中英文
/// 同时实现，且根据需要进行机翻（用户可编辑）. Chinese and English are present together,
/// the way a subtitle track carries two languages at once.
///
/// **Section 12.4 says a person-read string is a localization *configuration*** --
/// one locale at a time, chosen in settings. This file does not replace that. A
/// locale is still chosen from section 12.4's list of fourteen; dual copy is a
/// **display mode inside a locale**, and the reader's locale is always the primary
/// line. The secondary defaults to English and is itself a setting.
///
/// The pattern is not new here. `MaterialApp.title` has been `空庭 · Hollow Court`
/// since section 0.1, and it is `空庭 · Hollow Court` because Android's task switcher
/// shows one string with room for both. This generalises the one instance that
/// already existed.
///
/// **Nothing in this file touches the domain layer.** Section 3 keeps display text
/// out of it, and `Translated` exists precisely so that the distinction between a
/// written string and a generated one can be carried *without* a domain type
/// learning what a word is.
library;

import 'voice.dart';

/// Where a translated string came from.
///
/// **The same idiom as `UnitFactor.isEstimate`, applied to a sentence.** Section 5.3
/// says a dash has no international standard and a millilitre does, so the guess is
/// carried *in the type* rather than left to a comment: "a caller that shows a number
/// to a user has to decide what to do about `isEstimate`; a caller that does not look
/// cannot accidentally present a guess as arithmetic."
///
/// A screen that shows a machine translation beside a written one without saying
/// which is which is doing exactly that, with words instead of numbers.
enum TextOrigin {
  /// A person wrote this.
  authored,

  /// A machine produced this and nobody has touched it.
  ///
  /// Section 12.4's locale list contains 文言文 (`lzh`), which cannot be generated and
  /// should not be attempted. So a machine string is only ever offered where the pair
  /// is one this project is willing to generate, and that stays a decision at the
  /// call site rather than a hope.
  machine,

  /// A machine produced it and a person then changed it.
  ///
  /// Kept apart from [authored] because "a translator wrote this" and "the user
  /// corrected a machine" are different claims, and only one of them is something
  /// this project may redistribute.
  edited,
}

/// A string with the one fact that decides how it may be shown.
final class Translated {
  const Translated(this.text, this.origin);

  /// A string a person wrote.
  const Translated.authored(String text) : this(text, TextOrigin.authored);

  /// A string a machine produced.
  const Translated.machine(String text) : this(text, TextOrigin.machine);

  final String text;
  final TextOrigin origin;

  /// True when nobody has reviewed this string, so a screen must mark it.
  ///
  /// **A tribute to a failing test.** This file first offered `isGuest` and
  /// `isVouched` as a pair, and the two read as complements while not being one:
  /// an [TextOrigin.edited] string is both (a machine wrote it, and a person then
  /// read it), so the pair was ambiguous at exactly the origin that matters most.
  /// The two questions were always distinct and are now named as such:
  ///
  /// * may this be shown without saying it is a machine's -- [needsReviewMark]
  /// * may this project redistribute it -- [isOurOwnCopy]
  bool get needsReviewMark => origin == TextOrigin.machine;

  /// True when this project wrote it and may redistribute it.
  ///
  /// **Only [TextOrigin.authored].** Section 12.4 rejected 自定义中文 as a fifteenth
  /// locale because it would "put a user's own words into the shipped seed data
  /// instead of on top of it", and an [TextOrigin.edited] string is exactly that:
  /// the user's words, on top. A person wrote it and it is still not this project's
  /// copy, so the two predicates are not opposites and that is the point.
  bool get isOurOwnCopy => origin == TextOrigin.authored;

  /// The same string, now known to have been written by a person.
  ///
  /// Mirrors `UnitFactor.calibratedTo(measured)`: whatever the user typed is by
  /// definition no longer a guess. **The result is [TextOrigin.edited] and not
  /// [TextOrigin.authored]**, because the claim is "a person corrected a machine"
  /// and not "a translator wrote this" -- and collapsing the two would quietly turn
  /// a user's correction into this project's own copy.
  ///
  /// Section 12.4 already decided where the correction lives: the overlay, never the
  /// seed. It rejected 自定义中文 as a fifteenth locale, on the ground that it "would
  /// put a user's own words into the shipped seed data instead of on top of it", and
  /// an edited machine translation is that same thing. This method produces the value;
  /// section 8's overlay is what stores it.
  Translated editedTo(String typed) => Translated(typed, TextOrigin.edited);

  /// The string with a marker appended, for a screen that must show an unreviewed line.
  ///
  /// Deliberately not automatic -- a caller has to ask for it, so that no screen marks
  /// or fails to mark a string by accident. Reaches only [needsReviewMark] strings,
  /// which is [TextOrigin.machine] alone: a string the user corrected has been read by
  /// the one person who needs to know, and marking it would be telling them their own
  /// words are suspect.
  Translated asReviewMarked(String marker) =>
      needsReviewMark ? Translated('$text $marker', origin) : this;

  @override
  String toString() => origin == TextOrigin.authored ? text : '$text (${origin.name})';

  @override
  bool operator ==(Object other) =>
      other is Translated && other.text == text && other.origin == origin;

  @override
  int get hashCode => Object.hash(text, origin);
}

/// Why a secondary line is not being drawn.
///
/// **Named, because silent degradation is the thing this project keeps deciding
/// against.** `interaction-and-numbers.md` §14 records the conclusion from two shipping
/// games: the lowest quality tier should be "named, reachable, documented and tested
/// -- not an accident that happens when the GPU is weak". A second language on a
/// narrow screen is the same problem in typography, and a layout that drops it without
/// saying so is the accident.
enum SecondaryOmitted {
  /// The reader has the mode off, or has chosen no secondary language.
  bySetting,

  /// There is no secondary text -- nobody has written or generated one.
  ///
  /// Distinct from [bySetting] because the two have different fixes: one is a
  /// preference, the other is a gap that a translator or a machine could fill.
  notWritten,

  /// There is one and the layout has no room for it.
  noRoom,
}

/// One line of display copy, in the reader's language and optionally in a second.
///
/// **The type is the decision about whether a string is ever paired.** There is no
/// flag and no registry: a string that should never carry a second language stays a
/// plain `String`, and one that may is a [CopyLine]. A dual `Cancel`/`取消` on a button
/// is noise; a dual line of the character's speech is the product, because section
/// 14.1 keeps the character in the stable release *as copy*. Choosing the type at the
/// call site is how that distinction is expressed, and it costs nothing at the call
/// site that does not need it.
final class CopyLine {
  const CopyLine(this.primary, [this.secondary])
    : byLocale = const {},
      also = const {},
      voices = const {};

  /// **The same line, with more languages added and nothing rewritten.**
  ///
  /// The first version of this change was a script that rewrote all 158 definitions into the map form.
  /// That was abandoned before it wrote anything, for a reason worth recording: `lib/ui/theme.dart`
  /// contains **thirteen adjacent-literal concatenations** (`'a' 'b'`, which Dart joins at compile time),
  /// two escaped quotes and two double-quoted strings, so a parser simple enough to trust would have
  /// silently split those lines and dropped half a sentence. A translation is additive work; making it
  /// require a source rewrite is how a translation project acquires a bug it cannot find later.
  ///
  /// So a line gains languages by naming them: the authored pair stays exactly as it is, and [also]
  /// carries the rest.
  /// **Optional positional and named parameters cannot be mixed in Dart**, which is why this is a
  /// separate constructor with a required named [also] rather than a third positional argument: a line
  /// with only one authored language has no second argument to pass, and `null` in that slot would read as
  /// "there is a second language and it is empty" -- a different statement, and a false one.
  const CopyLine.withLanguages(this.primary, this.secondary, {required this.also, this.voices = const {}})
    : byLocale = const {};

  /// Languages beyond the authored pair, keyed by tag.
  ///
  /// Consulted after [byLocale] and before the fallback chain, which makes it the place a translation
  /// goes without disturbing anything already written.
  final Map<String, String> also;

  /// **What this line says in each voice that was written for it.** Empty for almost every line, and that is the
  /// design rather than a gap: a voice is authorship, not translation, and it belongs on the sentences a person
  /// actually reads -- an empty state, an explanation, an apology -- not on a unit label or a button.
  final Map<Voice, String> voices;

  /// **A line written for named locales, which is what a translated line is.**
  ///
  /// The two-argument constructor above is the shape this application grew up with: one authored line
  /// and an optional second one, which produced the bilingual pairs the reader sees. That shape has no
  /// room for a third language and no way to *choose* one -- `present` never looked at the reader's
  /// locale, so picking 日语 in settings changed nothing, which is the gap the owner found on 2026-09-22:
  ///
  /// > 首先要把完整的翻译搞定，然后把语言选项中除了中英日的语言全部剔除（中文保留各种类型），
  /// > 并设定为选定语言选项后立刻更改显示语言（主语言和界面语言统一设定）
  ///
  /// This constructor is the one that answers that. [byLocale] is keyed on a BCP-47 tag and resolved
  /// through [textFor]'s fallback chain; a tag that is absent falls back rather than showing nothing.
  const CopyLine.localised(this.byLocale, {this.voices = const {}})
    : primary = const Translated.authored(''),
      secondary = null,
      also = const {};

  /// The line in each locale it has been written for, keyed by tag.
  ///
  /// **Empty for a line authored the old way**, which is not a state to be ashamed of: it is a line
  /// that has not been translated yet, and [translationStatus] counts them so that "how much is left"
  /// is a number rather than an impression.
  final Map<String, String> byLocale;

  /// The line's text in [tag], following the fallback chain documented on [localeFallbacks].
  ///
  /// **The chain is explicit and ordered, and the order is a decision.** A reader who chose 日本語 and
  /// reached a string nobody has translated yet should see the *reference* language (English) rather
  /// than the Chinese the line happened to be authored in -- the reference is the language the project
  /// promises to keep complete (section 12.4), and Chinese being first-authored here is history rather
  /// than a hierarchy.
  String textFor(String tag, {Voice voice = Voice.plain}) {
    // **A voice speaks one language.** Asked in another, it says nothing and the plain line answers -- which is
    // what keeps a Chinese heiress out of an English interface and an English civil servant out of a Chinese one.
    final spoken = voices[voice];
    if (spoken != null && spoken.isNotEmpty && voice.language.isNotEmpty) {
      // **The voice's language has to be the reader's first choice, not merely somewhere in the chain.** The
      // first version asked whether the chain *contained* it -- and the chain's last resort is the authored
      // language, Chinese, so an English reader got the heiress. A voice is written for the people who read that
      // language; everyone else reads the plain line, which is a truthful "we have not written this for you"
      // rather than a stranger's register.
      final chain = localeFallbacks(tag);
      if (chain.isNotEmpty && chain.first == voice.language) return spoken;
    }
    for (final candidate in localeFallbacks(tag)) {
      final added = also[candidate];
      if (added != null && added.isNotEmpty) return added;
      final written = byLocale[candidate];
      if (written != null && written.isNotEmpty) return written;

      // **The authored pair *is* two languages, and this is the line that knows it.** A line written the
      // old way has no locale table: its Chinese is `primary` and its English is `secondary`. Without these
      // two cases the chain fell through to `primary.text` for every tag -- so asking an authored line for
      // English answered in Chinese, and a bilingual pair drew the same sentence twice in one language.
      // Found by a test that expected `Cellar` and got nothing, which is the shape of every honest bug: the
      // code was confident and the observation disagreed.
      if (candidate == 'zh-Hans' && primary.text.isNotEmpty) return primary.text;
      if (candidate == 'en' && (secondary?.text.isNotEmpty ?? false)) return secondary!.text;
    }
    // Nothing matched at all: a line with no text in any language it claims. Give back whatever exists.
    return primary.text.isNotEmpty ? primary.text : (secondary?.text ?? '');
  }

  /// True when this line has been written for [tag] itself rather than reached through the chain.
  bool isWrittenFor(String tag) =>
      (byLocale[tag] ?? also[tag] ?? '').isNotEmpty;

  /// The reader's language. Always present, by construction.
  final Translated primary;

  /// The other language, or null when there is not one.
  ///
  /// **Null is a real state and not a failure.** It is a line with one language in it,
  /// which is what most lines are, and section 12.4's rule about absent-not-defaulted
  /// applies here as it does in the domain layer: assuming a translation is a claim
  /// nobody made.
  final Translated? secondary;

  bool get hasSecondary => secondary != null;

  /// True when the second line is a machine's and has not been reviewed.
  bool get secondaryNeedsReviewMark => secondary?.needsReviewMark ?? false;

  /// What to draw, and what is not being drawn.
  ///
  /// [dualCopy] is the reader's setting. [roomForSecondary] is the layout's answer,
  /// and it is separate on purpose: the reader's preference and the screen's space are
  /// different facts, and a caller that conflates them cannot report which one acted.
  CopyPresentation present({
    required bool dualCopy,
    bool roomForSecondary = true,
    String? locale,
    String? secondLocale,
    Voice voice = Voice.plain,
  }) {
    // **The reader's locale decides the first line, and it is the whole point of the change.** Until
    // 2026-09-22 this method drew `primary.text` regardless of what settings said, so the language picker
    // was cosmetic. A localised line resolves through the fallback chain; a line authored the old way has
    // no chain to walk and returns what it always did.
    final first = locale == null ? primary.text : textFor(locale, voice: voice);

    // **The second line is resolved by language too, and the reason is a hole the change exposed.** The
    // second line used to be the authored `secondary` -- always English. Once the first line began
    // following the reader's locale, a reader whose language *is* English got English twice: the same
    // sentence, printed small underneath itself. So the second line is looked up in the settings' secondary
    // language, and the authored English remains the fallback for a line nobody has translated.
    final second = secondLocale == null || secondLocale == locale
        ? secondary?.text
        : textFor(secondLocale, voice: voice);

    if (!dualCopy) {
      return CopyPresentation._(first, null, SecondaryOmitted.bySetting);
    }
    if (second == null || second.isEmpty || second == first) {
      // **Nothing to draw when the two lines would be the same sentence.** That is not "not written": it is
      // a pair that resolved to one language, and saying so is more honest than printing a duplicate.
      return CopyPresentation._(first, null, SecondaryOmitted.notWritten);
    }
    if (!roomForSecondary) {
      return CopyPresentation._(first, null, SecondaryOmitted.noRoom);
    }
    return CopyPresentation._(first, second, null);
  }

  @override
  String toString() => secondary == null ? primary.toString() : '$primary / $secondary';
}

/// What a screen draws, and the reason for anything it does not.
final class CopyPresentation {
  const CopyPresentation._(this.primary, this.secondary, this.omitted);

  final String primary;

  /// The second line, or null.
  final String? secondary;

  /// Why there is no second line. Null when there is one.
  final SecondaryOmitted? omitted;

  bool get isPaired => secondary != null;

  /// Both languages on one line, for the places that have room for one string only.
  ///
  /// **The case that started all of this.** Android's task switcher shows an
  /// application as a single string, and `空庭 · Hollow Court` is what section 0.1
  /// decided goes there. A narrow window title is the same shape of problem.
  ///
  /// Falls back to the primary rather than to a bare separator, so a line with no
  /// second language cannot render as a trailing dot.
  String joined(String separator) =>
      secondary == null ? primary : '$primary$separator$secondary';
}

/// A name, and how it is said in another language.
///
/// **Not a [CopyLine], and the difference is not pedantic.** `纯白交响曲` is not a
/// translation of `ましろ色シンフォニー` -- it is a rendering of it, and the note records
/// the original in its own body (`日文：ましろ色シンフォニー`). Translating a proper noun
/// produces a different drink, so a name is kept, transliterated or rendered, and
/// whatever it was rendered *from* is preserved beside it.
///
/// This is also why a translation of a name is a [Translated] gloss rather than a
/// second [name]: a gloss may be a guess, and the name may not.
final class NamePair {
  const NamePair(this.name, {this.original, this.gloss});

  /// The name as it is shown.
  final String name;

  /// The name in its own language, when the source wrote one.
  final String? original;

  /// What the name means, when somebody has said. Allowed to be a machine's work.
  final Translated? gloss;

  bool get hasOriginal => original != null && original!.isNotEmpty;

  @override
  String toString() => hasOriginal ? '$name ($original)' : name;
}

/// **The fallback chain, in order, for a locale tag.**
///
/// Written out as a function rather than left implicit because *which* language a reader sees when a
/// string is missing is a decision, and a decision that lives in a comment is a decision nobody can test:
///
/// 1. **The tag itself.** `zh-HK` gets `zh-HK`.
/// 2. **The language's base variant, then the base language.** `zh-TW` → `zh-Hans`; `zh-HK` → `zh-Hans`.
///    The Chinese variants share one written base on purpose (see [shippedLocales]): 港繁 and 台繁 differ
///    in vocabulary, not only in glyphs, so the ones that differ are worth writing and the ones that do
///    not are not worth duplicating 158 times.
/// 3. **The reference language, `en`.** Section 12.4 names English the language this project keeps
///    complete, so it is the honest answer for a string nobody has translated.
/// 4. **`zh-Hans`, the language the strings were first written in.** Last rather than first: it is
///    history, not a hierarchy.
/// 5. **Whatever is left.** A line with an empty table returns its own two authored fields, and a caller
///    that gets an empty string has a line with nothing in it at all -- which [translationStatus] reports.
List<String> localeFallbacks(String tag) {
  final chain = <String>[tag];
  final dash = tag.indexOf('-');
  if (dash > 0) {
    final language = tag.substring(0, dash).toLowerCase();
    // The written base for a language whose variants share one: Chinese, in this build.
    if (language == 'zh') chain.add('zh-Hans');
    chain.add(language == 'zh' ? 'zh-Hans' : language);
  }
  for (final common in const ['en', 'zh-Hans']) {
    if (!chain.contains(common)) chain.add(common);
  }
  return chain;
}
