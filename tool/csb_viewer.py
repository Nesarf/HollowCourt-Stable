"""Draw a CocoStudio `.csb` layout as a picture, so the interface can be looked at on a PC.

This is the point of the whole reverse-engineering exercise: the geometry is now readable
(`csb_geometry.py`, validated against a phone screenshot on the top bar), and a picture is how a layout is
actually studied -- spacing, alignment, what overlaps what.

**What it draws.** Every node becomes a rectangle at its *absolute* position (positions accumulate down the
tree), with its name written at the top-left corner and its widget type shown by outline colour. Where a node
names a texture, the PNG is blitted from the extracted assets when it can be found -- so a screen made of
pictures looks like a screen rather than a wireframe.

**What it does not draw.** Text is written as the node's name and its string content, not in the real font at the
real size; rotation, scale and anchor-point offsets are applied approximately; and a node's own transform is not
composed with its children's beyond position. It is a **layout viewer**, not a renderer -- and saying so here is
the difference between a tool and a claim.

Usage:
    python tool/csb_viewer.py <file.csb> <assets-root> <out.png> [--no-textures]
"""

import os
import re
import sys

from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from csb_geometry import fields, options_of, string_at, u32, vec2, vector_tables  # noqa: E402
from csb_dump import looks_like_table, spans  # noqa: E402

# One colour per widget type, so the shape of a screen is readable at a glance.
COLOURS = {
    'Button': (60, 120, 220),
    'Sprite': (60, 160, 90),
    'Text': (230, 140, 40),
    'ImageView': (150, 90, 200),
    'SingleNode': (120, 120, 120),
}
DEFAULT_COLOUR = (90, 90, 90)


def safe_u32(data, at):
    """A u32 read that answers None instead of raising when the offset is past the end of the file.

    **This is the fix for the unreadable nodes, not the try/except around them.** Without a schema every field is
    a guess, and a guess that lands outside the buffer is a normal event rather than an exceptional one -- so the
    reads are guarded and the callers treat None as "this field was not a field".
    """
    if at is None or at < 0 or at + 4 > len(data):
        return None
    return u32(data, at)


def safe_vec2(data, at):
    if at is None or at < 0 or at + 8 > len(data):
        return None
    return vec2(data, at)


def safe_string(data, at):
    if at is None or at < 0 or at + 4 > len(data):
        return None
    try:
        return string_at(data, at)
    except Exception:
        return None


def type_and_options(data, node):
    """A node's class name and the table holding its WidgetOptions."""
    classname = safe_string(data, fields(data, node).get(0)) or ''
    return classname, options_of(data, node)


def texture_name(data, node, classname):
    """The file a node draws, following the schema: SpriteOptions.fileNameData, ButtonOptions.*Data."""
    options = options_of(data, node)
    if options is None:
        return None
    # options is the WidgetOptions; its parent payload holds the type-specific table, which is one level up in
    # practice, so look for the payload through the node instead and read the usual string fields.
    payload = None
    options_table = fields(data, node).get(2)
    if options_table is not None:
        outer = options_table + u32(data, options_table)
        if looks_like_table(data, outer):
            for _index, off, _width in spans(data, outer):
                if off == 0:
                    continue
                at = outer + off
                candidate = at + u32(data, at)
                if looks_like_table(data, candidate):
                    payload = candidate
                    break
    if payload is None:
        return None
    # **The texture path lives one table deeper than it looks.** `SpriteOptions.fileNameData` and
    # `ButtonOptions.normalData/pressedData/disabledData` are `ResourceData` tables -- `{path, plistFile,
    # resourceType}` -- so the string is inside a nested table, not in a field of the payload. The first version
    # looked only at the payload's own fields and therefore blitted nothing, while the file cheerfully said
    # `layouts/1080/topbar/top_button_settings.png` a few bytes away.
    found = set()

    def harvest(table, depth):
        if depth > 3 or table is None:
            return
        for _index, off, _width in spans(data, table):
            if off == 0:
                continue
            at = table + off
            text = safe_string(data, at)
            if text and re.search(r'\.(png|jpg|jpeg)$', text, re.I):
                found.add(text)
                continue
            step = safe_u32(data, at)
            if step is None:
                continue
            target = at + step
            if target < len(data) and looks_like_table(data, target):
                harvest(target, depth + 1)

    harvest(payload, 0)
    if not found:
        return None
    # Prefer a name that mentions the node, else the longest.
    for name in sorted(found, key=len, reverse=True):
        return name
    return None


SKIPPED = [0]


def collect(data, node, depth, px, py, out, budget):
    if budget[0] <= 0 or depth > 12:
        return
    budget[0] -= 1
    try:
        _collect_inner(data, node, depth, px, py, out, budget)
    except Exception:
        # **Counted, not hidden.** A field read as an offset that is really a scalar lands outside the buffer
        # sooner or later; the screen still draws, and the number of nodes that could not be read is printed
        # with the result rather than swallowed.
        SKIPPED[0] += 1


def _collect_inner(data, node, depth, px, py, out, budget):
    classname, widget = type_and_options(data, node)
    name = position = size = None
    if widget is not None:
        f = fields(data, widget)
        name = string_at(data, f.get(0))
        position = vec2(data, f.get(7)) or (0.0, 0.0)
        size = vec2(data, f.get(11))
    x = px + (position[0] if position else 0.0)
    y = py + (position[1] if position else 0.0)
    if size and size[0] > 0 and size[1] > 0:
        out.append({
            'name': name or classname or '?',
            'classname': classname,
            'x': x, 'y': y, 'w': size[0], 'h': size[1],
            'depth': depth,
            'texture': texture_name(data, node, classname),
        })
    for child in vector_tables(data, node, 1):
        collect(data, child, depth + 1, x, y, out, budget)


def load(data_path):
    data = open(data_path, 'rb').read()
    root_table = u32(data, 0)
    nodes = []
    for _index, off, _width in spans(data, root_table):
        if off == 0:
            continue
        at = root_table + off
        target = at + u32(data, at)
        if not looks_like_table(data, target):
            continue
        for child in vector_tables(data, target, 1):
            collect(data, child, 0, 0.0, 0.0, nodes, [6000])
    return nodes


def main():
    data_path, assets_root, out_path = sys.argv[1], sys.argv[2], sys.argv[3]
    with_textures = '--no-textures' not in sys.argv
    nodes = load(data_path)
    if not nodes:
        print('no nodes with a size found')
        return 1

    # The canvas: the bounding box of everything, padded, with the origin included so off-screen nodes show.
    min_x = min(0.0, min(n['x'] - n['w'] / 2 for n in nodes))
    min_y = min(0.0, min(n['y'] - n['h'] / 2 for n in nodes))
    max_x = max(n['x'] + n['w'] / 2 for n in nodes)
    max_y = max(n['y'] + n['h'] / 2 for n in nodes)
    pad = 20
    scale = 1.0
    width = int((max_x - min_x) + pad * 2)
    height = int((max_y - min_y) + pad * 2)
    # Keep the picture a sensible size: a 1920-wide canvas stays 1:1, a bigger one shrinks.
    if width > 2200:
        scale = 2200 / width
    image = Image.new('RGB', (int(width * scale), int(height * scale)), (18, 18, 22))
    draw = ImageDraw.Draw(image, 'RGBA')

    def to_px(x, y):
        return ((x - min_x + pad) * scale, (y - min_y + pad) * scale)

    blitted = 0
    for node in nodes:
        colour = COLOURS.get(node['classname'], DEFAULT_COLOUR)
        x, y = to_px(node['x'], node['y'])
        w, h = node['w'] * scale, node['h'] * scale
        box = [x - w / 2, y - h / 2, x + w / 2, y + h / 2]

        if with_textures and node['texture']:
            # Paths in the layouts are relative to the asset root and use forward slashes.
            relative = node['texture'].replace('\\', '/')
            for candidate in (relative, 'layouts/1080/' + relative, 'img/' + relative):
                full = os.path.join(assets_root, candidate)
                if os.path.isfile(full):
                    try:
                        sprite = Image.open(full).convert('RGBA')
                        sprite = sprite.resize((max(1, int(w)), max(1, int(h))))
                        image.paste(sprite, (int(box[0]), int(box[1])), sprite)
                        blitted += 1
                    except Exception:
                        pass
                    break

        draw.rectangle(box, outline=colour + (230,), width=2)
        if scale > 0.35:
            draw.text((box[0] + 3, box[1] + 2), node['name'][:34], fill=(255, 255, 255, 235))

    image.save(out_path)
    print('nodes with geometry: %d   textures blitted: %d   nodes unreadable: %d'
          % (len(nodes), blitted, SKIPPED[0]))
    print('canvas: x %.0f..%.0f  y %.0f..%.0f   (design units)' % (min_x, max_x, min_y, max_y))
    print('wrote %s  (%dx%d)' % (out_path, image.size[0], image.size[1]))
    return 0


if __name__ == '__main__':
    sys.exit(main())
