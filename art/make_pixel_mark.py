#!/usr/bin/env python3
"""The mark for the sizes where nothing else survives: one A, drawn at the size it ships at.

    python art/make_pixel_mark.py

**Why a second mark for small sizes.** The picture mark is a still life of a dozen objects. It is
beautiful at 256 pixels and unreadable at 48 -- measured, not assumed: at sixteen it is mottled colour
and nothing else. A mark that ships at fifteen sizes must be drawn for the sizes it ships at, and this
project learnt that once already from the other direction, when the medallion's letters were the first
thing to disappear below forty-eight (`docs/DESIGN.md` 12.7.1). The answer there was to draw the small
tiers differently rather than to shrink one drawing, and the same answer holds here.

**The letter is the publisher's.** The application is Hollow Court and it is published by S.M.Y.T. --
`关于空庭` names it -- so an A is not a borrowed symbol but the publisher's own mark, which is why the
owner asked for one. No ring: a ring plus a letterform was drawn and compared at sixteen pixels and did
not fit, which is the same structure that cost the medallion its letters.

**The bitmaps are written out rather than computed, and that is the third attempt.** Two earlier
versions derived the legs from an angle and rounded the endpoints to whole pixels, and both put
stair-steps and broken feet into a sixteen-pixel letter; a third tried a 4x4 grid enlarged four times,
which read as an H -- four pixels across cannot hold an apex that narrows and a base that spreads at
the same time, and its crossbar filled the counter that makes the letter legible. What ships is three
hand-checked bitmaps with the counter left open, because at these sizes the hole in the middle is the
letter.

**The stem is three cells at sixteen, not two.** The first working attempt used a two-pixel stem and
disappeared; four pixels closed the counter to a dot. Three keeps the two legs apart and the counter
open, and the larger sizes scale that proportion rather than inventing a new one.
"""
from __future__ import annotations

from pathlib import Path

# The application's own colours: the warm near-black ground and the ivory ink.
GROUND = "#16110A"
INK = "#F4E8CE"

# ---- the three drawings, as pixels ----
#
# `I` is ink, `.` is ground. Apex at the top, two legs spreading to the feet, the crossbar stopping short
# of the outer edge so it never sticks out past the diagonal, and the last foot row filled so a leg does
# not end in a single pixel.
A16 = [
    "................",
    "................",
    "................",
    "....III.III.....",
    "....III..III....",
    "....III..III....",
    "....III...III...",
    "...III....III...",
    "...IIIIIIIIII...",
    "..IIIIIIIIIII...",
    "..III......III..",
    "..III......III..",
    "..III.......III.",
    "................",
    "................",
    "................",
]

A24 = [
    "........................",
    "........................",
    "........................",
    "........................",
    "........................",
    "........IIII.IIII.......",
    ".......IIII..IIII.......",
    ".......IIII..IIII.......",
    "......IIII....IIII......",
    "......IIII....IIII......",
    "......IIII....IIII......",
    ".....IIII......IIII.....",
    ".....IIIIIIIIIIIIII.....",
    "....IIIIIIIIIIIIIIII....",
    "....IIIIIIIIIIIIIIII....",
    "....IIII........IIII....",
    "...IIII..........IIII...",
    "...IIII..........IIII...",
    "..IIII...........IIII...",
    "........................",
    "........................",
    "........................",
    "........................",
    "........................",
]

A32 = [
    "................................",
    "................................",
    "................................",
    "................................",
    "................................",
    "................................",
    "..........IIIII.IIIII...........",
    "..........IIIII..IIIII..........",
    "..........IIIII..IIIII..........",
    ".........IIIII....IIIII.........",
    ".........IIIII....IIIII.........",
    ".........IIIII....IIIII.........",
    "........IIIII......IIIII........",
    "........IIIII......IIIII........",
    "........IIIII......IIIII........",
    ".......IIIII........IIIII.......",
    ".......IIIIIIIIIIIIIIIIII.......",
    "......IIIIIIIIIIIIIIIIIIII......",
    "......IIIIIIIIIIIIIIIIIIII......",
    "......IIIIIIIIIIIIIIIIIIII......",
    ".....IIIII............IIIII.....",
    ".....IIIII............IIIII.....",
    ".....IIIII............IIIII.....",
    "....IIIII..............IIIII....",
    "....IIIII..............IIIII....",
    "....IIIII...............IIIII...",
    "................................",
    "................................",
    "................................",
    "................................",
    "................................",
    "................................",
]

GLYPHS = {16: A16, 24: A24, 32: A32}


def build(stem: int, apex: int, foot: int, top: float, bottom: float,
          bar_from: int, bar_to: int, size: int) -> list[str]:
    """The same letter, computed for a size too large to write out by hand.

    **Symmetry is enforced rather than hoped for.** A letter is symmetric and this function's arithmetic is
    not: with an odd stem the rounding can shift one leg by a cell on the apex row and again on the last
    foot row, and both were visible in the first attempt at these sizes. Mirroring the left half onto the
    right afterwards is exact, and needs no argument about which way a rounding went.
    """
    grid = [['.'] * size for _ in range(size)]
    centre = size / 2.0 - 0.5
    for step in range(foot - apex + 1):
        y = apex + step
        half = top + (bottom - top) * (step / (foot - apex))
        left, right = int(round(centre - half)), int(round(centre + half))
        for x in range(max(left, 0), min(right + 1, size)):
            if bar_from <= y <= bar_to:
                grid[y][x] = 'I'
            elif x < left + stem or x >= right - stem + 1:
                grid[y][x] = 'I'
    for y in range(size):
        for x in range(size // 2):
            grid[y][size - 1 - x] = grid[y][x]
    return [''.join(row) for row in grid]


# ---- the two sizes too large to hand-author ----
#
# A 32-pixel drawing enlarged to a 128-pixel icon is a chunky A, which is wrong at that size: the stem has
# to thin out as the mark grows, in the same proportion the three small ones already use. Measured against
# those, the working ratio is about a twelfth of the width for the stem and a fifth for the legs at the
# feet, so these are computed from it and then checked for symmetry.
# 48 sits between the hand-drawn 32 and the computed 64 and deserves its own drawing for the same reason:
# rendering the 32-pixel one at 48 makes a bolder letter than the size asks for.
GLYPHS[48] = build(stem=4, apex=6, foot=42, top=4, bottom=9, bar_from=22, bar_to=26, size=48)
GLYPHS[64] = build(stem=5, apex=8, foot=57, top=5, bottom=11, bar_from=30, bar_to=34, size=64)
GLYPHS[128] = build(stem=9, apex=16, foot=115, top=9, bottom=22, bar_from=60, bar_to=68, size=128)


def to_svg(rows: list[str], size: int) -> str:
    """One rectangle per horizontal run, in cells, scaled to a 1024 viewBox.

    `shape-rendering="crispEdges"` is what makes whole cells read as blocks: the default smooths
    neighbouring rectangles into each other, which is the one thing a drawing made of whole cells must
    not do.
    """
    unit = 1024 // size
    pieces = [f'  <rect x="0" y="0" width="1024" height="1024" fill="{GROUND}"/>']
    for y, row in enumerate(rows):
        x = 0
        while x < size:
            if row[x] != 'I':
                x += 1
                continue
            start = x
            while x < size and row[x] == 'I':
                x += 1
            pieces.append(
                f'  <rect x="{start * unit}" y="{y * unit}" width="{(x - start) * unit}" '
                f'height="{unit}" fill="{INK}"/>'
            )
    body = "\n".join(pieces)
    return f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024" shape-rendering="crispEdges">
  <!--
    The publisher's A, drawn at {size} pixels and enlarged by whole cells, so the small sizes carry a
    drawing rather than a shrinking of one. Generated by art/make_pixel_mark.py, so edit that and
    re-run rather than editing this. Two inks, both the application's own.
  -->
{body}
</svg>
"""


def main() -> int:
    here = Path(__file__).parent
    for size, rows in GLYPHS.items():
        out = here / f'icon-hc-a{size}.svg'
        out.write_text(to_svg(rows, size), encoding='utf-8', newline='\n')
        lit = sum(row.count('I') for row in rows)
        print(f'  wrote {out.name} ({size}x{size}, {lit} cells of ink, {out.stat().st_size} bytes)')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
