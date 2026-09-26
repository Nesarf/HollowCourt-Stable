#!/usr/bin/env bash
# Writes an <artifact>.commit receipt so provenance is recorded, not remembered.
#
#   packaging/write_receipt.sh <artifact> [note] [source-paths...]
#
# Call this at the END of every build, after the artifact exists.
#
# WHY IT RECORDS TWO COMMITS. The obvious receipt names HEAD. That is a proxy, and it goes wrong
# the same way every time: a commit that touches only docs moves HEAD, so the artifact starts
# reading as "from a different commit" although not one compiled byte changed. The quantity that
# matters is the commit of the SOURCE THAT GOES INTO THE ARTIFACT, so that is what src-commit
# records, and that is what the manifest compares. HEAD is kept for the full picture, not the
# verdict.
set -euo pipefail

ARTIFACT="${1:?usage: write_receipt.sh <artifact> [note] [source-paths...]}"
NOTE="${2:-}"
shift 2 || true
PATHS=("$@")
if [ ${#PATHS[@]} -eq 0 ]; then
  PATHS=(lib pubspec.yaml pubspec.lock)
fi

if git diff --quiet && git diff --cached --quiet; then
  DIRTY=no
else
  DIRTY=yes
fi

# The commit that last touched the paths this artifact is actually built from.
SRC_COMMIT="$(git log -1 --format=%H -- "${PATHS[@]}" 2>/dev/null || echo none)"
SRC_SUBJECT="$(git log -1 --format=%s "$SRC_COMMIT" 2>/dev/null || echo '(none)')"
# Do any of those paths currently differ from that commit?
if git diff --quiet "$SRC_COMMIT" -- "${PATHS[@]}" 2>/dev/null; then
  SRC_DIRTY=no
else
  SRC_DIRTY=yes
fi

{
  echo "artifact      : $(basename "$ARTIFACT")"
  echo "head          : $(git rev-parse HEAD)"
  echo "src-commit    : $SRC_COMMIT"
  echo "src-subject   : $SRC_SUBJECT"
  echo "src-paths     : ${PATHS[*]}"
  echo "src-dirty     : $SRC_DIRTY"
  echo "tree-dirty    : $DIRTY"
  echo "built at      : $(date -Iseconds)"
  # **Read from stdin, not from a path, and the difference is a stray backslash.** GNU coreutils
  # prefixes the whole line with `\` when the file name contains a backslash, because a name with a
  # backslash in it is escaped so the output stays parseable. Every Windows artifact here is named
  # `E:\Hollow Court Bundle\...`, so `sha256sum "$ARTIFACT" | cut -d' ' -f1` produced
  # `\49c8c432...` -- a fingerprint with a character in front of it that no checker would match and
  # no eye would notice, on the two rows of the manifest that are hardest to verify by hand. The
  # Android and AppImage receipts were clean only because they come through POSIX paths.
  #
  # `sha256sum < file` prints the hash and a `-` for the name, so there is no name to escape.
  echo "sha256        : $(sha256sum < "$ARTIFACT" | cut -d' ' -f1)"
  [ -n "$NOTE" ] && echo "note          : $NOTE"
  if [ "$SRC_DIRTY" = yes ]; then
    echo
    echo "The built source differs from src-commit, so src-commit does NOT fully describe this artifact."
  fi
} > "$(cd "$(dirname "$ARTIFACT")" && pwd)/$(basename "$ARTIFACT").commit"
