#!/usr/bin/env python3
"""Draws a second mark for Hollow Court: a constructivist composition, flat and cut.

    python art/make_construct_icon.py

WHY A SECOND GENERATOR RATHER THAN AN EDIT OF THE FIRST. `make_icon.py` draws a medallion, and the
medallion is not a drawing choice: `docs/DESIGN.md` 12.7.1 ties it to the character sheet, where the
halo keeps its three elements and its fifteen degrees of clockwise tilt from her setting. Replacing
that is a change of **identity**, not of style, so the medallion is left exactly as it is and this file
draws an alternative beside it. Nothing is installed from here until a person says which mark is the mark.

WHAT A CONSTRUCTIVIST COMPOSITION MEANS HERE, and it is a method rather than a borrowed picture. The
movement's devices are a diagonal axis that cuts the frame, a circle that meets it, and a square turned
on its corner; the palette is a printmaker's, flat and few. `docs/DESIGN.md` 12.7.1 already records this
project borrowing a method and deliberately not the art, and the same line is held here: nothing is
traced, nothing is named, and every shape is computed from the canvas.

**And the two faults of the reference image this answers are answered by construction, not by editing.**
That image was a collage separated by black outlines and carrying some fourteen thousand distinct
colours. The same document says the opposite is what survives: detail **cut out of** flat shapes rather
than drawn on them, and two inks rather than a spectrum. So there is not one stroke in this file, every
dividing line being the edge of a fill or of a cut, and the smallest tier is drawn in two colours with
the third carried by transparency so that it cannot become a third ink.

THE THREE DENSITIES ARE THE POINT, not a nicety. The measured lesson is in the same section: a mark
drawn once at 1024 and scaled down became a grey ring below 48 pixels, and the letters the application
is named for were the first thing to go. So each tier is its own drawing, and what the small one cannot
afford is **removed rather than shrunk**.
"""
from __future__ import annotations

import math
from pathlib import Path

# ---- the application's own colours, so the mark and the interface agree ----
#
# Every one of these is already in `lib/ui/theme.dart`: this is the honeyed court's ground and ink,
# the gold a reader taps, and the rose the navigation bar draws for the cellar. A mark in colours the
# application does not use would be a logo wearing somebody else's coat.
GROUND = "#16110A"
INK = "#F4E8CE"
ROSE = "#C4626A"
GOLD = "#E2A63E"
DEEP = "#6E5528"

SIZE = 1024
C = SIZE / 2.0

# ---- the composition, in one place, because every tier is a reduction of it ----
#
# A diagonal axis from the lower left to the upper right; a circle band that crosses it; the square
# turned on its corner at the centre. Three shapes, which is the whole vocabulary.
#
# **The brass plate is thinner than the ink one and offset across the diagonal**, so the two lie beside
# each other rather than one on top of the other. That single relationship is what the whole composition
# leans on: two flat values meeting at a diagonal boundary. The first attempt drew the brass plate along
# the same centre line at a width of two hundred and eighty, which put the ink out of sight except at
# the two ends and covered the right half of the circle -- a mark that read as dark diagonal plus a
# crescent. Widths and offsets are here together so that relationship is visible in one place.
AXIS_HALF = 74.0       # half the width of the ink diagonal
BAND_HALF = 70.0       # half the width of the brass plate, and it is narrower on purpose
BAND_OFFSET = 60.0     # how far the brass plate sits across the diagonal from the ink's centre line
RING_OUT = 372.0       # the circle band's outer radius
RING_IN = 300.0        # and its inner edge
DIAMOND = 286.0        # the half-diagonal of the centred square

# The rose square carries a bar cut out of its middle: the counter-change a constructivist print makes
# with its two inks, and what stops the diamond from being a plain lozenge at 16 pixels.
# The counter-change: a bar cut out of the diamond's middle **across** it, not along it.
#
# **Perpendicular to the axis, and that was the second attempt rather than the first.** A cut parallel to
# the diagonal runs beside the diagonal band and the two read as one smudged gesture once the mark is
# small; a cut across it makes the diamond read as a split lozenge, which is a shape, and leaves the band
# outside it doing its own work. Orientation aside, the bar is also thicker than it wants to be: the first
# cut was thirty units tall, read well at 256 pixels and shredded at sixteen, where the cut narrowed to
# under one pixel per edge. This project has learned that lesson from the other direction already -- a
# mark drawn in fine lines lost its letters below forty-eight pixels -- so the bar is sized for the
# smallest tier it must survive in rather than for the largest one it is drawn at.
BAR_HALF_H = 46.0
BAR_HALF_W = 100.0


TIERS = {
    #          axis   ring   band   diamond  bar    cut
    # **The palette is declared per tier, not assembled out of switches.** The first cut described each
    # tier by what it turned on, and the inks a drawing ended up using were whatever those switches
    # happened to produce -- which is how the ring rendered black and the axis all but vanished under its
    # own overlay. A print states its inks before it is pulled; so does this. The document's rule is
    # `two inks` for the smallest tier, and here that is not a promise to be verified afterwards, it is
    # the whole list.
    "full":  dict(axis=INK,  ring=INK,  band=DEEP,  diamond=ROSE, bar=GOLD,  cut=False),
    # Mid keeps the circle and the counter-change and drops the second plate: a reduction rather than a
    # recolour, and this is the tier between 48 and 96 pixels, where a diagonal boundary still resolves.
    "mid":   dict(axis=INK,  ring=INK,  band=None,  diamond=ROSE, bar=GOLD,  cut=False),
    # **Two inks, the third by transparency.** The bar across the diamond is cut through to the ground
    # rather than filled, so the drawing uses INK and ROSE and lets the ground serve as the third value:
    # one fewer ink than a fill would need, and the reason the counter-change still reads at 16 pixels.
    # The circle goes, because a band that thin is the first thing a small render turns into a smudge.
    # **Two inks, and the counter-change is removed rather than shrunk.** Three attempts at carrying it
    # into this tier are recorded because the failures are the useful part: a thin cut parallel to the
    # axis shredded the diamond into notches; thickening it left a light smear; a cut across the diamond
    # at a right angle crossed its two widest points and turned the whole mark into confetti at sixteen
    # pixels. A diagonal cut through a diamond is the worst case at this size, because the shape is
    # nothing but edges and the cut lands where its edges are farthest apart. So the smallest tier keeps
    # the two things that survive being small: the solid rose square and the ink diagonal.
    "small": dict(axis=INK,  ring=None, band=None,  diamond=ROSE, bar=None,  cut=False),
}


def fmt(value: float) -> str:
    """Two decimals, and no trailing `.00` -- the file is meant to be readable."""
    text = ("%.2f" % value).rstrip("0").rstrip(".")
    return text or "0"


def ring(fill: str) -> str:
    """The circle band, as one path so there is no stroke anywhere in the file.

    **`fill` is passed in rather than left off, and that is a fix rather than a tidy-up.** The first cut
    of this function omitted it, and an omitted fill is black: the ring rendered as a heavy black band
    that belonged to no palette, which is what an ink default looks like when nobody chose it. A
    stroke and a fill of the same width also differ at the edges once a renderer rounds them, and the
    document's rule is about fills: what a reader sees is the shape, not a line describing it.
    """
    return (
        f'  <path fill="{fill}" fill-rule="evenodd" d="'
        f'M{C + RING_OUT},{C} A{RING_OUT},{RING_OUT} 0 1 1 {C - RING_OUT},{C} '
        f'A{RING_OUT},{RING_OUT} 0 1 1 {C + RING_OUT},{C} Z '
        f'M{C + RING_IN},{C} A{RING_IN},{RING_IN} 0 1 1 {C - RING_IN},{C} '
        f'A{RING_IN},{RING_IN} 0 1 1 {C + RING_IN},{C} Z"/>'
    )



def bar(fill: str) -> str:
    """The counter-change across the diamond's middle, perpendicular to the diagonal.

    No rotation: the diamond is turned forty-five degrees and this bar is not, so the two cross at a
    right angle. In canvas coordinates that makes it a plain horizontal rectangle, which is also one
    fewer transform for a renderer to interpret at sixteen pixels.

    **This is the full and mid tiers' version.** The smallest tier has none: at sixteen pixels a cut
    across a diamond lands on the two widest points of a shape that is nothing but edges, and it turns
    the mark into confetti. That tier carries the solid square and the diagonal instead.
    """
    return (
        f'  <rect x="{fmt(C - BAR_HALF_W)}" y="{fmt(C - BAR_HALF_H)}" '
        f'width="{fmt(2 * BAR_HALF_W)}" height="{fmt(2 * BAR_HALF_H)}" fill="{fill}"/>'
    )


def stripe(half_width: float, offset: float, fill: str) -> str:
    """One diagonal band: a strip of the given half-width, its centre offset across the diagonal.

    Drawn as an over-long horizontal rectangle and rotated, so a band's edges are exactly parallel to
    the composition's own angle rather than to the canvas. **`offset` is what lets two strips lie beside
    each other instead of on top of each other**, and the first version of this had no such parameter:
    the brass strip was laid exactly over the ink one, so the ink showed only at the two ends and the
    diagonal read as one dark gesture with stubs. Two plates that are printed one over the other still
    have to be offset, or there is nothing to see.
    """
    half_len = SIZE * math.sqrt(2) / 2.0
    return (
        f'  <rect x="{fmt(-half_len)}" y="{fmt(offset - half_width)}" '
        f'width="{fmt(2 * half_len)}" height="{fmt(2 * half_width)}" fill="{fill}" '
        f'transform="translate({fmt(C)} {fmt(C)}) rotate(45)"/>'
    )


def diamond(body: str) -> str:
    """The square on its corner, at the centre: the one element every tier keeps."""
    return (
        f'  <path d="M{C},{C - DIAMOND} L{C + DIAMOND},{C} L{C},{C + DIAMOND} '
        f'L{C - DIAMOND},{C} Z" {body}/>'
    )


def build(tier: str = "full") -> str:
    spec = TIERS[tier]

    pieces = [
        f'  <rect x="0" y="0" width="{SIZE}" height="{SIZE}" fill="{GROUND}"/>',
    ]

    # The circle first, so the diagonal's second plate can cross it: a brass strip over an ink ring is a
    # boundary, and a boundary between two flat colours is the only kind of contrast this drawing has.
    if spec["ring"]:
        pieces.append(ring(spec["ring"]))

    # The axis, in ink. The one device the composition cannot do without, so it is INK in every tier.
    pieces.append(stripe(AXIS_HALF, 0.0, spec["axis"]))

    if spec["band"]:
        # The second plate, offset across the diagonal so the two strips lie **beside** each other. The
        # offset is the whole point: laid one exactly over the other, as the first version did, the ink
        # showed only at the ends and the diagonal read as a single dark gesture with two stubs.
        pieces.append(stripe(BAND_HALF, BAND_OFFSET, spec["band"]))

    # The diamond, always last so it is never covered: it is the one element every tier keeps.
    if spec["cut"]:
        # Transparency over the ground, so the bar is the ground showing through and not a third ink.
        pieces.append(
            f'  <defs><mask id="bar">'
            f'<rect x="0" y="0" width="{SIZE}" height="{SIZE}" fill="white"/>'
            f'<rect x="{fmt(C - BAR_HALF_W)}" y="{fmt(C - BAR_HALF_H)}" width="{fmt(2 * BAR_HALF_W)}" '
            f'height="{fmt(2 * BAR_HALF_H)}" fill="black"/>'
            f'</mask></defs>'
        )
        pieces.append(diamond(f'fill="{spec["diamond"]}" mask="url(#bar)"'))
    else:
        pieces.append(diamond(f'fill="{spec["diamond"]}"'))
        if spec["bar"]:
            pieces.append(bar(spec["bar"]))

    body = "\n".join(pieces)
    return f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {SIZE} {SIZE}" width="{SIZE}" height="{SIZE}">
  <!--
    Hollow Court's second mark, drawn for a size and not scaled to it. Generated by
    art/make_construct_icon.py, so edit that and not this.

    A constructivist composition: one diagonal axis, one circle band, one square on its corner. No
    strokes anywhere — every edge is the boundary of a fill or of a cut — and no shadows, because a
    shape that needs a shadow to separate it from its neighbour will not survive being small.
    Tier: {tier}.
  -->
{body}
</svg>
"""


def main() -> int:
    # `newline="\n"`, for the reason the sibling generator gives: without it Windows writes CRLF and
    # Nyarch writes LF, so the same generator would produce two different files depending on where it
    # ran, and the render script regenerates these on every run.
    #
    # **Alternatives, under their own names.** `icon-hc.svg` belongs to the medallion and is not
    # touched: which mark ships is a decision for the owner, and a generator that overwrote the
    # shipping icon while offering an alternative would be making that decision by accident.
    tiers = (("full", "icon-hc-construct.svg"),
             ("mid", "icon-hc-construct-mid.svg"),
             ("small", "icon-hc-construct-small.svg"))
    for tier, name in tiers:
        out = Path(__file__).with_name(name)
        out.write_text(build(tier), encoding="utf-8", newline="\n")
        print(f"wrote {out.name} ({tier}, {out.stat().st_size} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
