#!/usr/bin/env bash
#
# Runs `tool/sync_probe.dart` with the package config this platform needs.
#
#     tool/probe.sh host --dir <cellar> --name laptop --port 47654
#
# **Why a wrapper and not a line in the README.** `.dart_tool/package_config.json` lives in the project
# tree and is therefore shared between the Windows copy and the WSL copy of this project -- and one of
# them running `pub get` rewrites every package path for the other. The symptom is not a path error: it
# is hundreds of "Undefined name 'SimplePublicKey'" errors in a file that plainly imports the package,
# which reads as "the source is broken". It has cost time five times, twice in one session.
#
# Every Flutter build script in `packaging/` already begins with a `pub get` for exactly this reason.
# The probe is the one entry point that is *not* a Flutter command, so it needs the same line -- and
# putting it in a script is the difference between a rule somebody remembers and a rule that runs.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# The fallback is whatever `flutter` the developer already has on their PATH.

"$FLUTTER_BIN/flutter" pub get --directory "$REPO" >/dev/null
exec "$FLUTTER_BIN/dart" run "$REPO/tool/sync_probe.dart" "$@"
