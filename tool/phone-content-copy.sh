#!/usr/bin/env bash
# Copy an Android app's content directory off the phone in one stream.
#
# **Why one stream.** 44,673 individual `adb pull`s pay a per-file cost for 11.67 GB; `tar` on the device plus a
# single pull took 12m43s at 15.6 MB/s. The extraction on this end then took **35 minutes** for a reason worth
# remembering: Windows Defender burned 1,694 CPU-seconds of real-time scanning on the files as they appeared.
#
# **Read-only with respect to the game.** The tar is a new file beside the data and is deleted at both ends
# afterwards; nothing inside the app's directory is modified.
#
# Proven on 2026-09-21 against a mobile game (11.56 GiB, 44,671 files), verified path by path afterwards -- the
# diff against the device's own listing was exactly two transient SQLite journals the app keeps mode -rw-------.
#
# Usage: tool/phone-content-copy.sh <package> <destination>
#   tool/phone-content-copy.sh com.YostarJP.BlueArchive "/e/~Harumi~Desuwa~/bluearchive"
set -u

PACKAGE="${1:?usage: phone-content-copy.sh <package> <destination>}"
DEST="${2:?usage: phone-content-copy.sh <package> <destination>}"

# `adb` is a Windows binary: the remote path must keep MSYS_NO_PATHCONV=1 and the local one must be a drive
# path, or `adb pull` silently cannot create the destination.
export MSYS_NO_PATHCONV=1
ADB="${ADB:-adb}"
SRC="/sdcard/Android/data/$PACKAGE"
TAR="/sdcard/phone-content.tar"

case "$DEST" in
  /e/*) WIN="E:${DEST#/e}" ;;
  /d/*) WIN="D:${DEST#/d}" ;;
  *)    WIN="$DEST" ;;
esac

mkdir -p "$DEST"

echo "== [$(date +%H:%M:%S)] tar on device =="
"$ADB" shell "cd $SRC && tar -cf $TAR ."
"$ADB" shell "ls -l $TAR" | tr -d '\r'

echo "== [$(date +%H:%M:%S)] pull =="
"$ADB" pull "$TAR" "$WIN/phone-content.tar"

echo "== [$(date +%H:%M:%S)] extract =="
( cd "$DEST" && tar -xf phone-content.tar )

echo "== [$(date +%H:%M:%S)] remove both tars =="
"$ADB" shell "rm -f $TAR && echo removed" | tr -d '\r'
rm -f "$DEST/phone-content.tar"

echo "== [$(date +%H:%M:%S)] result =="
du -sh "$DEST"
echo "files: $(find "$DEST" -type f | wc -l)"
du -sh "$DEST"/files/* 2>/dev/null | sort -rh | head -8
echo "== free space: $(df -h "$(dirname "$DEST")" | tail -1 | awk '{print $4}') =="
