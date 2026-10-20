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

---

## The five worlds, in one place (2026-10-11)

**Written because the same world was carrying three different names in one file**, and because a reader of the source
could not have told which of them was current without opening four others.

### What a world is

A `HollowPaletteValue`: **a ground, a surface and a raised surface; a line and a hairline; a ground texture and an
ornament; an accent (`gold`) and a secondary accent (`rose`); and a [TextColours] group of five named text roles.**
`HollowTheme.build` turns the whole thing into a `ThemeData`, and `HollowPalette.use` is what makes every getter in the
application answer for the world in force.

**Nothing in the interface names a colour literally.** Measured 2026-10-11: the count of `color: Color(0x…)` outside
`theme.dart` is **zero**. That is the property that makes five worlds possible at all.

### The three names a world has, and why they are three

| | What it is | Where it lives | May it change? |
| --- | --- | --- | --- |
| **The identifier** | `honeyed`, `cosmicLatte`, … | `HollowPaletteValue.name` | **No.** It is the key a reader's `display.json` holds, and changing it silently returns them to the default world |
| **The Dart constant** | `HollowPaletteValue.cosmicLatte` | `theme.dart` | Only with a rename, and the two must match -- see the defect below |
| **The name a person reads** | 銅鳴 / 宇宙拿铁 / 群青 / 酒红 / 永遠の歌姫 | `Copy.themeLabelFor` | Freely, and that is the point |

**All three are needed and conflating any two of them is how this file got into the state it was in.** The identifier is
stable and ugly on purpose; the constant is for Dart; the label is prose in five languages.

### The five

| Identifier | Named | Accent | Light? | Told apart by |
| --- | --- | --- | --- | --- |
| `honeyed` | 銅鳴 / Brazen Bell | `#E8C34C` | no | **built out of copper on 2026-10-11** from nine families with pigment identities; its surfaces are a deliberate near-neutral so the five rooms keep their hues |
| `cosmicLatte` | 宇宙拿铁 / Cosmic Latte | `#876A29` | **yes** | the only light room |
| `winter` | 群青 / Ultramarine | `#7FD4E8` | no | **built out of ultramarine on 2026-10-11**; ground `#1B2A6B`, the colour the name has meant since 2026-10-01 |
| `wine` | 酒红 / Wine Red | `#D69B63` | no | **the first whose ground is a colour rather than a near-black**; still `#3A1219`, and the record candidate `#5C1F2B` was never applied |
| `eternalDiva` | 永遠の歌姫 / The Eternal Diva | `#39C5BB` | no | the only one carrying artwork, and no voice is written for it |

### What was retired, and the two things it left behind

**The 庭 taxonomy.** The worlds were once courts -- 琥珀庭, 白庭 -- and the list was retitled when it stopped being one.
Retitling a world is cheap; **retitling everything that referred to it is not**, and two references survived:

* **`Copy.themeWhiteCourt` lived ten days past the world it named.** `白庭` was deleted on 2026-10-01 and `CL` took its
  place; the palette value was renamed to `cosmicLatte` and the copy line was not. The label switch kept matching
  `'whiteCourt'`, so the light world fell through to the id fallback and its chip in 设置 read **`cosmicLatte`** -- a
  camelCase key, in no language. `theme_label_test.dart` now walks `HollowPalette.all` and refuses a label that equals
  a world's own key.
* **`Copy.themeAmber` was named for 琥珀庭**, and the constant kept that name while the world became 銅鳴. It is
  `themeBrazen` now. **No test can see a stale identifier** -- it is only wrong to somebody reading the source, which
  is why this section exists rather than another assertion.

**And one thing that is *not* a leftover, stated so it is not "fixed" later**: `honeyed` is still the identifier of
the world called 銅鳴, and `winter` is still the identifier of the one called 群青. **The identifier is a key, not a
description**, and renaming either would lose the choice of every reader who made it.

### The rules the worlds are held to

1. **Every world has a name in all five languages**, and the label is never the identifier. `theme_label_test.dart`.
2. **Every text role clears its contrast floor** against that world's surface *and* its ground. `theme_contrast_test.dart`.
3. **A world's identifier never changes.** A world may be added or removed; an identifier may not be rewritten.
4. **A theme this build does not carry falls back to the default**, because a setting written by a newer build still
   has to open.

---

## The colours two of them were supposed to be built from, and were not (2026-10-11)

**The owner reported it as a suspicion and the record confirms it**: *「群青主题貌似没用群青色构建......以及铜鸣也是」*.

**A world was retitled and the thing under the name was never recoloured.** That is the same fault as
`Copy.themeAmber` -- the label moved and the value did not -- and this one is worse because it is invisible: a chip
called 群青 over a near-black ground looks like a theme, not like a mistake.

| World | What the record says it is built from | What it is actually built from |
| --- | --- | --- |
| **群青** (`winter`) | **`#1B2A6B`**, a deep ultramarine, from the owner's note of 2026-10-01 | **`#0D1418`** -- which is 冬庭's near-black, 87 RGB units away from the colour it is named after |
| **酒红** (`wine`) | **`#5C1F2B`**, the candidate measured against the palette floor | `#3A1219` |
| **橡木桶** (oak barrel) | **`#3E2A18`**, the third candidate of the same note | **nothing carries it.** No world was built for it |
| **銅鳴** (`honeyed`) | the copper family below | `#16110A` with a gold accent -- the colours of 琥珀庭, which is what this world used to be called |

### The copper family, put here so it cannot be lost a second time

**Given by the owner on 2026-10-11 and recorded verbatim**, because the three colours above survived only as a
sentence in a conversation, and one of them (`#1B2A6B`) is the only reason the discrepancy could be proved at all.
**A palette that lives in chat is a palette that gets lost between two sessions.**

| Name | What it is | Hex | RGB | Pantone |
| --- | --- | --- | --- | --- |
| 红铜 (Red Copper) | 纯铜新切面，偏鲜艳的红橙金属调 | `#C45A34` | 196, 90, 52 | 18-1442 TPG (Bossa Nova) |
| 紫铜 (Purple Copper) | 纯铜自然氧化层，深沉、带紫感的暗红色 | `#8B3A3A` | 139, 58, 58 | 19-1540 TPG (Etruscan Red) |
| 铜 (Copper) | 标准金属铜色，温暖的经典工业质感 | `#B87333` | 184, 115, 51 | 16-1325 TPG (Copper) |
| 亮铜 (Bright Brass) | 抛光黄铜色，明亮偏金黄的高光色调 | `#E1B16C` | 225, 177, 108 | 14-1041 TPG (Golden Rod) |
| 古铜 (Bronze) | 青铜或做旧硫化铜，沉稳的黑褐金属色 | `#755A3F` | 117, 90, 63 | 18-1124 TPG (Bronze) |
| 白铜 (Cupronickel) | 铜镍合金，带有一丝温润暖调的银白色 | `#DDDDDD` | 221, 221, 221 | 12-0000 TPG (White Swan) |
| 铜绿 (Verdigris) | 氢氧化铜/碱式碳酸铜，复古的粉质青绿色 | `#43B3AE` | 67, 179, 174 | 16-5121 TPG (Verdigris) |
| 铜蓝 (Covellite) | 硫化铜矿物色，深邃、神秘的暗靛蓝色 | `#1A2F4C` | 26, 47, 76 | 19-3939 TPG (Blueprint) |

**The last row is worth noticing on its own**: 铜蓝's Pantone is **19-3939**, and `3939` is the build number the
project already assigns to 永遠の歌姫, whose accent is `#39C5BB`. Two different things carrying the same number is a
coincidence unless somebody says otherwise, and this note says it is one.

### What is not decided, and it is a design decision rather than a transcription

**Which swatch is the ground and which are the accents.** A world needs a ground, a surface, a raised surface, a line,
a hairline, an accent and a secondary accent, and the copper family is eight colours for seven roles. **The candidate
reading, offered rather than applied**: 古铜 `#755A3F` or a darkened 铜 `#B87333` as the ground, 铜绿 `#43B3AE` as the
accent (it is the one colour in the family that is not orange, and an accent has to be findable), 亮铜 `#E1B16C` as
the secondary. **That is a proposal, not a decision, and it is not in the code.**


### The copper build, second attempt: what it cost to brighten (2026-10-11)

The owner's decision was to brighten rather than to relax a floor. Two colours were lifted and a third followed, and
**the world still failed four floors**, so it was withdrawn a second time and the numbers are here rather than in a
branch.

| Role | Given | Lifted to | Result |
| --- | --- | --- | --- |
| `line` | 紫铜 `#8B3A3A` | `#CE6B69` | clears 3.0 on all three surfaces |
| `absent` | 铜蓝 `#1A2F4C` | `#6289C0` | clears 3.0 |
| `rose` | 红铜 `#C45A34` | `#DC7A4C` | 3.86 on the ground, then 4.47 on the surface, then **4.00 on `surfaceRaised`**, floor 4.5 |

**Re-measured 2026-10-21 against the surfaces that actually ship.** The two rows above that say "clears 3.0" were
read against that attempt's own surfaces. With `#3A312A` and `#4A4038` -- the values now in `theme.dart` -- `#CE6B69`
reads **3.59 on `surface` and 2.85 on `surfaceRaised`**, and `#6289C0` reads **3.55 and 2.81**. The raised surface is
the binding one for `theme_palette_test`, so neither clears it. What is being refused is not the floor but the
colour: lifting 紫铜 far enough needs `#B37F7F` (35% toward white) and 铜蓝 needs `#828D9D` (45%), where they are a
grey rose and a grey blue. **`tool/copper_check.dart` measures the nine families, not these three roles, so this cell
had never been read again.**

**And the "cheapest answer" has nowhere to land, which the same measurement now shows (2026-10-21).** The line above
that says giving these three colours fill roles is cheapest was written before anything was measured against a role
table. Measured against the nine roles and the three surfaces this world actually draws:

| Colour | on `ground` | worst of the three | `hairline` (must be **under** 1.8) | `line`/`absent` (3.0) | accent as text (4.5) |
| --- | --- | --- | --- | --- | --- |
| 紫铜 `#8B3A3A` | 1.94 | 1.33 | over by 0.14 | no | no |
| 铜蓝 `#1A2F4C` | 1.09 | 1.06 | **fits** | no | no |
| 铜紫 `#70459B` | 2.12 | 1.45 | over by 0.32 | no | no |
| 古铜 `#755A3F` | 2.31 | 1.58 | over by 0.51 | no | no |
| 红铜 `#C45A34` | 3.41 | 2.33 | over by 1.61 | no | no |
| 铜 `#B87333` | 3.89 | 2.66 | over by 2.09 | no | no |
| 铜绿 `#43B3AE` | 5.83 | 3.99 | over by 4.03 | **fits** | no |
| 亮铜 `#E1B16C` | 7.52 | 5.14 | over by 5.72 | **fits** | **fits** |
| 白铜 `#DDDDDD` | 10.87 | 7.43 | over by 9.07 | **fits** | **fits** |

**Six of the eight have no seat at all.** `hairline` is the only role that wants a dark colour, it takes exactly one
value, and 铜蓝 already holds it. The five other dark values are not dark enough for that role either -- its ceiling
is 1.8, because decoration must not compete with text, so 紫铜 at 1.94 is over it as well. On the bright side 亮铜,
白铜 and 铜绿 fill at most three of the four accent seats, and 铜绿 cannot be an accent drawn as text (3.99).

**So "use all eight" is not a choice this palette can express at nine roles.** Either the palette grows two or three
roles that are fills and never text, or the world keeps the three values that fit and the rest stay in this memo as
readings. The shipped palette is the second option, and now with the table that says why.

**Why the palette is not growing roles for them (2026-10-21).** Two fill-only roles would give the six dark values a
seat, and that is the option being declined, for a reason about roles rather than about colours: **a role with no
consumer is a value nobody draws.** No screen in `lib/ui` asks for a fourth fill today -- the three accents and the
hairline are what is actually used. Growing `HollowPaletteValue` to hold two more colours would put two dead values
into all five worlds, and their only justification would be that an eight-colour swatch list exists. If a screen ever
needs a fourth fill, the role gets added then, with a consumer and a floor to meet. Until then the three values that
fit are the world's colours, and `tool/copper_check.dart` keeps the arithmetic for whoever asks again.



**The third one is the finding.** 红铜 is not only a fill: it is drawn **as text** on all three surfaces, and
`theme_palette_test` holds an accent used as text to 4.5:1 against the *lightest* one. A colour that clears it there
needs a luminance of **0.341 or above** -- and at that point it is no longer 红铜, it is a salmon. **Three of the eight
cannot be used at the values they were given, and lifting them far enough to pass stops them being the colours that
were named.**

**And the fourth failure is not about contrast at all.** `materials_test` refuses a colour nudge that would quietly
merge two rooms: a copper ground of `#2B1A0F` sits close to 酒红's `#3A1219`, because **both are warm near-black
browns** -- the exact collision `docs/memo-themes.md` predicted at line 82 when it called 橡木桶 *"the third
brown-leaning world"* and said it would have to be separated as carefully as 白庭 and `CL`. **That prediction was
about the colour family and it holds for 銅鳴 too.**

**So the honest shape of the remaining decision is larger than which swatch is the ground.** Either the copper world
takes a ground that is not brown at all (铜蓝 `#1A2F4C` is the family's only candidate, and it is blueprint blue
rather than copper), or 酒红 or 銅鳴 is moved, or the family's three unusable values are replaced.

### The distance that blocked the copper ground, and the direction that solves it (2026-10-11)

The pair 銅鳴 / 酒红 was put on screen side by side to look at, and **the two are plainly different rooms**: one is a
near-black amber hall with a gold accent, the other is red with a rose accent. **They do not look alike.** So
`materials_test` is not measuring what a reader sees -- **it is measuring RGB distance between grounds**, and that
changes what the copper ground has to be.

| Ground | Distance from 酒红's `#3A1219` |
| --- | --- |
| 銅鳴 as shipped, `#16110A` | **38.6** (passes) |
| the first copper attempt, `#2B1A0F` | **20.4** (refused) |
| 古铜 `#755A3F` darkened to `#4A3524` | **40.5** |
| a saturated copper, `#5A3210` | **46.3** |

**What separates them is the blue channel, and that is the whole finding.** 酒红's ground has blue at 25; the shipped
銅鳴 has 10, and the refused copper had 15 -- so the attempt made the ground *less* distinguishable, because a
near-black copper and a near-black wine both sit at low blue with a warm cast. **A copper ground has to be orange
rather than brown**: `#5A3210` is (90, 50, 16), which is a copper at full chroma rather than at a fifth of it, and it
is nearly as far from 酒红 as the shipped amber is.

**And it is not free.** A ground of `#5A3210` sits at a luminance of 0.045, so ink has to clear 4.5:1 above it -- **a
luminance of 0.378 or more**, which 亮铜 `#E1B16C` (0.487) and 白铜 `#DDDDDD` (0.723) both do and 红铜 and 紫铜 do
not. `surfaceRaised` is the binding surface, as it was for 群青, and that is where the next attempt has to be checked
first rather than last.

**So the third remaining decision is now a smaller one than it was**: the ground does not have to stop being copper,
it has to stop being *dark* copper. The two colours that cannot be lifted far enough to be used as text -- 红铜 and
紫铜 -- still have to be dealt with, and the cheapest answer is to give them roles that are fills rather than text.

### The constraint was the wrong one, and the copper build failed on the right one (2026-10-11)

The third copper attempt cleared **every contrast floor on the first run** -- ink, secondary text, caption text, the
accent-as-text rule on the lightest surface, the separator rule, the decoration rule, and the five text roles. That is
the first time any copper build has done that, and the nine-family scheme with its four steps per family is why.

**It failed on one thing, and the thing is not what three attempts of reasoning had been about.**

    cellar and bar drifted into each other: hue 20.3 degrees, lightness 0.012 apart

`materials_test` does not measure RGB distance between themes at all. It measures **the app's own rooms against each
other**, and a room is apart from another when

    hue gap >= 25 degrees  OR  lightness gap >= 0.06

**Everything reasoned about in this document until now -- "the copper ground has to be far from 酒红's", the blue
channel, the 20.4 that was refused -- was the wrong constraint.** The one that binds is that the cellar and the bar
must be different rooms *within one palette*.

**And the fault is a sentence written into the file as though it were correct**: *the surfaces are the ground lifted
rather than another family's step, because a raised surface is the same room seen closer*. It is the same hue by
construction, eleven thousandths of lightness away, and it is exactly what the rule exists to refuse. **A comment that
argues for the thing a test forbids is worse than no comment**, and this one was written by the same person who had
just spent two attempts failing on a constraint that did not exist.

**So the remaining shape is smaller and clearer than it was**: the copper ground can stay, the nine families can stay,
and `surface` and `surfaceRaised` have to come from **a different hue family** -- which is precisely what the other
eight families are for, and what *「八个交错起来」* meant all along. 古铜 is ten degrees from 铜 and will not do it;
铜紫 and 铜蓝 are a hundred and more, and will.

### A constraint that was invented here, and three builds that paid for it (2026-10-11)

**The owner asked the question that should have been asked three attempts earlier: *「我有说过每个主题之间的底色要隔得远么？」* They had not, and nothing in this repository asks for it.**

`test/ui/theme_palette_test.dart` checks two things about worlds against each other, and neither is a ground colour distance:

    'two worlds are drawing the same ground'      -- the texture must differ
    'two worlds are drawing the same instrument'  -- the ornament must differ

**There is no assertion anywhere about how far apart two themes' grounds are.** `materials_test`'s `_distance` exists, and it measures **rooms inside one palette**, which is where the `20.3 degrees` failures actually came from -- cellar against bar, not 銅鳴 against 酒紅.

**So the number this document insists on repeatedly -- "27.1 from 酒红's ground against 20.4 refused" -- was derived from nothing.** It was inferred from three failures that were all about rooms, and then treated as a requirement. A copper build was **withdrawn on the strength of it**, and two later attempts were designed around it. That is a longer and more expensive version of the mistake this file already records twice: a claim that was never checked, written down as though it had been.

**What is true, and is only now separated out:**

* A world's ground has to be **internally** usable -- dark enough to leave room for five text weights. That is real, asserted, and it is what refused the very first eight-colour attempt.
* The app's **five rooms** have to differ in hue or lightness, and a strongly chromatic theme `surface` collapses them toward its own hue. **That is real, asserted, and it is what every `materials_test` failure was actually about.**
* The distance between two worlds' grounds is **a design preference nobody has stated**, and the shipped palette's closest pair is 5 RGB units apart and works.

**Kept rather than deleted**: the measurements are correct arithmetic about the wrong question, and the next person to reason about themes should see that this exact mistake was made here at length.
