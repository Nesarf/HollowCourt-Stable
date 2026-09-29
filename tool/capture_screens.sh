#!/usr/bin/env bash
# Capture every distinct screen a rhythm game shows, while somebody taps through it.
#
# **The hash is computed on the phone**: pulling a 3.6 MB PNG every second is the slow way, and most of those
# frames are identical. So the loop screencaps to /sdcard, hashes it there, and pulls the file only when the hash
# changed. That turns a ~1.2 s loop into a ~0.6 s one and keeps the traffic proportional to what actually moved.
#
# Usage: capture_screens.sh <device> <output-dir> <seconds> [interval]
set -u

ADB="${ADB:-adb}"
DEVICE="${1:-}"
[ -n "$DEVICE" ] || { echo "usage: $0 <device serial>   (see: adb devices)" >&2; exit 2; }
OUT="${2:-./captures}"
SECONDS_TO_RUN="${3:-480}"
INTERVAL="${4:-0.6}"

mkdir -p "$OUT"

# **adb is a Windows program and cannot see an MSYS path.** With MSYS_NO_PATHCONV=1 the remote path stays
# `/sdcard/...` (which is what the device needs) but the local destination must then be written the way Windows
# sees it, or `adb pull` answers "cannot create file/directory". That is the whole bug this line fixes: bash
# needs `/e/...` and adb needs `E:/...`, in the same command.
OUT_WIN="$(printf '%s' "$OUT" | cut -c2 | tr 'a-z' 'A-Z'):$(printf '%s' "$OUT" | cut -c3-)"
LOG="$OUT/capture.log"
: > "$LOG"

last=""
n=0
end=$(( $(date +%s) + SECONDS_TO_RUN ))

echo "start $(date +%H:%M:%S) device=$DEVICE out=$OUT for ${SECONDS_TO_RUN}s" >> "$LOG"

while [ "$(date +%s)" -lt "$end" ]; do
  # One round trip: capture and hash without moving the image.
  h=$(MSYS_NO_PATHCONV=1 "$ADB" -s "$DEVICE" shell 'screencap -p /sdcard/_cap.png; md5sum /sdcard/_cap.png' 2>/dev/null | tr -d '\r' | awk '{print $1}')
  if [ -z "$h" ]; then
    sleep "$INTERVAL"
    continue
  fi
  if [ "$h" != "$last" ]; then
    n=$((n + 1))
    name=$(printf '%s/%03d-%s.png' "$OUT_WIN" "$n" "$(date +%H%M%S)")
    if MSYS_NO_PATHCONV=1 "$ADB" -s "$DEVICE" pull /sdcard/_cap.png "$name" >/dev/null 2>&1; then
      echo "$(date +%H:%M:%S) #$n $h -> $(basename "$name")" >> "$LOG"
      last="$h"
    fi
  fi
  sleep "$INTERVAL"
done

echo "done $(date +%H:%M:%S) captured=$n" >> "$LOG"
