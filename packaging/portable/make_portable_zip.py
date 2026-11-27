#!/usr/bin/env python3
"""Writes the portable archive entry by entry, so that a symbolic link stays a link.

    python packaging/portable/make_portable_zip.py --out dist/hollow-court-<v>-portable.zip \\
        --file README.txt=dist/stage/README.txt \\
        --tree windows=build/windows/x64/runner/Release \\
        --tree linux=build/linux/x64/release/bundle \\
        --zip  macos=<artifact>.zip

**Why this is not `Compress-Archive`.** Measured on the 51541 archive: all 45 entries carried
`ExternalAttributes = 0`, including `linux/hollow_court`. That field is the only place a ZIP
file can hold a Unix mode, and two things follow from leaving it at zero. The executable bit
is gone, which is why the README has to teach a reader to `chmod +x` a file that was built
executable. And the 64 KiB-free field cannot say "this entry is a symlink", so a macOS `.app`
-- nine links holding three nested framework versions together -- unpacks as nine small text
files. The bundle's directory tree still looks right, and it will not load. A general-purpose
archiver on Windows is allowed to make that trade because Windows never reads the field; an
archive that ships a Mach-O bundle is not.

**Why the macOS bundle is copied out of a ZIP instead of off a disk.** There is no macOS build
output on this machine, so the only copy of the bundle is the CI artifact -- already a ZIP, and
already carrying the right modes, because `ditto` wrote it. Unpacking it first would be the one
step that destroys what we need: Windows' `Copy-Item -Recurse`, `Expand-Archive` and every GUI
unpacker materialise a link as a regular file. So the entries are re-emitted one at a time and
`external_attr` is carried across untouched. Even on a Mac, where `macos/Build/Products` would
exist, `--tree` is preferred over copying: this file reads the link itself with `os.readlink`
and writes it back as a link, which no copy step has to be trusted to preserve.

**Why a hand-written `ZipInfo` rather than `ZipInfo.from_file`.** `from_file` copies the mode
from `os.stat`, which on Windows reports nothing useful, and it sets `create_system` from the
running platform. So a build on Windows would mark entries as FAT and no unpacker would look at
the mode at all. Every entry here says `create_system = 3` (Unix) and states its mode outright,
which makes the archive identical in meaning whichever machine assembles it.

**Why the DOS attribute bits are kept too.** Windows Explorer reads the low 16 bits, not the
Unix mode in the high 16, to decide that a name ending in `/` is a folder it should show as one.
`DOS_DIRECTORY` is set on directory entries for that reason alone; it carries no information
Unix readers use.
"""

from __future__ import annotations

import argparse
import os
import stat
import sys
import time
import zipfile

# Unix file-type bits. `stat` names them, and the names are the same on every platform even
# where the underlying values differ, so nothing here is spelled out as a magic octal.
UNIX_SYSTEM = 3  # the ZIP "create system" code for Unix; without it the mode is ignored
DOS_DIRECTORY = 0x10  # low-half attribute bit Windows Explorer shows a folder from
DEFAULT_EXECUTABLE = ("linux/hollow_court",)


def _zip_time(path):
    """An mtime as the DOS timestamp a ZIP entry holds, clamped to what the format allows."""
    when = time.localtime(os.lstat(path).st_mtime)
    if when.tm_year < 1980:
        return (1980, 1, 1, 0, 0, 0)
    # DOS times have two-second resolution. Truncating here means the value read back out of
    # the archive equals the value written, which is the only way a rebuild is comparable.
    return (when.tm_year, when.tm_mon, when.tm_mday, when.tm_hour, when.tm_min,
            when.tm_sec - when.tm_sec % 2)


class Writer:
    """Emits entries into one archive and keeps the per-prefix tally the caller prints."""

    def __init__(self, sink):
        self.sink = sink
        self.entries = {}
        self.links = 0
        self.executable = ()

    def _count(self, prefix):
        self.entries[prefix] = self.entries.get(prefix, 0) + 1

    def directory(self, arcname, prefix):
        info = zipfile.ZipInfo(arcname.rstrip('/') + '/', date_time=(1980, 1, 1, 0, 0, 0))
        info.create_system = UNIX_SYSTEM
        info.external_attr = ((stat.S_IFDIR | 0o755) << 16) | DOS_DIRECTORY
        info.compress_type = zipfile.ZIP_STORED
        self.sink.writestr(info, b'')
        self._count(prefix)

    def file(self, arcname, path, prefix, mode=0o644):
        info = zipfile.ZipInfo(arcname, date_time=_zip_time(path))
        info.create_system = UNIX_SYSTEM
        info.external_attr = (stat.S_IFREG | mode) << 16
        info.compress_type = zipfile.ZIP_DEFLATED
        # **`writestr`'s second argument is the data, not a name to read.** Passing a path
        # writes the path: every file in windows/ and linux/ became its own filename, the
        # archive came out 4 MB smaller than the one it replaced, and nothing failed. The
        # bytes have to be read here; there is no "read it for me" form of this call.
        with open(path, 'rb') as handle:
            self.sink.writestr(info, handle.read())
        self._count(prefix)

    def link(self, arcname, path, prefix):
        """A symlink entry: the name in the central directory, the target as its whole body."""
        target = os.readlink(path).replace(os.sep, '/')
        info = zipfile.ZipInfo(arcname, date_time=_zip_time(path))
        info.create_system = UNIX_SYSTEM
        info.external_attr = (stat.S_IFLNK | 0o777) << 16
        info.compress_type = zipfile.ZIP_STORED
        self.sink.writestr(info, target)
        self.links += 1
        self._count(prefix)


def add_file(writer, arcname, path):
    if not os.path.isfile(path):
        raise SystemExit(f'--file {arcname}={path}: not a file')
    writer.file(arcname, path, '<top>', mode=0o644)


def add_tree(writer, prefix, root):
    root = os.path.abspath(root)
    if not os.path.isdir(root):
        raise SystemExit(f'--tree {prefix}={root}: not a directory')
    for here, dirs, files in os.walk(root, followlinks=False):
        dirs.sort()
        files.sort()
        relative = os.path.relpath(here, root)
        arcbase = prefix if relative == '.' else prefix + '/' + relative.replace(os.sep, '/')
        writer.directory(arcbase, prefix)
        # `os.walk` puts a link to a directory in `dirs`, then does not descend into it only
        # because `followlinks` is false. Removing it here keeps it out of the recursion and
        # lets the link be written as a link.
        for name in list(dirs):
            child = os.path.join(here, name)
            if os.path.islink(child):
                dirs.remove(name)
                writer.link(arcbase + '/' + name, child, prefix)
        for name in files:
            child = os.path.join(here, name)
            arcname = arcbase + '/' + name
            if os.path.islink(child):
                writer.link(arcname, child, prefix)
            else:
                mode = 0o755 if arcname in writer.executable else 0o644
                writer.file(arcname, child, prefix, mode)


def add_zip(writer, prefix, path):
    """Re-emits every entry of another archive under `prefix`, modes included and unread."""
    if not os.path.isfile(path):
        raise SystemExit(f'--zip {prefix}={path}: not a file')
    with zipfile.ZipFile(path) as source:
        for entry in source.infolist():
            info = zipfile.ZipInfo(prefix + '/' + entry.filename, date_time=entry.date_time)
            info.create_system = entry.create_system or UNIX_SYSTEM
            info.external_attr = entry.external_attr
            info.internal_attr = entry.internal_attr
            info.compress_type = entry.compress_type
            if stat.S_ISLNK(entry.external_attr >> 16):
                writer.links += 1
            writer.sink.writestr(info, b'' if entry.is_dir() else source.read(entry))
            writer._count(prefix)


def _pair(text, flag):
    head, sep, tail = text.partition('=')
    if not sep or not head or not tail:
        raise SystemExit(f'{flag} expects NAME=PATH, got {text!r}')
    return head.strip('/'), tail


def main(argv):
    parser = argparse.ArgumentParser(description='write the portable archive with its modes intact')
    parser.add_argument('--out', required=True, help='archive to write; replaced if it exists')
    parser.add_argument('--file', action='append', default=[], metavar='ARCNAME=PATH',
                        help='one file at the top of the archive, written before anything else')
    parser.add_argument('--tree', action='append', default=[], metavar='PREFIX=DIR',
                        help='a directory, read link by link')
    parser.add_argument('--zip', action='append', default=[], metavar='PREFIX=ZIP',
                        help='another archive\'s entries, re-emitted under PREFIX')
    parser.add_argument('--exec', action='append', metavar='ARCNAME',
                        help='mark this archive path 0755 (default: linux/hollow_court)')
    args = parser.parse_args(argv)

    out = os.path.abspath(args.out)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    if os.path.exists(out):
        os.remove(out)

    with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED, allowZip64=True) as sink:
        writer = Writer(sink)
        writer.executable = tuple(args.exec) if args.exec else DEFAULT_EXECUTABLE

        # The README first, because it is the only entry a reader is meant to open before
        # choosing a folder, and unpackers list entries in the order they were written.
        for item in args.file:
            arcname, path = _pair(item, '--file')
            add_file(writer, arcname, path)
        for item in args.tree:
            prefix, path = _pair(item, '--tree')
            add_tree(writer, prefix, path)
        for item in args.zip:
            prefix, path = _pair(item, '--zip')
            add_zip(writer, prefix, path)

    size = os.path.getsize(out)
    total = sum(writer.entries.values())
    print(f'   entries  {total}  ({writer.links} symlink(s))')
    for prefix, count in sorted(writer.entries.items()):
        print(f'   {prefix:<9} {count}')
    print(f'   wrote    {out} ({size / (1024 * 1024):.1f} MB)')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
