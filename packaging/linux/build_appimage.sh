#!/usr/bin/env bash
#
# Wraps the Flutter Linux bundle into an AppImage. Run INSIDE WSL, after
# tool/build_linux.sh has produced build/linux/x64/release/bundle:
#
#     wsl -d Nyarch -e bash packaging/linux/build_appimage.sh
#
# Three things about this that are not obvious:
#
# 1. appimagetool ships AS an AppImage, so running it needs FUSE. In a container or as
#    root it usually fails to mount itself, and `--appimage-extract-and-run` is the
#    supported way around that -- it unpacks itself and runs, which is all that is
#    wanted here.
# 2. The AppDir root holds the Flutter bundle AS IS, because `hollow_court` looks for
#    `lib/` and `data/` beside itself. Moving them into `usr/bin` is the usual AppImage
#    layout and would break the launcher.
# 3. The scratch directory is /tmp, which is inside the WSL distribution's virtual disk
#    -- that disk is E:\DaShaoHuo\wsl\..., so nothing lands on C:.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUNDLE="$REPO/build/linux/x64/release/bundle"
TOOL="${APPIMAGETOOL:-appimagetool}"
# The mark, from the same generator and the same render as the other two platforms:
# `art/render_icons.sh` draws it once and installs it three ways.
ICON="$REPO/art/render/icon-hc-192.png"
OUT_DIR="${OUT_DIR:-${TMPDIR:-/tmp}/hollow-court-bundle}"
# **The four-part version, i.e. the one the app itself displays.** pubspec holds the pair `1.0.0+514`
# because pub requires a three-part `build-name`; the name a round is called by is the pair joined with a
# dot, which is also what the packaging scripts pass to the About screen as APP_VERSION. Using the
# three-part form here made every round produce the same file name, so a new AppImage overwrote its
# predecessor and left nothing to roll back to -- the same fault the Android script had.
BUILD_NAME="$(grep -m1 '^version:' "$REPO/pubspec.yaml" | tr -d '
' | sed 's/version: *//; s/+.*//')"
BUILD_NUMBER="$(grep -m1 '^version:' "$REPO/pubspec.yaml" | tr -d '
' | sed 's/.*+//')"
VERSION="$BUILD_NAME.$BUILD_NUMBER"
APPDIR="$(mktemp -d /tmp/hollow-appdir-XXXXXX)"

[ -x "$TOOL" ] || { echo "no appimagetool at $TOOL" >&2; exit 1; }
[ -d "$BUNDLE" ] || { echo "no Linux bundle at $BUNDLE -- run tool/build_linux.sh first" >&2; exit 1; }

echo "== appdir =="
mkdir -p "$APPDIR/usr/share/icons/hicolor/192x192/apps"
cp -r "$BUNDLE"/. "$APPDIR/"
# EVERY NAME HERE IS THE APPLICATION ID, and that is not cosmetic.
#
# `linux/CMakeLists.txt` sets APPLICATION_ID to `hollow_court` and the runner hands it to
# GTK, so that is the name a running window reports. WSLg's app list -- and any desktop that matches
# a window to its launcher -- looks the icon up BY THAT NAME, and it logged `loadIconEvent is
# signalled. hollow_court` followed by `entry (nil), image (nil)` while these files were
# called `hollow-court`: the icon was present, installed, cached, and invisible, because nothing was
# ever going to look under that name.
cp "$ICON" "$APPDIR/hollow_court.png"
# `.DirIcon` is what a file manager shows for the AppImage FILE -- a different thing from the icon
# the desktop entry names for the installed application, and both are needed. Convention is a
# symlink to the icon at the AppDir root.
ln -sf hollow_court.png "$APPDIR/.DirIcon"
# A SET of sizes, not one, because that is what a desktop application ships and because a shell
# asks for the size it needs rather than scaling whatever it finds. Only a 192 was installed at
# first, and WSLg's icon lookup answered `image (nil)` with that 192 sitting in a directory its theme
# does declare -- so the search is not a simple nearest-size match and the honest answer is to give
# it the sizes a real application would.
for size in 16 24 32 48 64 128 256; do
  mkdir -p "$APPDIR/usr/share/icons/hicolor/${size}x${size}/apps"
  cp "$REPO/art/render/icon-hc-$size.png"      "$APPDIR/usr/share/icons/hicolor/${size}x${size}/apps/hollow_court.png"
done

cat > "$APPDIR/hollow_court.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=空庭
Name[en]=Hollow Court
Comment=A beverage cellar you actually own.
Comment[zh_CN]=一个真正属于你的酒窖。
Exec=hollow_court
Icon=hollow_court
Categories=Utility;Office;
X-AppImage-Vendor=S.M.Y.T.
Terminal=false
DESKTOP

# AppRun is what the AppImage executes. It execs the launcher with APPDIR set, so the
# bundle finds its own data regardless of where the image was mounted.
cat > "$APPDIR/AppRun" <<'APPRUN'
#!/bin/bash
HERE="$(dirname "$(readlink -f "${0}")")"
export APPDIR="$HERE"
exec "$HERE/hollow_court" "$@"
APPRUN
chmod +x "$APPDIR/AppRun"

echo "== appimagetool =="
ARCH=x86_64 "$TOOL" --appimage-extract-and-run --no-appstream "$APPDIR" \
  "$OUT_DIR/hollow-court-$VERSION-x86_64.AppImage"

rm -rf "$APPDIR"
echo "== receipt =="
# `linux` is in the source list because the runner under `linux/runner` is COMPILED into this
# artifact, and it was missing from the list until 2026-09-21 -- so `write_receipt.sh` fell back to
# its default of `lib pubspec.yaml pubspec.lock`, and the receipt pointed at the last commit that
# touched `lib` while the running binary came from `linux/`. The receipt was under-claiming its own
# sources: a change to the GTK runner would have left it reading `ok`.
# `packaging/windows/build.sh` gets this right (`lib windows pubspec.yaml`), which is how the
# asymmetry was spotted.
bash "$REPO/packaging/write_receipt.sh" "$OUT_DIR/hollow-court-$VERSION-x86_64.AppImage" \
  "built under WSL/Nyarch; run under WSLg on 2026-09-23 (35 s, Impeller, GTK window); never run on a real Linux desktop" \
  lib linux pubspec.yaml pubspec.lock packaging/linux tool/build_linux.sh

echo "== done: $OUT_DIR/hollow-court-$VERSION-x86_64.AppImage =="
