#!/usr/bin/env bash
#
# Create the Android release keystore, and the key.properties the Gradle build reads.
#
#     bash packaging/android/make_keystore.sh [alias]
#     bash packaging/android/make_keystore.sh --auto-password [alias]
#
# READ THIS BEFORE RUNNING IT. The key this writes IS the application's identity. Every future release
# must be signed with the same one or Android will refuse to install it over what is already there;
# lose it and no update can ever reach the copies that exist. So:
#
#   * keep a backup of the .jks somewhere that is not this machine and not this repository,
#   * the passwords are the only thing protecting it, and key.properties is git-ignored for that
#     reason,
#   * if this is run twice you get two different identities, and the second cannot update the first.
#
# It is deliberately NOT run automatically and NOT run by any other script.
set -eu

# TWO WAYS IN, because they are two different situations.
#
#   default            keytool prompts, the operator types a password, and this script does NOT
#                      capture it -- key.properties is written with placeholders for them to fill in.
#                      That is the right default when a person is at the keyboard: the password never
#                      passes through a shell, a log or a scrollback.
#
#   --auto-password    this script GENERATES a strong password, uses it for both the store and the key,
#                      and writes a COMPLETE key.properties. It exists because the alternative in a
#                      scripted setup is a placeholder left in place, which is a keystore nobody can
#                      open -- worse than either option. The cost is real and is why it is not the
#                      default: the password is printed, so it is on the terminal and in whatever
#                      holds that afterwards.
AUTO=no
if [ "${1:-}" = "--auto-password" ]; then
  AUTO=yes
  shift
fi
ALIAS="${1:-hollow-court}"

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
JKS="$REPO/android/release.jks"
PROPS="$REPO/android/key.properties"
KEYTOOL="${KEYTOOL:-keytool}"

[ -x "$KEYTOOL" ] || KEYTOOL="$(command -v keytool || true)"
[ -n "$KEYTOOL" ] || { echo "make_keystore.sh: no keytool (set KEYTOOL=...)" >&2; exit 2; }

if [ -f "$JKS" ]; then
  echo "make_keystore.sh: $JKS already exists. Refusing to overwrite an application's identity." >&2
  echo "                  Delete it deliberately if that is really what you mean." >&2
  exit 1
fi

printf 'alias      : %s\n' "$ALIAS"
printf 'keystore   : %s\n' "$JKS"
printf 'properties : %s\n' "$PROPS"

umask 077

if [ "$AUTO" = "yes" ]; then
  # 32 characters from a 62-symbol alphabet: about 190 bits, and it is typed nowhere.
  PASSWORD="$(python -c "
import secrets, string
alphabet = string.ascii_letters + string.digits
print(''.join(secrets.choice(alphabet) for _ in range(32)))
")"

  MSYS_NO_PATHCONV=1 "$KEYTOOL" -genkeypair \
    -keystore "$(cygpath -w "$JKS")" -alias "$ALIAS" \
    -keyalg RSA -keysize 4096 -validity 10000 \
    -storepass "$PASSWORD" -keypass "$PASSWORD" \
    -dname "CN=Hollow Court, OU=S.M.Y.T., O=S.M.Y.T., L=, ST=, C=" 2>&1 | tail -2

  {
    echo "# Written by packaging/android/make_keystore.sh --auto-password on $(date -Iseconds)."
    echo "# This file and android/release.jks together ARE the application's identity: without them no"
    echo "# update can ever reach an installed copy. Back both up somewhere that outlives this machine."
    echo "storeFile=release.jks"
    echo "storePassword=$PASSWORD"
    echo "keyAlias=$ALIAS"
    echo "keyPassword=$PASSWORD"
  } >"$PROPS"

  printf '\nGENERATED PASSWORD -- shown once, and now also in %s:\n\n    %s\n\n' "$PROPS" "$PASSWORD"
else
  printf '\nThe keytool prompts for a password, and asks for the same one again for the key.\n\n'

  MSYS_NO_PATHCONV=1 "$KEYTOOL" -genkeypair -v \
    -keystore "$(cygpath -w "$JKS")" \
    -alias "$ALIAS" \
    -keyalg RSA -keysize 4096 -validity 10000 \
    -dname "CN=Hollow Court, OU=, O=, L=, ST=, C="

  {
    echo "storeFile=release.jks"
    echo "storePassword=CHANGE-ME-TO-WHAT-YOU-TYPED"
    echo "keyAlias=$ALIAS"
    echo "keyPassword=CHANGE-ME-TO-WHAT-YOU-TYPED"
  } >"$PROPS"

  printf '\nkey.properties written with placeholders for the passwords.\n'
  printf 'PUT THE REAL PASSWORDS IN IT BY HAND -- they were not captured here, and this script does not\n'
  printf 'read them from the keytool prompt.\n'
fi

printf '\nNext:\n'
printf '    bash packaging/android/build.sh\n'
printf '    bash packaging/android/signing.sh <the apk it produced>\n'
printf 'and back the .jks AND its passwords up somewhere that is not this machine.\n'
