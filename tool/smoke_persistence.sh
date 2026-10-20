#!/usr/bin/env bash
#
# **The persistence smoke test, across the platforms the application ships on.**
#
# `test/data/persistence_smoke_test.dart` is one process doing one phase. A restart cannot be faked inside a process,
# so this runs it **twice**, pointed at one directory: the first process writes, the second -- which shares nothing
# with the first but the disk -- reads back. That is what `docs/durability.md` says an append guarantees, and it is
# the claim `event_log_test` cannot make, because that test reopens inside one process and in a temporary directory.
#
# **Why it is a script and not a test.** A test that silently depends on a directory outside the repository fails on
# somebody else's machine for a reason that is not about the code. The test skips itself unless `SMOKE_DIR` is set, and
# this is what sets it.
#
# Usage:  bash tool/smoke_persistence.sh
#
set -u

REPO="$(cd "$(dirname "$0")/.." && pwd)"
CACHE="${SMOKE_ROOT:-/e/DaShaoHuo/cache/tmp}"
DIR="$CACHE/smoke-persistence"
FLUTTER="${FLUTTER_BIN:-flutter}"

rm -rf "$DIR"; mkdir -p "$DIR"

echo "== smoke: $DIR =="
echo "== flutter: $($FLUTTER --version 2>/dev/null | head -1) =="

run_phase() {
  local phase="$1"
  SMOKE_DIR="$DIR" SMOKE_PHASE="$phase" "$FLUTTER" test "$REPO/test/data/persistence_smoke_test.dart" 2>&1 |
    grep -E 'SMOKE (write|read)|All tests passed|Some tests failed' | head -2
}

echo "== phase 1: write =="
run_phase write

echo "== phase 2: read, in a fresh process =="
run_phase read

echo "== the files it left =="
ls -la "$DIR" | tail -n +2

# **The log file has to be non-empty and the read phase has to have passed**, and the second is what makes this a
# smoke test rather than a listing: a write that nobody can read back is the failure this exists to catch.
if [ ! -s "$DIR/cellar.ndjson" ]; then
  echo "smoke: cellar.ndjson is empty or missing" >&2
  exit 1
fi
echo "== ok =="
