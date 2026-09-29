#!/usr/bin/env python3
"""Keeps the newest few builds in a release bundle and removes the rest.

**Dry run unless `--apply`**, which is the rule `hma fix` set and the reason it is safe to run. A cleanup that acts on the
first keystroke is a cleanup nobody dares to try, and the whole point of this one is that it gets run after every build.

    python tool/keep_bundle.py                      # what would go
    python tool/keep_bundle.py --apply              # and remove it
    python tool/keep_bundle.py -n 5 --apply         # keep five instead of three

**The bundle is a flat pile of release artifacts, and it grows by one full set per build.** By 2026-09-27 it held 22 builds
and 1.6 GB, every one of them a complete set of Windows, Linux and three Android ABIs. Only the newest few are ever
downloaded, and the rest are copies of a thing that exists in git -- but the *binaries* do not exist in git, so this
refuses to guess which to keep. It sorts by the newest file in each build, takes the top N, and prints exactly what it
would remove before removing anything.
"""
from __future__ import annotations

import argparse
import os
import re
import shutil
import sys

DEFAULT_BUNDLE = os.path.join('E:' + os.sep, 'Hollow Court Bundle')
FOLDER = re.compile(r'^1\.0\.0\+(\d+)$')
DEFAULT_KEEP = 3


def builds(bundle: str) -> list[tuple[float, str, int, int]]:
    """Every version folder, newest first, with its file count and byte size."""
    found = []
    for name in os.listdir(bundle):
        path = os.path.join(bundle, name)
        if not os.path.isdir(path) or not FOLDER.match(name):
            continue
        names = os.listdir(path)
        if not names:
            found.append((0.0, name, 0, 0))
            continue
        newest = max(os.path.getmtime(os.path.join(path, n)) for n in names)
        size = sum(os.path.getsize(os.path.join(path, n)) for n in names)
        found.append((newest, name, len(names), size))
    found.sort(reverse=True)
    return found


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description='keep the newest builds in a release bundle')
    parser.add_argument('--bundle', default=DEFAULT_BUNDLE,
                        help='the bundle directory (default: %s)' % DEFAULT_BUNDLE)
    parser.add_argument('-n', '--keep', type=int, default=DEFAULT_KEEP,
                        help='how many builds to keep (default: %d)' % DEFAULT_KEEP)
    parser.add_argument('--apply', action='store_true', help='actually remove; without it this only reports')
    args = parser.parse_args(argv)

    bundle = os.path.abspath(args.bundle)
    if not os.path.isdir(bundle):
        print('  找不到 %s' % bundle, file=sys.stderr)
        return 1
    if args.keep < 1:
        print('  --keep 至少是 1；要全删就自己动手，这个工具不提供。', file=sys.stderr)
        return 2

    found = builds(bundle)
    if not found:
        print('  %s 里没有版本文件夹' % bundle)
        return 0

    keep = found[:args.keep]
    drop = found[args.keep:]

    print('  %s' % bundle)
    print()
    for index, (_, name, count, size) in enumerate(found, 1):
        print('  %-16s %3d 个文件  %7.1f MB   %s' % (name, count, size / 1048576,
                                                     '留' if index <= args.keep else '清'))
    print()
    print('  共 %d 个版本、%.0f MB' % (len(found), sum(row[3] for row in found) / 1048576))

    if not drop:
        print('  已经只有 %d 个版本了，没有要清的。' % args.keep)
        return 0

    freed = sum(row[3] for row in drop)
    print('  留 %d 个，清 %d 个，释放 %.0f MB' % (len(keep), len(drop), freed / 1048576))

    if not args.apply:
        print()
        print('  这是演练 —— 一个文件都没删。要真删就加 --apply。')
        return 0

    removed = 0
    for _, name, _, _ in drop:
        shutil.rmtree(os.path.join(bundle, name))
        removed += 1
        print('  删了 %s' % name)
    print()
    print('  ✓ 清了 %d 个版本，释放 %.0f MB' % (removed, freed / 1048576))
    if os.path.isfile(os.path.join(bundle, 'MANIFEST.txt')):
        print('  MANIFEST.txt 留在顶层 —— 它是这份包的索引，不属于任何一个版本文件夹。')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
