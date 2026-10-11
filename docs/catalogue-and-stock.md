# The catalogue and the stock: two lists, not one

Written 2026-10-08, from the owner's question about **managing many ingredients and many recipes** -- *"原料和配方都很多的时候，如何提升管理效率"* -- and their observation that this is **仓库管理的逻辑**.

**This was a design note rather than a record. ① and ② are now built** -- the 原料 tab draws the reader's side and the
library's as two headed lists, and the library's is cut again into four demand classes, in
`lib/ui/ingredient_section.dart` with `IngredientDemand` behind it. `test/ui/ingredient_section_test.dart` and
`test/domain/model/ingredient_demand_test.dart` hold both to that. **③ through ⑤ are still unbuilt**, and
`docs/ingredient-gap.md`'s rule applies to everything below that is written in the present tense about them: nothing
there is a claim about what the code does.

## The finding, and it is not about speed

**A warehouse keeps the supplier's catalogue and its own stock as two tables and never mixes them.** 空庭 currently
mixes them: the 原料 tab lists **189 ingredients, which is what the library carries**, and a reader who actually manages
twenty of them has to find those twenty in that list.

**So the inefficiency is not that there is a lot of data. It is that two different things are drawn as one.** No
database changes that -- **a faster list of the wrong list is still the wrong list.**

## What already exists, measured

| Warehouse concept | 空庭 |
| --- | --- |
| SKU / barcode | **yes** -- manual entry, EAN check digit, unknown-code memory |
| Location | **yes, for bottles** -- `posXPermille` on the bar's shelves. **Not for ingredients** |
| Cycle counting | **yes** -- `BottleRecounted` |
| Reorder point | **half** -- the shopping list is derived from the *plan*, not from low stock |
| Velocity classification (ABC) | **nothing -- and the data is already there** |
| Dead stock | **nothing** |

**And the ABC table has already been measured**, in `docs/ingredient-gap.md`:

    189 ingredients:  33 used by four or more recipes
                      31 used by two or three
                      57 used by exactly one
                      68 used by none at all        <- 36% dead stock

**That last number has a cause worth remembering**: the library was derived *from* 103 recipes, and the derivation kept
every item of every drink. **So it carries about a third of things nothing uses**, and the interface has never told a
reader which third that is.

## The order, and why this one

**① Separate the catalogue from the stock, in the interface.** No new data, no new domain concept -- the predicate
already exists:

```dart
bool has(String ingredientId) => stock.bottles.any(
  (bottle) => bottle.sku == ingredientId && bottle.remaining.microlitres > 0,
);
```

**The split is: what the reader has a bottle of, plus what they wrote themselves, against the library's catalogue.**
Two headings over two grids, and the search applies to both.

**Built.** The headings are `Copy.ingredientMine` and `Copy.ingredientLibrary`, the cut is one pass of that predicate
over the seed in `_split`, and the count line now reads `written + held / catalogue` -- which is the first time the tab
can say how much of the library the reader is *not* looking after. **A held library ingredient moves to the reader's
side and stays read-only**, and the row needs only one flag to say that: the list already *is* the held-ness, so
`isMine` is left answering the one question the list cannot -- may this card be changed.

**② Then velocity.** Put ABC in front of the reader -- core, occasional, dead -- because **"68 of these are not your
responsibility" is information they cannot get today**, and it is the thing that makes a long list stop feeling like a
backlog.

**Built, and it is four classes rather than ABC's three.** `IngredientDemand` counts how many recipes call for each
ingredient -- **derived on every read, never stored**, because the number is a function of the recipes and a stored
copy would be a second truth that can disagree with the first. The second consequence is better than the saving: a
recipe the reader writes moves an ingredient out of dead stock the moment they save it, with nothing to invalidate.

    核心    ≥ 4 recipes     core        稼ぎ筋 / 主力
    偶尔    2-3              occasional  時々
    少见    1                rare        まれ
    死库存  0                dead        死に筋 / 死貨 / 滯銷

**The fourth class is the point, and merging it into the third -- which is what ABC does, calling both "C" -- would
hide the number this stage exists to show.** *Called for by one recipe* is a real ingredient that happens to be in one
drink; *called for by nothing* is a record the library kept because the derivation kept everything. The owner chose
four over three for exactly that reason.

**The library's half is drawn as four sub-sections, most wanted first**, which the owner chose over a badge on every
card: the heading and its count *are* the sentence -- 死库存 68 -- and a badge would have put the same fact on 189
cards to say it once. Each language gets its own trade term rather than a translation of the English, because a reader
who manages a store already has the word.

**A held ingredient shows no class at all.** It left the catalogue in ①, and *"you already have this"* is a better
answer than *"four recipes want it"*.

**③ Then location for ingredients**, the way bottles already have it. For somebody managing two hundred things, *"where
is it"* is asked more often than *"what is it called"*.

**④ Then reorder points from low stock**, rather than from the plan alone.

**⑤ And a database, if ever, last.** The review already said it and the numbers agree: the log is **1.6 KB after three
weeks**, the seed is 253 KB and never changes, and what a database would eventually fix is *query* cost -- which is
measurable, and `docs/log-compaction.md` records the shape: a cache that can be deleted and rebuilt, or it is not a
cache.

## Why ① is first

**It is the cheapest and it is the ground the other four stand on.** ② groups a list that is currently one list, ③
addresses things that are currently unaddressed, ④ triggers on a quantity whose meaning depends on knowing what the
reader actually holds. **Every one of them needs the reader's own things to be a set rather than a subset of a
catalogue.**
