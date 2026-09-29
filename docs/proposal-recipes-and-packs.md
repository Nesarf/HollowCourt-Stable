# Recipes, folders and ingredient kinds

Proposal, 2026-09-25, from the owner's direction:

> 配方文件夹的相关信息要允许用户自定义，咖啡我是举个例子，后面继续优化的时候再说，还有就是需要完善原料种类。

Three instructions, and the third is the largest one.

## 0. What is already true (measured, not assumed)

| | |
| --- | --- |
| Recipes | **103**, all shipped in `library.json`, all `packId: "official"`, all `extras.source: "iba"` |
| Their grouping | `extras.category` -- the IBA's own three: The Unforgettables 33 / New Era 35 / Contemporary Classics 35 |
| The recipes page | groups by **category** only; `packId` exists in the data and is **not used** |
| Can a user create one? | **No.** The application has exactly two write paths: a bottle (酒窖) and a journal entry (记录) |
| Ingredients | **189**, each `{id, name}` -- and **47 of them also carry a `category`, 142 do not** |
| Those 17 categories | mix two levels: `syrups`, `juices`, `citrus`, `sodas`, `herbsAndSpices` are *kinds*; `rum`, `whiskey`, `gin`, `brandy`, `vermouth`, `portAndSherry` are *families* |

So the taxonomy the owner describes is not a new idea bolted on: **`packId` is already the folder**, and it is
already empty of meaning because everything lives in one pack.

## 1. Folders (`packId`) become real, and the user defines them

A pack is *where a recipe came from*, so it is a thing the reader owns rather than an enum in the code.

```jsonc
{
  "id": "house",              // stable; a recipe refers to this
  "name": "自作酒",            // the reader's own words, in their own language
  "note": "2026 秋, 自己调的",  // optional, free text
  "accent": "#8A5A32",        // optional; a folder can look like itself
  "order": 20,                // where it sits among the folders
  "builtIn": false            // `official` is true and cannot be deleted
}
```

* **Shipped packs** (`official`) arrive with the build and are read-only.
* **User packs** live in the **same local store as the cellar** -- so a release update never overwrites them, which
  is the property that makes this safe to promise.
* The user can **create, rename, describe, recolour, reorder and delete** a pack; deleting one asks what happens to
  its recipes rather than silently orphaning them.
* `extras.source` stays as the *provenance* field beside it, because "which folder is it in" and "whose recipe is
  it" are different questions -- and a 友方酒 folder must be able to say **whose** it is. That is section 15's rule.

## 2. Creating a recipe

The same bottom sheet the cellar already uses for 记一瓶, for the same reason: one shape for one kind of writing.

1. **Name** (and, if wanted, a second-language name).
2. **Folder** -- pick an existing pack or make one without leaving the sheet.
3. **Ingredients** -- search the 189 and any the reader has added; amount and unit per line, the same `amount_row`
   the rest of the application uses.
4. **Method** -- free text with the existing vocabulary offered as suggestions, *not* as a closed list. The owner's
   point about coffee is the general case: a closed list of `shaken / stirred / built` would eventually demand that
   someone shake a pour-over.
5. **Glass, ice, garnish** -- likewise suggested rather than required.
6. **Save**, into the pack chosen.

User recipes are the **same record shape** as the shipped ones (`id`, `name`, `items`, `method`, `glass`, `ice`,
`packId`, `extras`), which is what lets one page hold both and one search find both. They are editable and
deletable; shipped recipes are not.

## 3. Ingredient kinds

The 142 unclassified ingredients are the actual work here, and the fix is the same two-level shape the recipes are
getting -- because the same mistake was made in both places:

```
kind        family (optional)      examples
----------  ---------------------  ------------------------------------------
spirit      gin, rum, whiskey      London Dry Gin, Aged Jamaican Rum
liqueur     --                     Cointreau, Campari
wine        vermouth, sherry       Dry Vermouth, Fino Sherry
beer        --                     Lager
juice       citrus, fruit          Lime Juice, Pineapple Juice
syrup       --                     Gomme, Orgeat
bitter      --                     Angostura
dairy       --                     Cream
spice       herbs                  Nutmeg, Mint
garnish     --                     Olive, Cherry
pantry      --                     Sugar, Egg White
```

* **Every** ingredient gets a `kind`; `family` is optional and refines it.
* The kinds are **data, not an enum**, so a reader can add one ("茶", "酊剂") the same way they add a pack.
* Existing categories are mapped rather than discarded: `portAndSherry` becomes `wine/sherry`, and so on.
* A test asserts every shipped ingredient has a kind -- the same guard style as the materials.

## 3b. Prices, cost and profit

Owner's instruction, 2026-09-25: *所有配方都要允许自定义售价等信息，方便用户知道对应配方的利润*.

**All** recipes -- including the 103 shipped ones -- because a profit is a fact about the reader's bar, not about
where the recipe came from. Measured first, and the measurement is the reason this is a section rather than a
field: there is **no price anywhere in the application today** -- not on a recipe, not on an ingredient (they are
`{id, name}` and nothing else), and the cellar's bottles record a volume and an ABV but not what was paid.

### The arithmetic, and where each half comes from

```
unit cost of an ingredient = what the bottle cost / how much was in it
cost of a recipe          = sum(amount used * unit cost)   + a per-serving allowance, if the reader wants one
profit                    = price charged - cost
margin                    = profit / price
```

**The left half already has a home.** The reader records bottles in the cellar -- that is the application's oldest
write path, section 8 -- so one more field on that sheet (what was paid) turns the cellar into the cost basis, and
does it the way a bar actually costs a pour: bottle price over bottle volume. A reader who has priced their gin
gets the cost of every gin drink without typing anything twice.

An ingredient with no price is **not an error and must not be hidden**: a recipe then reads `成本 12.40（3 种原料未标价）`
rather than a number that looks complete. A costing feature that quietly treats an unpriced ingredient as free is
worse than no costing feature, because its output is believable.

### What is stored, and what is never stored

| | |
| --- | --- |
| Shipped | **nothing about money.** The 103 keep their attribution and gain no prices; a shipped price would be wrong in every market it shipped to |
| The reader's file | bottle prices (on the cellar's own records), per-recipe prices, an optional manual unit cost per ingredient, a per-serving allowance, and the currency |
| Where | beside `cellar.ndjson`, on the same rule: an update never overwrites it |

### Currency, and honesty about it

One currency, chosen by the reader, defaulting to ¥ -- because a bar has one till. Numbers are formatted with the
reader's chosen symbol and **never converted**: this application has no exchange rates and will not invent them.

Derived costs are labelled as derived. A bottle's price divided by its volume is an estimate the moment somebody
pours a double, which is exactly why the manual override exists and why the derived number says where it came from.

### Where the numbers appear

* **On a recipe**: cost, price, profit, margin -- and the ingredients that are missing a price, named.
* **On a folder**: the pack's own summary, so "自作酒 makes 62% and the IBA list makes 41%" is a thing a reader can
  see rather than compute.
* **Sorting**: by profit and by margin, beside the existing sort orders -- the question "what should I push
  tonight" is the one this feature exists to answer.

## 4. Order of work

Each step is useful on its own, which is the point of the order:

1. **Packs as the first level.** The model, the local store, and the recipes page grouping by pack then category.
   Visible immediately, and it is what the owner asked to see first.
2. **The recipe creation sheet**, with folders creatable from inside it.
3. **Ingredient kinds**: the two-level taxonomy, the mapping of the 17 existing categories, and the guard test.
4. **Prices and profit**: a price field on the cellar's bottle sheet first (it is the cost basis and the smallest
   visible step), then per-recipe prices, then the recipe and folder summaries and the two new sort orders.
5. **Deferred, by the owner's own instruction**: anything coffee-specific. It is an example, not a requirement.

## 5. What is not proposed

* **Not a fixed list of folders.** 咖啡 was an example; so are 自作酒 and 友方酒. The folder set is the reader's.
* **No cloud, no account.** The store is a file beside the cellar's, which is also what makes 升级不覆盖 true.
* **No change to the shipped library's read-only-ness.** The 103 stay exactly as they are, IBA attribution and all.
