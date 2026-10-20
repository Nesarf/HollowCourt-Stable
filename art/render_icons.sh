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
RENDER="$HERE/render"

# **Which mark family this run draws, and the default is the medallion.**
#
#     art/render_icons.sh                    # the medallion: the mark tied to the character sheet
#     MARK=construct art/render_icons.sh     # the constructivist alternative
#     MARK=image art/render_icons.sh         # drawn from a picture the owner brought
#     MARK=a art/render_icons.sh             # the publisher's A, at every size
#     MARK=picture-and-a art/render_icons.sh # the picture, with the A where the picture fails
#
# They are separate generators rather than one with a style switch, because they are separate identities:
# the medallion keeps the halo's three elements and its fifteen degrees of tilt from the character's
# setting, and the others owe the character nothing. Which one ships is therefore a decision and not a
# preference, so it is named here in one line and all of them stay in the repository. Nothing is deleted
# when another is drawn.
#
# **`picture-and-a` is the owner's instruction stated as a rule, and the rule is a measurement.** The
# picture is the mark; the A stands in only where the picture's information is gone. Measured, size by
# size: at 256 and 128 the still life reads; at 96 and 64 it is a pattern but the picture as a whole still
# holds; at 48 it is a dense field of brown blocks from which nobody could name an object; at 32 and below
# it is mottled colour. So the picture takes 64 and up, and the A takes 48 and below. The one number that
# decides is here rather than scattered through the loop.
FIDELITY_FLOOR=64
MARK="${MARK:-medallion}"
case "$MARK" in
  medallion)
    GENERATOR="$HERE/make_icon.py"
    SVG="$HERE/icon-hc.svg"
    MID="$HERE/icon-hc-mid.svg"
    SMALL="$HERE/icon-hc-small.svg"
    ;;
  construct)
    GENERATOR="$HERE/make_construct_icon.py"
    SVG="$HERE/icon-hc-construct.svg"
    MID="$HERE/icon-hc-construct-mid.svg"
    SMALL="$HERE/icon-hc-construct-small.svg"
    ;;
  image)
    # **The source travels with the generator, and this checks it is there before drawing.** The
    # drawing is a function of the picture, so a missing input is a pipeline that cannot run; it should
    # say so in those words rather than fail inside Python with a traceback nobody can act on.
    SOURCE="$HERE/mark-source.png"
    [ -f "$SOURCE" ] || {
      echo "render_icons.sh: $SOURCE is missing; the image mark is drawn from it" >&2
      echo "  put the picture there, then: python3 art/make_icon_from_image.py $SOURCE" >&2
      exit 2
    }
    GENERATOR="$HERE/make_icon_from_image.py"
    # One drawing per size that needs one, and `drawing_for` picks by exact divisibility: a drawing's cells
    # have to land on whole pixels, which is why there are nine rather than three.
    P48="$HERE/icon-hc-image-48.svg"
    P64="$HERE/icon-hc-image-64.svg"
    P72="$HERE/icon-hc-image-72.svg"
    P96="$HERE/icon-hc-image-96.svg"
    P128="$HERE/icon-hc-image-128.svg"
    P192="$HERE/icon-hc-image-192.svg"
    P256="$HERE/icon-hc-image-256.svg"
    P384="$HERE/icon-hc-image-384.svg"
    PFULL="$HERE/icon-hc-image.svg"
    ;;
  picture-and-a)
    # **Both families, and the split happens at render time.** This is the owner's rule of 2026-09-30: the
    # picture is the mark and the A stands in only where the picture's information is gone. Both generators
    # run, so both sets of drawings exist and either can be rendered alone afterwards; the choice between
    # them for a given size is `FIDELITY_FLOOR` in the loop below and nowhere else.
    SOURCE="$HERE/mark-source.png"
    [ -f "$SOURCE" ] || {
      echo "render_icons.sh: $SOURCE is missing; half of this mark is drawn from it" >&2
      echo "  put the picture there, then: python3 art/make_icon_from_image.py $SOURCE" >&2
      exit 2
    }
    GENERATOR="$HERE/make_icon_from_image.py"
    ALSO_GENERATE="$HERE/make_pixel_mark.py"
    # The picture's nine drawings, so that a size above the floor renders from whole cells.
    P48="$HERE/icon-hc-image-48.svg"
    P64="$HERE/icon-hc-image-64.svg"
    P72="$HERE/icon-hc-image-72.svg"
    P96="$HERE/icon-hc-image-96.svg"
    P128="$HERE/icon-hc-image-128.svg"
    P192="$HERE/icon-hc-image-192.svg"
    P256="$HERE/icon-hc-image-256.svg"
    P384="$HERE/icon-hc-image-384.svg"
    PFULL="$HERE/icon-hc-image.svg"
    # The stand-ins, one per size below the floor: a letter drawn for 24 rendered at 16 is bolder than the
    # drawing made for 16, which is the same fault as enlarging a small drawing, one step down.
    A16="$HERE/icon-hc-a16.svg"
    A24="$HERE/icon-hc-a24.svg"
    A32="$HERE/icon-hc-a32.svg"
    A48="$HERE/icon-hc-a48.svg"
    ;;
  a)
    # **The publisher's A, for the sizes where the picture mark cannot be read.** This family exists
    # because the still life of a dozen objects is mottled colour at sixteen pixels: the drawing is
    # replaced rather than shrunk, which is the same answer the medallion's smaller tiers took in
    # `docs/DESIGN.md` 12.7.1. Three drawings, one A each, all ink on the application's own ground.
    GENERATOR="$HERE/make_pixel_mark.py"
    # Six drawings, one per size the letter ships at, because a letter has to thin as the mark grows: a
    # drawing made for 32 pixels rendered at 256 gives a chunky A, which is what the first attempt produced.
    A16="$HERE/icon-hc-a16.svg"
    A24="$HERE/icon-hc-a24.svg"
    A32="$HERE/icon-hc-a32.svg"
    A48="$HERE/icon-hc-a48.svg"
    A64="$HERE/icon-hc-a64.svg"
    A128="$HERE/icon-hc-a128.svg"
    ;;
  *)
    echo "render_icons.sh: unknown MARK '$MARK' (expected medallion, construct, image or a)" >&2
    exit 2
    ;;
esac

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

echo "== drawing ($MARK) =="
python3 "$GENERATOR"
if [ -n "${ALSO_GENERATE:-}" ]; then
  # The stand-in is drawn as well, so both sets of drawings exist on disk and either can be rendered alone.
  echo "== drawing the stand-in (the A) =="
  python3 "$ALSO_GENERATE"
fi

echo "== checking the XML =="
# **Every drawing the family named, gathered from the variables rather than from a second list.** A family
# now names up to ten drawings, and a list here would be a second place to keep in step -- which is how the
# check came to be looking at unset variables and failing the run instead of checking anything. This walks
# the same names the mapping above reads, checks only those that exist, and refuses if none does.
checked=0
for candidate in "${SVG:-}" "${MID:-}" "${SMALL:-}" "${TINY:-}" "${A16:-}" "${A24:-}" "${A32:-}" \
                 "${A48:-}" "${A64:-}" "${A128:-}" "${P48:-}" "${P64:-}" "${P72:-}" "${P96:-}" \
                 "${P128:-}" "${P192:-}" "${P256:-}" "${P384:-}" "${PFULL:-}"; do
  # **An `if`, not `[ ... ] && [ ... ] || continue`.** That idiom looks the same and is not: with
  # `set -e`, a failing test on the left of `&&` can end the script before the `||` is reached, which is
  # what happened here -- the run stopped at this line every time, with no message, before checking one
  # drawing. An `if` has no such trap.
  if [ -n "$candidate" ] && [ -f "$candidate" ]; then
    bash "$REPO/packaging/windows/check_comments.sh" "$candidate"
    checked=$((checked + 1))
  fi
done
[ "$checked" -gt 0 ] || { echo "render_icons.sh: no drawing was checked for family $MARK" >&2; exit 2; }
echo "  $checked drawing(s) checked"

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

# ---- which drawing a size is rendered from, one line per case ----
#
# **The rule is that a drawing's cells land on whole pixels, and that is measured rather than assumed.** An
# Android icon is 48 pixels at mdpi and 192 at xxxhdpi, and 192 is not a multiple of 128: rendering the
# 128-cell drawing at 192 gave 1.5 pixels per cell, and against a native 192-cell drawing a quarter of the
# pixels differed and the edges showed seams. So each size is served by the finest drawing that divides it
# exactly. Two sizes fall back to a coarser one because nothing divides them more finely: 144 to the 48-cell
# drawing, and 432 to the 72-cell one. 1024 uses the 512-cell drawing on purpose -- a 1024-cell drawing is a
# two-megabyte file for detail nobody reads at masthead size.
#
# Each family names its own drawings below and this reads them; a family that names none of them falls back
# to the three-tier defaults, which is how the medallion and the constructivist mark are still rendered.
drawing_for() {
  case "$1" in
    16)
      if   [ -n "${A16:-}" ]; then echo "$A16"
      elif [ -n "${TINY:-}" ]; then echo "$TINY"
      else echo "${SMALL:-}"; fi ;;
    24)
      if   [ -n "${A24:-}" ]; then echo "$A24"
      elif [ -n "${TINY:-}" ]; then echo "$TINY"
      else echo "${SMALL:-}"; fi ;;
    32)
      if   [ -n "${A32:-}" ]; then echo "$A32"
      elif [ -n "${TINY:-}" ]; then echo "$TINY"
      else echo "${SMALL:-}"; fi ;;
    48)
      if   [ -n "${A48:-}" ] && [ -n "${FIDELITY_FLOOR:-}" ] && [ 48 -lt "$FIDELITY_FLOOR" ]; then echo "$A48"
      elif [ -n "${P48:-}" ]; then echo "$P48"
      else echo "${MID:-}"; fi ;;
    64)   echo "${A64:-${P64:-${MID:-}}}" ;;
    72)   echo "${A64:-${P72:-${MID:-}}}" ;;
    96)   echo "${A128:-${P96:-${MID:-}}}" ;;
    128)  echo "${A128:-${P128:-${SVG:-}}}" ;;
    144)  echo "${A128:-${P48:-${SVG:-}}}" ;;   # 144 = 3 x 48; nothing in the set divides it more finely
    192)  echo "${A128:-${P192:-${SVG:-}}}" ;;
    256)  echo "${A128:-${P256:-${SVG:-}}}" ;;
    384)  echo "${A128:-${P384:-${SVG:-}}}" ;;
    432)  echo "${A128:-${P72:-${SVG:-}}}" ;;   # 432 = 6 x 72
    512)  echo "${A128:-${PFULL:-${SVG:-}}}" ;;
    1024) echo "${A128:-${PFULL:-${SVG:-}}}" ;;
    *)    echo "" ;;
  esac
}

for size in 1024 512 432 384 256 192 144 128 96 72 64 48 32 24 16; do
  source="$(drawing_for "$size")"
  if [ -z "$source" ] || [ ! -f "$source" ]; then
    echo "render_icons.sh: no drawing for $size pixels (family $MARK)" >&2
    exit 2
  fi

  # **144 is drawn at twice its size and halved.** Of the sizes that ship, 144 is the one whose own size has
  # no fine divisor: it divides by 48 and nothing else above it, and a 48-cell drawing enlarged three times
  # is a field of blocks -- rendered beside the same mark drawn at 96 cells and halved from 288, the finer
  # one keeps the objects legible and the coarse one loses them, which is a measurement and not a preference.
  # A power-of-two reduction is exact at the pixel level, so nothing is lost by it.
  #
  # It is written as one explicit case rather than derived from the drawing's name, because an earlier
  # attempt tried to derive it and asked `drawing_for` for sizes the table has no entry for -- 288 and 1024 --
  # which returned nothing and silently left the coarse drawing in place. The table above is the truth about
  # which drawings exist; anything else that needs one has to say so itself.
  render_at="$size"
  shrink=1
  if [ "$size" = 144 ]; then
    source="${P96:-$source}"
    render_at=288
    shrink=2
  fi
  rsvg-convert -w "$render_at" -h "$render_at" "$source" -o "$RENDER/icon-hc-$size.png"
  if [ "$shrink" -gt 1 ]; then
    # Halved by ImageMagick rather than rendered small, so the reduction is one exact step: every source
    # pixel becomes a whole block of two.
    magick "$RENDER/icon-hc-$size.png" -resize "$((100 / shrink))%" "$RENDER/icon-hc-$size.png"
  fi
  printf '  %-4s %-14s %-4s %s\n' "$size" "$(basename "$source")" \
    "$([ "$shrink" -gt 1 ] && echo "${shrink}x" || echo '')" "$(du -h "$RENDER/icon-hc-$size.png" | cut -f1)"
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
