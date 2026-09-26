#!/usr/bin/env python3
"""Draws the Hollow Court mark: a Renaissance medallion with HC at its centre.

    python art/make_icon.py            # writes art/icon-hc.svg
    rsvg-convert -w 1024 -h 1024 art/icon-hc.svg -o art/render/icon-hc-1024.png

WHY A GENERATOR AND NOT A HAND-WRITTEN SVG. The interesting parts of this mark are the two
letterforms, and the boring parts are roughly ninety repeated elements -- beads around a moulding,
leaves along two branches. Hand-writing the beads would be ninety chances to be one degree out, and
the result would be a file nobody could adjust. Here the ornament is a loop with a parameter, and
the letters are constructed from their own geometry, so "make the stems heavier" is a number.

WHY THE LETTERS ARE PATHS AND NOT `<text>`. A logo that depends on a font being installed is a logo
that renders differently on the next machine, and the render is what ships. `rsvg-convert` would
happily pick whatever `serif` resolves to -- here that is some Noto face, elsewhere it is something
else -- and the mark would quietly change.

A previous version built the letters from rectangles, trapezoids and two arcs: a Roman capital, drawn by
hand, with no font involved. A later one extracted the outlines of two blackletter capitals from an
OFL-1.1 typeface and committed them as geometry, which is a real way to work and was the honest thing to
do while the mark carried letters at all. The letters have since been removed: the centre of the mark is
the crystal, drawn here from four nested offset diamonds, so nothing is extracted from anything. What has
never changed is the rule -- this file needs no font, and neither does `rsvg-convert`, so the render on
the next machine is the render on this one.

THE PALETTE IS THE APPLICATION'S. The ground is the app's warm near-black, the field is the ink
colour aged into parchment, and the frame is brass rather than gold: a saturated gold beside
`#14110F` reads as a sticker, while brass sits in the same warm family as the app's rose accent.
"""
from __future__ import annotations

import math
from pathlib import Path

# **The letters are drawn by this project, not outlined from a typeface.** See `textura_glyphs.py` for why that
# changed and what it buys: an icon that ships in three formats with nothing to license and nothing to attribute.

# ---- the app's own colours, so the mark and the interface agree ----
GROUND = "#14110F"
INK = "#EDE4D8"
ROSE = "#C9848C"

# Brass, aged: a highlight that is not white, a mid that is not orange, a shadow that is not brown.
BRASS_HI = "#E4CB94"
BRASS = "#B79355"
BRASS_LO = "#6E5528"

# Parchment: warm, and lit from the upper left as if by a window.
PARCHMENT_HI = "#F2E8D6"
PARCHMENT = "#DCCBAE"
PARCHMENT_LO = "#B49F7F"

# The letters are nearly black but warm, because pure black on parchment reads as a printing error.
LETTER = "#241C14"

# Height in the mark's own units, and the gap between the capitals. Both are numbers here so that
# "make them larger" and "open the pair up" are edits to one line each -- which is the reason this
# file is a generator at all.
LETTER_HEIGHT = 268.0
LETTER_GAP = 20.0

SIZE = 1024
C = SIZE / 2

# Radii, outer to inner.
R_EDGE = 470          # the disc's edge, inside the square so a launcher's round mask cannot bite it
R_BRASS_IN = 452      # brass band
R_BEAD = 445          # bead-and-reel moulding centre line
R_FIELD = 424         # parchment field
# The halo, from the character sheet: from the inside out, a rainbow bismuth crystal, a white ring and
# twenty-four dark pyramids, the whole plane tilted fifteen degrees clockwise. Those three radii are
# these three.
R_PYRAMID = 384       # the twenty-four, outermost
R_WHITE = 344         # the white ring
R_BISMUTH_OUT = 312   # the rainbow crystal band
R_BISMUTH_IN = 286

# Fifteen degrees clockwise, and it is the one number in this file that comes from a document
# rather than from taste.
HALO_TILT = 15.0

# ---- three drawings of the same mark, chosen by the size it will be seen at ----
#
# **The rule this follows was already in `render_icons.sh` before this existed**: "the 16 in the taskbar is a
# 16 drawn at 16", rather than a 1024 resampled down. That principle was only being honoured for the *frame*;
# the drawing inside it was identical at every size, so the twenty-four pyramids, the seventy-two beads and the
# eight-stop bismuth ramp all collapsed into a grey ring below 48 pixels. A mark that ships at fifteen sizes
# has to be drawn for the sizes it ships at.
#
# The reference for how to do it is a crafting game's mark:
# one flat silhouette, detail carried by negative space rather than by thin lines, two inks on paper, and the
# whole thing legible as a stamp. Their oak branches are a solid shape with the veins cut out of it; ours are
# rings with fine detail *added*, which is the opposite and does not survive being small.
#
# So: the same medallion, drawn at three densities. Nothing about the identity changes -- the halo keeps its
TIERS = {
    #          beads  pyramids  hues  letter  fatten  white  band
    "full":    dict(beads=72, pyramids=24, hues=8, letter=268, fatten=0,  white=True,  band=26),
    "mid":     dict(beads=0,  pyramids=12, hues=5, letter=300, fatten=0,  white=True,  band=40),
    # **The small tier carries the crystal and nothing else.** At sixteen pixels the medallion's rim, its beads
    # and its pyramids are not small marks, they are noise: the rendering showed a warm blur with no readable
    # shape in it. `plain` drops everything except the ground and the emblem, which is the one thing that has to
    # survive -- the same decision the tiers already made about hues, taken one step further.
    "small":   dict(beads=0,  pyramids=8,  hues=2, letter=352, fatten=26, white=False, band=58, plain=True),
}


def polar(radius: float, degrees: float) -> tuple[float, float]:
    """A point on a circle. Degrees clockwise from three o'clock, matching SVG's y-down axes."""
    radians = math.radians(degrees)
    return (C + radius * math.cos(radians), C + radius * math.sin(radians))


def fmt(value: float) -> str:
    """Two decimals, and no trailing `.00` -- the file is meant to be readable."""
    out = f"{value:.2f}"
    return out[:-3] if out.endswith(".00") else out


def path(points: list[tuple[float, float]], close: bool = True, fill: str | None = None) -> str:
    """One `<path>` element from a list of corners.

    **The element, not the `d` string.** The first version returned the path data and the caller put
    it inside a `<g>`, which is not SVG: path data is an attribute value, so the letters were emitted
    as text content and rendered as nothing at all. The medallion came out perfectly and the two
    letters the mark is named for were simply absent, which is the sort of thing only looking at the
    render catches.
    """
    body = " ".join(
        f"{'M' if i == 0 else 'L'}{fmt(x)},{fmt(y)}" for i, (x, y) in enumerate(points)
    )
    data = f"{body} Z" if close else body
    paint = f' fill="{fill}"' if fill else ""
    return f'<path d="{data}"{paint}/>'


def glyph(data: str, x: float, y: float, height: float) -> str:
    """Places one letterform, supplied as path data, with its left edge at [x] and [height] tall.

    **Scaled by height alone, and it is not a shortcut.** The outlines are normalised to 1000 units tall, and each
    carries the aspect it actually has -- 0.891 for one letter, 0.903 for the other. Giving both letters one box
    would have to stretch one of them, and a stretched capital breaks the relationship between a letter's width
    and its diagonal strokes.

    The caller positions by left edge rather than by centre, because the pair has to be laid out as a pair -- see
    the two calls in [build], where the gap between them is the number that matters.
    """
    scale = height / 1000
    return (
        f'<g transform="translate({fmt(x)} {fmt(y)}) scale({fmt(scale)})">'
        f'<path d="{data}"/></g>'
    )


def letter_width(height: float, aspect: float) -> float:
    """How wide a letter of [height] comes out, so a caller can place the next one after it."""
    return height * aspect

def halo(tier: str = "full") -> str:
    """The character's halo, drawn as the medallion's inner structure.

    Three rings, in the order the character sheet gives them from the inside out: a rainbow bismuth
    crystal, a white ring, and twenty-four dark pyramids. The whole group is rotated fifteen degrees
    clockwise, which is also from the sheet.

    **Each pyramid is two triangles, not one.** A single triangle reads as a spike; two faces in
    different shades with a shared edge read as a solid with a light side and a dark side, which is
    what "a three-dimensional pyramid" asks for and what makes twenty-four of them legible as objects
    rather than as a sawtooth. The faces are drawn as one path so the shared edge cannot show a seam
    -- the same lesson the C's terminals taught earlier in this file.
    """
    out = []

    # The bismuth band: a rainbow, banded rather than blended.
    #
    # Real bismuth oxidises in steps, and the steps are the point -- a smooth gradient reads as a
    # plastic ring, while discrete segments with hard edges read as crystal. The ramp runs gold,
    # rose, violet, blue, teal and back, because that is the order the oxide film produces.
    spec = TIERS[tier]
    # The band keeps its centre line and grows both ways, so the ring, the pyramids and the letters keep the
    # proportions the character sheet gave them and only the *weight* of the crystal changes with size.
    band_mid = (R_BISMUTH_OUT + R_BISMUTH_IN) / 2
    band_out = band_mid + spec["band"] / 2
    band_in = band_mid - spec["band"] / 2
    # **Two inks on paper, which is the one thing the reference mark does that this one did not.** The first
    # cut of the smallest tier kept four crystal hues and the comparison render showed what that costs: at 24
    # pixels a four-colour band is a bright ring competing with the letters it surrounds, and the letters are
    # the mark. So the two smallest densities use the application's own two accents -- gold and rose, the same
    # pair the interface uses for "chosen" and "important" -- and the full density keeps the oxide ramp,
    # because at 128 pixels and up there is room for the crystal to be a crystal.
    oxide = ["#E4C271", "#D99A63", "#CE7A82", "#A96E9E", "#7B76B4", "#5E8FB8", "#63B0A8", "#8FC79C"]
    inks = ["#E4C271", "#CE7A82"]
    ramp = inks if spec["hues"] == 2 else oxide[: spec["hues"]]
    # Four facets per hue at full density, two at the middle one: fewer, larger segments are what a small
    # icon needs, and the ramp is cut short as well so that the band reads as two or three colours rather
    # than as a blurred spectrum.
    segments = len(ramp) * (4 if tier == "full" else 2)
    span = 360.0 / segments
    for i in range(segments):
        a0 = i * span
        a1 = a0 + span * 1.02          # the overlap keeps neighbouring segments from leaving a gap
        p0 = polar(band_out, a0)
        p1 = polar(band_out, a1)
        p2 = polar(band_in, a1)
        p3 = polar(band_in, a0)
        points = " ".join(f"{fmt(x)},{fmt(y)}" for x, y in (p0, p1, p2, p3))
        out.append(f'    <polygon points="{points}" fill="{ramp[i % len(ramp)]}"/>')

    # The white ring, thin and bright: the middle element, and what stops the bismuth from simply
    # running into the pyramids. **Dropped entirely in the smallest tier**, where a 13-unit stroke is a
    # fifth of a pixel and all it can do is grey the gap it was meant to clarify.
    if TIERS[tier]["white"]:
        out.append(
        f'    <circle cx="{C}" cy="{C}" r="{R_WHITE}" fill="none" '
        f'stroke="{INK}" stroke-width="13"/>'
    )
    out.append(
        f'    <circle cx="{C}" cy="{C}" r="{R_WHITE}" fill="none" '
        f'stroke="#FFFFFF" stroke-width="5" stroke-opacity="0.65"/>'
    )

    # The twenty-four, each with a lit face and a shadowed one.
    count = TIERS[tier]["pyramids"]
    # Bigger when there are fewer of them, so the ring reads as a ring of objects at any density rather
    # than as a sawtooth: at 24 they are 34 tall, at 8 they are 84.
    height = 34 if count >= 24 else (52 if count >= 12 else 84)
    half = 13 if count >= 24 else (22 if count >= 12 else 40)
    for i in range(count):
        degrees = 360.0 * i / count
        apex = polar(R_PYRAMID + height, degrees)
        left = polar(R_PYRAMID, degrees - half * 0.36)
        right = polar(R_PYRAMID, degrees + half * 0.36)
        tip = polar(R_PYRAMID + 2, degrees)
        # light face then dark face, sharing the spine from base to apex
        out.append(
            f'    <path d="M{fmt(left[0])},{fmt(left[1])} L{fmt(apex[0])},{fmt(apex[1])} '
            f'L{fmt(tip[0])},{fmt(tip[1])} Z" fill="#4A4038"/>'
        )
        out.append(
            f'    <path d="M{fmt(right[0])},{fmt(right[1])} L{fmt(apex[0])},{fmt(apex[1])} '
            f'L{fmt(tip[0])},{fmt(tip[1])} Z" fill="#241C14"/>'
        )
    return "\n".join(out)


def beads(tier: str = "full") -> str:
    """The bead-and-reel moulding: a ring of small spheres, each with its own highlight.

    This is the detail that says Renaissance rather than modern, and it is also the detail that
    disappears first when the icon is drawn at 32 pixels -- where it reads as a textured ring, which
    is all it needs to do. The highlights are what stop it looking like a dotted line.
    """
    count = TIERS[tier]["beads"]
    if count == 0:
        # The moulding cannot be drawn small, so at the lower densities the band becomes one flat ring.
        # A dotted ring at 32 pixels is a texture, and a texture is noise at that size.
        return f'    <circle cx="{C}" cy="{C}" r="{R_BEAD}" fill="none" stroke="{BRASS_LO}" stroke-width="10"/>'
    out = []
    for i in range(count):
        degrees = 360.0 * i / count
        x, y = polar(R_BEAD, degrees)
        r = 15.0
        out.append(
            f'    <circle cx="{fmt(x)}" cy="{fmt(y)}" r="{r}" fill="url(#bead)"/>'
        )
    return "\n".join(out)


# `laurel()` used to live here. It was removed when the halo arrived: the character sheet's
# twenty-four pyramids are the ornament inside the field, and the two rings of detail fought each
# other -- the branches ran through the pyramids and made both harder to read. Kept as a note rather
# than as dead code, because the branches were a deliberate choice once and the reason they went is
# worth having.

def prism(height: float, facet: float, steps: int = 4) -> str:
    """The centre of the mark: **the halo's own crystal, drawn as the crystal it is.**

    The two letters that used to stand here were outlined from a text face, and that made the one part of this
    mark that was not this project's -- a licence question inside an icon that ships in three formats. The owner
    removed the question on 2026-09-25 by removing the letters: the two letters HC were not needed.

    What replaces them is already the application's motif: the bismuth crystal from the halo, which also appears in
    the dividers, in the navigation's selected state and in the ornament behind every page.

    **Two attempts taught what a crystal is not.** A flat rhombus split into light and shadow read as a blade; a
    wider one with softer faces read as a pale triangle. Real bismuth is a *hopper* crystal -- nested plates,
    each a step in from the last, which is the shape's whole signature and the reason it is recognisable at all.
    So this is a stack of four diamonds, each inset and nudged along the plane, in alternating brass tones, with
    the palette's rose at the core. Drawn on the halo's own fifteen degrees.
    """
    plates = []
    for index in range(steps):
        scale = 1.0 - index * (0.78 / max(steps - 1, 1))
        half_h = (height / 2) * scale
        half_w = half_h * 0.86
        # Each plate slides a little down-left: the hopper's lip, and what stops the stack reading as a target.
        drift = height * 0.045 * index
        cx = C - drift * 0.5
        cy = C + drift
        top = (cx, cy - half_h)
        right = (cx + half_w, cy)
        bottom = (cx, cy + half_h)
        left = (cx - half_w, cy)
        face = BRASS_HI if index % 2 == 0 else BRASS
        plates.append(path([top, right, bottom, left], fill=face))
    # The core grows as the detail goes: at sixteen pixels the plates are a warm blur, and this is what is left
    # to say "there is something bright in the middle".
    core_r = height * (0.06 if steps >= 4 else 0.13)
    core = f'<circle cx="{fmt(C)}" cy="{fmt(C)}" r="{fmt(core_r)}" fill="{ROSE}"/>'
    return "".join(plates) + core


def build(tier: str = "full") -> str:
    spec = TIERS[tier]
    plain = spec.get("plain", False)
    # **A plain tier skips the whole medallion.** The sixteen-pixel rendering was a warm blur: a bead-and-reel
    # moulding, a pyramid ring and a bismuth band are not small marks at that size, they are noise around the one
    # shape that has to survive. What is left is the ground, its lattice and the crystal -- which came from the
    # halo in the first place, so the identity is intact and only the ornament is gone.
    medallion = "" if plain else f"""  <!-- The disc, on a dark rim so the mark holds an edge on a light background. -->
  <circle cx="{C}" cy="{C}" r="{R_EDGE + 14}" fill="#000000" fill-opacity="0.45"/>
  <circle cx="{C}" cy="{C}" r="{R_EDGE}" fill="{GROUND}"/>
  <circle cx="{C}" cy="{C}" r="{R_EDGE - 14}" fill="url(#brass)"/>
  <circle cx="{C}" cy="{C}" r="{R_BRASS_IN}" fill="{BRASS_LO}"/>

  <!-- The moulding, or one flat ring where a moulding cannot be drawn. -->
{beads(tier)}

  <!-- The field, its rule, and the two branches. -->
  <circle cx="{C}" cy="{C}" r="{R_FIELD}" fill="url(#field)"/>
  <circle cx="{C}" cy="{C}" r="{R_FIELD}" fill="url(#vignette)"/>
  <!-- The halo, tilted as one plane, exactly as the character sheet describes it. -->
  <g transform="rotate({HALO_TILT} {C} {C})">
{halo(tier)}
  </g>
"""
    # `letter` and `fatten` keep their names for the tiers' sake and now mean the emblem's height and the width
    # of its facet line: the tiers still describe how much detail the size can carry, which is all they ever did.
    emblem = prism(spec["letter"] * 1.55, max(spec["fatten"] * 0.10, 2.0), steps=spec.get("plates", 4))
    return f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {SIZE} {SIZE}" width="{SIZE}" height="{SIZE}">
  <!--
    Hollow Court's mark. Generated by art/make_icon.py, so edit that and not this.

    A Renaissance medallion: brass moulding, a bead-and-reel band, a laurel tied at the foot, and
    the two letters the name shortens to set in Roman capitals on the parchment inside. The
    construction is described where it is built, in the generator, because a description here would
    be a second copy of it.
  -->
  <defs>
    <radialGradient id="field" cx="38%" cy="31%" r="82%">
      <stop offset="0%" stop-color="{PARCHMENT_HI}"/>
      <stop offset="58%" stop-color="{PARCHMENT}"/>
      <stop offset="100%" stop-color="{PARCHMENT_LO}"/>
    </radialGradient>

    <linearGradient id="brass" x1="0" y1="0" x2="0.85" y2="1">
      <stop offset="0%" stop-color="{BRASS_HI}"/>
      <stop offset="42%" stop-color="{BRASS}"/>
      <stop offset="100%" stop-color="{BRASS_LO}"/>
    </linearGradient>

    <radialGradient id="bead" cx="35%" cy="30%" r="75%">
      <stop offset="0%" stop-color="{BRASS_HI}"/>
      <stop offset="70%" stop-color="{BRASS}"/>
      <stop offset="100%" stop-color="{BRASS_LO}"/>
    </radialGradient>

    <linearGradient id="leaf" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0%" stop-color="{BRASS}"/>
      <stop offset="100%" stop-color="{BRASS_LO}"/>
    </linearGradient>

    <!-- **The lattice, which is the same motif the interface draws behind everything.** Android does not
         treat a transparent icon background the way Windows and Linux do: a launcher shows the square it was
         given, so a disc floating in transparency reads as an empty tile on a home screen. The square is
         therefore filled: the ground colour, then the rhombus lattice over it, and the medallion sits on that
         rather than on nothing. -->
    <pattern id="lattice" width="128" height="128" patternUnits="userSpaceOnUse" patternTransform="rotate(45)">
      <rect width="128" height="128" fill="none"/>
      <path d="M0 64 L64 0 L128 64 L64 128 Z" fill="none" stroke="#EDE4D8" stroke-opacity="0.07"
            stroke-width="2.5"/>
    </pattern>

    <!-- The parchment darkens toward the edge, which is what a round field of anything does. -->
    <radialGradient id="vignette" cx="42%" cy="34%" r="72%">
      <stop offset="0%" stop-color="#000000" stop-opacity="0"/>
      <stop offset="72%" stop-color="#3A2A16" stop-opacity="0.10"/>
      <stop offset="100%" stop-color="#2A1D0E" stop-opacity="0.30"/>
    </radialGradient>
  </defs>

  <!-- The square first: ground, then the lattice the interface uses. -->
  <rect x="0" y="0" width="{SIZE}" height="{SIZE}" fill="{GROUND}"/>
  <rect x="0" y="0" width="{SIZE}" height="{SIZE}" fill="url(#lattice)"/>

{medallion}
    {emblem}
  </g>

  <g transform="translate({C} {C + 208})">
    <path d="M0,-26 L18,0 L0,26 L-18,0 Z" fill="url(#brass)"/>
    <path d="M-34,0 L-58,-12 M34,0 L58,-12" stroke="{BRASS}" stroke-width="6" stroke-linecap="round"/>
    <circle cx="0" cy="0" r="5" fill="{ROSE}" fill-opacity="0.9"/>
  </g>
</svg>
"""


if __name__ == "__main__":
    # `newline="\n"`, because without it Windows writes CRLF and Nyarch writes LF: the
    # same generator then produces two different files depending on where it runs, which shows
    # up as a spurious diff rather than as a bug. The render script regenerates these files on
    # every run, so the two would otherwise take turns overwriting each other.
    #
    # Three files, one per density, and `render_icons.sh` renders each size from the one drawn for it. The
    # unsuffixed name stays the full-detail drawing, because that is the file a reader and the documentation
    # point at.
    tiers = (("full", "icon-hc.svg"), ("mid", "icon-hc-mid.svg"), ("small", "icon-hc-small.svg"))
    for tier, name in tiers:
        out = Path(__file__).with_name(name)
        out.write_text(build(tier), encoding="utf-8", newline="\n")
        print(f"wrote {out.name} ({tier}, {out.stat().st_size} bytes)")
