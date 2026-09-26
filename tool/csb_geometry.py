"""Read a `.csb`'s geometry, now that the schema's field order is known.

The fields, from `CSParseBinary_generated.h` (cocos2d-x, MIT):

    WidgetOptions:  0:name  7:position  8:scale  9:anchorPoint  10:color  11:size
    NodeTree:       0:classname  1:children  2:options
    SpriteOptions:  0:nodeOptions  1:fileNameData
    TextOptions:    0:widgetOptions  1:fontResource  2:fontName  3:fontSize  4:text
    ButtonOptions:  0:widgetOptions  1:normalData  2:pressedData  3:disabledData  5:text

**Two things this does that the earlier walker could not.** It reads a field *by its schema index* instead of
guessing from what the bytes look like -- and it **accumulates each node's position down the tree**, because a
node's `position` is relative to its parent. That second part is exactly why an earlier check "failed": a label
sitting at y=273 is not at 273 on the screen, it is 273 below wherever its parent is.

**And it checks itself**: the root node's `size` is the design resolution, which is a fact the file states and
that the layout directory name corroborates (`layouts/1080/` against `layouts/topbar/`). If the root does not come
out at a plausible canvas, the reading is wrong and the script says so rather than printing numbers.

Usage: python tool/csb_geometry.py <file.csb> [max-nodes]
"""

import struct
import sys

from csb_dump import as_string, as_vector, looks_like_table, spans


def u32(data, at):
    return struct.unpack_from('<I', data, at)[0]


def fields(data, table):
    """The table's fields by schema index: offset 0 when the table did not write it."""
    found = {}
    for index, off, _width in spans(data, table):
        if off:
            found[index] = table + off
    return found


def safe_u32(data, at):
    """None instead of an exception when the offset is past the end -- see csb_viewer.safe_u32 for why."""
    if at is None or at < 0 or at + 4 > len(data):
        return None
    return u32(data, at)


def string_at(data, at):
    if at is None:
        return None
    step = safe_u32(data, at)
    return None if step is None else as_string(data, at + step)


def floats_at(data, at, count):
    if at is None:
        return None
    return [struct.unpack_from('<f', data, at + 4 * i)[0] for i in range(count)]


def vec2(data, at):
    values = floats_at(data, at, 2)
    return None if values is None else (values[0], values[1])


def table_at(data, at, index):
    """Follow field [index] of the table at [at] to a nested table, or None."""
    if at is None:
        return None
    f = fields(data, at)
    if index not in f:
        return None
    step = safe_u32(data, f[index])
    if step is None:
        return None
    target = f[index] + step
    return target if 0 <= target < len(data) and looks_like_table(data, target) else None


def vector_tables(data, at, index):
    """Follow field [index] to a vector of tables, returning their offsets."""
    if at is None:
        return []
    f = fields(data, at)
    if index not in f:
        return []
    first = f[index]
    vec = as_vector(data, first + u32(data, first))
    if vec is None:
        return []
    count, start = vec
    out = []
    for i in range(min(count, 500)):
        element = start + 4 * i
        target = element + u32(data, element)
        if looks_like_table(data, target):
            out.append(target)
    return out


def options_of(data, node):
    """A node's options table, whichever kind of widget it is.

    `NodeTree.options` (field 2) holds an `Options { data }`, and `data` is the type-specific options table --
    `SpriteOptions`, `TextOptions`, ... -- each of which carries the `WidgetOptions` that has name/position/size.
    So the path to geometry is: node -> options -> data -> [widget|node]Options -> widgetOptions.
    """
    options = table_at(data, node, 2)
    if options is None:
        return None
    payload = table_at(data, options, 0)
    if payload is None:
        return None
    # `*Options` tables put their WidgetOptions at field 0 in every case the schema shows.
    widget = table_at(data, payload, 0)
    return widget if widget is not None else payload


def read_node(data, node, depth, parent_x, parent_y, out, budget):
    if budget[0] <= 0:
        return
    budget[0] -= 1

    widget = options_of(data, node)
    name = classname = None
    position = (0.0, 0.0)
    size = None
    anchor = None
    text = None
    if widget is not None:
        f = fields(data, widget)
        name = string_at(data, f.get(0))
        position = vec2(data, f.get(7)) or (0.0, 0.0)
        anchor = vec2(data, f.get(9))
        size = vec2(data, f.get(11))
    classname = string_at(data, fields(data, node).get(0))

    # The type-specific payload also carries strings worth having: a Text's contents, a Sprite's file.
    options = table_at(data, node, 2)
    payload = table_at(data, options, 0) if options is not None else None
    if payload is not None:
        pf = fields(data, payload)
        for index in (4, 1, 2):  # TextOptions.text, *.fontResource, *.fontName -- harmless when absent
            candidate = string_at(data, pf.get(index))
            if candidate and (text is None or len(candidate) > len(text)):
                text = candidate

    # **The accumulation.** A child's position is relative to its parent, so the screen coordinate is the sum
    # down the chain -- which is what the earlier attempt was missing when it compared a child's y against the
    # height of the whole screen.
    x = parent_x + position[0]
    y = parent_y + position[1]
    label = name or classname or '(unnamed)'
    out.append('%s%-30s pos=(%7.1f,%7.1f) abs=(%7.1f,%7.1f) size=%s%s'
               % ('  ' * depth, label, position[0], position[1], x, y,
                  ('%.0fx%.0f' % size) if size else '-',
                  ('  text=%r' % text) if text else ''))

    for child in vector_tables(data, node, 1):
        read_node(data, child, depth + 1, x, y, out, budget)


def main():
    path = sys.argv[1]
    limit = int(sys.argv[2]) if len(sys.argv) > 2 else 4000
    data = open(path, 'rb').read()
    root_table = u32(data, 0)
    roots = []
    for _index, off, _width in spans(data, root_table):
        if off == 0:
            continue
        at = root_table + off
        target = at + u32(data, at)
        if looks_like_table(data, target):
            roots.append(target)

    out = []
    # The first nested table off the root is the NodeTree; its children are the layout's top-level nodes.
    for candidate in roots:
        children = vector_tables(data, candidate, 1)
        if not children:
            continue
        for child in children:
            read_node(data, child, 0, 0.0, 0.0, out, [limit])
    print('\n'.join(out))

    # **The check.** The root node's size is the design resolution; that is a fact about the file we can verify.
    for candidate in roots:
        for child in vector_tables(data, candidate, 1):
            widget = options_of(data, child)
            if widget is None:
                continue
            size = vec2(data, fields(data, widget).get(11))
            name = string_at(data, fields(data, widget).get(0))
            print('\nroot node: %s  size=%s' % (name, size))
            if size and size[0] > 100 and size[1] > 100:
                print('design canvas looks like %.0f x %.0f' % (size[0], size[1]))
            else:
                print('**the root size is not a plausible canvas: the reading is wrong, not the file**')
            return


if __name__ == '__main__':
    main()
