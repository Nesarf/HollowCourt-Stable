#!/usr/bin/env bash
#
# Installs the AppImage for one user, so that it appears in the desktop menu and can be
# started by name. Run INSIDE the distribution that will hold it:
#
#     wsl -d Nyarch -e bash packaging/linux/install_appimage.sh [path-to.AppImage]
#
# WHY A SCRIPT RATHER THAN FOUR COMMANDS. An AppImage is a portable file, so "installing" it is a
# decision about where it lives and what points at it, and that decision is worth writing down
# once: a copied file with a hand-made .desktop beside it is four steps anybody can do slightly
# differently, and the differences are what break later.
#
# WHY THE DESKTOP FILE AND ICON COME OUT OF THE APPIMAGE RATHER THAN FROM HERE. The image already
# carries both -- `packaging/linux/build_appimage.sh` puts `hollow_court.desktop` and a 192x192
# icon in the AppDir -- so extracting them means the menu entry says what the image says. Writing
# a second copy here would be a second place to keep in step, and the two would disagree the first
# time the name changed.
#
# THE ONLY LINE THAT HAS TO BE REWRITTEN IS `Exec`. Inside the image it is `Exec=hollow_court`,
# which is correct when the image is mounted and useless from a menu, because the menu starts the
# file and not the mounted tree. It points at the installed image instead.
#
# To remove it again:
#
#     rm -f ~/.local/bin/hollow-court \
#           ~/.local/share/applications/hollow_court.desktop \
#           ~/.local/share/icons/hicolor/192x192/apps/hollow_court.png
#
# The app's own data is NOT in any of those: it lives wherever the platform puts a user's
# documents, so an uninstall does not take the cellar with it. That is deliberate.
set -euo pipefail

# `--system` is taken out of the arguments BEFORE the source path is read. The first version read
# `$1` as the image and then looked for a flag later, so `--system` was treated as a filename and the
# script answered "no AppImage at --system" -- a flag that silently became data.
SYSTEM_INSTALL=0
POSITIONAL=()
for argument in "$@"; do
  case "$argument" in
    --system) SYSTEM_INSTALL=1 ;;
    *) POSITIONAL+=("$argument") ;;
  esac
done
SOURCE="${POSITIONAL[0]:-${TMPDIR:-/tmp}/hollow-court-bundle/hollow-court-1.0.0-x86_64.AppImage}"
APP_ID="hollow_court"
BIN_DIR="$HOME/.local/bin"
APP_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
ICON_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor/192x192/apps"
TARGET="$BIN_DIR/hollow-court"

[ -f "$SOURCE" ] || { echo "no AppImage at $SOURCE" >&2; exit 1; }

echo "== copying the image into place =="
mkdir -p "$BIN_DIR" "$APP_DIR" "$ICON_DIR"
cp "$SOURCE" "$TARGET"
chmod +x "$TARGET"
echo "   $TARGET  ($(du -h "$TARGET" | cut -f1))"

echo "== taking the desktop entry and icon out of the image =="
# The AppImage runtime unpacks what it is asked for and nothing else, so this does not cost a
# second copy of a 23 MB image. The pattern is a squashfs path, and the leading `./` matters.
SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT
(
  cd "$SCRATCH"
  "$TARGET" --appimage-extract 'hollow_court.desktop' >/dev/null 2>&1
  "$TARGET" --appimage-extract 'hollow_court.png' >/dev/null 2>&1
  # EVERY SIZE THE IMAGE CARRIES, not only the one at its root. WSLg's lookup answered
  # `find_icon_file ... Icon file:(null)` while a single 192 was installed, and found the image the
  # moment the set a real desktop application ships was there. This extraction is load-bearing.
  "$TARGET" --appimage-extract 'usr/share/icons/hicolor/*' >/dev/null 2>&1 || true
)

[ -f "$SCRATCH/squashfs-root/hollow_court.desktop" ] || {
  echo "the image carried no hollow_court.desktop -- refusing to invent one" >&2
  exit 1
}
[ -f "$SCRATCH/squashfs-root/hollow_court.png" ] || {
  echo "the image carried no hollow_court.png" >&2
  exit 1
}

sed "s|^Exec=.*|Exec=$TARGET %U|" \
  "$SCRATCH/squashfs-root/hollow_court.desktop" > "$APP_DIR/hollow_court.desktop"
cp "$SCRATCH/squashfs-root/hollow_court.png" "$ICON_DIR/hollow_court.png"
for src in "$SCRATCH"/squashfs-root/usr/share/icons/hicolor/*/apps/hollow_court.png; do
  [ -f "$src" ] || continue
  size_dir="$(basename "$(dirname "$(dirname "$src")")")"
  dest="${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor/$size_dir/apps"
  mkdir -p "$dest"
  cp "$src" "$dest/"
done

# **/usr/share/pixmaps is the file WSLg actually reads, and a per-user install never touched it.**
#
# Measured on 2026-10-31 by substituting a flat red square: every hollow_court.png under hicolor, in
# three separate homes, was replaced and the regenerated icon did not change at all. Restoring only
# /usr/share/pixmaps/hollow_court.png changed it straight back to the artwork. That directory is the
# X11-era fallback every icon lookup still searches, and the packaging script copies into it only on a
# --system install -- so the one file that decided the icon was the one file left alone.
PIXMAP_DIR=/usr/share/pixmaps
PIXMAP_SRC="$SCRATCH/squashfs-root/usr/share/icons/hicolor/64x64/apps/hollow_court.png"
if [ -d "$PIXMAP_DIR" ] && [ -f "$PIXMAP_SRC" ]; then
  if [ -w "$PIXMAP_DIR" ]; then
    cp "$PIXMAP_SRC" "$PIXMAP_DIR/hollow_court.png"
    echo "   $PIXMAP_DIR/hollow_court.png"
  elif sudo -n true 2>/dev/null; then
    sudo -n cp "$PIXMAP_SRC" "$PIXMAP_DIR/hollow_court.png"       && echo "   $PIXMAP_DIR/hollow_court.png (through sudo -n)"
  else
    echo "   NOTE: $PIXMAP_DIR is not writable and sudo wants a password." >&2
    echo "         WSLg reads its icon from that file; without it the window icon stays stale:" >&2
    echo "         sudo cp '$PIXMAP_SRC' $PIXMAP_DIR/hollow_court.png" >&2
  fi
fi

echo "== registering =="
# Best-effort: a distribution without these tools still has a working image, it just refreshes the
# menu cache on its own schedule. Failing the install over a cache would be the tail wagging the dog.
command -v update-desktop-database >/dev/null && update-desktop-database "$APP_DIR" 2>/dev/null || true
command -v gtk-update-icon-cache >/dev/null && gtk-update-icon-cache -qtf "${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor" 2>/dev/null || true

# A second, SYSTEM-WIDE copy, because the user one is not enough for everything that reads it.
#
# WSLg builds the app list that Windows' taskbar uses by scanning /usr/share/applications -- its own
# log names only system paths, one per line -- so an entry in one user's home is invisible to it, and
# the window comes up with a placeholder however correct the per-user install is. Requires root,
# so it is offered rather than assumed.
#
#     sudo bash packaging/linux/install_appimage.sh --system
#
if [ "$SYSTEM_INSTALL" = "1" ]; then
  if [ "$(id -u)" != "0" ]; then
    echo "== system copy: skipped, not root ==" >&2
  else
    # SELF-CONTAINED, and that is the fix for a real bug in the first version.
    #
    # It copied the desktop file out of `$HOME/.local/share/applications`, which is right when the
    # same person runs both installs and wrong the moment they are not: run as root over `sudo`, and
    # `$HOME` is /root, so the system entry pointed its Exec at /root/.local/bin -- a launcher for a
    # program that exists only for the administrator, installed for everybody.
    #
    # So the system copy takes what it needs from the IMAGE, and puts the image somewhere system-wide
    # that the entry can name. Two files, no dependency on any user's home.
    echo "== system copy =="
    mkdir -p /usr/local/bin /usr/share/applications /usr/share/icons/hicolor/192x192/apps
    cp "$SOURCE" /usr/local/bin/hollow-court
    chmod +x /usr/local/bin/hollow-court

    SCRATCH_SYS="$(mktemp -d)"
    (
      cd "$SCRATCH_SYS" || exit 1
      /usr/local/bin/hollow-court --appimage-extract "$APP_ID.desktop" >/dev/null 2>&1
      /usr/local/bin/hollow-court --appimage-extract "$APP_ID.png" >/dev/null 2>&1
      /usr/local/bin/hollow-court --appimage-extract 'usr/share/icons/hicolor/*' >/dev/null 2>&1 || true
    )
    [ -f "$SCRATCH_SYS/squashfs-root/$APP_ID.desktop" ] || {
      echo "the image carried no $APP_ID.desktop" >&2
      rm -rf "$SCRATCH_SYS"
      exit 1
    }
    sed "s|^Exec=.*|Exec=/usr/local/bin/hollow-court %U|"       "$SCRATCH_SYS/squashfs-root/$APP_ID.desktop" > "/usr/share/applications/$APP_ID.desktop"
    for src in "$SCRATCH_SYS"/squashfs-root/usr/share/icons/hicolor/*/apps/"$APP_ID".png; do
      [ -f "$src" ] || continue
      dest="/usr/share/icons/hicolor/$(basename "$(dirname "$(dirname "$src")")")/apps"
      mkdir -p "$dest"
      cp "$src" "$dest/"
    done
    # The pixmaps fallback too: one file, and the log's `find_icon_file` global search still tries
    # that directory first.
    cp /usr/share/icons/hicolor/64x64/apps/"$APP_ID".png /usr/share/pixmaps/ 2>/dev/null || true
    rm -rf "$SCRATCH_SYS"

    command -v gtk-update-icon-cache >/dev/null && gtk-update-icon-cache -qtf /usr/share/icons/hicolor 2>/dev/null || true
    command -v update-desktop-database >/dev/null && update-desktop-database /usr/share/applications 2>/dev/null || true
    grep -E '^(Name|Exec|Icon)=' "/usr/share/applications/$APP_ID.desktop" | sed 's/^/  /'
  fi
fi

# **On WSL the install is not finished until the Windows shortcut is handled.** WSLg writes one .lnk
# per desktop entry on every start, each naming an icon under %TEMP%\WSLDVCPlugin that it regenerates
# from artwork which can be stale -- and it overwrites any correction made by hand. The shortcut's own
# IconLocation wins over that regenerated file, so this sets it and then marks the .lnk read-only.
#
# Measured on 2026-10-31: every icon directory in the distribution held the current picture, and WSLg
# still rebuilt a 16 KB .ico carrying the old mark. Neither Windows' FileIO tracing nor inotify inside
# the distribution could see where it read the old one -- 9p reads are issued by the Windows side and
# appear in neither. So the shortcut is corrected rather than the thing it copies from.
#
# Needs Windows, so it is a PowerShell script beside this one, and it is best-effort: a distribution
# without WSLg has no shortcut to fix and every step above has already succeeded.
if grep -qi microsoft /proc/version 2>/dev/null && command -v powershell.exe >/dev/null 2>&1; then
  echo
  echo "== windows shortcut (WSLg) =="
  here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  repo="$(cd "$here/../.." && pwd)"
  distro="${WSL_DISTRO_NAME:-}"
  [ -n "$distro" ] || distro="$(uname -n)"
  if [ -f "$here/wslg-shortcut.ps1" ]; then
    script_win="$(wslpath -w "$here/wslg-shortcut.ps1" 2>/dev/null || true)"
    icon_win="$(wslpath -w "$repo/windows/runner/resources/app_icon.ico" 2>/dev/null || true)"
    if [ -n "$script_win" ]; then
      if [ -n "$icon_win" ]; then
        powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$script_win" -Distro "$distro" -IconSource "$icon_win"           || echo "   the shortcut was not updated; the install itself is fine" >&2
      else
        powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$script_win" -Distro "$distro"           || echo "   the shortcut was not updated; the install itself is fine" >&2
      fi
    fi
  else
    echo "   skipped: wslg-shortcut.ps1 is not beside this script"
  fi
fi

echo
echo "== installed =="
echo "   image   $TARGET"
echo "   menu    $APP_DIR/hollow_court.desktop"
echo "   icon    $ICON_DIR/hollow_court.png"
echo
sed -n 's/^\(Name\|Name\[en\]\|Exec\|Icon\)=/\   \1=/p' "$APP_DIR/hollow_court.desktop"
echo
case ":$PATH:" in
  *":$BIN_DIR:"*) echo "   '$BIN_DIR' is on PATH, so 'hollow-court' works in a new shell." ;;
  *) echo "   NOTE: '$BIN_DIR' is not on PATH; add it, or start the image by its full path." ;;
esac
