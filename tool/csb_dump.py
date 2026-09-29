"""Walk a CocoStudio `.csb` file without its schema.

`.csb` is FlatBuffers, and FlatBuffers is **self-describing at the wire level**: every table begins with a
signed offset back to its vtable, and the vtable says how many fields the table has and where each one sits.
That is enough to walk the whole file -- tables, vectors of tables, strings, and 8-byte float pairs -- without
knowing a single field *name*.

Which is the honest limit of this tool: **it can tell you the structure and the numbers, not which number is
"position" and which is "size".** Those names live in the schema. So the output is walked by eye against a
screenshot: if the float pairs land inside the design canvas and their ratios match what the screen shows, the
reading is real; if they do not, it is noise and is treated as such.

Usage:
    python tool/csb_dump.py <file.csb> [max-depth]
"""

import struct
import sys

# **Parsed defensively because this module is imported by the viewer and the geometry reader**, and an
# import must not depend on the importing program's command line -- which it did, and the first run of the
# viewer died with "invalid literal for int()" quoting a path.
def _depth_from_argv() -> int:
    if len(sys.argv) > 2 and sys.argv[2].isdigit():
        return int(sys.argv[2])
    return 6


MAX_DEPTH = _depth_from_argv()

# A field offset of 0 in a vtable means "absent", and flatbuffers pads tables, so the table's own size bounds
# how far a field offset may go. Both are used to sanity-check every read: a walker that reads garbage
# confidently is worse than one that stops.
def read_u16(data, at):
    return struct.unpack_from('<H', data, at)[0]


def read_i32(data, at):
    return struct.unpack_from('<i', data, at)[0]


def read_u32(data, at):
    return struct.unpack_from('<I', data, at)[0]


def vtable_of(data, table):
    """The vtable for a table at [table], or None when the bytes there are not a table."""
    if table + 4 > len(data):
        return None
    soffset = read_i32(data, table)
    vt = table - soffset
    if vt < 0 or vt + 4 > len(data):
        return None
    vsize = read_u16(data, vt)
    if vsize < 4 or vsize % 2 or vt + vsize > len(data):
        return None
    return vt, vsize


def field_offsets(data, table):
    found = vtable_of(data, table)
    if found is None:
        return []
    vt, vsize = found
    return [read_u16(data, vt + 4 + 2 * i) for i in range((vsize - 4) // 2)]


def as_string(data, at):
    """A flatbuffers string: uint32 length then that many bytes, and it must be printable ASCII."""
    if at + 4 > len(data):
        return None
    n = read_u32(data, at)
    if n == 0 or n > 4096 or at + 4 + n > len(data):
        return None
    raw = data[at + 4:at + 4 + n]
    if all(32 <= b < 127 or b in (9, 10, 13) for b in raw):
        return raw.decode('ascii')
    return None


def as_vector(data, at):
    """A flatbuffers vector: uint32 length then elements. Returns (n, first_element_offset) when plausible."""
    if at + 4 > len(data):
        return None
    n = read_u32(data, at)
    if n == 0 or n > 4096 or at + 4 + n > len(data):
        return None
    return n, at + 4


def floats(data, at, count=4):
    if at + 4 * count > len(data):
        return []
    return [struct.unpack_from('<f', data, at + 4 * i)[0] for i in range(count)]


def looks_like_table(data, at):
    return vtable_of(data, at) is not None


def walk(data, at, depth, out, label):
    pad = '  ' * depth
    if depth > MAX_DEPTH:
        return
    vt = vtable_of(data, at)
    if vt is None:
        text = as_string(data, at)
        if text is not None:
            out.append('%s%s string %r' % (pad, label, text))
            return
        nums = floats(data, at)
        out.append('%s%s raw %s' % (pad, label, ' '.join('%.3f' % f for f in nums)))
        return

    offsets = field_offsets(data, at)
    out.append('%s%s table@%d  fields=%d  present=%s'
               % (pad, label, at, len(offsets), [i for i, o in enumerate(offsets) if o]))
    for index, off in enumerate(offsets):
        if off == 0:
            continue
        target = at + off
        if target + 4 > len(data):
            continue
        as_off = read_u32(data, target)
        pointed = target + as_off
        # A uoffset that lands on a table, a string or a vector: the three things a field can hold.
        if looks_like_table(data, pointed) and off % 4 == 0 and pointed < len(data) - 4:
            walk(data, pointed, depth + 1, out, 'f%d ->' % index)
            continue
        text = as_string(data, pointed)
        if text is not None and 0 < as_off < len(data):
            out.append('%s  f%d -> string %r' % (pad, index, text))
            continue
        vector = as_vector(data, pointed)
        if vector is not None and 0 < as_off < len(data):
            count, first = vector
            out.append('%s  f%d -> vector of %d' % (pad, index, count))
            # A vector of uoffsets to tables is how children are stored; a vector of floats is a polygon or a
            # colour. Try the first element as a table and fall back to numbers.
            if count and looks_like_table(data, first + read_u32(data, first)):
                for i in range(min(count, 40)):
                    element = first + 4 * i
                    walk(data, element + read_u32(data, element), depth + 2, out, 'v%d' % i)
            else:
                vals = floats(data, first, min(count, 4))
                out.append('%s      first floats %s' % (pad, ' '.join('%.3f' % f for f in vals)))
            continue
        out.append('%s  f%d -> raw u32=%d  floats %s'
                   % (pad, index, as_off, ' '.join('%.3f' % f for f in floats(data, target))))




# ---------------------------------------------------------------------------------------------------------
# Second pass: the field's *span*, which the vtable also gives away.
#
# A table's fields sit in vtable order at increasing offsets, and the table's own size bounds the last one. So
# `next_offset - this_offset` is the **width of this field** -- 4 for a float or an offset, 8 for two floats, 16
# for four. That is what makes a Vec2 (position, size, anchor) readable without the schema: without the span,
# reading four floats at every field mixes the neighbour's value into this one's, which is exactly what the
# first version printed.
#
# A field is an **offset** when the u32 there points forward to something with a recognisable shape (a table, a
# length-prefixed ASCII string, a vector), and a **scalar** otherwise. That inference is the whole trick, and it
# is why this reads numbers and structure but not names.
def spans(data, table):
    found = vtable_of(data, table)
    if found is None:
        return []
    vt, vsize = found
    tsize = read_u16(data, vt + 2)
    offsets = [read_u16(data, vt + 4 + 2 * i) for i in range((vsize - 4) // 2)]
    out = []
    for i, off in enumerate(offsets):
        if off == 0 or off >= tsize:
            out.append((i, 0, 0))
            continue
        following = [o for o in offsets[i + 1:] if o > off]
        limit = min(following) if following else tsize
        out.append((i, off, limit - off))
    return out


def scalars(data, at, width):
    """Read a field of [width] bytes as floats when the width is a multiple of four."""
    if width < 4 or width % 4:
        return []
    return [struct.unpack_from('<f', data, at + 4 * i)[0] for i in range(width // 4)]


def node_tree(data, table, depth, out, budget):
    """Follow the tree, printing what each node says about itself."""
    if depth > 8 or budget[0] <= 0:
        return
    budget[0] -= 1
    pad = '  ' * depth
    names = []
    numbers = []
    children = []
    for index, off, width in spans(data, table):
        if off == 0:
            continue
        at = table + off
        target = at + read_u32(data, at)
        if width == 4 and 0 < read_u32(data, at) < len(data):
            text = as_string(data, target)
            if text is not None:
                names.append(text)
                continue
            if looks_like_table(data, target):
                continue  # a nested table: not a child node, and not a number
            vector = as_vector(data, target)
            if vector is not None:
                count, first = vector
                if count and looks_like_table(data, first + read_u32(data, first)):
                    children.append((count, first))
                    continue
        numbers.append((index, scalars(data, at, width)))
    label = ' | '.join(names) if names else '(unnamed)'
    # Only the numbers that could be geometry: a design canvas is a few hundred to a few thousand units, so
    # values in that band are worth printing and values in 0..1 (colour, anchor, scale) are summarised.
    geometry = [v for _i, vs in numbers for v in vs if 1.0 < abs(v) < 4000]
    small = [v for _i, vs in numbers for v in vs if 0.0 <= v <= 1.0]
    out.append('%s%s  geo=%s%s' % (
        pad, label,
        ' '.join('%.1f' % v for v in geometry[:12]),
        ('  unit=%d' % len(small)) if small else '',
    ))
    for _count, first in children:
        for i in range(min(_count, 40)):
            element = first + 4 * i
            node_tree(data, element + read_u32(data, element), depth + 1, out, budget)


def dump_tree(path):
    data = open(path, 'rb').read()
    root = read_u32(data, 0)
    out = []
    for _index, off, _width in spans(data, root):
        if off == 0:
            continue
        at = root + off
        target = at + read_u32(data, at)
        if looks_like_table(data, target):
            node_tree(data, target, 0, out, [400])
    return '\n'.join(out)


def main():
    path = sys.argv[1]
    # `tree` walks the node tree and prints names and geometry; the default dumps the raw structure.
    if len(sys.argv) > 3 and sys.argv[3] == 'tree':
        print(dump_tree(path))
        return
    data = open(path, 'rb').read()
    root = read_u32(data, 0)
    out = []
    out.append('file %s  %d bytes  root uoffset=%d' % (path, len(data), root))
    walk(data, root, 0, out, 'root')
    print('\n'.join(out))


if __name__ == '__main__':
    main()
