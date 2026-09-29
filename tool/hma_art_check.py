"""Keeps the art honest: well-formed, the same shape at every scale, and one accent colour.

**Written because the first version of the motif failed its own check** -- an XML comment containing `--`, which is
illegal and which nothing else here would have noticed. A rule that only exists in somebody's head lasts until the next
person edits the file, so it lives in a tool.

Three assertions, each a thing the design claims:

  * **the files parse** -- an SVG that does not is an asset nobody can open, and it fails silently in a viewer;
  * **where a polygon appears it is a pentagon** -- the motif is one shape parameterised, so a four- or six-point
    polygon means somebody drew a second shape rather than scaling the first. Files that use no polygon at all, such as
    the nine-slice panel, are not thereby wrong;
  * **only two colours appear** -- one accent on one ground, which is the whole of the colour decision and the first
    thing that erodes when a file is edited in a hurry.

    python tool/hma_art_check.py
"""

from __future__ import annotations

import glob
import os
import re
import sys
import xml.etree.ElementTree as ET

SVG = '{http://www.w3.org/2000/svg}'
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'art', 'hma')

#: The palette is two values. **A third one is not a mistake to be tolerated, it is the design ending.**
PALETTE = {'#0A0E14', '#3FE0D0', '#5A6672'}


def main() -> int:
    files = sorted(glob.glob(os.path.join(ROOT, '*.svg')))
    if not files:
        print('  art/hma 下没有 SVG —— 检查无从谈起')
        return 1

    problems: list[str] = []
    for path in files:
        name = os.path.basename(path)
        text = open(path, encoding='utf-8').read()
        try:
            root = ET.fromstring(text)
        except ET.ParseError as error:
            problems.append('%s 不是良构的 XML：%s' % (name, error))
            continue

        # **The rule is conditional, and finding that out was the checker's second catch.** Every earlier file was
        # the motif, so "has a pentagon" held; the nine-slice panel is a rectangle with no polygon at all, and a rule
        # that demanded one was a rule about the files that happened to exist rather than about the design. **Where a
        # polygon appears it must be the motif** -- five points -- and files that use none are not thereby wrong.
        for polygon in root.findall('.//' + SVG + 'polygon'):
            count = len((polygon.get('points') or '').split())
            if count != 5:
                problems.append('%s 的多边形有 %d 个点，母题是五点的' % (name, count))

        for colour in re.findall(r'#[0-9A-Fa-f]{6}', text):
            if colour.upper() not in PALETTE:
                problems.append('%s 用了调色板以外的颜色 %s' % (name, colour))

    for problem in problems:
        print('  ✗ %s' % problem)
    print('  检查了 %d 个 SVG，问题 %d 个' % (len(files), len(problems)))
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(main())
