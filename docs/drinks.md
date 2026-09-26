# The user's own drink notes: 45 recipes, and the model they require

**This is the project's first first-party dataset.** Every recipe in `data/sources/`
-- another source's 88, one source's 414 -- belongs to somebody else, and design section 15 says
plainly that the set which eventually ships must be written in-house. These are
written in-house. They are the user's own notes, in the user's own words, and
nothing about them needs a licence.

They are recorded here as **reference, not as seed** -- the user's decision, and
reading them confirms it, because **the current domain model cannot hold them**.

The appendix carries all 45 verbatim.

---

## 1. How they were read

Xiaomi Notes (`com.miui.notes`) on the phone, **read-only**, install untouched.

| Attempt | Result |
| --- | --- |
| `/data/data/com.miui.notes/databases/note.db` | **Permission denied.** No root; `su` does not exist |
| `adb backup` | **Dead.** Deprecated on Android 12+; produced a 47-byte empty archive |
| `content://notes/...` (`NotesProvider` is the declared authority and resolves without a `SecurityException`) | **No rows** to the `shell` uid |
| `uiautomator dump` | **Works for the list, fails for a body** |
| **MIUI local backup + protobuf walk** | **The route that worked** |

The `uiautomator` failure is worth stating precisely: the list gives up titles,
previews and dates as ordinary `text` attributes, and the **body does not**, because
it is an `android.webkit.WebView` marked `NAF="true"` -- *Not Accessibility
Friendly*. **A WebView declaring itself inaccessible is not readable by any
accessibility-driven tool**, which rules out the whole family.

Before that was understood, five bodies were read by `screencap` and decoded
visually. That works, and it is how the format was first seen -- but it captures the
**whole screen including the status bar**, so it is a route for a handful of notes,
not for forty-five.

### What the backup actually is, since none of it is documented

```
AllBackup/20260919_094944.zip
  ├─ descript.xml                      device, rom, package list
  └─ 笔记(com.miui.notes).bak          1,395,265 B
       └─ "MIUI BACKUP\n2\ncom.miui.notes…\n"  ∥  "ANDROID BACKUP\n5\n0\nnone\n"
            └─ tar (uncompressed)
                 └─ miui_bak/_tmp_bak   607,702 B   ← **protobuf, not SQLite**
```

Four things had to be worked out and none of them is written down anywhere:

1. The `.bak` is **two containers stacked**: a MIUI header line-block, then a
   **standard `ANDROID BACKUP` v5** header, then an **uncompressed tar**.
2. **The payload is protobuf, not a database.** There is no table to query. There
   is also no `.proto`, so it was walked **schema-lessly** -- a key is
   `(field number, wire type)`, and every length-delimited field is either a nested
   message or a string; try both, keep what parses.
3. The record map, recovered rather than given:

   | field | meaning |
   | --- | --- |
   | `2` | id (string) |
   | `5` / `6` | created / modified, milliseconds |
   | **`8`** | **body** |
   | `9` | metadata sub-message (10 fields) |
   | **`10`** | **folder name** -- denormalised onto every note |
   | **`14`** | **title** |

4. The body is a small **rich-text dialect**: `<text indent="N">…</text>` per
   line, plus `<b>`/`<i>`, plus `<MiMind Prdfix>{json}` for mind-map notes. The
   mind-map form is **recorded as unknown rather than parsed**, and none of the 45
   uses it.

**One consequence of the backup route that the screenshot route did not have: it
contains the entire notebook.** 295 note records, of which **45 are in the four
drink folders and 250 are not**. The extraction filters on **field 10 before
reading any content**, so nothing outside the four folders is rendered, printed or
written -- and the count of what was skipped is reported by the extractor rather
than left implicit.

---

## 2. The inventory: 45 notes in four folders

| Folder | Count | |
| --- | --- | --- |
| **酒单整合** | **27** | the authored drinks |
| **经典鸡尾酒** | **11** | the classics |
| **咖啡单整合** | 5 | |
| **奶饮单整合** | 2 | |

**An earlier revision of this record said 19.** That number came from reading the
on-screen list, which shows **six rows at a time**, and mistaking the viewport for
the collection. The backup made the real count available: **19 was what fits on a
screen, 27 was what is in the folder.**

**And the four folders are not the same kind of thing:**

- `经典鸡尾酒` is **eleven named classics** -- 椰林飘香, 老式, 尼格罗尼, 螺丝起子,
  曼哈顿, 亚历山大, 新加坡司令, 干马天尼, 玛格丽特, 美国佬, 金汤力 -- a reference
  section.
- The other three are **the user's own inventions**, and the naming is
  unmistakably theirs: 一氧化二氢 (dihydrogen monoxide, as a chemistry joke),
  等待戈多, 楽園図, 纯白交响曲 (`日文：ましろ色シンフォニー`), One Last Kiss,
  是，大臣, 西西弗斯, Ain Soph Aur, 「什亭之匣」.

**A model that cannot tell a reference section from an authored one mis-classifies
eleven of forty-five immediately.**

**And the invented half is not a list of recipes; it is a design practice.** There
are multi-drink series with a shared conceit (`黑魂三系列`, `三色堇系列`,
`生命之树`), themes drawn from games and animation (Needy Streamer Overload, Dark
Souls, Steins;Gate, 极乐净土), a ten-layer Pousse-Café specified by measured
density, and a whole note that is nothing but ratios.

---

## 3. Seven kinds of thing in one folder

This is the first thing an importer has to know, and it is not discoverable from
the another source or one source data, because **those sources are databases and these are
notes.**

| Kind | Example | What defines it |
| --- | --- | --- |
| **Single recipe** | `极乐净土` | ingredients, a method sentence, glassware, garnish |
| **Recipe with addressable ingredients** | `Ain Soph Aur` | ingredients numbered `①`–`⑩`; the process **refers back to them by number** |
| **Series** | `黑魂三系列`, `三色堇系列` | one note holds N drinks under a shared conceit |
| **Layered drink** | `反转大天空`, `生命之树（十层）` | `下层：` / `上层：` are structural, not prose |
| **Rule or ratio table** | `可尔必思应用` | no drink at all: ratios plus a positional default |
| **Design document** | `生命之树（十层）`, `升天/堕天/接地` | prose, tables, an SOP, risks, a plan comparison |
| **Variant by section** | `极乐净土`'s `无酒精版本：` | a second recipe inside the first |

### `Ain Soph Aur` is the most instructive of the 45

```
①伏特加40ml          基本装饰：⑦银色闪粉少许、⑧迷迭香*1
②接骨木花力娇酒25ml   可选装饰：⑨小块干冰*1、⑩白糖霜（杯缘）
③新鲜柠檬汁12ml
④甘蔗糖浆5ml          流程：
⑤橙苦精3～4滴        一、①②③④⑤+冰，摇8秒左右；
⑥苏打水适量           二、⑦撒在杯底，将上"一、"所出之物倒入杯中，再加入⑥；
                     三、依次加入⑨、⑩、⑧。
```

Two things here change the model:

- **The ingredients are an addressable namespace.** The process does not name
  ingredients, it **refers to them by index** -- `①②③④⑤+冰`, `再加入⑥`. So an
  ingredient needs a stable identity that a step can point at, and the order of the
  list is load-bearing.
- **The steps are numbered separately from the ingredients, and they cite each
  other's numbers.** `将上"一、"所出之物` -- a step refers to *the output of step
  one*. That is a **dataflow between steps**, expressed in prose but structurally
  present.

And it splits garnishes into **基本装饰 / 可选装饰**, which the model has one slot
for.

---

## 4. What these break

### 4.0 A correction: this section over-claimed, and reading the model shrank it

**This section was first written from the notes alone, without reading
`lib/domain/`.** Reading it afterwards showed that several of the "gaps" below were
already filled, and some were filled better than the notes assumed:

| Claimed as a gap | What actually exists |
| --- | --- |
| counted units -- dashes, 颗, 串, 份 | **`UnitDimension.count`**, **`UnitKind.discrete`**, and **`RecipeItem.count` as a `Rational`** -- with a comment explaining why four cherries doubled is eight in the spec and four in the glass. `1,5` is handled |
| ratios -- `2:7:1`, `1:12` | **`UnitDimension.ratio`**, with `part` filed under it and a comment on why `part` is not a volume |
| density, mass | **`Mass` in milligrams, `Ingredient.densityGPerMl`, and section 5.4's density bridge** |
| essential vs optional garnish | **`ItemRole.garnish` and `ItemRole.optional`**, scored differently by section 9 |
| "a line that says how to use it without saying how much" | **`UnmeasuredIngredient`** -- `rim of bar sugar`, `rinse of absinthe`. **This is already the right home for `补满`** |
| "the importer must not guess" | **`UnparsedIngredient`**, whose own comment says an importer wants to finish the run, collect every one of them, and report the list |

**So the honest statement is not "the model cannot hold these notes".** It is that
**the model is sound and the grammar is a different one** -- see section 4.5, which
is the most important finding in this record.

### 4.1 What remains, and it is narrower than it first looked

**The project chose integer microlitres.** Sections 5 and 6 are built on it, and the
choice is good: no floating point in the domain, one rounding at the boundary,
`Rational` on `BigInt`. What the notes add to it is less than first appeared.

| As written | What is genuinely missing |
| --- | --- |
| `冰镇汤力水 补满` | a **relative** amount: `UnmeasuredIngredient` is its right home, but the model then has no way to say *what it is relative to* |
| `蓝柑糖浆 2~3drops`, `橙苦精3～4滴`, `1-2球`, `50～60ml` | **a range.** Neither `amount` nor `count` can hold one, and the validator forbids both at once |
| `蓝宝石金 30ml（45ml）`, `干味思 15ml（-）` | **an alternate amount**, and **`-` meaning omit** |
| `南非醉茄粉 ½小匙（约1.5g）`, `黑胡椒 一小撮（约0.3g）` | **a unicode fraction**, and **an approximation** (`约`) carrying its own mass |
| `蜂蜜糖浆（蜂蜜:水 = 1:1）  10ml` | an ingredient **defined inline by its own ratio**, where section 4.2 has only a *category* for makeable things |
| `（Stir之后加入）`, `（先加冰后Stir）` | **order of operations attached to a line** |

### 4.2 And it is not only a quantity problem: two physical axes are missing

`生命之树（十层）` is the note that matters most for this project, because it is
the hardest thing section 12.1 will ever be asked to draw, and **the user has
already worked out the physics.**

```
| 1  | Malkuth | 深红   | 1.22      | 红石榴糖浆     | 原液+少量蜂蜜增重        |
| 2  | Yesod   | 紫红   | 1.16      | 黑加仑糖浆     | 原液+纯水按3:1稀释       |
…
| 10 | Kether  | 透明   | 0.79      | 伏特加         | 选高纯度(40%ABV以上)     |
```

- **Density is a first-class quantity, in g/ml.** A layered drink *is* a density
  ordering; it has nothing to do with volume. **The model has volume and no
  density.**
- **Temperature is a designed axis.** The note assigns a gradient by zone -- 4 ℃
  for layers 1–3, 6 ℃ for 4–7, 8 ℃ for 8–10 -- and states the reason: *低温增加下层
  密度，微温降低上层密度，物理上扩大层间差约0.005-0.01g/ml*. **That is a
  deliberate widening of the physical margin, and the model has no temperature at
  all.**
- **Layer index is identity.** Layer 1 is Malkuth and is deep red; layer 10 is
  Kether and is clear. A layer is not "an ingredient that happens to be first".

**This lands directly on section 12.1.** Its renderer draws liquid with layered
colour, and here is a real, authored, ten-layer stack with measured densities and a
temperature plan -- **the reference case the renderer was going to be judged
against, written by the person who is going to use it.**

### 4.3 And a note is not a recipe

Beyond ingredients and steps, the corpus needs: **method**, **glassware**,
**garnishes split into essential and optional**, **layers**, **variants**, **series
membership**, **a shared rule that belongs to the series and not the drink**,
**prose rationale**, **commentary that must round-trip without being mistaken for
data**, and **alternative designs presented for comparison**.

`三色堇系列` shows the series case cleanly: the note's first line is a rule that
belongs to **none** of the four drinks in it --

> 此类目下的所有咖啡都需要三色堇装饰（摆放位置不做限定，需注意醒目的同时要让客人能够轻松取出）

-- and the rule is not about flavour or appearance. **It is about the guest's
hands**: eye-catching, and still easy to take out.

### 4.4 And the format is not consistent, in ways an importer must absorb

- **Ingredients are written one-per-line in most notes and `、`-separated on one
  line in `黑魂三系列`.** Both are the same field.
- **Steps appear as `Steps：` inline** (三色堇系列) **and as a `流程：` block**
  (Ain Soph Aur) **and as a bare sentence** (极乐净土), and once as a box-drawing
  tree (生命之树).
- **Sections use `***` as a divider** and Chinese numerals as headings (`三、`).
- **Ratings use emoji** (`⚠️` / `✅` / `✅✅`) inside a comparison table.
- **Markdown tables appear inside note bodies.**
- **`H` typo**: `螺丝起子 伏特加 45m` -- real data has them, and an importer that
  silently coerces it to 45 ml is guessing.

**None of this is a criticism of the notes.** A note is what a person writes when
no schema is imposed on them; the inconsistency *is* the specification, and it is
the reason to read the corpus before writing the importer.

---

### 4.5 The finding that matters: it is a different grammar, not a longer one

`lib/domain/parsing/ingredient_phrase.dart` parses ingredient lines, and its own
comment states where its grammar came from:

> The grammar below is not invented; it is read off the 390 lines in the another source
> harvest, which between them use exactly four shapes:
>
> ```
> <number> <unit> of <ingredient>     356   2 oz of rye whiskey
> <number> of <ingredient>             28   1 of cherry
> <word> of <ingredient>                4   rim of bar sugar
> of <ingredient>                       2   of egg
> ```

**Every one of those four is English word order: the number first, and `of` before
the ingredient.** And the user's notes use the opposite:

```
重泥煤威士忌 30ml          ingredient first, amount second, no "of"
Cynar 20ml
橙味苦精 2dashes
冰镇汤力水 补满            ingredient first, then a use-word and no number at all
南非醉茄粉 ½小匙（约1.5g）   a unicode fraction, a Chinese unit word, an approximation
黑胡椒 一小撮（约0.3g）
①伏特加40ml                a circled numeral prefix
伦敦干金酒/柑橘系金酒 30ml    a slash-alternative inside the ingredient name
珠江原浆 330ml（Stir之后加入）  a parenthetical instruction after the amount
```

**So the delta is not "more quantity kinds". It is a second word order, a second set
of unit words, and a set of line decorations the English sources do not have.**

And the parser's own design says what to do about it. Its vocabulary is
**deliberately closed** --

> Kept as a closed set. An unfamiliar word in that position is reported as unparsed
> rather than accepted as a preparation, because accepting anything there is how
> `2 glugs of gin` would become a measurement.

-- and it has an outcome for "I do not understand this" that is a **result, not an
exception**:

> An importer meeting an unfamiliar spelling wants to finish the run, collect every
> one of them, and report the list -- which is more useful than dying on the first,
> and far more useful than guessing and reporting nothing.

**Therefore the correct move is a second grammar beside the first, not a widening of
the first.** Widening the existing regexes to accept a trailing amount would make
every English line ambiguous and would eventually admit `2 glugs of gin` -- the one
failure the file was written to prevent.

### 4.6 And the unit words are a lookup problem, not a new-unit problem

`UnitSystem` already has the units needed, in the right kinds:

| Kind | Units |
| --- | --- |
| absolute | `ml`, `cl`, `l`, `oz`, `tsp`, `tbsp`, `drop` |
| **cultural** (calibratable, `isEstimate`) | `dash`, `barspoon`, `pinch`, `shot` |
| **ratio** | `part` |
| **discrete** (never scaled) | `leaf`, `sprig`, `wheel`, `twist`, `peel`, `cube`, `wedge`, `slice`, `each` |

So Chinese unit words mostly **map onto units that already exist**:

| In the notes | Existing unit |
| --- | --- |
| `ml`, `滴` | `millilitre`, `drop` |
| `小匙`, `大匙` | `teaspoon`, `tablespoon` |
| `小撮`, `适量` | `pinch` / the relative case |
| `片` | `slice` |
| `颗`, `粒` | `each` |

**But `Unit` is matched by `id` only** -- the parser's `_unitFor` loops
`UnitSystem.all` and compares `unit.id == word`. A unit has an `id` and a `symbol`,
and no aliases, so `滴` cannot currently resolve to `drop`. **The addition is an
alias table keyed by word and locale, not a new unit type.**

And five words have **no equivalent at all**: `串` (a skewer of olives), `球` (a
scoop of ice cream), `根` (a stick of cinnamon), `份` (a portion -- and a portion of
espresso is culturally a volume), `若干` (some, with an example in parentheses).
Those are new discrete units, and `份` deserves an argument before it becomes one.

---

## 5. What this means for the design document, stated but not decided

Three sections are affected and none is changed here -- the decision is the user's:

| Section | Currently | Implied |
| --- | --- | --- |
| **5 / 6** -- integer microlitres | one numeric type, round once | **not** a replacement: the integer stays the base, and a **narrow** set of extra forms sits beside it -- relative, ranged, alternate, approximated |
| **6** -- the recipe model | ingredients and quantities | plus layered structure with density and temperature, variants, a series level with its own rules, and items that steps can cite by number |
| **12.1** -- liquid rendering | `LiquidColour`, layered colour | **density and temperature are inputs**, not decoration: a level the renderer was not given must be derivable from the glass, and a layered drink is ordered by physical property rather than by authoring order |
| **12.3** -- browsing | four tabs | a folder above the recipe, a series between the folder and the drink, and a **reference half beside an authored half** |
| **5.2 / 5.3 units** | three kinds, closed vocabulary | an **alias table keyed by word and locale**; the kinds do not change |

**And a note on fidelity:** an importer that normalises on the way in **destroys the
evidence that the schema is wrong.** These are recorded verbatim, including the
spacing and the two different tilde characters.

---

## Appendix: all 45, verbatim

Generated from the backup by `tools/`-adjacent scratch code, not retyped -- the bodies, the spacing and the punctuation are as they are in the notes. Created / modified dates are the device's local dates.

Fence length is 3 because the corpus contains backticks.


### 酒单整合 -- 27 notes


#### [327] 你觉得你是燃油饮吗？

*created 2026-09-01 · modified 2026-09-07 · 13 lines*

```
重泥煤威士忌 30ml

Cynar 20ml

红味美思 15ml

橙味苦精 2dashes

上述加冰摇匀，滤出

（点燃）151朗姆 15ml

半个完整橙皮，用以承装151朗姆。
```


#### [316] 一氧化二氢

*created 2026-07-26 · modified 2026-07-26 · 22 lines*

```
伦敦干金酒 45ml

冰镇无糖椰子水 30ml

冰镇汤力水 补满

蓝柑糖浆 2~3drops

柯林杯（可以加一条长冰然后叫做Ice Water）

——————————————————
变体：氯化钠注射液

伏特加/金酒 45ml

西柚汁 60ml

海盐水（盐水比1:1） 5ml

盐渍橄榄 1串（2颗）

柯林杯，粗盐粒边装饰（问就是SD上身了）
```


#### [303] Trancing Time

*created 2026-07-14 · modified 2026-07-22 · 11 lines*

```
珠江原浆 330ml（Stir之后加入）

荔枝力娇 20ml

红石榴糖浆 10ml

柠檬汁 10ml

Stir

啤酒杯，加冰（先加冰后Stir）
```


#### [313] 华沙

*created 2026-07-22 · modified 2026-07-22 · 13 lines*

```
雪树伏特加 50ml

樱桃力娇 15ml

蜂蜜糖浆（蜂蜜:水＝1:1） 10ml

橙味苦精 2dashes

Shake

蝶形杯，橙皮扭花、黑樱桃装饰

Na Zdrowie
```


#### [247] 生命之树（十层）

*created 2026-03-13 · modified 2026-07-20 · 71 lines*

```
| 1 | Malkuth | 深红 | 1.22 | 红石榴糖浆 | 原液+少量蜂蜜增重 |
| 2 | Yesod | 紫红 | 1.16 | 黑加仑糖浆 | 原液+纯水按3:1稀释 |
| 3 | Hod | 翠绿 | 1.10 | 绿薄荷利口酒 | +10%单糖浆(1:1)增重 |
| 4 | Netzach | 宝蓝 | 1.05 | 蓝橙利口酒 | +5%单糖浆微调 |
| 5 | Tiferet | 淡紫 | 1.00 | 紫罗兰利口酒 | 原液(标准密度) |
| 6 | Gevurah | 淡紫灰 | 0.95 | 薰衣草利口酒 | +5%伏特加减重 |
| 7 | Chesed | 鹅黄 | 0.90 | 接骨木花利口酒 | +10%伏特加减重 |
| 8 | Binah | 橙黄 | 0.86 | 君度 | +15%伏特加减重 |
| 9 | Chokmah | 透明 | 0.91→0.83 | 金酒 | +20%伏特加减重(注意需重新校准) |
| 10 | Kether | 透明 | 0.79 | 伏特加 | 选高纯度(40%ABV以上) |

搜索结果提到"冷液体更稠密更稳定"，建议所有材料冷藏。我进一步设计温度梯度：
- 第1-3层（高密度糖浆区）：4℃冷藏
- 第4-7层（中密度利口酒区）：6℃冷藏
- 第8-10层（低密度烈酒区）：8℃微回温
低温增加下层密度，微温降低上层密度，物理上扩大层间差约0.005-0.01g/ml，相当于为密度差"加保险"。

杯型：Pousse-Café专用分层杯，口径4cm，高15cm，直壁
总容量：60-70ml（每层6-7ml）
预冷：-5℃

策略4：工具精密化分层注入
搜索结果详述了吧勺引流法，对十层挑战需升级工具组合：
1. 螺旋长柄吧勺：每层更换或用纯水冲洗，避免交叉污染
2. 精密注酒器（针管/滴管）：搜索结果明确推荐"滴管/针管处理上层微量液体"，第8-10层用1ml注射器精准注入
3. 流速控制：≤0.5ml/秒（比原方案的1ml/秒更慢），液体应"如丝绸滑落"
4. 静置时间：每层注入后静置20秒（原方案15秒），待界面稳定
策略5：界面稳定剂（备选进阶）
若纯液体方案仍不稳定，可在层间注入0.3mm极薄琼脂凝胶层（0.1%浓度，几乎无色无味）。这会略微牺牲"纯液体"的纯粹性，但能100%保证物理隔绝。此为高端定制选项，可作为"完美版"与"标准版"的双轨供应。
***
三、标准化操作SOP
1. 预处理（出品前2小时）
   ├─ 所有母液用密度计校准
   ├─ 分三组温度区冷藏(4℃/6℃/8℃)
   └─ 杯具冷冻至-5℃

2. 分层注入（出品时，预计8-10分钟）
   ├─ 第1-3层：直接倒入+吧勺引流，每层静置20秒
   ├─ 第4-7层：吧勺引流，流速0.5ml/秒，静置20秒
   └─ 第8-10层：1ml注射器滴注，沿杯壁缓流，静置30秒

3. 品控检查
   ├─ 侧面观察界面清晰度（无雾状过渡带）
   ├─ 若有轻微混合，用吧勺深入界面滴入高密度液体下压修复
   └─ 合格后方可出品
***
四、风险控制与备选方案
风险1：制作耗时过长
吉尼斯纪录显示十层鸡尾酒耗时一小时，即便优化后仍需8-10分钟/杯。建议：
- 限量供应：每日限10杯，预约制
- 预分层母液：提前调配好10种密度母液装于滴瓶，出品时仅做注入
风险2：颜色失真
密度调整（加糖浆/伏特加）可能稀释颜色。对策：
- 选用高浓度食用色素微调色泽（如第5层紫罗兰加微量蓝色素保持淡紫）
- 优先选择本身颜色浓郁的原料品牌（如Tempus Fugit紫罗兰利口酒色泽饱和）
风险3：酒精度失衡
上层多次添加伏特加减重可能导致整体过烈。对策：
- 每层总量严格控制在6ml
- 总酒量约30-35ml（相当于一杯标准短饮），提供慢饮指南：建议分10口，每口对应一层源质
***
五、方案对比与推荐
| 方案 | 层数 | 稳定性 | 制作时间 | 文化还原度 | 推荐场景 |
|------|------|--------|---------|-----------|---------|
| 原方案 | 10层 | ⚠️ 低 | 8分钟 | 100% | 不建议量产 |
| 密度重构版（推荐） | 10层 | ✅ 高 | 10分钟 | 95% | 限定高端供应 |
| 凝胶界面版 | 10层 | ✅✅ 极高 | 15分钟 | 90% | 展示/比赛用 |
| 精简5层版 | 5层 | ✅✅ 极高 | 5分钟 | 70% | 常规菜单供应 |
***
总结
十层稳定分层的本质是**"密度工程"**：将0.01的临界差扩大至0.04以上的安全区间，辅以温度梯度、窄口杯具、精密工具三重保障。这套方案保留了原酒单"十层十异"的文化与视觉完整性，将理论设计转化为可复制的出品标准。建议先以"密度重构版"为主推，搭配5层精简版作为日常供应，既守住文化深度，又保障运营效率。
«可查看搜索来源获取分层技法的完整教学视频与常见失误排查指南，以及吉尼斯十层鸡尾酒纪录的参考细节。»
```


#### [304] 特制初星萃取

*created 2026-07-18 · modified 2026-07-18 · 29 lines*

```
伦敦干金酒/柑橘系金酒 30ml

橙汁 60ml

树莓汁 30ml

蓝柑力娇 10ml

蔗糖糖浆5ml

橙味苦精 2滴

（可选）气泡水 10ml 或 甜味苏打水 补满

Stir

（个人认为搞个贴纸啥的挺好）
————————————————————
橙汁 90ml

树莓汁 45ml

蓝柑汽水 30ml

蜂蜜 10ml

柠檬汁 5ml

Stir
```


#### [302] 红色电音·极地大冲击

*created 2026-07-14 · modified 2026-07-14 · 11 lines*

```
波本威士忌 30ml

白橙皮力娇 15ml

柠檬汁 30ml

红石榴糖浆 2滴

Shake

冰威士忌杯，加冰
```


#### [249] ギリギリボーダーライン

*created 2026-03-13 · modified 2026-07-10 · 24 lines*

```
蓝柑力娇 20ml

伏特加 45ml

新鲜柠檬汁 15ml

蔗糖糖浆 10ml

苏打水 30ml

食用银粉 适量

柠檬片 1片

Steps：
①沿杯壁倒入蓝柑力娇。

②缓慢沿杯壁倒入伏特加。

③加入柠檬汁与蔗糖糖浆，用吧勺轻搅杯底至酸甜平衡，注意避免破坏分层。

④沿杯壁倒入苏打水至杯口1cm处。

⑤在杯口边缘撒食用银珠，最后斜插柠檬片，完成制作。
```


#### [245] 极乐净土

*created 2026-03-13 · modified 2026-07-03 · 8 lines*

```
灰雁伏特加 45ml
君度橙味力娇15ml
芒果汁 50～60ml
蔓越莓汁 40～50 ml
以上原料，装入摇壶加冰摇匀，滤出酒液，倒入加冰的长饮杯中。

无酒精版本：先加入芒果汁和蔓越莓汁各70～90ml，再加入10ml的金桔糖浆/黄柠檬汁，加冰摇匀，倒入放有冰块的长饮杯中，再加入甜味无汽苏打水补满，总液量200ml以上。

```


#### [258] 骑士的身前身后"Il cavaliere: il fuori e il rientro"

*created 2026-03-27 · modified 2026-07-03 · 21 lines*

```
托斯卡纳红酒500ml

肉桂棒 2根

生姜片 10g

丁香 5-6粒

小豆蔻 3粒

干薰衣草花 1小匙

紫罗兰花瓣 少许

玫瑰花瓣干 1小匙

蜂蜜40g

肉豆蔻 少许

上述香料与蜂蜜，放入托斯卡纳冷浸48小时，将酒液滤出微热到常温即可饮用
```


#### [294] 「什亭之匣」（シッテムの箱）

*created 2026-07-03 · modified 2026-07-03 · 15 lines*

```
伏特加40ml

蓝橙力娇酒15ml

接骨木花利口酒10ml

薰衣草糖浆5ml

上述原料加冰混合摇匀，过滤倒入杯中后，加入苏打水至八分满（或根据实际情况适量添加）

预处理杯具：杯壁内侧用柠檬汁轻擦后撒上食用银箔，静置晾干

（可选）装饰：食用级干冰5g，在苏打水之前放入杯底

装饰：薄荷叶*1、蓝莓（或洛神花/覆盆子）*1
```


#### [250] Ain Soph Aur

*created 2026-03-14 · modified 2026-07-03 · 14 lines*

```
①伏特加40ml
②接骨木花力娇酒25ml
③新鲜柠檬汁12ml
④甘蔗糖浆5ml
⑤橙苦精3～4滴
⑥苏打水适量

基本装饰：⑦银色闪粉少许、⑧迷迭香*1
可选装饰：⑨小块干冰*1、⑩白糖霜（杯缘）

流程：
一、①②③④⑤+冰，摇8秒左右；
二、⑦撒在杯底，将上“一、”所出之物倒入杯中，再加入⑥；
三、依次加入⑨、⑩、⑧。
```


#### [246] 生命之树（三层）

*created 2026-03-13 · modified 2026-07-03 · 22 lines*

```
红石榴糖浆 20ml

君度橙味力娇 30ml

迷迭香糖浆 10ml

紫罗兰力娇 40ml

新鲜迷迭香 1枝

红樱桃 1颗

Steps：
①冰古典杯

②将红石榴糖浆直接倒入杯底

③将君度与迷迭香糖浆提前加冰摇匀，然后沿吧勺背面缓缓倒入杯中

④沿勺背缓缓倒入紫罗兰力娇

⑤将迷迭香轻放于紫罗兰层表面，最后放置红樱桃，完成“生命之树（三层）”的制作。
```


#### [293] 黑魂三系列

*created 2026-07-03 · modified 2026-07-03 · 62 lines*

```
① 环印骑士直剑
黑朗姆酒 45ml、查特酒 15ml、黑刺梅金酒 15ml、橙味苦精 3滴、151金朗姆 15ml 点燃。

②月光大剑
孟买蓝宝石金酒 50ml、蓝柑力娇 15ml、接骨木花力娇酒 10ml 、青柠汁 15ml 、椰奶 15ml、食用银粉 少许 。

③雷多大锤
波本威士忌 50ml、卡鲁瓦咖啡力娇 20ml、黑可可力娇 10ml、单糖浆 10ml、浓奶油 20ml、肉豆蔻粉 少许 撒在顶层。

④濡湿小镰刀
梅斯卡尔 40ml、黑朗姆20ml、黑樱桃力娇5ml、柠檬汁8ml、苦艾酒 5滴、蛋清 1个、公丁香 3颗。

⑤半叶大刀
焙茶金酒 45ml、干味美思 15ml、柚子汁 20ml、蜂蜜糖浆 10ml、紫苏叶 2片 揉搓。

⑥老ASS
陈年朗姆酒 45ml、杜林标力娇 15ml、费内特布兰卡 10ml、浓缩咖啡 20ml、伯爵红茶糖浆8ml、橙味苦精 3滴、烟熏海盐溶液 少许 杯口、肉桂棒 1根 点燃。

⑦教宗骑士曲剑
绝对伏特加 45ml、紫罗兰力娇 15ml、白可可力娇 15ml、柠檬汁 15ml、蛋清 1个。

⑧哈兰德大曲
重泥煤威士忌 40ml、金巴利 20ml、甜味美思 20ml、黑樱桃糖浆 10ml、橙味苦精 2滴。

⑨黑暗剑
健力士黑啤 半品脱 后加、黑刺李金酒 44ml 、诺迪斯22ml、咖啡力娇 22ml、黑巧克力碎 少许、黑樱桃力娇 11ml。

⑩法兰大剑
苏格兰威士忌 45ml、杜林标力娇 15ml、意大利苦杏酒 10ml、橙味苦精 3滴、迷迭香 1枝 燃烧。

⑩①盖尔大剑
田纳西威士忌 50ml、甜苦艾酒 15ml、重泥煤威士忌5ml、血橙汁 25ml、黑刺李果酱 1.5茶匙、橙味苦精 3滴。

⑩②芙莉德大镰刀
白朗姆酒 40ml、佩罗南茴香酒 10ml、椰子奶油 10ml、白可可力娇 10ml、接骨木花糖浆 5ml。

⑩③古达的戟
黑麦威士忌 50ml、干味美思 15ml、陈年查特酒 10ml、橙味苦精 2滴、烟熏海盐溶液 少许 杯口。

⑩④连射弩
伏特加 40ml、野格 20ml、汤力水 加满 、青柠汁 15ml、跳跳糖 少许 杯口。

⑩⑤宠爱戒指
百香果力娇 30ml、桃味伏特加 40ml、蜂蜜糖浆 15ml、柠檬汁 10ml、蛋清 1个、食用金粉 少许。

⑩⑥人松脂
龙舌兰酒 45ml、黑刺李金酒 25ml、紫罗兰力娇15ml、葡萄汁 10ml、焦糖粒 少许 杯口。

⑩⑦小零食
梅斯卡尔 30ml、咖啡力娇 20ml、黑巧克力酱 15ml、伯爵红茶糖浆 10ml、浓缩咖啡 15ml、可可粉 顶层 厚撒。

⑩⑧踹哈
黑麦威士忌 50ml、野格 20ml、费内特布兰卡 10ml、甜味美思 15ml、橙味苦精 3滴。

⑩⑨灰烬
重泥煤威士忌 40ml、查特绿酒 10ml、干味美思 15ml、柠檬汁 5ml、橙味苦精 3滴、烟熏海盐 少许 杯口。

②⑩伊鲁席尔
孟买蓝宝石金酒 45ml、蓝柑力娇 15ml、紫罗兰力娇 10ml、椰奶 20ml、柠檬汁 10ml、食用银粉 少许。

②⑩①薪王
单一麦芽威士忌 50ml、杜林标利口酒 15ml、意大利苦杏酒 10ml、血橙汁 20ml、橙味苦精 3滴、迷迭香 点燃。
```


#### [292] Waltz No.2

*created 2026-07-02 · modified 2026-07-02 · 15 lines*

```
伏特加 45ml

紫罗兰力娇 15ml

黑樱桃力娇 10ml

柠檬汁 3ml

橙味苦精 3滴

Shake

香槟杯（coupe）

柠檬皮卷装饰
```


#### [286] 西西弗斯

*created 2026-07-01 · modified 2026-07-01 · 17 lines*

```
黑麦威士忌 60ml

陈年朗姆 30ml

金巴利 45ml

缬草油（使用生命之水和干燥根萃取） 3滴

干味美思 15ml

海盐溶液（水盐比20:1） 2ml

Stir

冰老式岩石杯，加冰球

杯口喷香蜂草油（使用生命之水和鲜叶萃取）
```


#### [283] 大天空（far in the blue sky…）

*created 2026-06-27 · modified 2026-07-01 · 19 lines*

```
蓝宝石金 30ml（45ml）

干味美思 15ml（-）

蓝柑力娇 15ml

青柠汁 10ml

海盐 1g（-）

冷泡伯爵红茶 15ml（-）

上六（三）在杯中混匀（stir）

汤力水 135ml

（可选）柚子皮油 喷1

无酒精版本：蓝柑糖浆15ml+青柠汁10ml+橙花水3滴+汤力水150ml，补满甜味无汽苏打水（30-45ml）
```


#### [285] 可尔必思应用

*created 2026-07-01 · modified 2026-07-01 · 21 lines*

```
以下各种应用，无注明情况下，可尔必思在最后

美式：4:1

生椰拿铁（咖啡液+厚椰乳）：2:7:1

牛奶：2:1

苏打：4:1

清酒：1:1

烧酒：1:1

初恋（朗姆+君度+红石榴糖浆）：3:3:1:2

天使之吻（白兰地+可可酒）：1:1:1

威士忌：3:7


```


#### [282] 反转大天空

*created 2026-06-27 · modified 2026-06-30 · 7 lines*

```
柯林杯

下层：汤力水90ml+蔗糖糖浆15ml

上层：30蓝柑力娇+15ml孟买蓝宝石金酒，混匀（不加冰）

原料全部预冰
```


#### [254] 翠の撫子

*created 2026-03-27 · modified 2026-06-27 · 19 lines*

```
高球杯，加长冰

Jim Beam Apple 45ml

浓缩冷泡煎茶 30ml

新鲜柠檬汁 10ml

接骨木花糖浆 5ml

加冰摇匀上述后滤出

苏打水 沿长冰补满

无酒精版本：冷泡伯爵红茶25ml+20ml苹果汁+浓缩冷泡煎茶30ml+新鲜柠檬汁10-15ml+接骨木花糖浆5ml，用苏打水/干姜水补满

（注：根据我的经验，没有浓缩冷泡煎茶是可以使用煎茶粉代替的，3-10g的煎茶粉配30ml水，请注意这里如果用抹茶粉会导致最后成品的糖感偏重，口感方面则会偏顺滑。煎茶主要是苦涩的口感，涩感较重，我个人会放到8g以上，然后根据情况调整糖浆的剂量，或者更换为基础的蔗糖糖浆等。柠檬汁我用的是青柠，会比较符合预期口感。总体应该会给人一种“凛冽”底下带着“温柔”的感觉，当然因为jba的原因，总体糖量不会很多，如果用其他青苹果金酒就需要重新调整了。
由于我不是调酒师，所以之前试方的时候用的是在柯林杯里直接调的办法，且并未提拉冰快，主要是考虑到配方本身的顺序，也因此在加料的时候比较小心。）

```


#### [256] 天真爛漫で折れない「ニンジンと桜の夢」

*created 2026-03-27 · modified 2026-06-27 · 15 lines*

```
纯米大吟酿 45ml（无酒精版本为米醋+苹果汁/梨汁，1:4，总液量20-30ml）

胡萝卜汁 20ml

樱花糖浆 15ml

香柚汁 10ml

上述加冰摇匀后滤出

苏打水 适量

高球杯

装饰：食用樱花花瓣、胡萝卜片、粉色吸管
```


#### [281] 熏汤力金

*created 2026-06-27 · modified 2026-06-27 · 7 lines*

```
汤力水 45ml

（孟买蓝宝石）金酒 125ml

接骨木花利口酒 10ml

烟桂熏杯 15s
```


#### [260] 帝王舞步

*created 2026-03-30 · modified 2026-03-30 · 7 lines*

```
白橙皮利口酒 30ml

蓝橙糖浆 15ml

乌拉那茨树莓酒 20ml

汤力水 适量
```


#### [259] 悠久の鏗鏘の魂

*created 2026-03-28 · modified 2026-03-28 · 24 lines*

```
伦敦干金酒 45ml

白龙舌兰 15ml

蓝柑力娇酒 10ml

清柠檬汁 15ml

上述倒入搅拌杯加冰搅拌26次后滤入尼克与诺拉杯

苦艾酒 喷雾 1次

————————————————
长成熟日本威士忌40ml
艾雷岛单一麦芽威士忌10ml
紫罗兰力娇酒10ml
干雪莉酒15ml
食用银粉少量

洛克杯冰至-18℃，放入方冰
所有原料放入搅拌杯，加冰搅拌50次，滤入杯中
冰上放一块黑巧克力


```


#### [257] 玄姫

*created 2026-03-27 · modified 2026-03-27 · 13 lines*

```
日本威士忌 或 黑麦威士忌 60ml

金巴利 30ml

甜味美思 20ml

橙味苦精 3滴

上述加入搅拌杯加冰搅拌半分钟

威士忌杯（冰），方冰

装饰：黑巧克力 1块、红樱桃 1颗、食用金箔 少许（可选）、橙皮油 少许（可选）
```


#### [255] 青薔薇の祈り

*created 2026-03-27 · modified 2026-03-27 · 13 lines*

```
冰古典杯（水淋后冰三分钟），5cm冰球

纯米大吟酿 65ml

紫罗兰力娇酒 10ml

接骨木花糖浆 8ml（最后倒入，淋在冰球上）

柠檬汁 8ml（若允许，用5ml柠檬+3ml青柠）

苦艾酒 2～3滴

蝶豆花 若干 装饰
```


#### [251] 升天/堕天/接地

*created 2026-03-15 · modified 2026-03-15 · 61 lines*

```
游戏主角其实是同一人的双重身份：现实中阴郁、依赖、黑发的糖糖（Ame-chan），以及直播时化身粉蓝双马尾、媚宅天使的超天酱（超绝最可爱天使酱 / KAngel）。她切换人格时，外貌与性格天差地别——一个闪亮讨好观众，一个深陷压力与“过量”。我分别为她们各设计一款原创鸡尾酒特调，完全捕捉她们的核心形象与游戏氛围（甜美上瘾 vs 黑暗依赖）。配方简单易做，可在家调制，也可去酒吧点名定制。酒精含量适中，请适量饮用，勿真的“Overdose”！

1. 超天酱专属特调：「小天使请安†升天†」粉蓝天使渐变特调灵感来源：超天酱的粉蓝渐变双螺旋马尾、闪亮水手服、满身爱心蝴蝶结、PEACE大眼，以及她直播时甜美活泼、让人一眼就“升天”的媚宅天使形象。整杯饮料像她的直播画面一样可爱、闪亮、让人欲罢不能！配方（1杯，约200ml）：30ml 伏特加（轻微刺激，像粉丝的关注） 
20ml 蓝橙利口酒（Blue Curaçao，代表蓝色马尾） 
30ml 覆盆子糖浆 / 粉红柠檬汁（代表粉色马尾与甜美）
适量 苏打水 / 香槟（气泡活泼感）
少许 食用金/银色闪粉（天使闪亮效果）
装饰：心形糖果、蝴蝶结小伞、粉蓝渐变吸管

制作步骤：摇酒壶加入伏特加、蓝橙酒、覆盆子糖浆 + 冰块，摇30秒至冰凉。
滤入高脚香槟杯，慢慢倒入苏打水，让蓝色在下、粉色在上形成自然渐变层。
撒闪粉，插上心形装饰。
 
口感与视觉：甜蜜清新、气泡跳跃，先蓝后粉的渐变色超级吸睛！喝一口就觉得“†升天†”，像超天酱在镜头前卖萌一样让人上瘾。适合派对或想变可爱的时候～

2. 糖糖专属特调：「糖糖NEEDY Overdose」黑糖深渊特调灵感来源：糖糖现实中的黑长直发、阴沉忧郁、玻璃心与强烈占有欲，以及游戏里“压力爆表、吃药、过量上网”的黑暗面。整杯像她隐居在家时的内心——表面甜，内里苦涩又让人无法自拔。配方（1杯，约200ml）：40ml 黑朗姆酒（深沉基底，像她的黑发与阴郁） 
20ml 咖啡利口酒（Kahlúa，代表阴沉咖啡色调） 
30ml 能量饮料（如红牛，象征“过量”刺激与粉丝压力）
10ml 黑糖浆 / 焦糖糖浆（黑糖主题）
2滴 苦艾酒 / 安哥斯图拉苦精（增添“精神不稳”的复杂苦味）
装饰：黑樱桃、黑色吸管、一颗“药丸”形状彩糖（致敬游戏里的药）

制作步骤：摇酒壶加入朗姆酒、咖啡酒、黑糖浆、苦精 + 冰块，摇匀至冰凉。
滤入岩石杯或高杯，缓缓注入能量饮料（会冒出泡沫，像压力爆表）。
放入黑樱桃沉底。
 
口感与视觉：先甜后苦、强烈刺激，能量饮料的泡沫像“过量”一样翻涌。喝着喝着就觉得“NEEDY”上头，像糖糖依赖P-chan一样戒不掉。适合深夜独饮或想沉浸黑暗氛围的时候。

这两款特调完美体现了角色的双面性：超天酱是闪亮可爱、让人瞬间升天的天使；糖糖则是深渊般黏人、容易过量的真实自我。如果你想无酒精版、换成特定酒基、或加游戏梗元素（比如再来一杯“P-chan限定”），随时告诉我，我可以继续调！  小天使请安～†升天†（或…别真的升天哦） 


 「⏚接地⏚」怪诞/meme限定特调
（超天酱直播事故纪念款·粉丝弹幕狂刷版）灵感来源：
超天酱正†升天†卖萌直播，突然网卡掉帧、现实感拉满，“啪”一声⏚接地⏚！
从粉蓝双马尾天使瞬间坠落成黑长直neet黑泥怪，弹幕刷满“哈哈哈天酱接地了”“P-chan快拉她起来”“这也太meme了吧”。
表面还想装可爱，底下全是压力、黑泥、尴尬、短路电流……整杯就是把游戏坏档+直播事故+粉丝乐子浓缩成一杯，丑得离谱却莫名上头的怪诞meme神作！配方（1杯，约250ml·接地失败量）：30ml 廉价伏特加（接地气到尘埃里的那种）
15ml 蓝橙利口酒（天使残骸，勉强留点颜色）
15ml 覆盆子糖浆（粉色遗迹，装可爱用）
40ml 红牛（过量压力电击液）
1小勺 即溶咖啡粉（黑泥本体）
少许 食用活性炭粉（让它彻底变泥！）
3滴 Tabasco辣酱（直播烧脑·精神崩溃味）/3～5滴生命之水 
装饰（meme重点）：一根故意掰断的粉蓝吸管（掉线象征）
几片散落的蝴蝶结彩糖（像被粉丝撕下来）
手写小纸条“⏚已接地⏚ 已阵亡”
黑樱桃沉底（像死鱼眼瞪着你）

制作步骤（故意不专业版）：把伏特加、咖啡粉、炭黑粉、辣酱先扔进摇壶，疯狂乱摇10秒（像直播卡顿一样不均匀）。
倒进普通玻璃杯（别用高脚杯，太装了），再随意挤一点蓝橙酒+糖浆，不搅拌，让颜色自己乱混成诡异灰紫泥浆状。
最后猛灌红牛，泡沫狂喷、短路般爆起，像天酱直接接地失败！
插上断吸管，贴好“⏚已接地⏚”纸条，完事。越丑越正宗。

口感与视觉：
颜色像被踩过的彩虹泥巴+紫灰霉变，视觉直接meme拉满（拍照发群里绝对爆笑）。
第一口还有一点天使的甜，第二口咖啡+辣酱+能量饮料直接电击上头，苦辣酸甜混成一团，像糖糖的玻璃心碎了一地。
喝到后面越来越“NEEDY”，想再点一杯……结果发现自己已经接地了，哈哈哈。警告：
这杯真的会让你体验“从天堂到地狱”的meme坠落感！
适合深夜刷NEEDY GIRL OVERDOSE坏结局、看天酱鬼畜视频、或跟朋友一起“哈哈哈她接地了”的时候喝。
勿真喝到Overdose，也不要真去直播间刷“天酱接地”被永封哦～要不要我再给你做一个更离谱的（比如P-chan视角限定、纯药味版、无酒精neet版）？
还是直接把三杯（升天†、NEEDY、⏚接地⏚）凑成一套“超天酱人格分裂套装”？
随时说，我继续调！⏚已接地⏚

```


### 经典鸡尾酒 -- 11 notes


#### [325] 椰林飘香

*created 2026-08-19 · modified 2026-08-19 · 11 lines*

```
白朗姆 45ml

菠萝汁 90ml
，
椰浆 60ml

莱姆汁 15ml

Stir, Machine

飓风杯，菠萝片装饰
```


#### [315] 老式

*created 2026-07-23 · modified 2026-07-23 · 7 lines*

```
波本威士忌 50ml

甘香方糖 1块

橙味苦精 3drops

威士忌杯，方冰，橙皮扭花装饰
```


#### [314] 尼格罗尼

*created 2026-07-23 · modified 2026-07-23 · 9 lines*

```
金酒 30ml

金巴利 30ml

甜味美思 30ml

Stir

古典杯，方冰，橙皮扭花装饰
```


#### [312] 螺丝起子

*created 2026-07-22 · modified 2026-07-22 · 7 lines*

```
伏特加 45m

橙汁 120ml

Stir

柯林杯/威士忌杯，橙片装饰
```


#### [311] 曼哈顿

*created 2026-07-22 · modified 2026-07-22 · 9 lines*

```
黑麦（或波本）威士忌 40ml

甜味美思 20ml（干曼哈顿用干味美思，完美曼哈顿用干甜各半）

橙味苦精 2drops

Stir

马天尼杯，樱桃装饰
```


#### [308] 新加坡司令

*created 2026-07-22 · modified 2026-07-22 · 15 lines*

```
伦敦干金酒 40ml

樱桃白兰地 20ml

柠檬汁 30ml

石榴汁 10ml

橙味苦精 2drops

气泡水 适量

Shake

芬西玻璃杯，樱桃、菠萝装饰
```


#### [310] 亚历山大

*created 2026-07-22 · modified 2026-07-22 · 11 lines*

```
白兰地 20ml

可可甜酒 20ml

鲜奶油 20ml

豆蔻粉 少许

Stir

马天尼杯
```


#### [309] 干马天尼

*created 2026-07-22 · modified 2026-07-22 · 7 lines*

```
干金酒 50ml

干味美思 10ml

Shake

马天尼杯
```


#### [307] 玛格丽特

*created 2026-07-22 · modified 2026-07-22 · 9 lines*

```
龙舌兰 40ml

君度橙味力娇 20ml

莱姆汁 20ml

Shake

玛格丽特杯，柠檬片蘸湿杯口后沾盐霜
```


#### [306] 美国佬

*created 2026-07-22 · modified 2026-07-22 · 9 lines*

```
金巴利 30ml

甜味美思 30ml

气泡水 适量

古典杯，加冰

Stir
```


#### [267] 金汤力

*created 2026-04-27 · modified 2026-07-22 · 10 lines*

```
金酒 45ml
汤力水 补满（135ml）

下面是两个把金酒换成咖啡液的版本

另：Espresso Tonic（浓缩汤力）
杯中加冰，汤力水180ml，浓缩咖啡30ml。橙片或柠檬片装饰。

另：Americano Tonic（美式汤力）
把浓缩换成冰美式（汤力水和冰美式的比例可酌情调整），再加几滴糖浆即可。
```


### 咖啡单整合 -- 5 notes


#### [289] 最后的浪人

*created 2026-07-02 · modified 2026-07-02 · 9 lines*

```
双份浓缩*1

冲绳黑糖糖浆 15ml

燕麦奶 150ml

烤黑芝麻碎 3g

Steps：在杯中加入糖浆，然后倒入打发至微微发泡的燕麦奶与糖浆混合，再倒入咖啡液，最后撒上黑芝麻碎。
```


#### [291] One Last Kiss

*created 2026-07-02 · modified 2026-07-02 · 61 lines*

```
浅烘焙水洗耶加雪菲冷萃咖啡 200ml（粉水比1:12）

全脂牛奶 30ml

海藻酸钠 0.5g

冷压玫瑰花水 40ml（花水比1:5）

覆盆子果泥 30ml

马斯卡彭奶酪 50g

吉利丁片 2片（5g）

食用金箔 1小片

Step1：
①吉利丁处理：将吉利丁片放入冰水中浸泡约5分钟至软化，取出挤干水分备用。

②奶酪糊制备：将奶酪与牛奶放入锅中小火加热搅拌至顺滑融合，温度不超过60℃。

③融合：将泡软的吉利丁片加入奶酪糊中，持续搅拌至完全溶解无颗粒。

④冷藏：将奶酪糊倒入高脚玻璃杯底部，轻轻震动使表面平整，放入冰箱冷藏4℃环境下凝固至少6小时，最好过夜。

⑤可用标准：奶酪冻应完全凝固，轻晃杯体不流动，表面光滑无气泡。

Step2：
①粉水比：取咖啡豆按1:12粉水比称量（例如25g粉配300ml水）。

②冷萃：将咖啡粉与冷水混合，搅拌均匀后密封，放入冰箱冷藏萃取12小时。

③过滤：萃取完成后用滤纸过滤，得到清澈的冷萃咖啡液，取200ml备用。

Step3：
①调配：取200ml咖啡与40ml玫瑰花水混合，搅拌均匀。

②闻香：玫瑰花香与咖啡果酸平衡，玫瑰香气不应完全盖过咖啡香。

③冷藏：将混合液放回冰箱冷藏，保持低温用于后续分层。

Step4：
①过筛：取覆盆子果泥过筛去除籽粒，得到细腻的果泥液。

②增稠：在果泥液中加入海藻酸钠，用搅拌器充分搅拌至完全溶解。

③pH检测：测试果泥液酸碱度，若pH低于6，可添加微量碳酸氢钠（约0.1%）中和至pH接近7，以防凝胶强度减弱。

④静置消泡：将调配好的果泥液静置15分钟消泡后备用。

⑤混装：取出盛有奶酪冻的高脚杯，用吧勺背面贴杯壁，缓慢地将果泥液引流至奶酪冻上，操作速度控制在每秒1-2ml，避免冲击底层奶酪冻，最后会形成约1.5cm厚的红色中间层。

Step5：
①检查备用料温度：确保花咖混合液的温度在4-10℃，混装的奶酪冻与果泥液也已冷藏稳定。

②分层注入：使用吧勺背面贴杯壁将花咖混合液沿勺背缓慢倒入高脚杯中，注意混合液应清晰悬浮在红色果泥液层之上，填充至杯口约1cm处留空。

③金箔装饰：用镊子夹取金箔轻轻放置于花咖混合液层的液面中央，至此完成所有步骤。

Ps：进行终段检查后，One Last Kiss需立即上桌，15分钟内饮用为佳，防止长时间静置导致分层模糊，可建议顾客从上至下分层品鉴。

```


#### [290] 是，大臣

*created 2026-07-02 · modified 2026-07-02 · 11 lines*

```
意式浓缩 1份

伯爵红茶 40ml

香草荚糖浆 20ml

全脂牛奶 150ml

干金盏花瓣 2g

Steps：在杯中加入糖浆，然后依次加入热红茶、打发到一定程度的牛奶以及咖啡液，最后撒上干花瓣。
```


#### [288] 三色堇系列

*created 2026-07-01 · modified 2026-07-02 · 36 lines*

```
此类目下的所有咖啡都需要三色堇装饰（摆放位置不做限定，需注意醒目的同时要让客人能够轻松取出）

经典三色堇（热饮）：
意式浓缩 1份
紫罗兰糖浆 10ml
香草糖浆 5ml
Steps：将糖浆加入150ml牛奶混合并加热打发后，与咖啡液混合。

真夏の夜の銀夢（冷饮）：
＊冰萃意式浓缩 1份
火龙果汁 15ml
百香果汁 10ml
蔓越莓汁 5ml
接骨木花糖浆 10ml
伯爵红茶糖浆 5ml
Steps：将果汁和糖浆加冰用雪克杯摇匀后倒入咖啡杯中，再缓缓倒入咖啡液。

ToHeart!（阿芙佳朵）：
意式浓缩 1份
香草/浆果味冰淇淋 1-2球
彩色糖珠 若干（如15颗）
Steps：在冰淇淋球上快速淋咖啡液然后用糖珠等进行装饰，咖啡液建议热用（萃取水温在90℃左右），阿芙佳朵的最佳品尝区间较短，需提前说明。

Trio（摩卡奇诺）：
意式浓缩 2份（36g）
白巧克力 10g
全脂牛奶 240ml
紫罗兰糖浆 15ml
覆盆子糖浆/樱花糖浆 少许
Steps：
①将200ml牛奶和糖浆混合，加热后打出奶泡
②往杯中倒入牛奶
③将白巧和40ml全脂牛奶一起加热融化后，少量多次倒入咖啡液并混匀（请根据实际在足够大的容器里进行混匀操作），沿吧勺背部倒入杯中，最后在顶层用覆盆子糖浆/樱花糖浆画细螺旋
Ps1：如果有多余的奶泡，可以最后倒在最上层，然后在奶泡上面撒一些柠檬皮屑，覆盆子糖浆/樱花糖浆的添加顺序也请随之调整
Ps2：Trio须使用容量500ml左右的杯（或大于460ml的杯）承装

```


#### [284] 纯白交响曲

*created 2026-06-29 · modified 2026-07-01 · 6 lines*

```
日文：ましろ色シンフォニー
英文：Pure White Symphony

1、炼乳15g+香草糖浆10ml+双份浓缩+1g盐，加热搅匀
2、全脂牛奶200ml+白巧克力30g，加热至巧克力融化，可打奶泡
3、把1作为基底，将2沿1的杯壁倒入，如果有奶泡，可在最上层撒一些杏仁碎
```


### 奶饮单整合 -- 2 notes


#### [299] 等待戈多

*created 2026-07-04 · modified 2026-07-04 · 39 lines*

```
全脂牛奶 270ml

桃胶 6g（提前18小时泡发，然后提前一小时炖煮50分钟，剩下的十分钟用来降温）

红糖 10g（提前用50℃左右的少量温水调开）

玫瑰水 6ml（10g玫瑰花瓣配500ml水煮10分钟，放凉备用）

“辛油”（将1颗压碎的小豆蔻、10ml蜂蜜、2颗公丁香、1小段迷迭香和1片干姜，用40mlJim Beam Apple、15ml孟买蓝宝石金酒、10ml151朗姆和5ml重泥煤威士忌，置于试管内冷浸24小时）

香草糖浆 5ml

伯爵红茶糖浆 5ml（如有必要可用一小盒奶球提前混合）

酥油 ½茶匙

轻烤夏威夷果碎 ½匙

香蜂草+薰衣草酒萃液（香蜂草9g，薰衣草3g生命之水300ml，冷萃48小时以上）

海盐 一小撮（约0.3-0.5g）

食用金箔 少许

肉桂棒 1根

Step1： 将准备好的桃胶和酥油分别加热到60℃和50℃，倒入65℃的主锅与其中的热牛奶混合，然后维持温度缓缓加入红糖并搅拌；

Step2：取最多15ml“辛油”过滤后加入主锅（如香辛味超出预期可减量，且若只是需要这个形式，或者想愚弄一下这位粗鲁的宾客，滴3-5滴即可，重泥煤威士忌的真正用处就得以体现了），维持75℃煮3-5分钟让风味融合并蒸发酒精，确保酒精味散去后离火，待温度降至65℃以下后拌入玫瑰水、香草糖浆和伯爵红茶糖浆，过筛滤入预热的厚壁陶瓷杯；

Step3： 表面撒夏威夷果碎、海盐，点缀食用金箔并插入肉桂棒，最后用喷壶朝杯口喷一次香蜂草液。

Another：根据“辛油”每次制作的结果，即便是5分钟也没办法确定酒精是否能够完全蒸发完毕，因此，不建议将“等待戈多”和常规奶饮放在一起，考虑到用料复杂，可放入预约菜单。

Ps1：如顾客有酒精过敏或不适宜接触酒精，可将“喷酒萃液”的部分换成“另取点燃一根烟桂棒熏杯5s”，这是代价，嘻嘻。

Ps2：考虑到大部分人对香料的直接接受度不算高，不论是喷酒萃液还是烟桂棒熏杯，都要在离杯体至少50cm高的地方进行，让“加了点什么又感觉没有”的氛围存在即可，以及，如果烟桂的烟体因温度问题无法主动下沉，可作引导。

Ps3：若客人觉得不够甜，只给他甘香方糖，别的不给，如果客人执意要自己加点什么别的，那么就需要拿出一份免责声明了。
```


#### [298] 楽園図

*created 2026-07-04 · modified 2026-07-04 · 21 lines*

```
茉莉花茶汤 80ml

燕麦奶 220ml

蝶豆花 5–6朵

姜黄粉 ½小匙（约2g）

肉桂粉 ¼小匙（约1g）

南非醉茄粉 ½小匙（约1.5g）

蜂蜜 1小匙

黑胡椒 一小撮（约0.3g）

Step1：燕麦奶加蝶豆花小火加热至60–70℃，过滤得蓝色奶液；

Step2：将姜黄粉、肉桂粉、南非醉茄粉用少许（30ml以下）温奶调成糊状后倒回蓝奶中搅匀，续煮1–2分钟；

Step3：杯中先倒入茉莉花茶汤作底，再缓缓注入温热蓝金奶液形成渐层，关火后加入黑胡椒与蜂蜜，最后可点缀干茉莉或肉桂棒。
```

