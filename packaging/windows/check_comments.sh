#!/usr/bin/env bash
# Refuses a WiX source whose XML comments contain '--'.
#
#   packaging/windows/check_comments.sh <file.wxs> [...]
#
# WHY THIS EXISTS AS A SCRIPT. WiX reports this as
#
#     error WIX0104: Not a valid source file; detail: An XML comment cannot contain '--',
#     and '-' cannot be the last character. Line 75, position 60.
#
# and the line and position point at the comment rather than at the mistake, which is a long
# sentence's worth of text to search by eye. The rule was already written down in
# packaging/README.md after the first time it cost this project a build, and it cost a second
# build anyway: **a rule in prose is not a check.** This is the check, and it is a separate file
# so that it can be run against a fixture and shown to work, rather than trusted.
#
# Only comments are checked. A '--' in element text or an attribute value is perfectly legal XML,
# and a check that refused it would be wrong about the language and would fire on the next
# innocent file.
set -euo pipefail

if [ $# -eq 0 ]; then
  echo "usage: check_comments.sh <file.wxs> [...]" >&2
  exit 2
fi

status=0
for file in "$@"; do
  if [ ! -f "$file" ]; then
    echo "no such file: $file" >&2
    status=1
    continue
  fi
  if ! awk '
    /<!--/ { inside = 1 }
    inside {
      line = $0
      gsub(/<!--/, "", line)
      gsub(/-->/, "", line)
      if (line ~ /--/) {
        printf "  %s:%d: \x27--\x27 inside an XML comment\n", FILENAME, FNR
        bad = 1
      }
    }
    /-->/ { inside = 0 }
    END { exit bad }
  ' "$file"; then
    echo "  ^ WiX will reject this as WIX0104: an XML comment cannot contain a double hyphen." >&2
    echo "    Rewrite it as a comma, a colon, or an em dash; do not simply delete it." >&2
    status=1
  fi
done
exit $status
