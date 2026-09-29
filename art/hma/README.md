# HMA's art -- first pass

**The motif is a wedge cut out of a bar**, because the platform defines itself as a seam: `docs/HMA.md` says of the local
model bridge 「缝留着，桥不发」 -- *leave the gap, do not ship the bridge*. A notch is that sentence drawn.

**The accent is cold (`#3FE0D0`) on a near-black ground (`#0A0E14`)** and is the only colour, which puts it opposite the
application's gold and rose rather than beside them. Two things in one family that are not the same thing.

## What was borrowed, and what was not

The owner's rule for this work is 「可以接近一个节奏游戏那一侧，但仍旧要我们自己进行设计」 -- **borrow the logic, design the
thing.** Three pieces of logic, each from a measurement rather than an impression:

| Borrowed | From | Here |
| --- | --- | --- |
| **A motif repeated at several scales of the same shape** | the study's first finding | `motif.svg` -- one polygon, four sizes, the notch a constant fraction so the shape stays itself |
| **Button states defined as a set** | the study's second finding | `button-normal` / `-press` / `-disable` -- and **the notch is what moves**, so the state is legible without colour |
| **One accent, not a palette** | the study's summary | one hexadecimal value in the whole directory |

**Nothing is borrowed as an asset**, and there was nothing to borrow: the shape is a polygon with five points.

## These are sources, not images

**There is no SVG rasteriser on this machine.** `convert` is Windows' filesystem tool rather than ImageMagick, and
Illustrator is on `D:` where the owner keeps it. So these files are **what gets opened in Ai**, and the check that runs
here is the one that can run here: **they parse as XML, and the geometry is asserted.** Nothing in this repository claims
to have looked at a picture it has not looked at.

## Files

| File | What |
| --- | --- |
| `motif.svg` | the wedge at 16 / 32 / 64 / 128 px |
| `button-normal.svg` `button-press.svg` `button-disable.svg` | the three states, as a set |
| `panel-9slice.svg` | a panel for Unity's nine-slice: a rectangle, an inner accent line, and a 16px border that holds the corners |
| `wash.svg` | a tileable 256×256 background at alpha 0.05 -- deliberately far below the 0.36 ceiling the study measured, because a background behind white text has less room than one behind an illustration |
| `divider.svg` | the motif repeated along a rule, brightening toward the middle |

**The panel carries no motif, and that is the design rather than an omission**: a nine-slice with a notch cut into a
corner cannot be sliced, so the motif goes where it can repeat without breaking anything.

## The pipeline, because it is not obvious

    SVG  (source, here)  ->  Ai  (renders, on D:)  ->  PNG  ->  Unity  (imports)

**Unity does not import SVG.** Writing that down matters: a project that assumes otherwise discovers it at the moment
somebody opens the editor, and the step it silently skips is the one that produces the actual asset.

## The check

    python tool/hma_art_check.py

Three assertions, each one a thing the design claims: **the files parse** (an SVG that does not is an asset nobody can
open, and it fails silently in a viewer); **where a polygon appears it is a pentagon** (the motif is one shape
parameterised, so a four- or six-point polygon means somebody drew a second shape instead of scaling the first -- and
files that use no polygon at all, such as the nine-slice panel, are not thereby wrong); **only the palette's colours
appear** (one accent on one ground, which is the first thing to erode when a file is edited in a hurry).

**It earned its place immediately**: the first version of  had  inside an XML comment, which is illegal,
and nothing else here would have noticed.

## 哪些渲出来了，哪些没有（2026-09-26 ✓）

**渲染脚本会把空白的产物删掉** ✓，**所以工程里留下的就是真的画出来的** ✓：

| 图 | 结果 |
| --- | --- |
| `motif.png` ✓✓ | **240 / 240 行有内容** |
| `wash.png` ✓ | **80 / 256 行** —— **稀疏是设计** ✓ |
| `button-*.png` ✗ `divider.png` ✗ `panel-9slice.png` ✗ | **只有 2 行残影，等于空白** ✗✓ |

**原因不明** ✗ —— **五次诊断之后仍然不明** ✓ —— **所以按规矩记成「不明」，不写成结论** ✓✓。

**已知的观察（不是结论）** ✓：失败的都是**很少或无多边形**的图 ✓，而两张成功的是**多多边形**的 ✓；但 `panel-9slice` 并不比 `wash` 小多少 ✓，所以**尺寸解释不了它** ✗✓。

**而源文件是对的** ✓✓：`art/hma/*.svg` 在任何查看器里都正常 ✓，**Ai 也能直接打开 ✓** ——
**缺的是「把它变成 PNG」这一步** ✗，**不是图本身** ✓。

**渲染脚本现在验自己的产物** ✓✓ —— 它原先报「失败 0 个」而其中五张是空白 ✓，
**那正是这个工程反复在找的那种「通过了但不对的检查」** ✗✓。
