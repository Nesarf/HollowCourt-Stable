"""Run section 20.4.1's watermark check over an asset set.

**The check is not "look at the sprite"**, and DESIGN.md 20.4.1 gives two counter-examples found on this very
workstation: a 16-byte `DLCExpansion.dll` whose contents are the ASCII string `OsawariPJ DLsite`, and a `.pmd`
header comment reading `Copyright：CRYPTON FUTURE MEDIA, INC`. Both are provenance, neither is visible in a
render. So this scans what a preview would not show, in four passes:

1. **Names** -- every file and directory, because a bone, material or folder named after a store is provenance
   even when no picture contains one.
2. **Container metadata** -- PNG `tEXt`/`iTXt`/`zTXt`/`eXIf` chunks, read as chunks rather than through an
   image library, since the point is the fields and not the pixels.
3. **Sidecar and marker files** -- small files sitting beside assets, which is where storefronts plant
   per-channel markers precisely so a leaked copy can be traced.
4. **Every byte, on request** (`--bytes`) -- for the case nobody looks at.

**It reports, it does not judge.** A marker found is a fact to be weighed against the terms; a clean result says
nothing about what the licence permits, and DESIGN.md is explicit that those are two independent facts.

Usage: python tool/watermark_check.py <directory> [--bytes] [--max-files N]
"""

import os
import re
import struct
import sys
import zipfile

# Provenance markers, not "suspicious words": storefronts and distribution groups leave their own names behind,
# and that is what a marker is. A hit here means "read the surrounding bytes and decide", nothing more.
MARKERS = [
    'dlsite', 'dmm.co', 'fanza', 'booth.pm', 'fantia', 'melonbooks', 'alice-books',
    'patreon', 'fanbox', 'pixiv', 'gumroad', 'itch.io',
    'watermark', 'trial version', 'demo version',
    'cracked', 'repack', 'fitgirl', 'skidrow', 'codex', 'razor1911', 'plaza',
]

PNG_META_CHUNKS = {b'tEXt', b'iTXt', b'zTXt', b'eXIf', b'tIME'}
SIDECAR_SUFFIXES = ('.txt', '.url', '.nfo', '.md', '.dll', '.ini', '.json', '.bat', '.cmd')
SIDECAR_SIZE_LIMIT = 64 * 1024


def marker_hits(text):
    lowered = text.lower()
    return [m for m in MARKERS if m in lowered]


PRINTABLE = set(range(0x20, 0x7F))


def marker_context(window):
    """Markers found **inside a run of readable text**, with the run, rather than anywhere in the bytes.

    **The first run of this check over the whole copy produced 27 hits and almost all of them were noise.**
    `plaza` is five letters: in 5 GB of binary, at 26^-5 per position, a few hundred chance occurrences are
    expected -- and that is what they were. A storefront's marker is not a byte run, it is a *string*: the
    16-byte `DLCExpansion.dll` that DESIGN.md 20.4.1 cites holds readable ASCII from its first byte to its last,
    and a name planted in an asset sits in a name field. So a hit only counts when **both** sides of it are
    non-alphanumeric -- a whole token inside readable text -- and the enclosing text is reported so a reader can
    judge rather than trust.

    **The second run produced 23 hits and the token rule removed nearly all of them**, including every one of the
    base64 blobs: `LevelSkill/*.bytes` is base64 text, so long printable runs are the norm there and a five-letter
    coincidence was being read as a marker. What survived is a short list and each one was then looked at.
    """
    out = []
    lowered = window.lower()
    for marker in MARKERS:
        start = lowered.find(marker)
        while start >= 0:
            left = start
            while left > 0 and ord(window[left - 1]) in PRINTABLE:
                left -= 1
            right = start + len(marker)
            while right < len(window) and ord(window[right]) in PRINTABLE:
                right += 1
            run = window[left:right]
            before = window[start - 1] if start > 0 else ' '
            after = window[start + len(marker)] if start + len(marker) < len(window) else ' '
            bounded = not (before.isalnum() or after.isalnum())
            if len(run) >= 12 and bounded:
                out.append((marker, run.strip()[:120]))
            start = lowered.find(marker, start + 1)
    return out


def scan_names(root):
    hits = []
    count = 0
    for base, dirs, files in os.walk(root):
        for name in list(dirs) + files:
            count += 1
            found = marker_hits(name)
            if found:
                hits.append((os.path.join(base, name), found))
    return count, hits


def png_metadata(path):
    """The chunk fields a preview never shows. Returns the strings found, or None if it is not a PNG."""
    out = []
    with open(path, 'rb') as handle:
        if handle.read(8) != b'\x89PNG\r\n\x1a\n':
            return None
        while True:
            header = handle.read(8)
            if len(header) < 8:
                break
            length, kind = struct.unpack('>I4s', header)
            if kind in PNG_META_CHUNKS:
                body = handle.read(min(length, 1 << 20))
                if kind in (b'tEXt', b'zTXt', b'iTXt'):
                    out.append('%s: %s' % (kind.decode(), body[:400].decode('utf-8', 'replace')))
                else:
                    out.append('%s: %d bytes' % (kind.decode(), length))
            else:
                handle.seek(length, os.SEEK_CUR)
            handle.seek(4, os.SEEK_CUR)  # CRC
            if kind == b'IEND':
                break
    return out


def scan_pngs(root, max_files):
    checked = 0
    with_metadata = []
    hits = []
    for base, _dirs, files in os.walk(root):
        for name in files:
            if not name.lower().endswith(('.png', '.jpg', '.jpeg', '.webp')):
                continue
            checked += 1
            if checked > max_files:
                return checked, with_metadata, hits
            path = os.path.join(base, name)
            try:
                found = png_metadata(path)
            except Exception as error:
                hits.append((path, ['unreadable: %s' % error]))
                continue
            if found:
                with_metadata.append((path, found))
                marked = marker_hits(' '.join(found))
                if marked:
                    hits.append((path, marked))
    return checked, with_metadata, hits


def scan_sidecars(root, max_files):
    found = []
    checked = 0
    for base, _dirs, files in os.walk(root):
        for name in files:
            if not name.lower().endswith(SIDECAR_SUFFIXES):
                continue
            path = os.path.join(base, name)
            try:
                size = os.path.getsize(path)
            except OSError:
                continue
            checked += 1
            if checked > max_files:
                return checked, found
            if size <= SIDECAR_SIZE_LIMIT:
                found.append((path, size))
    return checked, found


def scan_bytes(root, max_files, sample=False):
    """Read file contents with the tail of each chunk carried into the next, so a marker on a boundary is not
    missed.

    **`sample` is the honest middle, and the difference is stated rather than glossed.** A marker planted in a
    storefront's file sits in a header, a trailing comment field, or a sidecar -- and a 12 GB set that is 99 %
    video and UnityFS packs does not need every byte of every payload read to find one. In sampling mode a file
    of 256 KB or less is read whole and a larger one contributes its first and last 64 KB; **which files got the
    whole treatment and which got the ends is what the printed counts say**, so the result can never be read as
    more coverage than it had.
    """
    hits = []
    scanned = 0
    whole = 0
    sampled = 0
    for base, _dirs, files in os.walk(root):
        for name in files:
            path = os.path.join(base, name)
            scanned += 1
            if scanned > max_files:
                return scanned, hits, whole, sampled
            if scanned % 2000 == 0:
                print('   ... %d files, %d markers' % (scanned, len(hits)), flush=True)
            try:
                size = os.path.getsize(path)
                with open(path, 'rb') as handle:
                    if sample and size > 256 * 1024:
                        blocks = [handle.read(64 * 1024)]
                        handle.seek(max(0, size - 64 * 1024))
                        blocks.append(handle.read(64 * 1024))
                        sampled += 1
                    else:
                        blocks = []
                        while True:
                            block = handle.read(1 << 22)
                            if not block:
                                break
                            blocks.append(block)
                        whole += 1
                    found = set()
                    contexts = []
                    carry = b''
                    for block in blocks:
                        window = (carry + block).decode('latin-1')
                        contexts.extend(marker_context(window))
                        carry = (carry + block)[-64:]
                    if contexts:
                        hits.append((path, sorted(set(contexts))))
            except OSError:
                continue
    return scanned, hits, whole, sampled


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    if not args:
        print(__doc__.strip().splitlines()[0])
        return 2
    root = args[0]
    deep = '--bytes' in sys.argv or '--sample' in sys.argv
    max_files = 10 ** 9
    for arg in sys.argv[1:]:
        if arg.startswith('--max-files'):
            max_files = int(arg.split('=')[1]) if '=' in arg else 10 ** 9

    print('set: %s' % root)
    if not os.path.isdir(root):
        print('not a directory')
        return 2

    count, name_hits = scan_names(root)
    print('1. names: %d files and directories, %d markers' % (count, len(name_hits)))
    for path, found in name_hits[:12]:
        print('   %s  %s' % (found, os.path.relpath(path, root)))

    checked, with_metadata, png_hits = scan_pngs(root, max_files)
    print('2. images: %d checked, %d carried metadata, %d markers' % (checked, len(with_metadata), len(png_hits)))
    for path, found in (with_metadata[:4] if not png_hits else png_hits[:8]):
        print('   %s  %s' % (os.path.relpath(path, root), str(found)[:150]))

    sidecars, sidecar_files = scan_sidecars(root, max_files)
    print('3. sidecars (small .txt/.url/.nfo/.dll and kin): %d checked, %d found' % (sidecars, len(sidecar_files)))
    for path, size in sidecar_files[:12]:
        print('   %6d B  %s' % (size, os.path.relpath(path, root)))

    if deep:
        sampled = '--sample' in sys.argv or '--bytes' not in sys.argv
        scanned, byte_hits, whole, sample_count = scan_bytes(root, max_files, sample=sampled)
        print('4. contents: %d files read as %d whole and %d ends-only (first and last 64 KB), %d markers'
              % (scanned, whole, sample_count, len(byte_hits)), flush=True)
        for path, found in byte_hits[:12]:
            print('   %s  %s' % (found, os.path.relpath(path, root)))
    else:
        print('4. contents: skipped (pass --sample for the whole set, --bytes for every byte)')
    return 0


if __name__ == '__main__':
    sys.exit(main())
