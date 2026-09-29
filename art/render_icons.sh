#!/usr/bin/env bash
#
# Draws the mark and renders every size the three platforms need.
#
#     art/render_icons.sh              # from anywhere; paths are resolved from this file
#
# WHY THE COMMENT CHECK IS IN HERE. `make_icon.py` writes the SVG, and the first version of it put a
# double hyphen inside an XML comment, which is not XML: the renderer refused the file with a
# position pointing into the comment rather than at the mistake. `packaging/windows/check_comments.sh`
# already existed for exactly that rule on the WiX sources, written after the same thing cost two
# builds there. The check is a script with a name about WiX and a rule about XML, so it runs here
# too -- adding a second copy of the rule for SVG would be the second place to keep in step.
#
# WHY rsvg-convert AND NOT A DESIGN TOOL. Both the SVG and the PNGs are in the repository, and the
# PNGs are what ship. A generator plus a renderer is a pipeline anybody can re-run; a file dragged
# out of an editor is a binary nobody can reproduce.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
SVG="$HERE/icon-hc.svg"
RENDER="$HERE/render"

command -v python3 >/dev/null || { echo "python3 is needed to draw the mark" >&2; exit 1; }
command -v rsvg-convert >/dev/null || { echo "rsvg-convert is needed to render it" >&2; exit 1; }

echo "== clearing the previous render =="
# Removed BEFORE anything is drawn, on purpose. A generator that fails leaves the previous SVG and
# the previous PNGs in place, and the PNGs are what ship -- so a broken pipeline looks exactly like
# a working one until somebody notices the mark has not changed. That is not hypothetical: it
# happened while this file was being written, and the giveaway was only that the new render had the
# same checksum as the old one.
rm -f "$RENDER"/icon-hc-*.png
echo "  cleared"

echo "== drawing =="
python3 "$HERE/make_icon.py"

echo "== checking the XML =="
bash "$REPO/packaging/windows/check_comments.sh" "$SVG"
bash "$REPO/packaging/windows/check_comments.sh" "$HERE/icon-hc-mid.svg"
bash "$REPO/packaging/windows/check_comments.sh" "$HERE/icon-hc-small.svg"

echo "== rendering =="
# **Each size is rendered from the drawing made for it.** The mark ships at fifteen sizes and was one
# drawing at all of them, so the twenty-four pyramids, the seventy-two beads and the eight-stop bismuth ramp
# collapsed into a grey ring below 48 pixels -- which is the same fault this script's own note about the .ico
# was written about, one level up: a small size has to be *drawn* small. `make_icon.py` emits three densities
# and the boundaries are here, where the sizes are:
#
#   128 and up   the whole medallion: 24 pyramids, the bead-and-reel moulding, all eight crystal hues
#   48 to 96     twelve pyramids, no moulding (one flat ring instead), five hues, larger letters
#   32 and down  eight pyramids, no white ring, four hues, letters at 352 units and stroked to hold their
#                diagonals -- at 16 pixels a Textura capital is a third of a pixel wide and it is the first
#                thing to disappear
#
# The reference is a crafting game's mark: one flat silhouette, detail as negative space rather than thin lines,
# two inks on paper.
mkdir -p "$RENDER"
for size in 1024 512 432 384 256 192 144 128 96 72 64 48 32 24 16; do
  if [ "$size" -ge 128 ]; then source="$SVG"
  elif [ "$size" -ge 48 ]; then source="$HERE/icon-hc-mid.svg"
  else source="$HERE/icon-hc-small.svg"
  fi
  rsvg-convert -w "$size" -h "$size" "$source" -o "$RENDER/icon-hc-$size.png"
  printf '  %-4s %-8s %s\n' "$size" "$(basename "$source")" "$(du -h "$RENDER/icon-hc-$size.png" | cut -f1)"
done

echo "== installing =="
# Every platform gets the same mark from the same render, which is the point of having an icon
# pipeline at all. The three do not agree on a size or a format, so the sizes are named here once:
#
#   Android  five densities, and the launcher picks by the screen's own density
#   Windows  one .ico holding several sizes, because Windows asks for different ones in the taskbar,
#            the title bar and the file explorer, and it wants a small size to be DRAWN small rather
#            than scaled down from a large one
#   Linux    the 192 the AppImage's desktop entry names, and the same file at the sizes a menu uses
mkdir -p "$REPO/android/app/src/main/res/mipmap-mdpi"          "$REPO/android/app/src/main/res/mipmap-hdpi"          "$REPO/android/app/src/main/res/mipmap-xhdpi"          "$REPO/android/app/src/main/res/mipmap-xxhdpi"          "$REPO/android/app/src/main/res/mipmap-xxxhdpi"

install_one() {
  cp "$RENDER/icon-hc-$1.png" "$2"
  printf '  %-46s %s
' "$2" "$(du -h "$2" | cut -f1)"
}
install_one 48  "$REPO/android/app/src/main/res/mipmap-mdpi/ic_launcher.png"
install_one 72  "$REPO/android/app/src/main/res/mipmap-hdpi/ic_launcher.png"
install_one 96  "$REPO/android/app/src/main/res/mipmap-xhdpi/ic_launcher.png"
install_one 144 "$REPO/android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png"
install_one 192 "$REPO/android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png"

# And the copy the Linux runner loads for the window icon. It is an asset rather than a file the
# runner finds on disk, so it lives under assets/ and is declared in pubspec -- this line is what
# keeps it from drifting away from the render.
mkdir -p "$REPO/assets/icon"
install_one 256 "$REPO/assets/icon/hollow-court.png"

# ImageMagick rather than Pillow, and the reason is in this script's own comment above: Pillow's
# ICO writer takes ONE image and resizes it to each size, which is exactly the downscaling the note
# warns against. `magick` assembles the icon from the separately rendered frames, so the 16 in the
# taskbar is a 16 drawn at 16. The first version used Pillow and produced seven sizes that were all
# resampled from 1024 -- the comment was right and the code disagreed with it.
magick   "$RENDER/icon-hc-16.png" "$RENDER/icon-hc-24.png" "$RENDER/icon-hc-32.png"   "$RENDER/icon-hc-48.png" "$RENDER/icon-hc-64.png" "$RENDER/icon-hc-128.png"   "$RENDER/icon-hc-256.png"   "$REPO/windows/runner/resources/app_icon.ico"
printf '  %-46s %s
' "$REPO/windows/runner/resources/app_icon.ico"   "$(du -h "$REPO/windows/runner/resources/app_icon.ico" | cut -f1)"

echo
echo "== done: $RENDER, and the three platforms =="
