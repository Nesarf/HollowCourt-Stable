#!/usr/bin/env python3
"""Refuses to build when `.dart_tool/package_config.json` belongs to the other platform.

    python tool/check_pub_config.py

**The failure this exists to stop, in its own words.** `.dart_tool/package_config.json` lives in the project
tree and holds **eighty-five absolute paths** into the pub cache. This machine's Windows side has them under
`E:/DaShaoHuo/cache/pub/...` and the WSL side runs `pub get` into `/home/nyarch/.pub-cache/...`, so whichever
side ran `pub get` last rewrites every one of them for the other. What the other side then sees is not a path
error: `flutter build` reports **hundreds of "Offset, Paint and Rect are undefined"** in files that plainly
import them, which reads as a broken source tree and sends a reader looking for a bad edit. Both build scripts
already carry a paragraph warning about it, and a paragraph is not a check.

**What it does.** Reads the config, takes the first package's `rootUri`, and asks whether that path exists
*here*. If it does not, the config was written by the other side and the build stops with the one instruction
that fixes it. It is deliberately not cleverer than that: it does not try to repair the file, because a tool
that silently rewrites a generated file during a build is a tool whose own state cannot be trusted.

**What it does not do.** It cannot fix the underlying coupling. The honest fixes are a checkout per platform, a
container, or a pub cache both sides can reach -- each of those is a decision about how this project is built
rather than a patch, and the record of that is in `docs/TODO.md`. This makes the failure legible in the
meantime, which is the part that can be done without that decision.
"""
from __future__ import annotations

import json
import os
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent

# **Overridable so the two answers can be tested rather than argued about.** In normal use this is the
# project's own config and nobody passes anything; a test hands it a file it wrote itself, which is the only
# way to exercise the refusing branch without making this machine's real config wrong on purpose.
CONFIG = Path(os.environ.get('PUB_CONFIG') or (REPO / '.dart_tool' / 'package_config.json'))


def main() -> int:
    if not CONFIG.is_file():
        # No config at all is not this check's business: `pub get` has simply not run yet, and the build
        # script runs it before anything else.
        print('  no package config yet -- `pub get` has not run; nothing to check')
        return 0

    try:
        data = json.loads(CONFIG.read_text(encoding='utf-8'))
    except (OSError, ValueError) as problem:
        print('  package config could not be read (%s); run `flutter pub get`' % problem)
        return 1

    packages = data.get('packages') or []
    if not packages:
        print('  package config lists no packages; run `flutter pub get`')
        return 1

    # **The first package is enough, and it is the right one to look at.** A config written by one side has
    # every rootUri under that side's cache, so one path answers the question for all eighty-five. Checking
    # them all would report the same fact eighty-five times.
    root = packages[0].get('rootUri') or ''
    if not root.startswith('file://'):
        # A relative URI resolves against the config's own directory and therefore works anywhere. Nothing
        # to check, and worth saying rather than passing in silence.
        print('  package config uses relative roots (%s) -- portable by construction' % root)
        return 0

    path = root[len('file://'):]
    # A `file:///E:/...` URI arrives as `/E:/...` on Windows, which is not a path the OS accepts.
    if os.name == 'nt' and len(path) > 2 and path[0] == '/' and path[2] == ':':
        path = path[1:]

    if os.path.isdir(path):
        print('  package config matches this platform (%s)' % os.path.dirname(path))
        return 0

    print('', file=sys.stderr)
    print('  **This checkout\'s package config belongs to the OTHER platform.**', file=sys.stderr)
    print('  It points at %s,' % path, file=sys.stderr)
    print('  which does not exist here.', file=sys.stderr)
    print('', file=sys.stderr)
    print('  Building now would fail with hundreds of "Offset, Paint and Rect are undefined"', file=sys.stderr)
    print('  errors in files that import them -- a path problem wearing a source problem\'s clothes.', file=sys.stderr)
    print('', file=sys.stderr)
    print('  Fix it in one command, on THIS side:', file=sys.stderr)
    print('      flutter pub get', file=sys.stderr)
    print('', file=sys.stderr)
    print('  The two platforms share `.dart_tool/`, so whichever ran `pub get` last wins; there is no way', file=sys.stderr)
    print('  to build both without one of them doing it again. See `docs/TODO.md` for the decision that', file=sys.stderr)
    print('  would remove the coupling.', file=sys.stderr)
    return 1


if __name__ == '__main__':
    raise SystemExit(main())
