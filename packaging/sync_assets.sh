#!/usr/bin/env bash
#
# Copies the two first-party data files into the bundle's asset directory.
#
# Why this exists, and why it is a script rather than a note: `data/` is where the library and the names are
# authored, edited, tested and cross-checked -- every guard in `test/data/seed/` reads them from there. The app
# cannot read `data/`; it reads `assets/`, which is a second copy. Those two copies were kept in step by hand,
# and on 2026-09-23 they were **91 drinks out of step**: fifteen drinks had been added to `data/drinks/library.json`
# and `assets/drinks/library.json` still held 88, so the Windows build shipped the old list and the recipes
# screen said the library held 88 entries while the library said 103. Nothing failed: the tests read one file and
# the app read the other.
#
# So there are now two mechanisms and they are different kinds. This script is the *action*; the test
# `test/data/seed/shipped_assets_match_the_data_test.dart` is the *guard*, and it fails the suite the moment the
# copies differ. A build script that forgets to call this one is caught by the other.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

for pair in "drinks/library.json" "names/names.json"; do
  src="$REPO/data/$pair"
  dst="$REPO/assets/$pair"
  [ -f "$src" ] || { echo "missing source: $src" >&2; exit 1; }
  cp "$src" "$dst"
  echo "==> synced $pair ($(wc -c < "$dst") bytes)"
done
