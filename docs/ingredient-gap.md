# The ingredient gap, measured

Written 2026-10-01, before doing the library expansion, because the owner asked for it to be done with heavy web
research — and the first thing the research did was disprove two things I had already told them. Both are below,
because a correction that is not written down is a correction somebody makes again.

## What is actually true

Measured from `assets/drinks/library.json`:

| | |
| --- | --- |
| Ingredients | **189** |
| Of those, carrying a `category` | **47** — so **142 were never classified** |
| Categories the enum declares | 33 |
| Categories the seed uses | **17** — so **16 are empty** |
| An ingredient's shape | `{id, name}`, and `category` / `defaultUnit` where somebody added them |
| Recipes | 103, all from IBA's three categories |

**An ingredient record is a name and an id**, and the category is an *added* field rather than a base one — which is
why the count of unclassified ingredients is a count of records nobody has been through, not a count of missing data.

## Two claims of mine that this contradicts

**1. "`tequilaAndMezcal` has nothing in it" — the *category* is empty, the *ingredients* are not.**

`Tequila` and `Mezcal` are both in the library. So are Margarita, Paloma, Tommy's Margarita and Tequila Sunrise.
**I read an empty category name as an empty shelf**, which is precisely the mistake a category field exists to make
visible — and I made it while looking straight at the field.

**2. "Harvesting IBA's full list would add a batch of ingredients."**

`all-cocktails` is paged, and its last page holds two entries, so the whole list is about **102** — against the
**103** this project already has. **There is no larger corpus to fetch.** The project harvested the three category
pages and that was already the whole list.

## What the gap actually is

**Classification, not size.** 142 ingredients have no category, and the authority's own taxonomy is about
*cocktails* — The Unforgettables, The Contemporary, The New Era — rather than about ingredients. **An ingredient
taxonomy does not exist there to be fetched**, so this is work the project has to do or commission rather than
download.

**And the line to hold while doing it is the one the library's own `note` already follows**, in its words: *"Names
and standard proportions are referenced (© IBA, all rights reserved); the instruction text and every translation are
ours."*

| Sourced and cited | Written here |
| --- | --- |
| A name, an alternative spelling | A description |
| A category, a family, a relationship | Any prose about how it tastes |
| That a thing is a base spirit or a modifier | Any composition list copied from a page |

**A category name and a classification are facts.** A paragraph describing a liqueur is somebody's writing, and none
of it goes in.

## Step 1 is done, and it exposed a second taxonomy nobody uses

**All 189 ingredients now carry a `kind`** -- liqueur 43, spirit 34, pantry 16, syrup 15, fruit 13, juice 13, wine
12, dairy 10, spice 10, mixer 10, bitter 4, tea 3, garnish 3, beer 3 -- written by
`tool/classify_ingredients.py`, which maps the 47 existing categories rather than discarding them.

**And the 16 empty categories are still empty**, because `kind`/`family` is *not* the same field as `category`. The
project now has two taxonomies side by side, which is not a state to leave alone. Measured before deciding:

| | |
| --- | --- |
| `IngredientCategory` values | **33**, of which the seed uses 17 |
| `isSubstance` / `isBrowseGrouping` / `isAlcoholic` callers | **none** -- definitions with no users |
| Screens that group or filter by category | **none** -- `stock_page` sorts by sku |
| Where `category` is actually consumed | the model and the codec -- **stored, never decided on** |
| `kind` coverage | **189 of 189** |
| `category` coverage | 47 of 189 |

**So the older of the two is the one nothing reads**, and the newer one covers everything. That is not an argument
to keep both, and it is not one to delete the old one either: the enum carries three *browse groupings*
(`itemsYouCanMake`, `theModernBar`, `top25MostUsed`) that are a real screen affordance rather than a kind of
anything -- a distinction `ingredient_category.dart` already argues for at length.

**Consolidating them is a decision rather than a chore**, and it is left here for the owner:

1. **`kind`/`family` becomes the substance taxonomy and `category` is retired to browse groupings only.** The
   cleanest reading of the proposal, and it costs a stock-page pass plus a seed migration for the 47 records.
2. **Keep both, with `kind` authoritative and `category` kept for the picker.** Cheapest, and it leaves two fields
   that disagree about what an ingredient is.
3. **Delete the enum and the field.** Simplest, and it throws away the browse groupings, which would then have to
   be rebuilt as data.

## Step 2 is done: option ① chosen, and the older taxonomy retired

**The owner chose the first of the three.** `kind`/`family` is now the substance taxonomy; `IngredientCategory` is
**the three browse groupings and nothing else**; and the 47 ingredients that carried a substance category had it
*converted* rather than deleted -- `tool/classify_ingredients.py` records each one's origin in a comment, so the
reason a family was chosen survives the change that made it a family.

**What went, and why it went rather than being kept "just in case":**

| Removed | Why it was dead |
| --- | --- |
| 27 substance members of the enum | nothing read them: `isSubstance`/`isAlcoholic` had no callers, no screen grouped or filtered by category, and the artifact now carries no `category` at all |
| `IngredientCategory.fromSource` | **it was a lookup of the enum's own member names beside two misspellings** -- it proved that a name matched itself, which is not a source mapping |
| `Ingredient.category`'s substance role | the field survives for a browse grouping, which is all it can now hold |

**`SourceBucket` and `Level` stay.** `Level` was nearly deleted by mistake -- it looks like it belongs to the
category enum, and it does, but the six source buckets are still three-to-three across it and that is a real
distinction about provenance.

## Step 3 is much smaller than this document first said, and the correction matters

**Two claims of mine from the step-2 report were wrong, and the measurement is what killed them.**

**1. "Eleven names are waiting for data."** Ten of them are not waiting for anything. Section 4.2's shapes are
answered in the library already; what differs is *which field answers them*. Measured over the whole artifact:

```
Whisk(e)y -> spirit/whiskey      Beer & Cider -> kind beer        Juices  -> kind juice
Gin       -> spirit/gin          Wine         -> kind wine        Syrups  -> kind syrup
Port&Sherry -> wine/fortified    Liqueurs     -> kind liqueur     Sodas   -> kind mixer
```

A family is used **where it refines something**, which is exactly what the proposal's own table shows -- a spirit
gets a family, a syrup does not. `Wine` needs no family; `Port & Sherry` does, and has one.

**2. The library is not short of ingredients.** It is short of *demand* for them:

| | |
| --- | --- |
| Ingredients a recipe names but the library lacks | **0** |
| Ingredients used by exactly one recipe | 57 |
| Used by two or three | 31 |
| Used by four or more | 33 |
| **Used by no recipe at all** | **68** |

**Two-thirds of the library exists to serve the recipes and a third of it serves nothing**, because it was derived
*from* those recipes and the derivation kept every item of every drink. That is not a defect in the data -- it is
what "derived from 103 recipes" produces -- but it does mean **"add more ingredients" is not the fix for anything.**
The fix, if anything, is on the other side: the reader can now write recipes, and 68 ingredients are waiting for
someone to use them.

## So what step 3 actually is

**One name, and one kind.** Checked against section 4.2's twenty-four shapes one at a time:

**Twenty-three are held. `Mock Spirits` is the only empty one** -- no ingredient in the library is a non-alcoholic
spirit, and that is the whole of the gap the vocabulary has.

**And it is a `kind`, not a browse grouping.** Section 4.2's own annotation is what settles it: the three groupings
are the ones the document *says* are groupings -- "makeable at home", "preset configurations", "frequency" -- and
`Mock Spirits` is listed among the non-alcoholic substances beside `Sodas` and `Pantry Items`. So the answer is
`kind: 'mockSpirit'`, and the earlier reading of it as a fourth grouping was wrong.

**And the owner decided not to fill it**, on 2026-10-01: *"先不加"*.

**Why that is the right answer rather than a deferral.** A zero-proof spirit is a *product* category -- Seedlip,
Lyre's, Ritual and the rest are brands -- so filling it means either listing brands this project has no
relationship with or inventing generic entries nobody asked for. **And the door is already open on the other
side**: a reader who keeps one adds it themselves through ③, which is exactly what the authored-ingredient family
was built for. Shipping a speculative row to save them one form would be adding data to the library that nothing
uses, which is the *other* finding on this page -- **68 ingredients are already in that position**.

**So `Mock Spirits` stays empty, and it stays empty on purpose.** The vocabulary does not require every name it
writes to be populated; it requires the ones that are to say what they are, and that is now true of all 189.

## And one test was lying, which is the part worth reading

`seed_vocabulary_test` had a case asserting that **every** name section 4.2 writes resolved to a category. It
listed twenty-three names. **The section writes twenty-four**, and the one left out was `Mock Spirits` -- **no
ingredient in the library is one, and none ever was**, so the test could not have passed with it included.

**The name was dropped rather than the claim corrected**, which is the failure mode worth naming: a test that
removes what it cannot satisfy reports coverage it does not have, and it looks exactly like a test that passes.

It is now two sets that have to add up to twenty-four: the shapes the library **holds** (thirteen), and the ones it
**does not** (eleven, each with its reason -- ten are held as a `kind` rather than a family, and `Mock Spirits` is
held as nothing at all). `expect(held + notYetHeld, hasLength(24))` is what stops a name from being quietly moved
back out of the list.

**That eleven-item list is step 3**, handed over rather than rediscovered.

**Nothing is done about it here.** Step 1 is committed and green, and this section exists so that the next person
meets the choice deliberately rather than by discovering two fields that both claim to say what a thing is.

## The plan that follows from this

**The shape is the proposal's**, not a new invention — `docs/proposal-recipes-and-packs.md` §3 asks for two levels:

```
kind        family (optional)      examples
spirit      gin, rum, whiskey      London Dry Gin, Aged Jamaican Rum
liqueur     --                     Cointreau, Campari
wine        vermouth, sherry       Dry Vermouth, Fino Sherry
bitter      --                     Angostura
```

with **the kinds as data rather than an enum**, so a reader can add 茶 or 酊剂 the way they add a pack.

Three passes, in order:

1. **Classify the 142.** Every shipped ingredient gets a `kind`, and a `family` where it refines one. Existing
   categories are *mapped* rather than discarded — `portAndSherry` becomes `wine/sherry` — so nothing already
   recorded is lost.
2. **Retire the empty categories.** Of the 16 declared and unused, several are *browse groupings* rather than
   substances (`itemsYouCanMake`, `theModernBar`, `top25MostUsed`) and the section on `IngredientCategory` already
   says so; those stay for a picker and answer `isBrowseGrouping`. The rest are either filled by step 1 or dropped.
3. **Add what is genuinely missing**, which is the smallest of the three. 189 ingredients derived from 103 IBA
   recipes cover a lot; what they do not cover is what is *not in an IBA recipe* — tea, more bitters, tintures,
   regional spirits.

**A test asserts every shipped ingredient has a kind**, which the proposal already asks for. That is the guard that
keeps the 142 from coming back.
