#!/usr/bin/env bash
# Records which commit each artifact in the bundle was built from.
#
# An acceptance result belongs to one artifact and an artifact belongs to one commit, so a bundle
# with no manifest is a bundle whose successes transfer themselves to code they never ran on.
# Run this after building, before handing anything to anyone.
set -euo pipefail

BUNDLE="${1:-/d/hollow-court/dist}"

if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "refusing: the working tree is dirty, so no commit describes these artifacts" >&2
  exit 1
fi

COMMIT="$(git rev-parse HEAD)"
SUBJECT="$(git log -1 --format=%s)"
COMMIT_EPOCH="$(git log -1 --format=%ct)"

# **`OTHER` was one condition wearing two meanings.** Four artifacts here were built from
# `b166909` and stood beside four that said `ok`, because commits after that build touched
# `android/gradle.properties` (the JVM heap, and Kotlin's incremental cache turned off because it
# could not be closed) and `linux/CMakeLists.txt` (the CMake 4 install-prefix guard). Neither
# decides what is compiled, so "rebuild it" there asks for a build that would hand back the same
# bytes -- and a row that can never turn green is how the real `OTHER` stops being read, which is
# the failure this file's own header warns about.
#
# **The list below is of compiled inputs, not of build configuration, and the first attempt got
# that backwards.** A list of configuration files has to grow every time somebody adds a script,
# so it goes red for the least interesting reason available -- including on the commit that adds
# it, because every receipt's `src-paths` covers `packaging`. Compiled inputs are a small and
# stable set, and a file outside it falls to the harmless verdict rather than to a demand for a
# rebuild, which is the direction an unknown file should fall.
#
# What this does not catch: a `linux/CMakeLists.txt` edit that changes the source list rather
# than the install prefix. Both of its edits so far were the prefix, and the names of the files
# that moved are printed beside every `cfg` row, so a reader can tell without trusting this
# paragraph.
COMPILED_INPUTS_RE='^(lib|assets|art|character)/|^pubspec\.(yaml|lock)$|^windows/runner/|^linux/(runner/|my_application\.)|^android/app/src/|^android/app/build\.gradle|^macos/Runner/'

CFG_FILES=''
NOTES=''

# Succeeds when nothing since the receipt touched a compiled input, and records what did move.
compiled_inputs_unchanged() {
  local from="$1"; shift
  local files f
  files="$(git diff --name-only "$from" HEAD -- "$@" 2>/dev/null)" || return 1
  [ -n "$files" ] || return 1
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    if printf '%s' "$f" | grep -Eq "$COMPILED_INPUTS_RE"; then
      return 1
    fi
  done <<< "$files"
  CFG_FILES="$(printf '%s' "$files" | tr '\n' ' ' | sed 's/ $//')"
  return 0
}

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
  echo "  cfg:<sha>   no compiled input moved since the receipt, so a rebuild would hand back the"
  echo "              same bytes; the files that did move are listed under the table"
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
    # **A directory is not an artifact, and the loop used to treat it as one.** With the bundle holding
    # per-version folders beside the flat files, every folder came through `stat` (0 bytes) and `sha256sum`
    # (an error on stderr that landed in the middle of the manifest) and was printed with an empty sha and a
    # receipt of `unrecorded` -- four rows saying nothing is known about four things that are not artifacts.
    # A manifest is read to find out whether a file is the file; a row that can never resolve is the fault
    # this file's own header warns about, so the loop only walks regular files.
    [ -f "$f" ] || continue
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
      elif [ -n "$rp" ] && compiled_inputs_unchanged "$rc" $rp; then
        rec="cfg:$(echo "$rc" | cut -c1-7)"
        NOTES="$NOTES$(printf '  %-42s %s' "$(basename "$f")" "$CFG_FILES")
"
      else
        rec="OTHER:$(echo "$rc" | cut -c1-7)"
      fi
    else
      rec="unrecorded"
    fi
    printf '%-42s %-11s %-18s %s
' "$(basename "$f")" "$(stat -c%s "$f")" "$rec" "$(sha256sum "$f" | cut -c1-16)"
  done
  if [ -n "$NOTES" ]; then
    echo
    echo "cfg rows: what moved since the receipt was written, and no compiled input did."
    printf '%s\n' "$NOTES"
  fi
  echo
  echo "unrecorded is not a defect and not a pass. It means the source is unknown, which is a"
  echo "different statement, and the fix is to rebuild with the receipt in place rather than to"
  echo "argue that it is probably fine."
} > "$BUNDLE/MANIFEST.txt"

cat "$BUNDLE/MANIFEST.txt"
