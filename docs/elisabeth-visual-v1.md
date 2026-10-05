# 伊丽莎白的视觉图，第一版

Written 2026-10-01. **The owner produced this with GPT and asked for it to be recorded rather than judged**:

> *「我试着用 gpt 跑了一下伊丽莎白的视觉图，虽然有不少地方不满意，但姑且能看，记下来吧」*

`art/elisabeth-sheet-v1.png`. It is recorded as a **first attempt at a visual reference**, not as a settled design, and
the reasons it is not settled are listed below rather than left to be rediscovered.

## What it is

A character sheet in the ordinary sense: a full-length figure in the formal dress, three-view drawings, a nine-face
expression set, two dress variants, shoes at two heel heights, accessory details, a weapon plate, and a body
measurement block. 1312x1199, RGB, no transparency.

**It agrees with the written sheet on nearly everything it states**, which is why it is worth keeping at all. Read
against `character/zh/elizabeth-card.md`:

| The image says | The card says |
| --- | --- |
| 22 years old, 173cm, 69kg, B104/W81/H95 | **the same four numbers** |
| 彩色铋质无定态超长剑「耶梦加得」 | the same weapon, by the same name |
| 第45代家主, 德·阿曼纳克家 | the same house and generation |
| 翡翠邦联's nine districts, named | the same nine |
| 傲娇、优雅、貌美、嫉恶如仇 | the same character |

## What is wrong with it, named

**These are the owner's dissatisfaction made specific, not a review the owner asked for.** They are worth writing
down because each one is a thing a second attempt has to change, and a general "not satisfied" cannot be acted on.

1. **The figure is not 173cm.** Every drawing on the sheet reads as the same short, wide-eyed proportions, including
   the chibi in the corner -- and the block beside them says 173cm. **The number and the drawing contradict each
   other on the face of the sheet**, which is the most visible fault and the one a person notices first.
2. **The weapon is a broad double-edged longsword.** The card's 「彩色铋质无定态超长剑」 is a bismuth-coloured blade
   whose length is unknown even to her -- an idea about *indeterminacy*. What is drawn is a conventional fantasy
   greatsword with a crystalline hilt, which is a different idea wearing the same word. **The iridescent colour
   came through; the indeterminacy did not.**
3. **The head is a small tilted hat, not a crown.** Nothing on the sheet corresponds to the diamond-and-pyramid
   headpiece the character carries, and the roses and moissanite are absent.
4. **The eyes read as amber.** Both the large figure and the expression set are warm brown-gold. This is a
   divergence from a described feature rather than a rendering artefact, so it is listed rather than explained away.
5. **The signature block spells the name wrong in English**: it renders the family as **`d'Armenac`**, where the
   card says **`d'Armanac`**. Worth its own line because a name is the cheapest thing to get right and the most
   irritating to find wrong.

## One thing this file has already turned up, which is not about the image

**The house name is spelled two ways in this repository.**

| Where | Spelling |
| --- | --- |
| `character/zh/elizabeth-card.md`, `character/ja/elizabeth-card.md` | **`Élisabeth Muse Marie d'Armanac`** |
| `tool/hma_models.py` (both the Chinese and Japanese prompts) | **`Élisabeth Muse Marie d'Armagnac-Cognac`** |

**Both cannot be right, and the difference is not a translation** -- it is two spellings of one French house. Recorded
here rather than fixed, because which is correct is the owner's to say and a silent pick would make it
indistinguishable from a decision. **The image agrees with neither exactly**: it uses `d'Armenac`.

## How it is classified

**`generated`**, in the sense this repository's provenance file means: it came from a tool, it is not a third party's
file, and its origin is stated rather than implied. **The same rule the two 永遠の歌姫 pieces and the application mark
follow** -- see `docs/asset-provenance.md`.

**It depicts nobody else's character**, so unlike those pieces it raises no licensing question: Élisabeth is this
project's own. What it is not yet is *settled*, which is why it is filed as a v1 next to a list of what to change.
