"""Build a labelled contact sheet from a directory of PNGs, composited on a dark ground.

**Why the dark ground is the point.** White-on-transparent artwork renders as a blank square: the rhythm game study
lost a pass to this with `title_logo_white` (89,162 opaque pixels of 524,288 -- "the picture is empty" was really
"the picture is white"), and a mobile game's `pattern_artdeco_line` is the same trap. A reference set has to
be looked at on the ground it was drawn for, or the review is of the background.

Usage: python tool/sheet_on_dark.py <dir> <out.png> [--match substr] [--columns N] [--cell PX] [--limit N]
"""

import os
import sys

from PIL import Image, ImageDraw


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    if len(args) < 2:
        print(__doc__.strip().splitlines()[0])
        return 2
    source, out = args[0], args[1]

    match = ''
    columns, cell, limit = 6, 200, 30
    for arg in sys.argv[1:]:
        if arg.startswith('--match'):
            match = arg.split('=', 1)[1] if '=' in arg else ''
        elif arg.startswith('--columns'):
            columns = int(arg.split('=', 1)[1])
        elif arg.startswith('--cell'):
            cell = int(arg.split('=', 1)[1])
        elif arg.startswith('--limit'):
            limit = int(arg.split('=', 1)[1])

    names = sorted(n for n in os.listdir(source) if n.lower().endswith('.png') and match.lower() in n.lower())
    if not names:
        print('no files matched')
        return 1
    names = names[:limit]

    rows = (len(names) + columns - 1) // columns
    label_height = 14
    sheet = Image.new('RGB', (columns * cell, rows * (cell + label_height)), (18, 16, 22))
    draw = ImageDraw.Draw(sheet)
    for index, name in enumerate(names):
        row, column = divmod(index, columns)
        try:
            image = Image.open(os.path.join(source, name)).convert('RGBA')
        except Exception as error:
            print('unreadable: %s (%s)' % (name, error))
            continue
        image.thumbnail((cell, cell), Image.LANCZOS)
        # Centred on the cell, over the dark ground, so transparency shows as the ground rather than as white.
        x = column * cell + (cell - image.width) // 2
        y = row * (cell + label_height) + (cell - image.height) // 2
        sheet.paste(image, (x, y), image)
        draw.text((column * cell + 3, row * (cell + label_height) + cell + 1), name[:34], fill=(190, 180, 200))

    sheet.save(out)
    print('%d textures -> %s (%dx%d)' % (len(names), out, sheet.width, sheet.height))
    return 0


if __name__ == '__main__':
    sys.exit(main())
