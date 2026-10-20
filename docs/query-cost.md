# What a fold costs, and why there is no cache

Written 2026-10-11, answering stage ⑤ of `docs/catalogue-and-stock.md` -- *"and a database, if ever, last"* -- which
names its own gate:

> what a database would eventually fix is *query* cost -- **which is measurable**.

This is the measurement. The script is `tool/query_cost.dart` and it is kept so the question can be asked again with a
number rather than an opinion.

## The numbers

`dart run tool/query_cost.dart`, on the development machine, one process, warmed first:

```
  events   total ms   per fold ms        all eight folds, as `Cellar.of` builds them
      11       0.36          0.04        <- the cellar this application actually has
      40       0.59          0.07
     366       2.77          0.35
    1454       7.17          0.90
    7254      11.85          1.48
   36254      45.86          5.73        <- 5,000 bottles, four pours each, a decade of daily use
```

**The first number is the one that decides it.** `docs/archival.md` and the review both measured the working log at
**1.6 KB and eight events after three weeks**, which is the row above: **0.36 ms to rebuild every fold in the
application from scratch.**

And it is **linear** -- 2.7 µs per event for all eight -- so the cost only matters where nobody lives. A cellar of
five thousand bottles poured from four times each is 36,254 events and **46 ms**, paid once per write and once per
provider rebuild rather than per frame.

## Where it goes, because the answer is not "the folds are slow"

```
AT 36254 EVENTS -- one fold at a time
  StockLedger.of           30.05 ms
  Overlay.of               22.15 ms
  ShelfLayout.of            3.28 ms
  RecipeBook.of             3.51 ms
  IngredientBook.of         0.93 ms
  RecipeCollections.of      0.75 ms
  PackBook.of               0.54 ms
  ShelfBook.of              0.54 ms

WHERE A FOLD GOES
  filter, then sort                 6.35 ms
  filter only                       1.43 ms
  sort once, filter eight          13.75 ms
```

**Nine tenths of a fold is its sort.** Each of the eight filters the whole event list and then sorts what it kept, so
a single read of the cellar sorts the same list eight times.

## Why it was left alone anyway

**Because removing it costs more than it saves, and the currency is not milliseconds.**

The obvious fix is to sort once in `Cellar.of` and let the folds trust their input. It would be about a threefold
saving at the size where the saving does not matter, and it would replace a **fold's own invariant** with a caller's
promise. The sort is not tidiness: a merged log holds a peer's events interleaved with local ones, and *"a write that
replaced a value has to be applied after the write it replaced however the arrivals happened to land"* is the rule
that makes two devices agree. A fold that stopped sorting would be correct exactly as long as every caller remembered,
and **wrong silently** the first time one did not -- in a log that merges from peers and from packages, which is the
whole design.

That is the same trade `overlay.dart` refuses when it says a compacted log *"would need the tombstone kept, and the
day someone adds compaction is the day this paragraph stops being true"*: an invariant that costs nothing today and
cannot be re-derived once it is gone is worth more than a factor that only appears at a size nobody reaches.

## And a database

**No, and the numbers above are the reason rather than a preference.** A database would be a *second* store of the
same facts, which every design decision in this project has refused: the log is the only truth, the folds are
functions of it, and `Cellar.of` exists so that two folds cannot come from different generations of one log. Trading
that for 0.36 ms would be trading the property the application is built on for nothing at all.

**What would change the answer is a number, not a taste.** If the working log ever reaches the tens of thousands of
events, the row above says what it will cost, and the first thing to try is still not a database -- it is asking why
eight folds are needed for one screen.

## What would actually be slow, and is not measured here

**The seed**, which is 253 KB of JSON -- 129 KB of `library.json` and 124.5 KB of `names.json` -- and is loaded once
per launch. It never changes, so it is not a query cost and a database would not touch it; `docs/catalogue-and-stock.md`
records the measurement. If a launch ever feels slow, that is where to look, and this file is deliberately not a claim
about it.
