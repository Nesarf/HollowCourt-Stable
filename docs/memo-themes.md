# Memo: the light worlds, and the collision already scheduled

Written on 2026-10-01, from an owner's note that arrived before the work rather than after it:

> *「米白色的那个主题可能和我后续版本规划的宇宙拿铁的主题有冲突，这个写到备忘录里」*

## Settled 2026-10-01: 白庭 is deleted and `CL` takes its place

**The owner chose "delete 白庭 and add `CL`"** over renaming one into the other, and over shipping both. So
`whiteCourt` is gone from `HollowPaletteValue.all` and **`cosmicLatte` stands where it stood** -- same ornament
(a guilloche), same texture (laid paper), same dark ink, and the ground is the measured `#FFF8E7`.

**The rest of the palette was carried over unchanged, and that is a measurement rather than a shortcut.** The new
ground is lighter than the old one in every channel and the ink here is dark, so every contrast ratio this room had
either holds or improves; the light-mode rules section 12.9.1 argues for are still exercised by exactly one world,
which is the guarantee the replacement had to preserve. **Deleting 白庭 without standing `CL` in its place would
have left the application with no light theme at all**, which the old comment on that test called a worse state
than a duplicate.

**And a stored setting naming `whiteCourt` now falls back to the default**, because a world's `name` is its wire
format. That is the cost of deletion as opposed to a rename, and it is the one the owner chose with the trade
visible.

**The chip reads `宇宙拿铁 J1407b-FFF8E7`**, carrying the colour the way the version name does -- so a person
looking at the theme list can tell which ground the light world is without opening it.

## The collision

Two worlds are meant to be the light ones, and the distance between them is small enough to be a problem.

| World | Build | Ground | Where it is recorded |
| --- | --- | --- | --- |
| **白庭** (`whiteCourt`) | **deleted 2026-10-01** | `#F4F1E9` | gone |
| **`CL` — 宇宙拿铁** | **`48000`, not yet built** | **`FFF8E7`** | `docs/TODO.md` §八 |

**Those are the same colour to a reader.** Both are near-white creams; the difference is four points of red, seven
of green and two of blue — under 1% each. Side by side they are distinguishable; **one after the other, in two
different builds, they are not.** A person who chose 白庭 because they wanted the light world would be handed what
looks like the same light world under a new name, and would reasonably conclude the theme switch does nothing.

**Why this only became visible now.** 白庭 (`#F4F1E9`) was built as a light world with a warm cast, and it is
recorded as *ivory*: 「**there are two kinds of ivory**」 in section 12's own words, which is the distinction it was
drawn to make against the amber world rather than against a future one. `CL`'s colour came later, chosen from a
different direction — `FFF8E7` is **cosmic latte**, the average colour of the light of the whole sky, and the name
`J1407b` is an exoplanet. Neither choice is wrong. **They were made a month apart and nobody put them next to each
other**, which is exactly what a memo is for.

## What is not decided here

**Whether 白庭 moves, changes or stays.** Three shapes, none of them chosen:

1. **白庭 keeps its colour and `CL` differs more.** Cheapest, and it spends the collision rather than solving it —
   `CL`'s whole identity is that specific measured colour, so moving it means the name and the value stop meaning
   the same thing.
2. **白庭 shifts to a colder, bluer light** — a genuinely different light world rather than a second cream. It
   keeps both names honest and needs a full contrast pass, since every light-world rule in
   `test/ui/theme_palette_test.dart` was written against `#F4F1E9`.
3. **One of them is dropped.** The blunt answer, and the only one that cannot fail a contrast test.

**Whatever happens, it has to happen before `48000` is built**, because after that the collision is in a release
that people have installed. **That is the deadline this memo exists to state**, and it is not urgent today: the
build sequence in `docs/TODO.md` §八 puts `44100` and `48000` after `3939`, and `3939` is the current release.

## The rule this suggests, which is worth more than the collision

**A palette is not a swatch.** Two worlds that differ by under a few percent in every channel are one world with
two names, and the existing contrast tests cannot see it: they check that each colour is *readable*, never that two
worlds are *distinguishable*. A guard would be a distance check across the palette list — **and the honest version
of it is a check that two worlds cannot be told apart**, which is a claim about perception rather than about
contrast. It is written here as a candidate rather than a decision, because the threshold would be a guess and this
project does not ship guesses.

## The three colours the owner has now chosen

Also from the same note, and recorded here because this is the file that will be open when the theme list is next
touched:

> *「剩下两个主题，我希望用橡木桶和群青这两个颜色，然后加一个酒红色」*

| Intended world | Colour named | Note |
| --- | --- | --- |
| **橡木桶** (oak barrel) | a barrel brown | **the third brown-leaning world**, after 琥珀庭 `#16110A` — must be separated from it as carefully as 白庭 and `CL` need separating |
| **群青** (ultramarine) | a deep blue | the first blue that is not 冬庭's `#0D1418` near-black — plenty of room, but 冬庭's accent `#8FBAC6` is already blue and needs checking against it |
| **酒红** (wine red) | a wine red | new; the palette's only red today is `rose`, which is an *accent* rather than a ground |

**Which build numbers they take is not decided**, and `docs/TODO.md` §八 currently assigns themes only to `3939`
and `48000`. Three worlds need three entries in that table, or one build that carries all three — that is the
owner's call, and the table is where it goes.

**Nothing here is in the code.** No palette has been added, and 白庭 is unchanged.

## Measured afterwards, and it moves the worry

The note above was written from the colours as named. Then the distances were measured, and **the collision the
owner predicted is not the tightest one in the shipped application** — it is only the tightest one between two
*light* worlds.

Ground colours, Euclidean distance in RGB:

| Pair | Ground distance |
| --- | --- |
| **冬庭 vs 永遠の歌姫** | **5.0** |
| 白庭 vs `CL` | **13.2** |
| 永遠の歌姫 vs 琥珀庭 | 15.9 |
| 琥珀庭 vs 冬庭 | 16.9 |

**So three worlds already ship with grounds as close as, or closer than, the pair that has not been built yet.**
「底色太近」is the established condition of this palette rather than a fault introduced by `CL`.

**And what separates them is not the ground.** The three dark worlds are told apart by their accents, and those
are far apart:

| Pair | Ground | Accent |
| --- | --- | --- |
| 琥珀庭 vs 冬庭 | 17 | **161** |
| 冬庭 vs 永遠の歌姫 | 5 | 87 |
| 琥珀庭 vs 永遠の歌姫 | 16 | 212 |

**琥珀庭 and 冬庭 have nearly the same ground and are the easiest pair in the application to tell apart**,
because what a reader sees is a whole screen of ground *plus* gold or ice-blue. **The test that matters is
therefore the pair (ground, accent), not the ground alone** — and the accepted floor is already set by what
ships: a ground distance of 5 is shipped, and it works, because the accents differ by 87.

**`CL` is where the real risk is, and it is not the ground.** Its accent has not been chosen.
白庭's is `#876A29`; **if `CL`'s is a warm gold too, that pair will be the tightest in the application on both
axes at once** — ground 13 and accent possibly very small. That, rather than the two creams, is the decision
that should be made before `48000`.

### The three new colours, checked against that floor

| Candidate | Nearest existing ground | Distance |
| --- | --- | --- |
| 橡木桶 `#3E2A18` | 琥珀庭 `#16110A` | 49 |
| 酒红 `#5C1F2B` | 琥珀庭 | 79 |
| 群青 `#1B2A6B` | 冬庭 `#0D1418` | 87 |

**All three are further from their nearest neighbour than any two existing worlds are from each other**, so
none of them collides. 橡木桶 is the closest of the three to 琥珀庭, and 49 is nearly three times the widest
current gap — comfortable, and worth keeping in mind only if a *fourth* brown is ever proposed.
