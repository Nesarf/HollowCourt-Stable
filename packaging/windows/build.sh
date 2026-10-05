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

# **And then ask whether that config is OURS.** `pub get` writes absolute paths into `.dart_tool/`, and the
# Linux side of this project shares that directory, so the one that ran last owns it. Building with the other
# side's config fails as hundreds of undefined `Offset`, `Paint` and `Rect` -- a path problem that reads as a
# broken source tree. `tool/check_pub_config.py` says which it is, in one sentence and with the fix.
python3 "$REPO/tool/check_pub_config.py"

VERSION="$(grep -m1 '^version:' pubspec.yaml | tr -d '
' | sed 's/version: *//; s/+.*//')"
BUILD_NUMBER="$(grep -m1 '^version:' pubspec.yaml | tr -d '
' | sed 's/.*+//')"
DEFINES="--dart-define=APP_VERSION=$VERSION.$BUILD_NUMBER-J1407b-FFF8E7 --dart-define=BUILD_COMMIT=$(git rev-parse HEAD 2>/dev/null || echo unknown)"

# A double hyphen inside an XML comment is a syntax error that WiX reports at a position
# pointing at the comment rather than at the mistake. It has now cost this project a build twice,
# and the second time was after the rule was written down in packaging/README.md. A rule in prose
# is not a check, so the check is a script.
#
# **And it runs before the compile, not after it.** It sat below the Flutter build, so a mistake in a
# comment was discovered only once six and a half minutes of compiling had been spent on a source file
# WiX was never going to accept -- which is how it was found the third time. The cost of a check and the
# cost of what it protects are different numbers, and the cheap one goes first.
bash "$REPO/packaging/windows/check_comments.sh" "$REPO/packaging/windows/hollow-court.wxs"

echo "==> flutter build windows --release (About screen reads $VERSION.$BUILD_NUMBER)"
PATH="$FLUTTER_BIN:$PATH" flutter build windows --release $DEFINES --project-root "$REPO" 2>/dev/null \
  || (cd "$REPO" && PATH="$FLUTTER_BIN:$PATH" flutter build windows --release $DEFINES)

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
# **`art` is in this list because the application icon is built from it.** `art/render_icons.sh` writes
# `windows/runner/resources/app_icon.ico`, which Flutter embeds in `hollow_court.exe`, so a change to `art/` changes
# what this installer carries. The list omitted it and the MSI therefore read `OTHER` the moment the icon pipeline
# was repaired; the Linux script has carried `art` for the same reason since 2026-09-21.
bash "$REPO/packaging/write_receipt.sh" "$OUT_DIR\hollow-court-$MSI_VERSION.msi" \
  "wix msi validate: $ICE_FINDINGS findings ($ICE_CODES); ICE43/ICE57 are the per-user shortcut's keypath, ICE48 is the fixed install path by design, ICE60 is unversioned files; none is fatal and none is unexamined" \
  lib windows art pubspec.yaml packaging/windows

# The .wixpdb is WiX's debug-symbol file for the MSI: not shipped, but it is what turns a crash
# report from a user back into a line of source, so its provenance has to match the MSI's.
# Without its own receipt it reads 'unrecorded' forever, and a manifest that permanently reports
# one unknown row is a manifest people stop reading.
if [ -f "$OUT_DIR\hollow-court-$MSI_VERSION.wixpdb" ]; then
  bash "$REPO/packaging/write_receipt.sh" "$OUT_DIR\hollow-court-$MSI_VERSION.wixpdb" \
    "companion to hollow-court-$MSI_VERSION.msi; maps a crash back to source, never shipped" \
    lib windows art pubspec.yaml packaging/windows
fi

echo "==> burn bundle (the .exe installer)"

# **The `.exe` is built FROM the `.msi`, and that order is the design rather than an accident.** The MSI owns
# the files, the shortcuts and the uninstall entry; the bundle carries it, with a bootstrapper in front. So
# there is one description of what "installed" means and the `.exe` is a delivery method for it, which is why
# this runs after the MSI has been built and validated rather than beside it.
#
# **`-ext` takes the extension's NAME, not a path.** That cost four failed builds: a path is accepted by the
# option, ignored silently, and the failure surfaces later as `WIX0200: unhandled extension element`, which
# reads like a mistake in the source rather than a missing extension. The extension lives in this machine's WiX
# cache, added once with `wix extension add -g WixToolset.BootstrapperApplications.wixext`, and this checks for
# it so a fresh machine gets a sentence instead of that error.
if ! "$WIX" extension list -g 2>/dev/null | grep -q 'BootstrapperApplications'; then
  echo "build.sh: the Burn extension is not in this machine's WiX cache." >&2
  echo "  The .exe installer needs it, and it is one command:" >&2
  echo "      wix extension add -g WixToolset.BootstrapperApplications.wixext" >&2
  echo "  (5.0.2 is what this was built against, matching this machine's wix.exe)" >&2
  exit 2
fi

SETUP_WIN="$(cygpath -w "$OUT_DIR/hollow-court-$MSI_VERSION-setup.exe")"
"$WIX" build -ext WixToolset.BootstrapperApplications.wixext \
  -arch x64 \
  -d "BundleVersion=$MSI_VERSION" \
  -d "MsiPath=$MSI_WIN" \
  -d "BundleIcon=$(cygpath -w "$REPO/windows/runner/resources/app_icon.ico")" \
  -o "$SETUP_WIN" \
  "$(cygpath -w "$REPO/packaging/windows/hollow-court-bundle.wxs")"

echo "==> receipt (bundle)"
bash "$REPO/packaging/write_receipt.sh" "$SETUP_WIN" \
  "burn bundle carrying hollow-court-$MSI_VERSION.msi; the MSI is the install and this is the double-clickable delivery of it" \
  lib windows art pubspec.yaml packaging/windows

# **The bundle has a `.wixpdb` too, and the first round forgot it.** A manifest row that reads
# 'unrecorded' never resolves on its own, so the file would have sat there as a permanent unknown in a
# document that is only worth reading while every line means something. Same reason the MSI's companion is
# receipted above, and the same list of sources.
if [ -f "$OUT_DIR\hollow-court-$MSI_VERSION-setup.wixpdb" ]; then
  bash "$REPO/packaging/write_receipt.sh" "$OUT_DIR\hollow-court-$MSI_VERSION-setup.wixpdb" \
    "companion to hollow-court-$MSI_VERSION-setup.exe; maps a crash back to source, never shipped" \
    lib windows art pubspec.yaml packaging/windows
fi

echo "==> done: $OUT_DIR\hollow-court-$MSI_VERSION.msi"
echo "==> done: $OUT_DIR\hollow-court-$MSI_VERSION-setup.exe"
