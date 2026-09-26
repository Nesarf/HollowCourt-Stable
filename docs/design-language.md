# The design language: one grammar, five materials

Written 2026-09-25, from the owner's brief:

> 美术资源的建立可以考虑参考 a rhythm game 的色调与质感，然后 UI 方面可以综合所有研究对象进行设计，目的是防止画面单调，
> 且各功能之间的视觉相互独立，不杂糅。

Two instructions that pull in opposite directions, and the tension between them is the point. *Do not let the
screens look monotonous* asks for variety; *each function visually independent, nothing blended together* asks
for separation. What holds both together is that the variety lives in **material**, and the sameness lives in
**grammar**. Five rooms, one building.

## 1. What is borrowed from where

| Source | What it gives | What it does not |
| --- | --- | --- |
| **a rhythm game** | Its **tone and material** -- low saturation overall, exactly one saturated accent, hairline rules where a panel would be easier, and the sense that surfaces are *finished* rather than filled (a subtle inner shadow, a bevel, a grain) | Its high-key white ground, and its unreadable small text. Section 12 of `DESIGN.md` records that the second one is the mistake of its design that we refuse to repeat |
| **a crafting game** | Flat silhouettes, **two inks** and no more, detail by subtraction, and a printed *stamped* quality | Its flatness at large sizes: a stamp is furniture, not a page |
| **one source** | Liquid rendering: the meniscus, the meniscus's shadow, the light through the glass | Its data model |
| **another source** | Density: many rows, tight, with the numbers aligned in a column | Its chrome |
| **a mobile game** | Layering -- a card is a stack of planes with an identity underneath, and the identity survives being covered | Its asset pipeline |

The a study of a rhythm game's control-level findings are adopted as rules, because each one is a decision we would
otherwise have to make and can now make with evidence:

1. **A pressed state is another drawing, not a tint or a scale.** `x.png` / `x_pressed.png` throughout a rhythm game's
   assets. Ours: the ground lifts and the hairline brightens.
2. **A primary button is a shape, not a rounded rectangle.** a rhythm game's is a trapezoid with 45° hairline texture.
   Ours: the cut corner and the prism, below.
3. **A divider is a rule plus the motif at its smallest.** a rhythm game's is a line and a 10×10 diamond. Ours is a rule
   and a 10-pixel prism, which is already in `PrismDivider`.
4. **Parts are neutral; colour comes from what is layered on them.** White backing textures serving several
   occasions. Ours: the panels are the court's own dark ground and the material arrives on top.

## 2. The grammar (identical everywhere)

* The **palette** of section 12: the court ground, brass, rose, ink, on a twenty-four-hour clock of light.
* The **motif**: the bismuth prism, and nothing else decorative. It appears in the halo, the dividers, the
  navigation's selected state, the empty states, and now at the centre of the mark itself.
* **Hairlines, not panels.** A rule in `HollowPalette.line` is the default way to separate anything.
* **Type**: the two-register system of section 12.6, headings in the serif register and data in the lining one.
* **The corner cut.** Every surface that needs a shape gets it by cutting one corner at 45°, never by rounding.

## 3. The five materials (different, deliberately)

Each function gets a material of its own. A reader should be able to tell which room they are in from a
glimpse of a corner, and no two rooms should share a texture.

| Function | Material | Made of | Why this one |
| --- | --- | --- | --- |
| **酒窖 Cellar** | **Wood and glass** | Warm timber hairlines, and each bottle's body filled with one source's liquid treatment | It is a cellar: the shelves are wood and the point of the screen is what is *in* the glass |
| **吧台 Bar** | **Stone and brass** | Cool grey with a fine grain, brass edges that catch the light, and a crafting game's two-ink flatness for the measured parts | A bar top is stone; the flatness keeps a row of small numbers readable |
| **配方 Recipes** | **Paper** | A parchment field, printed rules, a stamped ornament in the corner | Recipes are printed things, and this is the one screen where a light ground is honest |
| **记录 Journal** | **Ledger** | Ruled lines, a margin rule, entries aligned in columns | It is a log: the column is the interface |
| **设置 Settings** | **Brass plate** | A metal panel with engraved tick marks and the prism as a practical mark | Settings are the machine room: the one place where the plain geometry is the right answer |

## 4. How this is enforced rather than described

A design document that nothing checks is a wish. So:

1. **Every material is a value in one file**, `lib/ui/materials.dart`, so a screen cannot invent its own wood.
2. **A test asserts the materials stay distinct**: the five functions' surface colours must differ by more than a
   threshold in at least two channels, so "we made them all the same dark grey" fails the suite.
3. **Every function's screen is captured in the acceptance set**, so monotony is visible in a diff of the images
   rather than argued about.
4. **The a rhythm game mistake is a test too**: the low-contrast small text of section 12.9.1 already has four
   assertions behind it, and no new material may introduce text below that ratio.

## 5. Order of work

The order is by how much of the application a change touches:

1. **The icon** -- done in this round: the two borrowed letterforms are gone, replaced by the halo's own crystal,
   which removes the last element of this mark that was not made here.
2. **The navigation bar** -- done: it is `HollowNavBar`, drawn here, with the motif as its indicator.
3. **The five materials** -- `materials.dart`, then each screen's surface in turn: cellar, recipes, bar, journal,
   settings.
4. **The controls** -- buttons, chips, fields, sheets, progress, in that order of visibility.
5. **The empty states and the ornament** -- the last place the five rooms can be told apart cheaply.
