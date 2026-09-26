#!/usr/bin/env bash
#
# Say which signing key an APK carries.
#
#     bash packaging/android/signing.sh <apk> [--fingerprint]
#
# WHY THIS EXISTS RATHER THAN TRUSTING THE BUILD. A "release" APK signed with the debug key is
# indistinguishable from a properly signed one by looking at it, and the difference is permanent: the
# platform will only install an update whose signature matches the copy already installed, and the
# debug keystore lives inside the build directory. So the question "which key is in this artifact?" is
# asked of the ARTIFACT, not of the build log -- and the answer is a certificate fingerprint that can
# be recorded next to the artifact.
set -u

APK="${1:?usage: signing.sh <apk> [--fingerprint]}"
WANT_FP="${2:-}"

SDK="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"
APKSIGNER="$(ls -d "$SDK"/build-tools/*/apksigner.bat 2>/dev/null | tail -1)"
if [ -z "$APKSIGNER" ]; then
  echo "signing.sh: no apksigner under $SDK/build-tools" >&2
  exit 2
fi
if [ ! -f "$APK" ]; then
  echo "signing.sh: no such artifact: $APK" >&2
  exit 2
fi

OUT="$(MSYS_NO_PATHCONV=1 cmd.exe /c "$(cygpath -w "$APKSIGNER")" verify --print-certs "$(cygpath -w "$APK")" 2>&1)"
DN="$(printf '%s\n' "$OUT" | grep -m1 'certificate DN' | sed 's/.*DN: //')"
FP="$(printf '%s\n' "$OUT" | grep -m1 'SHA-256 digest' | sed 's/.*digest: //')"

if [ "$WANT_FP" = "--fingerprint" ]; then
  printf '%s\n' "$FP"
  exit 0
fi

printf 'artifact : %s\n' "$(basename "$APK")"
printf 'signer DN: %s\n' "${DN:-（apksigner 没有报出 DN）}"
printf 'SHA-256  : %s\n' "${FP:-（apksigner 没有报出指纹）}"
case "$DN" in
  *"CN=Android Debug"*) printf 'verdict  : DEBUG-SIGNED -- an installation of this can never be updated\n' ;;
  "")                   printf 'verdict  : UNKNOWN -- apksigner said nothing usable\n' ;;
  *)                    printf 'verdict  : signed by a release key\n' ;;
esac
