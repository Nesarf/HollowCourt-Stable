#!/usr/bin/env bash
# Records which commit each artifact in the bundle was built from.
#
# An acceptance result belongs to one artifact and an artifact belongs to one commit, so a bundle
# with no manifest is a bundle whose successes transfer themselves to code they never ran on.
# Run this after building, before handing anything to anyone.
set -euo pipefail

BUNDLE="${1:-/e/Hollow Court Bundle}"

if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "refusing: the working tree is dirty, so no commit describes these artifacts" >&2
  exit 1
fi

COMMIT="$(git rev-parse HEAD)"
SUBJECT="$(git log -1 --format=%s)"
COMMIT_EPOCH="$(git log -1 --format=%ct)"

{
  echo "Hollow Court -- artifact provenance"
  echo
  echo "source commit  : $COMMIT"
  echo "commit subject : $SUBJECT"
  echo "commit date    : $(git log -1 --format=%cI)"
  echo "pubspec version: $(grep -E '^version:' pubspec.yaml | awk '{print $2}')"
  echo "manifest made  : $(date -Iseconds)"
  echo
  echo "A dirty tree makes this file meaningless, so it refuses to write one."
  echo
  echo "Provenance is compared on the SOURCE-PATH COMMIT, not on HEAD. A commit that touches only"
  echo "docs moves HEAD and changes nothing that is compiled, so judging on HEAD would report every"
  echo "artifact as stale forever -- which is how a real signal turns into noise."
  echo
  echo "  ok          the source this was built from is the source in the tree now"
  echo "  src-dirty   built from uncommitted source, so no commit fully describes it"
  echo "  OTHER:<sha> built from different source; rebuild it"
  echo "  unrecorded  no receipt. Unknown, NOT fine -- unknown and fine are different words."
  echo
  printf '%-42s %-11s %-18s %s
' FILE BYTES RECEIPT SHA256
  printf '%-42s %-11s %-18s %s
' ---- ----- ------- ------
  for f in "$BUNDLE"/*; do
    case "$f" in
      */MANIFEST.txt|*.commit) continue ;;
    esac
    r="$f.commit"
    if [ -f "$r" ]; then
      rc="$(awk -F': *' '/^src-commit/{print $2; exit}' "$r")"
      rd="$(awk -F': *' '/^src-dirty/{print $2; exit}' "$r")"
      rp="$(awk -F': *' '/^src-paths/{print $2; exit}' "$r")"
      # Recompute the source commit now, with the same paths, and compare. A docs-only commit
      # moves HEAD but leaves this alone, which is the point.
      now="$(git log -1 --format=%H -- $rp 2>/dev/null || echo none)"
      if [ "$rc" = "$now" ] && [ "$rd" = "no" ]; then
        rec="ok"
      elif [ "$rc" = "$now" ]; then
        rec="src-dirty"
      else
        rec="OTHER:$(echo "$rc" | cut -c1-7)"
      fi
    else
      rec="unrecorded"
    fi
    printf '%-42s %-11s %-18s %s
' "$(basename "$f")" "$(stat -c%s "$f")" "$rec" "$(sha256sum "$f" | cut -c1-16)"
  done
  echo
  echo "unrecorded is not a defect and not a pass. It means the source is unknown, which is a"
  echo "different statement, and the fix is to rebuild with the receipt in place rather than to"
  echo "argue that it is probably fine."
} > "$BUNDLE/MANIFEST.txt"

cat "$BUNDLE/MANIFEST.txt"
