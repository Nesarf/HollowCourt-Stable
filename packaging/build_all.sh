#!/usr/bin/env bash
#
# Builds all three targets at once, each in its own checkout.
#
# **Why this exists, in the guard's own words.** `tool/check_pub_config.py` says the shared
# `.dart_tool/package_config.json` "cannot be fixed by a check", and names the honest fixes: *a checkout per
# platform, a container, or a pub cache both sides can reach*. This is the first of those three, and the owner
# chose it on 2026-09-30.
#
# **The problem it solves is time rather than correctness.** Measured, cold: 142 s for Linux, 79 s of WiX, 71 s
# for the three APKs, 59 s for Windows -- 419 s in sequence, and the three builds cannot overlap in one tree
# because whichever platform runs `pub get` last rewrites eighty-five absolute paths that the other two are
# reading. In three trees they do not meet, so the three run together and the wall clock is the longest one
# rather than the sum.
#
# **Each worktree keeps its own caches between runs**, which is the other half of the gain: `build/` and
# `.dart_tool/` are ignored by git, so they are not copied when a worktree is created and they survive a
# `git worktree remove`. The layout is therefore made once and reused:
#
#     E:\hollow-court-par\android   one checkout, Windows paths
#     E:\hollow-court-par\linux     one checkout, WSL paths
#     E:\hollow-court-par\windows   one checkout, Windows paths
#
# **What it does not do is decide anything about what is built.** Versions still come from `pubspec.yaml` in
# this tree, the artifacts land in the same `E:\Hollow Court Bundle`, and the receipts and the manifest are
# the same scripts the sequential path runs. It is the same build, twice as fast.
#
# Usage:  bash packaging/build_all.sh [--clean]
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PAR="${PAR_DIR:-E:\\hollow-court-par}"
PAR_UNIX="$(echo "$PAR" | sed 's|\\|/|g')"
REV="$(git -C "$REPO" rev-parse HEAD)"
OUT_DIR="${OUT_DIR:-E:\\Hollow Court Bundle}"
MANIFEST=0

for arg in "$@"; do
  case "$arg" in
    --clean) MANIFEST=1 ;;
  esac
done

export ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-E:/DaShaoHuo/art-tools/android-sdk}"
export ANDROID_HOME="$ANDROID_SDK_ROOT"
WIX="${WIX:-/e/DaShaoHuo/tools/dotnet-tools/wix}"
WSL_DISTRO="${WSL_DISTRO:-Nyarch}"

log() { printf '%s  %s\n' "$(date +%H:%M:%S)" "$*"; }

# **`--detach`, so a parallel build never moves a branch.** The worktrees are scratch: they are put at a commit
# and built, and nothing about the repository's own history depends on them.
ensure_worktree() {
  local name="$1" path="$PAR_UNIX/$1"
  if [ -d "$path/.git" ] || [ -f "$path/.git" ]; then
    git -C "$path" checkout --detach --force "$REV" >/dev/null 2>&1 || true
  else
    mkdir -p "$PAR_UNIX"
    git -C "$REPO" worktree add --detach "$path" "$REV" >/dev/null 2>&1
  fi
  # **The worktree has to carry what this tree is building, not what it last committed.**
  #
  # The first version of this script checked each worktree out at HEAD and copied `pubspec.yaml`, which looked
  # sufficient and was not: **a build from uncommitted source produced the previous binary in all three trees.**
  # It was invisible in the result because everything reported success -- the worktrees simply compiled the older
  # code, and the only evidence was a timestamp on an executable that had not moved. A 63-second "parallel build"
  # was three builds of source that was already compiled, and reporting that number would have been reporting a
  # measurement of nothing.
  sync_working_tree "$path"
  printf '%s' "$path"
}

# Brings a worktree to the state of this one: HEAD, then every uncommitted change, then the untracked files.
#
# `checkout --detach --force` first, because a previous run may have left edits behind and applying a diff on top
# of those would conflict. **Caches are untouched on purpose**: `build/` and `.dart_tool/` are git-ignored, so
# they appear in no diff and survive this, which is the time this script exists to save.
sync_working_tree() {
  local path="$1"
  git -C "$REPO" diff HEAD --binary > "$path/.sync.patch" 2>/dev/null || true
  if [ -s "$path/.sync.patch" ]; then
    if ! git -C "$path" apply --whitespace=nowarn "$path/.sync.patch" >/dev/null 2>&1; then
      echo "build_all.sh: could not apply this tree's changes in $path" >&2
      echo "  it is at $REV and your edits sit on top; remove it with 'git worktree remove --force $path' and retry" >&2
      exit 1
    fi
  fi
  rm -f "$path/.sync.patch"
  # **Untracked files too**, because a new source file is a real thing to build and `git diff` does not mention it.
  git -C "$REPO" ls-files --others --exclude-standard -z |
    while IFS= read -r -d '' f; do
      mkdir -p "$path/$(dirname "$f")"
      cp "$REPO/$f" "$path/$f"
    done
}

ensure_worktree android > /dev/null
ensure_worktree linux   > /dev/null
ensure_worktree windows > /dev/null
log "==> three checkouts at ${REV:0:7}; nothing shared but the pub cache"

# **Logs are kept rather than discarded, and the first version got this wrong in a way worth recording.** They
# lived in a `mktemp -d` that an EXIT trap removed, so a failing run printed "the logs are worth reading" and
# then showed nothing at all. A report that offers evidence and delivers none is worse than a bare failure.
LOG_DIR="${LOG_DIR:-/e/DaShaoHuo/cache/build-logs}"
T="$LOG_DIR/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$T"
# `latest` is replaced rather than linked: **the first version used `ln -s` and failed on the second run**, because a
# previous fallback had copied the directory there and `rm -f` does not remove a directory.
rm -rf "$LOG_DIR/latest"
ln -s "$T" "$LOG_DIR/latest" 2>/dev/null || cp -r "$T" "$LOG_DIR/latest" 2>/dev/null || true
log "==> logs in $T"

# --------------------------------------------------------------------------------------------- Android
(
  cd "$PAR_UNIX/android" || exit 1
  export PATH="$PATH"
  bash packaging/android/build.sh > "$T/android.log" 2>&1
  echo "android exit=$?" > "$T/android.status"
) &
P_ANDROID=$!

# --------------------------------------------------------------------------------------------- Windows
(
  cd "$PAR_UNIX/windows" || exit 1
  WIX="$WIX" OUT_DIR="$OUT_DIR" bash packaging/windows/build.sh > "$T/windows.log" 2>&1
  echo "windows exit=$?" > "$T/windows.status"
) &
P_WINDOWS=$!

# ----------------------------------------------------------------------------------------------- Linux
# The WSL side reaches the worktree through `/mnt/e/...`, which is the same directory by another name.
(
  # `pwd -W` gives the Windows form, and **in this shell it already uses forward slashes** -- `E:/dir`, not
  # `E:\dir`. The first version carried a backslash-to-slash substitution borrowed from elsewhere and it was
  # both unnecessary and broken: with `\\` inside a double-quoted string sed receives `s|\|/|g` and reports an
  # unterminated command, so the substitution printed nothing and the mount point came out as
  # `/mnt/e/hollow-court-par/linux` -- missing the slash that makes it a path. **Measured, not reasoned about:**
  # the failing run's own log said exactly that, which is why the logs are kept now.
  LINUX_WIN_PATH="$(cd "$PAR_UNIX/linux" && pwd -W)"
  case "$LINUX_WIN_PATH" in
    /*) LINUX_MNT="$LINUX_WIN_PATH" ;;                                  # already a unix path
    [A-Za-z]:/*) LINUX_MNT="/mnt/$(printf '%s' "$LINUX_WIN_PATH" | sed 's|^\([A-Za-z]\):|\L\1|')" ;;
    *) LINUX_MNT="$LINUX_WIN_PATH" ;;
  esac
  if [ ! -d "$LINUX_WIN_PATH" ]; then
    echo "the linux worktree is not at '$LINUX_WIN_PATH' at all" > "$T/linux.log"
    echo "linux exit=1" > "$T/linux.status"
    exit 1
  fi
  # **The check that this path is visible to WSL happens inside WSL, and the first version got that wrong.**
  # `[ -d /mnt/e/... ]` was run here, in the shell that is reading this file -- which is git-bash, where `/mnt`
  # does not exist and the answer is always no. So the Linux target was skipped on every run while the script
  # reported it as a failure, and the path it named in the log was correct all along. **A path's existence is a
  # question about the machine you are standing on**, and the two sides of this build are different machines.
  if ! wsl -d "$WSL_DISTRO" -e bash -lc "[ -d '$LINUX_MNT' ]" 2>/dev/null; then
    echo "$LINUX_WIN_PATH is not visible to WSL as $LINUX_MNT" > "$T/linux.log"
    echo "linux exit=1" > "$T/linux.status"
    exit 1
  fi
  # `tool/build_linux.sh` writes beside its own worktree, so only the AppImage's output directory is given here.
  # **The argument is passed as one word rather than interpolated into a nested string** -- the first version
  # wrapped the whole command in a quoted heredoc-ish string and the quoting did not survive.
  # **The AppImage's output directory is translated, not hardcoded.** The first version wrote
  # `/mnt/e/Hollow Court Bundle` literally while the script accepted `OUT_DIR` and passed it to the other two
  # targets -- so the option worked for Windows and Android and silently did nothing for Linux. It is the same
  # fault the script's own header describes finding elsewhere: an option that is honoured in two places out of
  # three is an option a reader cannot trust.
  OUT_DIR_WIN="$(cd "$OUT_DIR" 2>/dev/null && pwd -W || printf '%s' "$OUT_DIR")"
  case "$OUT_DIR_WIN" in
    /*) OUT_DIR_MNT="$OUT_DIR_WIN" ;;
    [A-Za-z]:/*) OUT_DIR_MNT="/mnt/$(printf '%s' "$OUT_DIR_WIN" | sed 's|^\([A-Za-z]\):|\L\1|')" ;;
    *) OUT_DIR_MNT="$OUT_DIR_WIN" ;;
  esac
  wsl -d "$WSL_DISTRO" -e bash -lc "cd '$LINUX_MNT' && bash tool/build_linux.sh && OUT_DIR='$OUT_DIR_MNT' bash packaging/linux/build_appimage.sh" > "$T/linux.log" 2>&1
  echo "linux exit=$?" > "$T/linux.status"
) &
P_LINUX=$!

wait $P_ANDROID $P_WINDOWS $P_LINUX

echo
log "==> results"
FAILED=0
for target in android windows linux; do
  status="$(cat "$T/$target.status" 2>/dev/null || echo "$target exit=unknown")"
  printf '    %-8s %s\n' "$target" "$status"
  case "$status" in *exit=0) ;; *) FAILED=1 ;; esac
done

if [ "$FAILED" -ne 0 ]; then
  echo
  echo "one or more targets failed; the logs are worth reading rather than re-running:" >&2
  for target in android windows linux; do
    echo "--- $target (last 12 lines) ---" >&2
    tail -12 "$T/$target.log" 2>/dev/null >&2
  done
  exit 1
fi

# The manifest is the one step that has to happen after everything, because it hashes all of it.
if [ "$MANIFEST" -eq 1 ]; then
  bash "$REPO/packaging/make_manifest.sh" > "$T/manifest.log" 2>&1 && log "==> manifest" || {
    echo "make_manifest.sh failed:" >&2; tail -5 "$T/manifest.log" >&2; }
fi

log "==> done; artifacts in $OUT_DIR"
