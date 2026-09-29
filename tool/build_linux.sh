#!/usr/bin/env bash
#
# Builds the Linux target. Run this from the project root, inside WSL:
#
#     wsl -d Nyarch -e bash tool/build_linux.sh
#
# Why a script rather than a line in the README: Flutter keeps absolute paths in
# .dart_tool/package_config.json, and that directory is shared between the
# Windows and Linux copies of this project because it lives in the project tree.
# A pub get on one side rewrites the paths for the other, and the other then
# cannot find the Flutter SDK at all -- which surfaces as hundreds of errors
# about Material widgets being undefined, in a file that plainly imports them.
#
# So every build begins with a pub get. It costs a few seconds and it is the
# whole difference between a build that works and one that fails in a way that
# looks like the source is broken.
set -euo pipefail

# Where the project is, worked out from this file rather than from the working directory.
#
# **The stale-tree guard below used this variable before it was defined anywhere**, and `set -u`
# turned that into `REPO: unbound variable` at line 48, so the script died before it built anything.
# It went unnoticed because the guard's own logic was tested in isolation against a fixture and the
# SCRIPT was never run end to end afterwards: the thing that passed a test and the thing that
# shipped were not the same thing. Testing the piece is not testing the path.
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# The Linux half of this machine's toolchain. Override FLUTTER_ROOT to build
# somewhere else.
FLUTTER_ROOT="${FLUTTER_ROOT:-/opt/flutter}"
export PATH="$FLUTTER_ROOT/bin:$PATH"

# storage.googleapis.com resets connections on Flutter's artefact repository
# from this network; the mirror serves the same files.
export FLUTTER_STORAGE_BASE_URL="${FLUTTER_STORAGE_BASE_URL:-https://mirrors.cloud.tencent.com/flutter}"

if [ ! -x "$FLUTTER_ROOT/bin/flutter" ]; then
  echo "no flutter at $FLUTTER_ROOT -- set FLUTTER_ROOT, or see the README" >&2
  exit 1
fi

# The SECOND absolute-path trap in this repository, and the same species as the first: a build tree
# configured on one distribution carries that distribution's paths, and a different distribution
# resolves them to nothing.
#
#   Ubuntu-24.04 cached:  /usr/lib/x86_64-linux-gnu/glib-2.0/include
#   Nyarch (Arch):        /usr/lib/glib-2.0/include
#
# CMake reports it as `Imported target "PkgConfig::GTK" includes non-existent path ... in its
# INTERFACE_INCLUDE_DIRECTORIES`, which names the path but not the reason, and the reason is that
# the build directory outlived the distribution it was made in. Deleting build/linux is the fix,
# and it costs one rebuild.
#
# Checked rather than described, for the same reason the double-hyphen rule in packaging/windows
# had to become a script: the .dart_tool trap below was written down here and still cost time again
# in its CMake form.
if [ -d "$REPO/build/linux" ]; then
  # `|| true` on the end, and without it this line killed the script in the ordinary case.
  #
  # With `set -o pipefail`, a `grep` that matches nothing makes the whole pipeline return 1, and an
  # assignment whose command substitution fails returns that status -- so `set -e` aborted the build
  # on every run where the tree was NOT stale, which is nearly every run. A guard written to stop a
  # silent failure introduced one, and it stayed invisible because the guard's logic was tested on
  # its own, against a fixture, while the script it lives in was not run end to end afterwards.
  stale="$(grep -rho '/usr/lib/[a-z0-9_-]*-linux-gnu/[a-z0-9./_-]*' "$REPO/build/linux" 2>/dev/null | sort -u | head -3 || true)"
  if [ -n "$stale" ]; then
    echo "== stale build tree ==" >&2
    echo "build/linux was configured somewhere that used a multiarch layout, and this" >&2
    echo "distribution does not have these paths:" >&2
    echo "$stale" | sed 's/^/  /' >&2
    echo >&2
    echo "Removing it; a rebuild is the whole cost." >&2
    rm -rf "$REPO/build/linux"
    echo >&2
  fi
fi

echo "== package config for this platform =="
flutter pub get

# **The bundle's copy of the library is refreshed here, not by hand.** `data/` is what the tests check and
# `assets/` is what the app loads; keeping them in step was manual until 2026-09-23, when a Windows build
# shipped 88 drinks while the library held 103. The guard for the same thing lives in
# test/data/seed/shipped_assets_match_the_data_test.dart.
bash "$REPO/packaging/sync_assets.sh"


echo
echo "== build =="
# The About screen reads these, and NOTHING passed them until 2026-09-23 -- so the screen showed a
# hardcoded default on every platform while its own comment claimed the scripts supplied the values.
VERSION="$(grep -m1 '^version:' pubspec.yaml | tr -d '' | sed 's/version: *//; s/+.*//')"
BUILD_NUMBER="$(grep -m1 '^version:' pubspec.yaml | tr -d '' | sed 's/.*+//')"
# **One line, and it used to be two.** The first version passed the second define on a continuation whose
# backslash was lost on the way in, so that line became a command of its own:
#
#     tool/build_linux.sh: line 88: --dart-define=BUILD_COMMIT=...: command not found
#
# **And the build itself had already succeeded without either define**, which is the part worth keeping:
# the bundle existed, the status was 127, and anybody reading only the artifact would have shipped a build
# whose About screen says `unknown`. Both defines fit on one line.
flutter build linux "$@" --dart-define=APP_VERSION="$VERSION.$BUILD_NUMBER" --dart-define=BUILD_COMMIT="$(git rev-parse HEAD 2>/dev/null || echo unknown)"

echo
echo "== artifact =="
ls -la build/linux/x64/*/bundle/ 2>/dev/null || ls -la build/linux/*/bundle/ 2>/dev/null || true
