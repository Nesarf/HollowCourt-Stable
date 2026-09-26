# Proposal: measures are a reading preference, in both axes

The instruction, verbatim: **计量单位（原料量和花费）记得做可选的多样化** -- the unit used for an
ingredient's amount and the unit used for what it cost are both **choices a reader makes**,
and more than one has to be available.

This file exists because the requirement touches two rules this project already has, and
following either one naively produces a wrong answer. It states what is already built,
what the requirement adds, and the four decisions that are the reader's rather than mine.

Nothing here is implemented yet.

## 1. What already exists, and it is most of the hard part

**Amounts.** `lib/domain/units/` holds an integer base of microlitres and a `UnitSystem`
over it. Three things in it were built for exactly this requirement before it was asked for:

- `UnitFactor.isEstimate` carries *"this conversion is a guess"* **in the type**, because
  section 5.2 says a dash has no international standard while a millilitre does.
- Units that **cannot** become microlitres exist and say why: a *part* has no size until the
  total is known, and a count is not a volume at all. A preference over units therefore
  cannot be a preference over *all* units -- some amounts are not convertible and no setting
  changes that.
- `roundHalfUp` is the single exit from exact arithmetic to a whole number, and section 5.3
  requires rounding to happen once, at the edge.

**Money.** `lib/domain/pricing/price.dart` holds `Currency` with `minorUnitDigits`, and
that field is already load-bearing: JPY and KRW have **no subdivision**, so a model that
assumed two digits reports a Japanese price a hundred times too high, consistently. The
integer base is minor units, and `Money.times` is the one place a fraction becomes whole.

**Where the current build is fixed.** The add form says `容量（毫升）` and the price field
says `价格（分）`, and the price history sheet prints `1762.86 / L` and `0.79 CNY`. Every one
of those is a hard-coded choice, and the locale layer has no say in it.

## 2. The rule that decides the whole design

**A measure is a view, and the stored value never changes with it.**

A quantity stays a whole number of microlitres and a price stays a whole number of minor
units, whatever the reader has chosen to see. The alternative -- storing what somebody typed
-- is what makes an application lose a drink when the reader switches from ounces to
millilitres, and it is the same failure section 8 refuses when it keeps the seed and the
overlay apart: **the stored form must not depend on a preference.**

So the preference is applied at two places and no others: when a field is **labelled**, and
when a number is **printed**. It is never applied when a number is parsed into the base,
because the base has one unit by definition.

## 3. The two axes, and they are not the same kind of choice

| | Amounts | Money |
| --- | --- | --- |
| Base already fixed | microlitres | minor units of a currency |
| What varies | the unit *shown*: ml, cl, L, fl oz, 合, 勺, oz | the **currency**, which also changes the base's scale |
| Bound to locale? | yes -- section 12.4 lists "units as drawn on screen" as the reader's locale | **this is the open question**, see 4.2 |
| Already has a per-value qualifier | `UnitFactor.isEstimate` | `Currency.minorUnitDigits` |

The asymmetry matters: switching an amount's unit is **pure formatting**, while switching a
currency is a **different number in the base** -- `Money.fromMinorUnits` means one thing in
CNY and another in JPY. Treating them as one setting would put a formatting change and a
unit-of-account change behind the same switch.

## 4. The reader's answers, and what is still open

The instruction that settled most of this, verbatim: **钱默认跟语言区走（可换），可设置副币种（最多3个，
连同主币种共四个之间不得重复）；原料计量单位也是默认用语言区的常用单位，主单位1个，副单位最多3个，
都可替换，都不可重复，要区分固体液体组合等**.

### 4.1 Settled: one primary and up to three secondary, with no repetition

**Both axes are the same sentence with a different noun**, so they are one type and not two:
`lib/domain/preferences/choice_set.dart` holds `ChoiceSet<T>`, which enforces one primary,
at most three secondary, and no repetition among the four -- at construction and after every
change. Writing the uniqueness rule twice would be writing a rule that will disagree with
itself.

The operation with two behaviours is promotion, and it is documented as such: promoting a
choice that is **already a secondary swaps** it with the primary, so a reader who makes 欧元
primary does not lose the currency they had; promoting a choice that is **absent** lets the
old primary leave, because the set is bounded and the thing they explicitly replaced is the
least surprising candidate.

### 4.2 Settled: money follows the locale, and is changeable

The default comes from the reader's locale and the reader may change it. This rejects the
"independent setting that is only defaulted from the locale" option I had proposed, and the
reason the reader's rule is the better one is worth keeping: a currency that silently
relabelled somebody's cellar would be wrong *and confident*, and the instruction removes that
by making the locale a starting point rather than an authority.

### 4.3 Settled: measures default to the locale's customary unit, and the axis is matter state

One primary, up to three secondaries, all replaceable, none repeating -- and **the sets are
per matter state rather than one global set**, because 要区分固体液体组合等.

Three of those categories already exist in the domain and do not have to be invented:

| Instruction | What the domain already has |
| --- | --- |
| 液 | `Volume`, base microlitres |
| 固 | `Mass`, base milligrams -- a separate type on purpose, so a volume and a mass cannot be added |
| 组合 | **corrected by the reader**, see below: not a third table, but a set whose members may come from more than one dimension |

**「组合」is a set that may cross dimensions, and my first reading of it was wrong.** The
instruction's example settles it: 比如奶油，如果是固体奶油就用克，液体奶油就用毫升，以及糖浆/蜂蜜这种克和
毫升都能用的，默认以毫升为主计量而克为负计量，诸如此类. So the category is not "units that refuse
to convert" -- it is **an ingredient measurable in more than one dimension, with a declared
primary**. Cream is not composite by nature: the same cream is a solid measured in grams or a
liquid measured in millilitres, and which one applies is the form it is in when somebody uses
it.

Three consequences follow, and the third is the one that has to be built:

1. **The measure set is per ingredient, not per dimension.** The primary and secondary slots
   are exactly where "which form" gets answered, so 固体奶油 has grams as its primary and
   液体奶油 has millilitres as its primary -- one ingredient, two forms, one mechanism.
2. **Where both work, the volume is the default.** 糖浆 and 蜂蜜 take millilitres as primary
   and grams as secondary, and that is the instruction rather than a preference of mine.
3. **Crossing dimensions needs a density, and the domain already has one.**
   `lib/domain/dosing/density.dart` exists, and it is the only thing that can make 克 and 毫升
   meet for a given substance. A composite measure set is therefore **not complete without a
   density** for that ingredient -- and where there is none, the second unit is a label a
   reader may read but nothing may convert through, which is a state that has to be *visible*
   rather than silently rounded into a number that looks like arithmetic.

A count and a part are a **separate** case from composite, not the same one: a count is not a
quantity of either kind, and `UnitNotConvertible` already exists to say why. Folding them into
this category would have put "one lime" and "honey, by weight" behind the same switch.

### 4.4 Still open: the twelve locales nobody has used

A currency and a unit set are per-locale tables, and section 12.4's rule for the `.arb` files
applies here too: generating a table for twelve languages would produce exactly the `machine`
strings `TextOrigin` exists to keep apart from `authored` ones. So the tables want the same
treatment -- a default that is honestly a default, and a mark on anything nobody has checked.
**This one is not answered yet.**

### 4.5 Also still open: may the two be mixed

Ounces in a recipe against millilitres in the cellar. Section 5.3's arithmetic is exact
either way, so this is a question about surfaces rather than about correctness, and the
instruction's "都可替换" does not settle whether the choice is per-axis or per-screen.

## 5. Why this is not just a formatting change

Three places in the existing code already depend on the answer, and each would be wrong in a
way nothing would report:

1. **`standardPour` is 45 ml.** It is a `Volume`, so it is exact and unit-independent -- but
   the sheet prints `45 ml` beside the label. In a locale reading ounces that string is a lie
   about a number that is not wrong.
2. **The price chart's axis is `/ L`.** Switching an amount unit does not change a price per
   litre, but a reader who has chosen gallons will read it as one. The axis label and the
   reader's unit have to agree, which means the axis is not a constant in the painter.
3. **`价格（分）` names the minor unit in the label.** With a currency setting, that label is
   a function of the setting and of `minorUnitDigits` -- and for JPY it has to say something
   else entirely, because there is no 分.

## 6. What is deliberately not proposed

- **No new unit without a measured definition.** Section 5.2's rule, unchanged.
- **No change to the stored base.** Not microlitres, not minor units, ever; the preference is
  a view.
- **No automatic conversion of an entered amount.** A field labelled `fl oz` parses ounces
  into microlitres at the boundary, once, and the log keeps microlitres.
- **No rounding anywhere but the edge.** Section 5.3.

## 7. Order of work, when it is taken up

1. The unit axes as tables (locale -> amount units, locale -> default currency), no UI.
2. Both settings on the settings surface that section 12.4's layer already established, so
   there is one place a preference lives.
3. The three call sites in section 5 above, each with a test that reads the rendered string.
4. Only then the picker UI, which is the easy part.
