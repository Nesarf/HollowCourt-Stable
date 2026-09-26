# Proposal: first-party drinks, and the grammar that reads them

**For approval. No code written yet.**

> ### Deferred by the user, 2026-09-19
>
> 我上传的这些原创数据，先不要进空庭，等后面本体对外发布了再说，先保证空庭的净化度。
>
> **So: the 45 notes do not enter 空庭.** They stay in `docs/drinks.md` as a
> reference record and nothing else. No importer, no seed regeneration, no new
> entries in the app, and **空庭 stays clean of the user's own original material**
> until the main body has been released.
>
> This is a **scope decision, not a technical one**, and it does not weaken any
> finding above -- the grammar is still a different grammar, and the notes are still
> the only first-party content this project has. It only says *when*, and the answer
> is "not yet".
>
> **What that means for the plan below:** steps 1-2 (the unit word table and the
> second grammar) are not blocked by the deferral in the sense that they could be
> built -- but they exist to read *these notes*, and with the notes out of scope they
> have no consumer. So **the whole proposal is parked**, not partially started. A
> grammar written for a corpus nobody is importing is a grammar written from
> imagination, which is the specific failure `IngredientPhrase` avoided by reading
> 390 real lines.
>
> **What is unaffected:** the correction in `docs/drinks.md` §4.0 stands; the record
> of how the notes were read stands; and `tools/miui_notes.py` stays, because it is a
> reader for a backup format and not a feature of the app.
>
> The companion document `proposal-dual-copy.md` is **not** deferred -- it is about
> the interface, is needed by the shipped copy, and does not depend on the corpus.

The goal is a straight line from the user's own notes to a drink the app can pour:

```
小米笔记  ->  tools/miui_notes.py  ->  importer  ->  seed  ->  空庭
```

and the reason to do it now is that it is the first time this project has content
of its own. Section 15 requires the shipped set to be written in-house; 45 notes
in `docs/drinks.md` answer that, and nothing else in `data/sources/` can.

This document says what would have to change. It is deliberately ordered by
dependency, and the first item is not the one the earlier record expected.

---

## 0. What this does not cover

- **Not the renderer.** Section 12.1's density and temperature work follows this,
  and depends on it.
- **Not the UI beyond what the data forces.** A new level above a recipe shows up
  in section 12.3 and that is noted in item 5, but the browsing design is its own
  proposal.
- **Not the 502 existing seed recipes.** another source's and one source's data already round-trips
  through `SeedCodec` v1. Whatever happens here must keep doing so.

---

## 1. What already exists, read rather than assumed

This had to come first, because an earlier revision of `docs/drinks.md` listed
"gaps" that reading `lib/domain/` then removed. The domain layer is **further along
and better argued than the note corpus needs:**

| | |
| --- | --- |
| `UnitDimension { volume, mass, count, ratio }` | `ratio` is its own dimension, with a comment on why `part` is not a volume |
| `UnitKind { absolute, cultural, discrete }` | section 5.2's three tiers; `UnitFactor.isEstimate` carries "this is a convention" **in the type**, and `calibratedTo` replaces it |
| `RecipeItem.count` as a `Rational` | four cherries doubled is eight in the spec and four in the glass -- and `1,5` is handled |
| `ItemRole { base, modifier, garnish, optional }` | the essential/optional garnish split the notes have |
| `UnmeasuredIngredient` | `rim of bar sugar`, `rinse of absinthe` -- **already the right home for `补满`** |
| `UnparsedIngredient` | "I do not understand this" as a *result*, not an exception |
| `Ingredient.densityGPerMl`, `Mass`, section 5.4 | the density bridge exists |
| `LiquidVisual.layered` | layers are anticipated -- as a **boolean and two colours** |

**So the honest framing is not "the model is wrong". It is that the grammar reads a
different language.**

---

## 2. The four changes, in dependency order

### 2.1 The grammar -- this is the work

`IngredientPhrase` states its own provenance:

> The grammar below is not invented; it is read off the 390 lines in the another source
> harvest, which between them use exactly four shapes:
> `<number> <unit> of <ingredient>`, `<number> of <ingredient>`,
> `<word> of <ingredient>`, `of <ingredient>`

**All four are English word order: quantity first, `of` before the name.** The
user's notes are the opposite, and they are not a variant of it:

```
重泥煤威士忌 30ml              name, number, unit, no "of", no space needed
Cynar 20ml
橙苦精3～4滴                    name and number run together -- the split needs the unit word
冰镇汤力水 补满                  name, then a use-word and no number
①伏特加40ml                    a circled numeral prefix
伦敦干金酒/柑橘系金酒 30ml       a slash-alternative inside the name
珠江原浆 330ml（Stir之后加入）    a parenthetical instruction after the amount
蓝宝石金 30ml（45ml）           a parenthetical alternate amount
南非醉茄粉 ½小匙（约1.5g）       a unicode fraction and an approximation
```

**Proposal: a second set of shapes, tried beside the first, with the matching shape
reported.**

```dart
/// Which word order a line turned out to use. Reported, not assumed, because a
/// line that could be read two ways is a line that must be reported rather than
/// guessed at -- the rule IngredientPhrase already states for `2 glugs of gin`.
enum PhraseOrder { quantityFirst, nameFirst }
```

`IngredientPhrase.parse(String raw, {UnitSystem? units, PhraseOrder? order})`
returns the same four outcomes it already does, plus the order it used. New shapes:

```
[①] <name> [<space>] <number> <unit> <parentheticals>*
[①] <name> [<space>] <number> <range-tilde> <number> <unit>
[①] <name> <space> <use-word>
```

The split is anchored on a **trailing unit word**, which is why the closed unit
vocabulary has to come first (2.2). This is what makes `橙苦精3～4滴` parseable at
all: without knowing `滴` is a unit, there is no boundary to cut on.

**Why a second grammar and not a wider first one.** The file's own comment:

> Kept as a closed set. An unfamiliar word in that position is reported as unparsed
> rather than accepted as a preparation, because accepting anything there is how
> `2 glugs of gin` would become a measurement.

Widening the English regexes to accept a trailing amount makes **every English line
ambiguous** -- `2 oz of rye whiskey` could then split as name `2 oz` + amount
`rye whiskey`. Two shapes, tried in a fixed order, with the order reported, keeps
both languages unambiguous and keeps the failure visible.

### 2.2 Unit words -- an alias table, not new units

`UnitSystem` already carries the right units in the right kinds. What it lacks is a
way to reach them by a word other than `id`: `_unitFor` compares `unit.id == word`,
and `Unit` has an `id` and a `symbol` but **no aliases**. So `滴` cannot resolve to
`drop` today.

**Proposal:** `UnitSystem.unitNamed(String word, {Locale? locale})` backed by a
word table. Nothing about `Unit`, `UnitKind` or `UnitDimension` changes.

| In the notes | Resolves to |
| --- | --- |
| `ml` `毫升`, `滴` | `millilitre`, `drop` |
| `小匙`, `大匙` | `teaspoon`, `tablespoon` |
| `小撮`, `适量` | `pinch` |
| `片` | `slice` |
| `颗`, `粒` | `each` |

**Five words have no equivalent and are proposed as new discrete units:** `串`, `球`,
`根`, `粒`. And **`份` is deliberately not on that list** -- a portion of espresso is
culturally a volume, and turning it into a count would make "1 份" and "30 ml" two
different numbers for the same thing. `份` should be a **cultural unit with a
suggested size**, like `dash`, until somebody argues otherwise.

### 2.3 The narrow quantity additions

**Not a union replacing the integer.** The integer stays the base and stays the
representation of anything measurable. Four forms sit beside it, and each is one
field or one case:

| Form | Example | Proposal |
| --- | --- | --- |
| **ranged** | `2~3drops`, `50～60ml`, `1-2球` | `RecipeItem.amountMax: int?` and `countMax: Rational?` -- **a second bound, not a new type** |
| **alternate** | `30ml（45ml）`, `15ml（-）` | `RecipeItem.alternate: Alternate?`, where `Alternate` is either another amount or **`omitted`** for `-` |
| **approximated** | `约1.5g`, `大约`, `若干（如15颗）` | `RecipeItem.isApproximate: bool` -- and it is a **flag, not a range**, because "about 1.5 g" is one number the writer was unsure of |
| **relative** | `补满` | `RecipeItem.fillTo: FillTarget?` |

**`fillTo` is the one that needs an argument, and it fits section 6 well.** Today an
unmeasurable line becomes an `UnmeasuredIngredient` and **is not a recipe item at
all** -- the reason given is that "an item that says `some sugar` cannot be deducted
from a bottle". **`补满` is different**: it is a real pour of a real liquid, and its
amount is unknown *until the glass is in front of you*. Section 6 already records an
**operation rather than a state**, so the Batch records the volume actually poured
and the ledger stays correct. So `fillTo` earns its place where `Unmeasured` does
not:

```dart
/// A recipe line with no fixed amount, filled to something at pour time.
///
/// Section 4.4 deliberately gives an unmeasurable line no representation, because
/// "some sugar" cannot be deducted from a bottle. This is the other case: a real
/// pour of a real liquid whose amount depends on the glass, so the recipe cannot
/// state it and the *pour* does. Section 6 records an operation rather than a
/// state, which is what makes that safe.
final class FillTarget {
  /// Null when the source said only "top up".
  final Volume? containerVolume;
}
```

### 2.4 Layers, density and temperature

`LiquidVisual.layered` is a **boolean with two colours**, and `生命之树（十层）` is
ten layers with a measured density each. This is the largest genuinely new thing,
and it is also the one section 12.1 is waiting for.

```dart
/// One layer of a drink that is served in layers.
final class Layer {
  final int index;             // 1 = the bottom
  final List<RecipeItem> items;
  /// Grams per millilitre, when it is known.
  final Rational? densityGPerMl;
  /// Serving temperature in degrees Celsius, when the source gives one.
  final Rational? servingTemperatureC;
  /// What the source called this layer: "Malkuth", "下层", "上层".
  final String? name;
}
```

Three points, each taken from the notes rather than invented:

1. **Density belongs to the layer, not only to the ingredient.** `生命之树` reaches
   1.22 by *adjusting* pomegranate syrup with honey, so the layer's density is an
   authored number and `Ingredient.densityGPerMl` is only a starting point.
2. **Temperature is per zone.** The note assigns 4 ℃ to layers 1-3, 6 ℃ to 4-7 and
   8 ℃ to 8-10, and states why: 低温增加下层密度，微温降低上层密度，物理上扩大层间差约
   0.005-0.01g/ml.
3. **A validator, in this project's style.** A layered drink requires **descending**
   density upward. So `Recipe.validate()` gains a rule that reports an inversion --
   and, following the existing convention that *absent is not a problem*, reports
   nothing when a density is missing.

```dart
// layer 4 is 1.05 g/ml and layer 3 is 1.10 g/ml  ->  fine
// layer 4 is 1.16 g/ml and layer 3 is 1.10 g/ml  ->  "layer 4 (1.16) is denser
//                                                    than layer 3 (1.10) below it"
```

### 2.5 Series, variants, and the two halves

Three small additions, each because a note in the corpus needs it:

| | Proposal |
| --- | --- |
| **`三色堇系列`** holds four drinks and a rule that belongs to none of them | `Series { id, name, rule?, memberIds }`, with `Recipe.seriesId` |
| **`一氧化二氢`** holds a drink and `变体：氯化钠注射液` | `Recipe.variantOf: String?` and `variantLabel: String?`. **A variant stays a Recipe**, so it scores, stocks and pours like one |
| **十一 classics vs thirty-four authored** | `Recipe.family: Family { reference, authored }` |

**`family` is the one worth arguing for.** The four folders are not the same kind
of thing, and eleven of forty-five are somebody else's classics. Section 12.3 will
want to browse them apart, and section 9 scores them the same -- which is correct,
and is exactly why the distinction has to be data rather than a folder name.

---

## 3. The seed format

`SeedCodec` is JSON, `hollow-court-seed` v1, and it **refuses a version it does not
know**:

```dart
if (version > formatVersion) throw SeedFormatException(
  'the seed is version $version and this build reads up to $formatVersion');
```

**That stays.** Refusing an unknown *structure* is right, and the `Unknown` lesson
from `arcade.md` is about a different level: an unknown **value inside a known
version**. a rhythm game's `EventType.Unknown` exists so a reader meets a new event *kind*,
files it, and writes it back.

So, per `arcade.md` and `zenless.md`:

| Rule | From | How it applies here |
| --- | --- | --- |
| **A declared `unknown` for anything enumerated** | `arcade.md` | a new `ItemRole`, `Unit`, or `Glass` arriving in v1 data must have somewhere to go that is not an exception and not a silent drop |
| **Errors reported by line number** | `arcade.md` | the seed is JSON, so this is the importer's report: `drinks.md line 412` for a note, and a `{file, line}` for the seed |
| **Folder and convention, not a manifest** | `zenless.md` | 45 recipes is a rhythm game's scale, not 绝区零's. **No manifest.** |
| **Never normalise the evidence on the way in** | `drinks.md` | two tilde characters and a `45m` typo are findings, not dirt |

**And `formatVersion` goes to 2**, because `layers`, `series`, `variantOf` and
`family` are structural. v1 documents keep loading; v2 documents do not load in a
v1 build, which is the behaviour the codec already has.

---

## 4. The pipeline, and where the source of truth stays

```
小米笔记                       the user writes here; it stays the source
  |  tools/miui_notes.py        already written, already filters by folder
  v
drinks.json                    45 records, 4 folders, nothing else
  |  a new importer            the second grammar of 2.1
  v
assets/seed/*.json             derived, git-ignored, built like the another source seed
  v
空庭
```

**The notes stay the source of truth and the seed stays derived.** The importer runs
at build time, not at run time: an app that read Xiaomi Notes directly would be an
app coupled to one phone's note format, and `seed_repository` already establishes
that the seed is a file the app loads from wherever it finds it.

---

## 5. What I would not do

1. **Not widen the English grammar.** 2.1 gives the reason.
2. **Not replace the integer microlitre with a union.** The integer is right for
   everything measurable, and a union as *the* representation would put a case
   analysis into every piece of dosing arithmetic -- dilution, ABV, scaling, match
   scoring -- to serve four forms that are rare in the seed and common in the notes.
3. **Not make `Unmeasured` into an item.** `补满` is not `rinse`; 2.3 gives the
   reason, and it is about whether stock can be deducted.
4. **Not read the notes at run time.** Section 4.
5. **Not put the 250 non-drink notes anywhere.** The backup is a whole notebook and
   `tools/miui_notes.py` filters before reading, which is the behaviour to keep.
6. **Not change section 12.1 or 12.3 in this pass.** They follow.

---

## 6. Cost, order, and the decisions I need

| # | Step | Depends on | Size |
| --- | --- | --- | --- |
| 1 | Unit word table + `unitNamed` | -- | small |
| 2 | Second grammar, with the order reported | 1 | **the largest single piece** |
| 3 | Four quantity forms | 2 | small each |
| 4 | `Layer`, density, temperature, the inversion validator | 3 | medium |
| 5 | `Series`, `variantOf`, `family` | -- | small |
| 6 | Seed v2 + codec | 3, 4, 5 | medium |
| 7 | The importer, with a line-numbered report | 2-6 | medium |
| 8 | Regenerate the seed; the app shows 45 more drinks | 7 | small |

**Steps 1 and 2 carry the risk and everything else is downstream**, which is why the
grammar is first.

### The decisions I need from you

1. **Is a second grammar acceptable**, or would you rather the notes be
   hand-normalised into the existing English order once? The second is less code and
   throws away the evidence; the first keeps the notes as they are written.
2. **`份`** -- a cultural unit with a suggested size, or a count? (2.2 argues for
   cultural.)
3. **`family: reference | authored`** -- is the eleven/twenty-four split worth
   putting in the data, or is it a folder name that stays a folder name?
4. **Does `formatVersion` become 2**, or do the new fields ride in `extras` until
   they are settled? (I would say 2: `extras` is where a schema goes to hide.)

---

## 7. What could be wrong

- **The Chinese grammar may be more irregular than the five shapes suggest.** Five
  was enough for 390 English lines; 861 lines of Chinese may want more, and the
  honest way to find out is to run the parser over all 45 notes and **count the
  `UnparsedIngredient` results** rather than to enumerate shapes in advance.
- **`family` may be wrong.** It might really be "whose recipe is this", which is a
  provenance question, and `origin` already exists for provenance.
- **The density ordering may not be checkable in practice**, because most of the
  45 notes give no density at all. Then the validator fires on one note and the
  rule is decoration -- which is worth knowing before building it.
- **The second grammar may make the first ambiguous in ways not yet seen**, which is
  why the order is *reported* rather than decided silently.
