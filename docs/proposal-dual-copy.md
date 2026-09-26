# Proposal: dual copy -- Chinese and English at once, with machine translation the user can edit

**Approved and built, in two stages.** The types and the one pair that already existed
came first; §4.4 records the second stage, in which the whole copy inventory followed.
Everything below is kept as it was written, with the stale sentences marked rather than
rewritten, because the two stages disagree about one thing and the disagreement is the
interesting part.

The instruction was: 中英文方面的相互影响可以采用双字幕的类型，也就是中英文同时实现，且根据需要进行机翻（用户可编辑）。

That is a change to what section 12.4 assumes. It currently says a person-read string
"is a **localization configuration**, not a single translation" -- one locale active
at a time, chosen in settings. Dual copy says **both are present together**, the way a
subtitle track carries two languages at once.

**And the pattern is already in this document.** `MaterialApp.title` is
`空庭 · Hollow Court` (section 0.1), chosen because Android's task switcher shows one
string. That is a dual-copy instance, decided before there was a name for it.

This proposal generalises it, and reuses machinery the document already has rather
than adding a second one.

---

## 1. What already exists, and gets reused

| | |
| --- | --- |
| **Section 8's overlay layer** | "the same machinery that lets someone call a gin 'my gin' lets them replace any label" |
| **`自定义中文` rejected as a fifteenth locale** | because it "would put a user's own words into the shipped seed data instead of on top of it" |
| **`UnitFactor.isEstimate` / `calibratedTo`** | a guess carried **in the type**, replaceable by a measurement, so no caller can present a guess as arithmetic |
| **Section 12.4's two rules** | identifiers ASCII and English; display copy real UTF-8 |
| **Section 0.1's pair** | 空庭 · Hollow Court, one string with both |

**Every one of the four pieces this needs is already designed.** What is new is the
combination, and one type.

---

## 2. The design

### 2.1 A pair is not a locale

Section 12.4's locale list stays exactly as it is -- fourteen locales, chosen one at a
time, `.arb` files under `lib/ui/l10n/`. **Dual copy is a display mode *within* a
locale, not a replacement for the list.**

```dart
/// A string in more than one language, each with a stated origin.
///
/// Not a locale. Section 12.4 chooses one locale at a time from a list of fourteen;
/// this is the case the document already has once, where two languages are wanted
/// in the same place at the same time -- `空庭 · Hollow Court` on the task switcher,
/// and a subtitle track under a line of dialogue.
final class CopyLine {
  /// The language the reader asked for. Always present.
  final String primary;

  /// The other one, when there is one.
  ///
  /// Nullable, and null is a real state: a line nobody has translated yet is a line
  /// with one language in it, and section 12.4's rule about absent-not-defaulted
  /// applies here as it does in the domain layer.
  final String? secondary;
}
```

### 2.2 The origin of a string is carried in the type

This is the `UnitFactor.isEstimate` idiom applied to text, and it is the whole reason
the instruction says *and the user can edit it*. A machine translation and a written
translation are different facts, and a screen that shows both without saying which is
which is a screen lying to its reader.

```dart
/// Where a translation came from.
///
/// Section 5.3's rule for a dash, applied to a sentence: the system offers a
/// starting value, marks it as a guess rather than a fact, and lets the user
/// replace it with something of their own. A caller that shows the string has to
/// decide what to do about [machine]; a caller that does not look cannot present a
/// guess as a written line.
enum TextOrigin {
  /// A person wrote this.
  authored,

  /// A machine produced this and nobody has touched it.
  machine,

  /// A machine produced it and a person then changed it.
  ///
  /// Kept apart from [authored] because "the translator wrote this" and "the user
  /// corrected a machine" are different claims, and only one of them can be
  /// contributed back.
  edited,
}

final class Translated {
  final String text;
  final TextOrigin origin;

  /// The same string, now known to have been written by a person.
  ///
  /// Mirrors `UnitFactor.calibratedTo`: whatever the user typed is by definition no
  /// longer a guess.
  Translated editedTo(String typed) => Translated(typed, TextOrigin.edited);
}
```

### 2.3 Machine translation happens on demand, and it is cached as a *machine* result

- **On demand**, not at build time. A build cannot know which of fourteen locales a
  reader will want, and translating all of them into each other is 182 directions.
- **Cached**, because the same string is on screen repeatedly and a network call per
  frame is not a design.
- **Marked**, so that a later contributor can find every `machine` string and replace
  it, which is the cheap path from `machine` to `authored`.
- **Editable**, which is 2.5 and is where the existing machinery gets reused.

**And the direction is not symmetric.** Section 12.4's list contains 文言文 (`lzh`), a
locale whose translation cannot be machine-generated and should not be attempted. A
`machine` string is therefore **only ever offered where the pair is one this project
is willing to generate**, and the type makes that a decision at the call site rather
than a hope.

### 2.4 Dual copy is not for everything

Section 12.4's two-rule table is unchanged, and dual copy lives entirely on the second
row:

| | Dual copy? |
| --- | --- |
| Identifiers, keys, event types, log lines, diagnostics, design documents | **No.** ASCII, English, one string |
| Labels, headings, empty states, error copy | Yes, when the line is worth pairing |
| **The character's own lines** | Yes -- section 14.1 keeps the character in the stable release *as copy*, so her voice is the thing most worth having in both |
| Recipe and ingredient names | **See 2.6: a name is not a translation** |

**Not every string should be paired.** A dual `Cancel`/`取消` on a button is noise; a
dual line of her speech is the product. The rule is the same one section 12.4 already
asks of every string: *who reads this, and where does it end up?*

### 2.5 The user's edit goes to the overlay, and never into the seed

**This is the part section 12.4 already decided, and it applies unchanged.**

The document rejected 自定义中文 as a fifteenth locale for a precise reason: it "would
put a user's own words into the shipped seed data instead of on top of it". A
machine translation the user then corrects is **exactly that situation**, so the rule
carries over:

| | |
| --- | --- |
| The seed and the `.arb` files | shipped strings, and `machine` ones that nobody has replaced |
| **The user's correction** | **section 8's overlay**, keyed by the string's key |
| Sync | the overlay is per-device data and syncs like everything else in section 10; the seed is replaced wholesale on update and the overlay never is |

So an edited translation **survives an update**, and it does not become something this
project redistributes. The distinction is already drawn; this only has to not cross it.

### 2.6 A name is not a translation, and the corpus proves it

The user's own drink names are already multilingual *within one note*:

```
纯白交响曲        with 日文：ましろ色シンフォニー as its body
ギリギリボーダーライン
Trancing Time     One Last Kiss      「什亭之匣」（シッテムの箱）
```

**Three scripts, and one of them is a documented original behind a rendering.** So a
name has two different things that must not be conflated:

- **the name**, which is a proper noun and is not translated -- it is kept, or
  transliterated, or rendered, and the source is recorded
- **the gloss**, which is a translation and is paired like any other copy

```dart
/// A name and how it is said in another language.
///
/// Not [CopyLine]: `纯白交响曲` is not a translation of `ましろ色シンフォニー`, it is a
/// rendering of it, and the note records the original. Translating a proper noun
/// produces a different drink.
final class NamePair {
  final String name;
  /// The original, when the source wrote one: "日文：ましろ色シンフォニー".
  final String? original;
  /// A translation, which is a gloss and is allowed to be a guess.
  final Translated? gloss;
}
```

### 2.7 Layout, which is where dual copy is actually paid for

Two languages in one place is **not** one string with a newline in it:

- **Height doubles on every line that carries a pair**, so a list designed around one
  line will scroll differently. Section 12.3's four tabs are the first place this
  shows up.
- **The secondary is smaller and dimmer** -- it is the subtitle, and section 12.3's
  typography has to allow a second level that is still readable.
- **CJK and Latin do not share metrics.** A paired line's height is not twice one
  language's height; it is the sum of two different ones, and section 12.4 already
  notes that locale switching rebinds fonts because sizes and shapes depend on the
  language.
- **A pair can be switched off**, per screen, because a reader who wants one language
  should not be made to read two.

---

## 3. What this does not do

1. **It does not translate the domain layer.** Section 3's rule stands: the domain
   layer contains no display text, and it can be tested without a locale loaded. A
   `NamePair` reaches the UI as a pair of strings; it does not become a domain concept.
2. **It does not put a machine string where a written one is required.** Section
   20.4's posture and section 12.4's credit fields both want an author; `TextOrigin`
   is what lets a screen say "machine, unreviewed" instead of implying otherwise.
3. **It does not add locales.** Fourteen stay fourteen.
4. **It does not build the localization layer.** Section 12.4 says one written before
   there are screens to localize "would be guessing at the strings it is supposed to
   hold". This is the opposite: **the types and the one pair that already existed**,
   with no `.arb` file, no locale resolution, no settings key and no `intl` wiring. The
   47 remaining strings in `Copy` are her voice, §4.2 (c) says her voice is written by
   hand, and that is a content task -- so the layer waits for it, and the mechanism is
   in place when it arrives.

   **Superseded by §4.4.** The 47 strings have since been converted, and the sentence
   above is right about the layer and wrong about the strings: writing them *was* a
   content task, and it is done. What still waits is the `.arb` files, locale
   resolution, the settings key and `intl` -- which is what this item was really about.
5. **It has nothing to do with the deferred seed.** See the note in
   `proposal-first-party-seed.md`: the corpus stays out of the app, so nothing here
   depends on it. `空庭 · Hollow Court` and the existing copy are the whole test surface.

---

## 4. Decisions

### 4.1 Primary language -- answered by the user

> 用户语言区为主语言，副语言默认英语（可换成别的）

**The reader's locale is always the primary line. The secondary defaults to English
and is itself a setting.** So dual copy is not "Chinese and English everywhere"; it is
"the reader's language, plus one reference language they choose", and English is
merely the default choice of reference. A French reader gets fr + en, and changing the
reference to zh is a setting rather than a different build.

This also removes the question of what happens when the reader's locale *is* Chinese or
English: they are the same two cases as anybody else, and the reference language simply
must not be the primary. That is one guard, at one place.

### 4.2 The rest -- decided here, under 保证空庭工程纯净

The remaining three were delegated on the condition that the engineering stays pure, so
each answer below is argued from an existing rule rather than from convenience.

**(a) Per-string or global mode -- neither: the type is the decision.**

There is no flag and no registry. **A string that should never carry a second language
stays a `String`; one that may is a `CopyLine`.** The distinction is expressed by
choosing the type at the call site, which costs nothing at the sites that do not need
it, and no boolean is threaded through the widget tree.

*Why this is the pure answer and not a dodge:* a flag would make the decision **a value
that a caller can get wrong at runtime**, and would put a second parameter on every
widget that draws text. A type makes the decision **impossible to get wrong** and
visible in the signature. It is the same move section 5.3 makes with
`UnitFactor.isEstimate` -- the fact lives in the type, not in a comment and not in a
parameter somebody can forget.

**(b) Where `machine` text lives -- the overlay, immediately, never the seed.**

Not a separate cache. One storage location and one lifecycle:

| | |
| --- | --- |
| Where a generated translation goes on first use | **the overlay** -- the same place a correction goes |
| Why not a cache | a cache is a second lifecycle for the same fact, and the two would disagree about whether a string survives an update |
| Does it sync | **yes**, section 10. A translation generated on the phone should be on the desktop |
| Does it reach the seed | **never.** Section 12.4's rule: the user's words go *on top of* the shipped data |
| How it is found later | `TextOrigin.machine` -- every unreviewed string is one predicate away, which is the cheap path to replacing them |

**(c) The character's copy is hand-written in both languages -- and asserted.**

**Yes, for her copy. No for the rest.** Section 14.1 keeps the character in the stable
release **as copy**, so the words are the product rather than a label on it. And her copy
is a **bounded set** -- the strings that carry her voice -- where a full interface is not,
so writing both languages by hand is affordable here and is not affordable there.

The rule is **checked rather than trusted**:

```dart
final pairedCopy = <String, CopyLine>{'appName': Copy.appName};  // now 23 entries
// grew as strings were converted; the check itself did not change
test('is written by a person in both languages', ...)
```

*Why a test and not a convention:* section 0.1 already carries a test asserting that no
about copy that lives only in a prose document is a rule that a later contributor will
break without noticing.

**(d) The small-screen self-doubt -- named, not silent.**

`CopyLine.present` takes `roomForSecondary` separately from the reader's `dualCopy`, and
returns a `SecondaryOmitted` saying **which** of three things happened: the setting, no
translation written, or no room. `interaction-and-numbers.md` §14 records the conclusion
from two shipping games -- the lowest tier should be "named, reachable, documented and
tested, not an accident that happens when the GPU is weak" -- and a dropped subtitle is
that problem in typography. **A narrow screen loses the subtitle and keeps the line**,
and the reason is a value rather than a shrug.

### 4.3 What is built

`lib/ui/l10n/dual_copy.dart`, plus the first real instance and its tests:

| | |
| --- | --- |
| `TextOrigin`, `Translated` | the origin carried in the type, with `editedTo` mirroring `UnitFactor.calibratedTo` |
| `CopyLine`, `CopyPresentation`, `SecondaryOmitted` | a pair, what to draw, and why not |
| `NamePair` | a name is not a translation |
| **`Copy.appName`** | **the first `CopyLine`, and not a conversion** -- `app.dart` has joined `appTitle` and `appSubtitle` by hand since section 0.1, which is a dual line with the type missing |
| 16 tests | including the guard that grows with the conversion |

**The other 47 strings in `Copy` are not converted**, and that is deliberate: they are her
voice, (c) says her voice is written by hand in both languages, and writing 47 English
lines is a **content** task rather than an engineering one. The mechanism is in place for
them and `pairedCopy` is the list that grows.

**Superseded by §4.4**, which is that content task, and what it found.

**And one correction found by building it.** The first version offered `isGuest` and
`isVouched` as a pair, and a test failed on `edited` because the two read as complements
while not being one -- a machine wrote it *and* a person read it. The predicates were
renamed to the two questions that were actually hiding in them: `needsReviewMark` ("may
this be shown without saying it is a machine's") and `isOurOwnCopy` ("may this project
redistribute it"), which part company at exactly `edited`. **The failing test was right
and the design was wrong**, which is the order they should arrive in.

---

### 4.4 The 47 strings, and the wall that the four tabs are

**Built.** The content task named above was done, and doing it turned up a finding worth
recording: the split between "may pair" and "may not" is not a matter of taste. Three
things confine a string to one line, and none of them is a preference.

| Wall | What it is | What it costs |
| --- | --- | --- |
| **The platform** | `NavigationDestination.label` takes a `String` | **Section 12.3's four tabs cannot pair.** A bilingual tab label is a different navigation bar, not a different string |
| **The platform again** | `InputDecoration.labelText` and `hintText` take a `String` | The three form labels and their hints cannot pair |
| **Composition** | `'${Copy.stockBottles} · ${bottles.length}'`, and `withCount`'s `{count}` | A `CopyLine` cannot go inside a string. These look like copy and are really operands |

**And section 2.7 turns out to have called it.** It says the four tabs are "the first place
this shows up"; what shows up there is the wall.

So `Copy` ends up as two groups, and the rule between them is mechanical:

- **A `CopyLine` is displayed as itself, with room to be two lines** -- her sentences,
  screen titles, empty states, banners. **23** of them, each with a hand-written English
  line, `authored` on both sides.
- **A `String` is already confined to one line** by the platform, by a composition, or by
  the widget that owns it -- the four tabs, the form labels, the counts, the chips, the
  buttons, a badge's second line. **24** of them, and their English belongs to section
  12.4's `.arb` layer.

**Two things this buys, and one it does not.** The compiler now holds the second group: a
constant that cannot pair is a `String`, so there is no way to add it to `pairedCopy`,
which is 23 entries and is checked. The bad news is section 9's three verdicts -- her
register, and the one place the split costs something, since a badge already has two lines
and a chip label has one. Their register stays Chinese-only until the layer lands.

**And a test had to grow rather than be bent.** `theme_and_swatch_test.dart` checks that no
string a person reads carries the internal full name, and its list mixed both types the
moment the second type existed -- so it stopped compiling, which is the compiler doing that
file's job. Fixing it made the check **stronger**: it flattens every pair and checks the
English too, where the earlier version would have passed an internal name reaching a reader
through the secondary line.

**The guard bites.** Setting one secondary to `Translated.machine` fails with
`cellarNotYet secondary is machine` and `Expected: TextOrigin.authored` -- the constant is
named in the failure, which is the standard `persona_check.py` is held to.

---

## 5. What could be wrong

- **The reference-language guard does not exist yet.** 4.1 says the secondary must not be
  the primary, and no code can enforce that while there is no locale and no setting: dual
  copy is one `Provider<bool>` defaulting to on, and the reference language is English by
  construction rather than by choice.
- **Dual copy may not survive contact with small screens.** Two lines per item on a
  1220x2712 phone is fine; the same on a small window on a laptop is not, and the
  fallback is a per-string decision made too late if it is made after the layout.
- **`TextOrigin` may be too coarse.** "Machine, unreviewed" and "machine, reviewed by
  somebody who is not the author" are different, and section 12.4's credit fields
  suggest the project will eventually care.
- **The overlay key may be the wrong key.** Section 8's overlay is designed for terms;
  replacing a *sentence* needs the key to be stable across a seed update, and a seed
  replaced wholesale is exactly when a key changes.
