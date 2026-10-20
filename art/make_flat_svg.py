#!/usr/bin/env python3
"""Traces a flat-coloured PNG into a two-colour SVG, at one exact ink.

    python3 art/make_flat_svg.py <source.png> <out.svg> [--ink 39C5BB] [--threshold 128] [--tolerance 0.6]

**Why this exists rather than a hand redraw.** The owner supplied two raster pieces drawn from a
generated image and asked for them as SVG, at a higher resolution, in one colour and no other:
「用SVG重新画，用更高像素去画，且限定#39C5BB这一种色号，不能用别的」. Redrawing a portrait by hand is
not something to promise, and it is also not what is wrong with the source. What is wrong with the
source is measurable:

  * **it is not two colours.** A sample of each image finds ~2500 distinct colours and an alpha
    channel that takes every value from 0 to 254 -- it is an anti-aliased raster, and the ink is not
    even the colour asked for (`#27B4A9` in one, `#2CA8A9` in the other).
  * **the edges are soft in the way that survives scaling badly.** Thresholding `alpha > 254` keeps
    0.5% of the frame, which is the tell that almost nothing in it is truly opaque.

So the fix is a trace, and a trace is exact about both complaints: every filled pixel becomes one
ink, and the boundary is placed where the alpha actually crosses the threshold rather than on the
nearest pixel edge.

**Sub-pixel boundaries are the point, not a refinement.** Walking pixel edges would reproduce the
staircase the raster already has -- a second kind of softness rather than a fix for the first. So the
contours are computed by marching squares over the alpha channel, which interpolates the crossing
along each cell edge and therefore follows the drawing rather than the pixel grid.

**One ink, on nothing.** The output is the single colour asked for, with the page transparent. The
source is a shape, not a picture: it has no ground of its own, and choosing one here would be
inventing a decision the caller has not made. `--ink` is the only colour this program can write.
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

import numpy as np
from PIL import Image


def parse_ink(text: str) -> tuple[int, int, int]:
    """`39C5BB`, `#39C5BB` or `0x39C5BB` into three bytes."""
    cleaned = text.strip().lstrip('#').removeprefix('0x').removeprefix('0X')
    if len(cleaned) != 6:
        raise argparse.ArgumentTypeError('an ink is six hex digits, such as 39C5BB')
    try:
        value = int(cleaned, 16)
    except ValueError as problem:
        raise argparse.ArgumentTypeError('an ink is six hex digits, such as 39C5BB') from problem
    return ((value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF)


def alpha_field(source: Path) -> np.ndarray:
    """The alpha channel as float, in row-major order.

    **Alpha rather than luminance**, because these files carry their shape in transparency: the ink is
    flat and the background is empty, so the only thing that separates them is whether a pixel is
    there at all. Reading luminance would trace the ink's own brightness, which is the same number
    everywhere and would trace nothing.
    """
    image = Image.open(source)
    if image.mode != 'RGBA':
        image = image.convert('RGBA')
    return np.asarray(image, dtype=np.float64)[:, :, 3] / 255.0


def cell_segments(field: np.ndarray, threshold: float):
    """Every boundary crossing, as pairs of points, one pair per marching-squares cell.

    The standard sixteen cases, written out rather than table-driven: the table is the same length as
    the switch and cannot be read at a glance, and three of these cases disambiguate on the cell's
    average -- which is the part a reader needs to see.
    """
    inside = field > threshold
    # The value at which a crossing is placed, as a fraction across the cell edge.
    def at(v0: float, v1: float) -> float:
        span = v1 - v0
        return 0.5 if span == 0 else (threshold - v0) / span

    segments = []
    rows, cols = field.shape
    for y in range(rows - 1):
        for x in range(cols - 1):
            v00 = field[y, x]
            v10 = field[y, x + 1]
            v11 = field[y + 1, x + 1]
            v01 = field[y + 1, x]
            code = (int(inside[y, x]) | (int(inside[y, x + 1]) << 1)
                    | (int(inside[y + 1, x + 1]) << 2) | (int(inside[y + 1, x]) << 3))
            if code == 0 or code == 15:
                continue
            # Crossing points on the four edges, named for the edge.
            top = (x + at(v00, v10), y)
            right = (x + 1, y + at(v10, v11))
            bottom = (x + at(v01, v11), y + 1)
            left = (x, y + at(v00, v01))
            case = {
                1: [(left, top)], 2: [(top, right)], 3: [(left, right)],
                4: [(right, bottom)], 5: [(left, bottom), (top, right)],
                6: [(top, bottom)], 7: [(left, bottom)],
                8: [(bottom, left)], 9: [(bottom, top)], 10: [(top, left), (bottom, right)],
                11: [(bottom, right)], 12: [(right, left)], 13: [(right, top)],
                14: [(top, left)],
            }[code]
            if code in (5, 10):
                # **The saddle, and the average decides it.** Two corners filled and two empty can be
                # read two ways; which way the ink actually goes is what the cell's middle says. Taken
                # as one answer everywhere, a diagonal stroke would be cut into separate blobs.
                middle = (v00 + v10 + v11 + v01) / 4 > threshold
                if code == 5:
                    case = [(left, bottom), (top, right)] if middle else [(left, top), (bottom, right)]
                else:
                    case = [(top, left), (bottom, right)] if middle else [(left, bottom), (right, top)]
            segments.extend(case)
    return segments


def link(segments) -> list[list[tuple[float, float]]]:
    """Chains the segments into closed rings.

    Points are keyed on their rounded coordinates, which is safe here and only here: every crossing
    lies on a cell edge, two edges of one cell meet at a corner, and the rounding is to a millionth of
    a pixel. Two crossings that are not the same point cannot collide at that precision.
    """
    def key(point):
        return (round(point[0], 6), round(point[1], 6))

    outgoing: dict[tuple[float, float], list] = {}
    for a, b in segments:
        outgoing.setdefault(key(a), []).append((a, b))

    rings = []
    for start_key in list(outgoing):
        while outgoing.get(start_key):
            ring = []
            current = start_key
            while True:
                options = outgoing.get(current)
                if not options:
                    break
                a, b = options.pop()
                ring.append(a)
                current = key(b)
                if current == start_key:
                    break
            if len(ring) >= 3:
                rings.append(ring)
    return rings


def simplify(ring, tolerance: float) -> list[tuple[float, float]]:
    """Douglas-Peucker, iteratively.

    **Iteratively rather than by recursion**, because a ring can hold tens of thousands of points and
    the recursion would be as deep as the ring is long -- which is a stack overflow on exactly the
    drawings worth tracing.
    """
    if len(ring) < 3:
        return ring
    keep = [False] * len(ring)
    keep[0] = keep[-1] = True
    stack = [(0, len(ring) - 1)]
    while stack:
        first, last = stack.pop()
        if last <= first + 1:
            continue
        ax, ay = ring[first]
        bx, by = ring[last]
        dx, dy = bx - ax, by - ay
        length = (dx * dx + dy * dy) ** 0.5
        worst, worst_at = -1.0, None
        for i in range(first + 1, last):
            px, py = ring[i]
            if length == 0:
                distance = ((px - ax) ** 2 + (py - ay) ** 2) ** 0.5
            else:
                distance = abs(dy * px - dx * py + bx * ay - by * ax) / length
            if distance > worst:
                worst, worst_at = distance, i
        if worst > tolerance and worst_at is not None:
            keep[worst_at] = True
            stack.append((first, worst_at))
            stack.append((worst_at, last))
    return [point for point, kept in zip(ring, keep) if kept]


def to_path(rings, tolerance: float, scale: float) -> str:
    parts = []
    for ring in rings:
        points = simplify(ring, tolerance)
        if len(points) < 3:
            continue
        first = points[0]
        pieces = ['M %.3f %.3f' % (first[0] * scale, first[1] * scale)]
        for x, y in points[1:]:
            pieces.append('L %.3f %.3f' % (x * scale, y * scale))
        pieces.append('Z')
        parts.append(' '.join(pieces))
    # **One path with the even-odd rule, rather than a nesting analysis.** A hole is a ring wound the
    # other way around, and even-odd fills it as a hole without anybody deciding which ring contains
    # which -- which is a containment test that costs a pass over every ring pair and gets islets wrong.
    return ' '.join(parts)


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description='trace a flat PNG into a one-ink SVG')
    parser.add_argument('source')
    parser.add_argument('out')
    parser.add_argument('--ink', default='39C5BB', help='the only colour written, as six hex digits')
    parser.add_argument('--threshold', type=float, default=0.5, help='alpha above this is ink, 0..1')
    parser.add_argument('--tolerance', type=float, default=0.35, help='simplification, in pixels')
    parser.add_argument('--scale', type=float, default=1.0, help='multiply every coordinate')
    args = parser.parse_args(argv)

    ink = parse_ink(args.ink)
    source = Path(args.source)
    if not source.is_file():
        print('%s: no such file' % source, file=sys.stderr)
        return 2

    field = alpha_field(source)
    rows, cols = field.shape
    print('  source   : %dx%d' % (cols, rows))
    print('  ink      : #%02X%02X%02X, and nothing else' % ink)

    segments = cell_segments(field, args.threshold)
    print('  crossings: %d' % len(segments))
    rings = link(segments)
    print('  rings    : %d' % len(rings))

    path = to_path(rings, args.tolerance, args.scale)
    kept = path.count('L') + path.count('M')
    print('  vertices : %d after simplification' % kept)

    width = cols * args.scale
    height = rows * args.scale
    svg = (
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<svg xmlns="http://www.w3.org/2000/svg" width="%g" height="%g" '
        'viewBox="0 0 %g %g">\n'
        '  <path fill="#%02X%02X%02X" fill-rule="evenodd" d="%s"/>\n'
        '</svg>\n' % (width, height, width, height, ink[0], ink[1], ink[2], path)
    )
    Path(args.out).write_text(svg, encoding='utf-8', newline='\n')
    print('  wrote    : %s (%.1f KB)' % (args.out, len(svg) / 1024))
    return 0


if __name__ == '__main__':
    raise SystemExit(main(sys.argv[1:]))
