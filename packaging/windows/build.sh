#!/usr/bin/env bash
# Builds the Windows installer from a clean tree.
#
# Two steps and one variable, and the variable is the part that was learned the hard
# way: WiX resolves a relative path against the WORKING DIRECTORY and not against the
# .wxs file, so a release folder named relative to the source is looked for in the wrong
# place and reported as a missing file. Passing it absolutely removes the question.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WIX="${WIX:-wix}"
FLUTTER_BIN="${FLUTTER_BIN:-$(dirname "$(command -v flutter 2>/dev/null || echo /usr/bin/flutter)")}"
RELEASE_DIR="$(cygpath -w "$REPO/build/windows/x64/runner/Release" 2>/dev/null || echo "$REPO/build/windows/x64/runner/Release")"
OUT_DIR="${OUT_DIR:-E:\Hollow Court Bundle}"
VERSION="$(grep -m1 '^version:' "$REPO/pubspec.yaml" | tr -d '
' | sed 's/version: *//; s/+.*//')"

echo "==> package config for this platform"
# BEFORE ANY BUILD, A PUB GET FOR THE PLATFORM YOU ARE ON.
#
# `.dart_tool/package_config.json` lives in the project tree and is SHARED between the Windows and the
# Linux copies of this project, so a `pub get` on one side rewrites every path for the other. The other
# then cannot find the Flutter SDK, and the failure does not look like a path problem: it looks like
# hundreds of errors saying that `Offset`, `Paint` and `Rect` are undefined, in a file that plainly
# imports them.
#
# It has now happened in both directions. Linux was the first, and `tool/build_linux.sh` has carried
# the note since; Android was the second, found when `flutter build apk --release` failed on
# `lib/ui/price_chart.dart` while `flutter analyze` on the same tree reported no issues at all --
# because analyze had run before the Linux build overwrote the file and the APK build after it.
#
# `flutter pub get` costs seconds. Not running it costs an hour of reading a compiler's opinion about

# **The bundle's copy of the library is refreshed here, and not by hand.** `data/` is what the tests check;
# `assets/` is what the app loads; keeping the two in step was a manual step until 2026-09-23, when a Windows
# build shipped 88 drinks while the library held 103. `test/data/seed/shipped_assets_match_the_data_test.dart`
# is the guard for the same thing.
bash "$REPO/packaging/sync_assets.sh"

# code that is fine.
PATH="$FLUTTER_BIN:$PATH" flutter pub get >/dev/null

VERSION="$(grep -m1 '^version:' pubspec.yaml | tr -d '
' | sed 's/version: *//; s/+.*//')"
BUILD_NUMBER="$(grep -m1 '^version:' pubspec.yaml | tr -d '
' | sed 's/.*+//')"
DEFINES="--dart-define=APP_VERSION=$VERSION.$BUILD_NUMBER --dart-define=BUILD_COMMIT=$(git rev-parse HEAD 2>/dev/null || echo unknown)"

echo "==> flutter build windows --release (About screen reads $VERSION.$BUILD_NUMBER)"
PATH="$FLUTTER_BIN:$PATH" flutter build windows --release $DEFINES --project-root "$REPO" 2>/dev/null \
  || (cd "$REPO" && PATH="$FLUTTER_BIN:$PATH" flutter build windows --release $DEFINES)

# A double hyphen inside an XML comment is a syntax error that WiX reports at a position
# pointing at the comment rather than at the mistake. It has now cost this project a build twice,
# and the second time was after the rule was written down in packaging/README.md. A rule in prose
# is not a check, so the check is a script and it runs here.
bash "$REPO/packaging/windows/check_comments.sh" "$REPO/packaging/windows/hollow-court.wxs"

# PATHS ARE CONVERTED HERE AND NOT LEFT TO THE CALLER'S ENVIRONMENT.
#
# wix.exe is a Windows program, and a POSIX path reaches it unchanged unless git-bash happens to
# convert it -- which depends on whether the caller has MSYS_NO_PATHCONV set. This script worked for
# as long as every caller had conversion on, and then failed with
#
#     error WIX0103: Cannot find the input file '/e/hollow-court/packaging/windows/hollow-court.wxs'
#
# the first time it was run with MSYS_NO_PATHCONV=1. The path was always wrong to hand over; it had
# merely been being fixed up by accident. cygpath makes the script independent of who runs it.
WXS_WIN="$(cygpath -w "$REPO/packaging/windows/hollow-court.wxs")"

# **The MSI name comes from the .wxs, not from pubspec.** The two carry different versions on purpose:
# pubspec holds the pair `1.0.0+514` and the app displays `1.0.0.514`, while Windows Installer compares
# only three fields and ignores a fourth, so the installer's product version is `1.0.514`. Naming the
# file after what the artifact reports keeps the two from disagreeing, and it gives this round its own
# name so the previous MSI survives as the rollback -- pubspec naming did neither.
#
# **And it fails loudly on an empty capture.** The first version of these lines let sed's replacement be
# eaten -- a literal 0x01 byte landed in the script where the back-reference should have been -- and an
# empty MSI_VERSION would have named the artifact `hollow-court- .msi` while every check downstream still
# passed. Two characters are now read out with their delimiters instead of by substitution.
MSI_VERSION="$(grep -m1 '^      Version="' "$REPO/packaging/windows/hollow-court.wxs" | cut -d'"' -f2)"
case "$MSI_VERSION" in
  ''|*[!0-9.]*)
    echo "build.sh: could not read a version out of the .wxs (got '$MSI_VERSION')" >&2
    exit 1 ;;
esac
MSI_WIN="$(cygpath -w "$OUT_DIR/hollow-court-$MSI_VERSION.msi")"

echo "== MSI product version: $MSI_VERSION (app display version $VERSION.$BUILD_NUMBER) =="
echo "==> wix build  ($MSI_VERSION, release dir $RELEASE_DIR)"
"$WIX" build "$WXS_WIN" \
  -arch x64 \
  -d "ReleaseDir=$RELEASE_DIR" \
  -o "$MSI_WIN"

echo "==> validating"
# **COUNTED, NOT REMEMBERED.** This step used to pipe the validator through `grep -v WIX1076 || true`
# and hand the receipt a hard-coded sentence -- "51 ICE findings, only ICE64 has a real consequence".
# Both halves were wrong by the time anybody looked: the package reports five findings, not 51, and
# ICE64 is not among them. The 51 was true of an earlier shape of this package, when the files were
# harvested into the user's profile and ICE38/ICE64/ICE91 had something to complain about; moving the
# install to a fixed path removed those checks and nobody updated the sentence. A receipt is a claim
# about an artifact, so it is now built from the validator's own output.
#
# The findings are NOT failures and the build does not stop for them: ICE43 and ICE57 are the
# per-user Start Menu shortcut sharing a component with a file outside the profile, and ICE48 is the
# fixed install path, which `.wxs` argues for at length. What must not happen is the artifact
# carrying a count nobody measured.
VALIDATION="$REPO/build/windows/wix-validation.txt"
mkdir -p "$(dirname "$VALIDATION")"
"$WIX" msi validate "$OUT_DIR\hollow-court-$MSI_VERSION.msi" > "$VALIDATION" 2>&1 || true
grep -oE 'ICE[0-9]+' "$VALIDATION" | sort | uniq -c | sort -rn | sed 's/^/    /'
ICE_FINDINGS=$(grep -cE 'ICE[0-9]+' "$VALIDATION" || true)
ICE_CODES=$(grep -oE 'ICE[0-9]+' "$VALIDATION" | sort -u | tr '\n' ' ' || true)
echo "    $ICE_FINDINGS findings: $ICE_CODES"
echo "    full output: $VALIDATION"

echo "==> receipt"
bash "$REPO/packaging/write_receipt.sh" "$OUT_DIR\hollow-court-$MSI_VERSION.msi" \
  "wix msi validate: $ICE_FINDINGS findings ($ICE_CODES); ICE43/ICE57 are the per-user shortcut's keypath, ICE48 is the fixed install path by design, ICE60 is unversioned files; none is fatal and none is unexamined" \
  lib windows pubspec.yaml packaging/windows

# The .wixpdb is WiX's debug-symbol file for the MSI: not shipped, but it is what turns a crash
# report from a user back into a line of source, so its provenance has to match the MSI's.
# Without its own receipt it reads 'unrecorded' forever, and a manifest that permanently reports
# one unknown row is a manifest people stop reading.
if [ -f "$OUT_DIR\hollow-court-$MSI_VERSION.wixpdb" ]; then
  bash "$REPO/packaging/write_receipt.sh" "$OUT_DIR\hollow-court-$MSI_VERSION.wixpdb" \
    "companion to hollow-court-$MSI_VERSION.msi; maps a crash back to source, never shipped" \
    lib windows pubspec.yaml packaging/windows
fi

echo "==> done: $OUT_DIR\hollow-court-$MSI_VERSION.msi"
