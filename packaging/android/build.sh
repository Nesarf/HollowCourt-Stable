#!/usr/bin/env bash
#
# Build the Android release, put it in the bundle, and write its receipt.
#
#     bash packaging/android/build.sh              # one APK per ABI (the stable release)
#     UNIVERSAL=1 bash packaging/android/build.sh  # one APK for every device, three times the size
#
# WHY ANDROID NEEDED A SCRIPT AT ALL. Windows and Linux each had one; Android was a `flutter build apk`
# typed by hand followed by a hand-written receipt, which is how the artifact the project had verified
# and the artifact in the bundle drifted apart once already. An artifact is a claim about the source it
# was built from, and on Android it is ALSO a claim about the key that signed it -- so the receipt here
# records both, and the fingerprint is read out of the built APK rather than out of the build log.
#
# WHY ONE APK PER ABI, which is the difference between this script and its first version. A plain
# `flutter build apk --release` produces one **universal** APK, and this project shipped it for weeks:
#
#     52.8 MB total -- lib/x86_64 18.81 MB + lib/arm64-v8a 17.39 MB + lib/armeabi-v7a 14.97 MB
#
# so every reader downloaded fifty-two megabytes to install seventeen, and **x86_64 is not even a
# phone** -- it is emulators and a handful of Intel tablets. Section 14.1 says the size budget is a hard
# constraint rather than an aspiration, because the number is paid by every user; a universal APK pays
# it three times over. `--split-per-abi` gives one file per architecture, and a phone installs the one
# that matches it.
#
# The universal build is still available behind `UNIVERSAL=1`, because there is one honest reason to
# want it: handing a single file to a device whose architecture you do not know. That is what the phone
# round needed, and it is why the flag exists rather than the mode being deleted.
set -eu

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO"

# The two pubspec fields, kept apart because pub requires a three-part version and the owner named a
# four-part one: `1.0.0+514` is the pair, `1.0.0.514` is what it is called. Both the APK's `versionName`
# and the About screen's value come from these two numbers, so a bump in pubspec moves every place a
# version is shown.
VERSION="$(grep -m1 '^version:' pubspec.yaml | tr -d '
' | sed 's/version: *//; s/+.*//')"
BUILD_NUMBER="$(grep -m1 '^version:' pubspec.yaml | tr -d '
' | sed 's/.*+//')"
DISPLAY_VERSION="$VERSION.$BUILD_NUMBER"
COMMIT="$(git -C "$(dirname "$0")/../.." rev-parse HEAD 2>/dev/null || echo unknown)"
DEFINES="--dart-define=APP_VERSION=$DISPLAY_VERSION --dart-define=BUILD_COMMIT=$COMMIT"

OUT_DIR="${OUT_DIR:-/e/Hollow Court Bundle}"
SPLIT="${UNIVERSAL:-0}"

export PATH="${FLUTTER_BIN:-$(dirname "$(command -v flutter 2>/dev/null || echo /usr/bin/flutter)")}:$PATH"

echo "== package config for this platform =="
# A PUB GET BEFORE EVERY BUILD, and the reason is not tidiness. `.dart_tool/package_config.json` sits
# in the project tree and is shared with the Linux side of this project, so a `pub get` run in WSL
# rewrites all 85 package paths to `/home/nyarch/.pub-cache/...` and Windows can then no longer find
# the Flutter SDK. The error that produces names no path: it is hundreds of complaints that `Offset`,
# `Paint` and `Rect` are undefined in `lib/ui/price_chart.dart`, a file that imports them. That is how
# this script came to exist -- the first `flutter build apk --release` after a Linux build failed
# exactly that way, 19:37 having been the moment the Linux side rewrote the file.
flutter pub get >/dev/null

# **The bundle's copy of the library is refreshed here, and not by hand.** `data/` is what the tests check;
# `assets/` is what the app loads; keeping the two in step was a manual step until 2026-09-23, when a Windows
# build shipped 88 drinks while the library held 103. `test/data/seed/shipped_assets_match_the_data_test.dart`
# is the guard for the same thing.
bash "$REPO/packaging/sync_assets.sh"


if [ "$SPLIT" = "1" ]; then
  echo "== flutter build apk --release (universal, one file for every device) =="
  BUILD_ARGS="--release"
  PRODUCED="build/app/outputs/flutter-apk/app-release.apk"
  # The stale universal file this mode replaces is removed from the bundle below, so the bundle never
  # holds both a per-ABI set and a universal file that look equally current.
else
  echo "== flutter build apk --release --split-per-abi (one file per architecture) =="
  BUILD_ARGS="--release --split-per-abi"
  PRODUCED="build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk
build/app/outputs/flutter-apk/app-x86_64-release.apk"
fi

# THE EXIT STATUS IS CHECKED, and that is not a formality. The first version of this script piped the
# build into `tail`, so a build that FAILED at :app:validateSigningRelease was reported as a success --
# and the copy below then put the PREVIOUS, debug-signed APK into the bundle looking exactly like a
# fresh one. That is the same species as the stale icon render and the stale Linux binary this project
# has already been bitten by twice: an artifact that is current-looking and not current.
# The defines are what the About screen reads. Until 2026-09-23 nothing passed them and the screen showed
# its default, which was a version number rather than a word, so every build claimed to be 1.0.0+1.
echo "== About screen will read: $DISPLAY_VERSION from $COMMIT =="
if ! flutter build apk $BUILD_ARGS $DEFINES 2>&1 | tail -4; then
  echo "build.sh: flutter build apk FAILED -- nothing was copied and no receipt was written" >&2
  exit 1
fi

BUILD_TOOLS="$(ls -d "${ANDROID_SDK:-${ANDROID_HOME:-${ANDROID_SDK_ROOT:-/usr/lib/android-sdk}}}"/build-tools/* 2>/dev/null | tail -1)"

# ---- the version the ARTIFACT reports, which is what the file name has to use -------------------------
#
# **This used to read pubspec, and on a four-part version that is wrong in a way that costs something.**
# pub requires `major.minor.patch`, so the name the owner chose (`1.0.0.514`) lives in the Android build
# file while pubspec holds `1.0.0+514`. Naming from pubspec would have called this build
# `hollow-court-1.0.0-*.apk` -- **the same name as the previous round's** -- and the cleanup below would
# then have deleted that file, taking the only rollback copy with it. So the name is read out of the
# built APK's own manifest: an artifact is the authority on which version it is, and a file name that
# disagrees with its contents is the same species of wrong as a receipt for an artifact that is gone.
FIRST_PRODUCED="$(printf '%s\n' $PRODUCED | head -1)"
APK_VERSION=""
if [ -n "$BUILD_TOOLS" ] && [ -x "$BUILD_TOOLS/aapt2" ]; then
  APK_VERSION="$("$BUILD_TOOLS/aapt2" dump badging "$FIRST_PRODUCED" 2>/dev/null |
    sed -n "s/^package: name='[^']*' versionCode='[^']*' versionName='\([^']*\)'.*/\1/p")"
fi
if [ -z "$APK_VERSION" ]; then
  echo "build.sh: could not read versionName out of $(basename "$FIRST_PRODUCED")" >&2
  echo "          falling back to pubspec's build-name $VERSION, which may collide with a previous round" >&2
  APK_VERSION="$VERSION"
fi
echo "== artifact versionName: $APK_VERSION (pubspec build-name $VERSION) =="

mkdir -p "$OUT_DIR"
# The previous files **of this same version** go first, whatever shape they were: a universal APK left
# beside a new per-ABI set is an artifact whose name says "release" and whose contents are the old build.
# **Files of other versions are kept**, and that is a change of behaviour worth stating: with a four-part
# version each round now has its own name, so the previous round's APK survives as the rollback that the
# one-name-per-version arrangement used to destroy.
rm -f "$OUT_DIR"/hollow-court-"$APK_VERSION"-*.apk
# **And their receipts, which the first version of this left behind.** A receipt is a claim *about an
# artifact*, so one whose artifact is gone is not harmless: the manifest finds a `.commit` file, looks
# for the file it describes, and reports a row nobody can resolve -- and after the per-ABI change it left
# `-release.apk.commit` describing an APK that no longer exists.
for receipt in "$OUT_DIR"/hollow-court-"$APK_VERSION"-*.apk.commit; do
  [ -f "$receipt" ] || continue
  [ -f "${receipt%.commit}" ] || rm -f "$receipt"
done

# ---- the checks that must run on every file this script produces -------------------------
#
# One function rather than a loop body, because the checks are the reason this script exists and both of
# them are things a build can pass while being wrong.

# **A release APK without `android.permission.INTERNET` cannot open a socket at all**, and it fails with
# EPERM rather than with anything a reader could act on:
#
#     SocketException: Connection failed (OS Error: Operation not permitted, errno = 1)
#
# Flutter's template declares that permission in `src/debug/AndroidManifest.xml` only -- a debug build
# needs it for the Dart VM service -- so this shipped in a release APK and every LAN sync on a real phone
# failed while every test passed, because the tests run in a debug build. Found by syncing two physical
# devices, which is the only thing that could have found it. This is the cheap version of that afternoon.
check_permissions() {
  local apk="$1"
  if [ -z "$BUILD_TOOLS" ] || [ ! -x "$BUILD_TOOLS/aapt2" ]; then
    echo "== permission check skipped: aapt2 not found under ${ANDROID_SDK:-${ANDROID_HOME:-${ANDROID_SDK_ROOT:-/usr/lib/android-sdk}}}"
    return 0
  fi
  # **A failure to read the APK is not a missing permission**, and the first version of this check
  # conflated them: the file had just been written and aapt2 was briefly unable to open it, so the guard
  # accused the build of the one thing it was actually doing right. Two different problems, two messages.
  if ! PERMISSIONS="$("$BUILD_TOOLS/aapt2" dump permissions "$apk" 2>&1)"; then
    echo "build.sh: could not read $apk, so the permission check did not run:" >&2
    echo "          $PERMISSIONS" >&2
    exit 1
  fi
  case "$PERMISSIONS" in
    *android.permission.INTERNET*)
      echo "== permission check: INTERNET is declared in $(basename "$apk")" ;;
    *)
      echo "build.sh: $(basename "$apk") DOES NOT DECLARE android.permission.INTERNET" >&2
      echo "          section 10's LAN sync cannot open a socket without it, and the failure on a device" >&2
      echo "          is EPERM rather than anything that names the permission." >&2
      exit 1 ;;
  esac
}

# THE POST-CONDITION, AND IT IS THE POINT OF THE WHOLE ARRANGEMENT. A debug-signed APK beside a
# key.properties that exists means the build silently did not use the key -- which happened here, and was
# caught only because this check was added. Intent is read from the tree; the answer is read from the
# artifact.
check_signing() {
  local apk="$1"
  local signer
  signer="$(bash "$REPO/packaging/android/signing.sh" "$apk")"
  printf '%s\n' "$signer"
  if [ -f "$REPO/android/key.properties" ] && printf '%s' "$signer" | grep -q 'DEBUG-SIGNED'; then
    echo "" >&2
    echo "build.sh: android/key.properties EXISTS but $(basename "$apk") is DEBUG-SIGNED." >&2
    echo "          The build did not use the release key. Refusing to call this a release." >&2
    exit 1
  fi
}

# `packaging/android` is in the source list for the reason `linux/runner` is in the AppImage one: this
# script and the signing setup are what produced the artifact, so a change to either makes the receipt
# under-claim its own sources. It read `ok` across a signing change until this line.
write_one() {
  local produced="$1" name="$2" apk="$3"
  [ -f "$produced" ] || { echo "build.sh: the build did not produce $produced" >&2; exit 1; }
  cp "$produced" "$apk"
  [ -f "$apk" ] || { echo "build.sh: the copy did not land: $apk" >&2; exit 1; }

  local abi="universal"
  case "$name" in
    *arm64-v8a*) abi="arm64-v8a (every modern phone)" ;;
    *armeabi-v7a*) abi="armeabi-v7a (older 32-bit phones)" ;;
    *x86_64*) abi="x86_64 (emulators and Intel tablets)" ;;
  esac
  # Android's own manifest check would catch it, but a receipt that does not say which architecture the
  # file is for is a receipt a person has to open the file to understand.
  local size
  # `awk` rather than `bc`: this runs under git-bash, where bc is not guaranteed, and a size label that
  # silently came out empty would be a receipt that lost the one number it was added for.
  local mb
  mb="$(wc -c <"$apk" | awk '{printf "%.1f", $1/1048576}')"
  local note="release apk for $abi; ${mb} MB; signed sha256:$(bash "$REPO/packaging/android/signing.sh" "$apk" --fingerprint 2>/dev/null || echo unknown)"
  if printf '%s' "$(bash "$REPO/packaging/android/signing.sh" "$apk" 2>/dev/null || true)" | grep -q 'DEBUG-SIGNED'; then
    note="release apk for $abi; DEBUG-SIGNED"
  fi

  bash "$REPO/packaging/write_receipt.sh" "$apk" "$note" lib android pubspec.yaml assets packaging/android
}

for produced in $PRODUCED; do
  case "$produced" in
    *arm64-v8a*) name="hollow-court-$APK_VERSION-arm64-v8a.apk" ;;
    *armeabi-v7a*) name="hollow-court-$APK_VERSION-armeabi-v7a.apk" ;;
    *x86_64*) name="hollow-court-$APK_VERSION-x86_64.apk" ;;
    *) name="hollow-court-$APK_VERSION-release.apk" ;;
  esac
  apk="$OUT_DIR/$name"
  write_one "$produced" "$name" "$apk"
  check_permissions "$apk"
  echo "== which key signed $(basename "$apk") =="
  check_signing "$apk"
  echo "== done: $apk ($(du -h "$apk" | cut -f1)) =="
done

echo "== the bundle now holds: =="
# A loop rather than `ls | awk`: the bundle path contains a space, so field-splitting ls output printed
# three truncated paths next to three sizes -- a summary that is wrong in the one place a person looks to
# confirm the build is right.
for apk in "$OUT_DIR"/hollow-court-"$APK_VERSION"-*.apk; do
  [ -f "$apk" ] || continue
  printf '   %-44s %6.1f MB
' "$(basename "$apk")" "$(wc -c <"$apk" | awk '{printf "%.1f", $1/1048576}')"
done
