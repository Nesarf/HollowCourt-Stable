#!/usr/bin/env bash
#
# Are the artifacts in the bundle built from the current source?
#
#     bash tool/staleness.sh
#
# **The question this answers, and why it keeps coming up.** An artifact always lags its source -- that is normal
# and not a defect. What is not normal is not knowing *how far* it lags, because then staleness has to be found the
# way it was found today: by screenshotting a handset and reading a heading that should have changed.
#
# Every build writes a receipt beside its artifact (packaging/write_receipt.sh) naming the commit it came from.
# Comparing that with HEAD turns the question into arithmetic, and it is the check that says whether a fix has
# reached an installer at all -- which is the difference between "fixed" and "fixed in the repository".

# **A companion check, and the one that reaches screens no hand can.** Dart keeps non-Latin strings as UTF-16 and
# Latin ones as UTF-8 inside `libapp.so`, so the strings a build actually contains can be read straight out of the
# artifact:
#
#     unzip -o -j "E:/Hollow Court Bundle/hollow-court-<version>-arm64-v8a.apk" #         lib/arm64-v8a/libapp.so -d /tmp/apk && #     python -c "import io; d=io.open('/tmp/apk/libapp.so','rb').read(); #         print('外部接缝', d.count('外部接缝'.encode('utf-16-le')), #               '| 外部连接', d.count('外部连接'.encode('utf-16-le')))"
#
# The two strings it probes for are the application's own developer-screen labels, written in Traditional Chinese
# in `lib/ui/theme.dart` (the seam list and the outside-connections heading), so they are quoted above exactly as
# the artifact carries them.
#
# Verified 2026-09-25 by comparing two builds of the same code: 1.0.0.1018 reported the seam label once and the
# connections label not at all; 1.0.0.1019 reported the reverse. **This is how a screen that MIUI will not let an agent tap gets checked** -- the
# question "did the fix reach the artifact" is answered by the artifact, with no device, no taps and no screenshot.
#
# The two files were byte-identical in *size* and different in hash, which is why the check is a string count and
# not a size comparison.

set -uo pipefail
# No `-e`: this script asks git questions whose "no" answers are the point, and `--is-ancestor` answers 1.
cd "$(dirname "${BASH_SOURCE[0]}")/.."
REPO="$(pwd)"
BUNDLE="${BUNDLE:-/e/Hollow Court Bundle}"
HEAD_SHA="$(git rev-parse HEAD)"
HEAD_SUBJECT="$(git log --oneline -1 | cut -c1-70)"

echo "== head =="
echo "   $HEAD_SUBJECT"
if [ -n "$(git status --porcelain)" ]; then
  echo "   !! the working tree has uncommitted changes, so no artifact can be current"
fi

echo "== artifacts =="
found=0
for receipt in "$BUNDLE"/*.commit; do
  [ -e "$receipt" ] || continue
  found=1
  name="$(basename "$receipt" .commit)"
  # The receipt aligns its colons (`src-commit    : <sha>`), so the field number is not fixed -- strip the label
  # rather than counting columns. The first version printed `$2`, which is the colon, and reported every artifact
  # as having no commit recorded; a check that says "no data" about 23 files looks exactly like a broken check.
  src="$(sed -n 's/^src-commit[[:space:]]*:[[:space:]]*//p' "$receipt" | tr -d '\r')"
  if [ -z "$src" ]; then
    printf '   %-46s no src-commit recorded\n' "$name"
    continue
  fi
  if git merge-base --is-ancestor "$src" "$HEAD_SHA" 2>/dev/null; then
    behind="$(git rev-list --count "$src..$HEAD_SHA")"
    if [ "$behind" = "0" ]; then
      printf '   %-46s current\n' "$name"
    else
      printf '   %-46s %s commit(s) behind\n' "$name" "$behind"
      # The subjects of what it is missing: the difference between "stale" and "stale by something that mattered".
      git log --oneline "$src..$HEAD_SHA" | head -5 | sed 's/^/        /'
    fi
  else
    printf '   %-46s built from a commit that is not an ancestor of HEAD\n' "$name"
  fi
done

if [ "$found" = "0" ]; then
  echo "   (no receipts in $BUNDLE -- nothing to compare)"
fi
