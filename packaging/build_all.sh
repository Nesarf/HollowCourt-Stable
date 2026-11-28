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
#     D:\hollow-court-par\android   one checkout, Windows paths
#     D:\hollow-court-par\linux     one checkout, WSL paths
#     D:\hollow-court-par\windows   one checkout, Windows paths
#
# **What it does not do is decide anything about what is built.** Versions still come from `pubspec.yaml` in
# this tree, the artifacts land in the same `D:\hollow-court\dist`, and the receipts and the manifest are
# the same scripts the sequential path runs. It is the same build, twice as fast.
#
# Usage:  bash packaging/build_all.sh [--clean]
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PAR="${PAR_DIR:-D:\\hollow-court-par}"
PAR_UNIX="$(echo "$PAR" | sed 's|\\|/|g')"
REV="$(git -C "$REPO" rev-parse HEAD)"
OUT_DIR="${OUT_DIR:-D:\\hollow-court\\dist}"
MANIFEST=0
CLEAN=0

# **`--clean` used to mean "run the manifest at the end", which is the opposite of what it says.** It now
# clears the two kinds of state that outlive a checkout (see `clean_every_worktree` further down) and
# still asks for the manifest, because a build from zero is one whose result is worth recording.
# `--manifest` alone exists for what the old spelling was reaching for: record what is already there
# without rebuilding it.
for arg in "$@"; do
  case "$arg" in
    --clean)    CLEAN=1; MANIFEST=1 ;;
    --manifest) MANIFEST=1 ;;
  esac
done

# **These two defaults name where the toolchains are on this machine, and both of them moved.**
# The Android SDK was under `E:` until that drive was cleared; WiX is not a folder of binaries any
# more -- it is a `dotnet tool` in the global tool directory, already on PATH, which is exactly what
# `packaging/windows/build.sh` has always assumed (`WIX="${WIX:-wix}"`). The outer script was
# overriding that assumption with a path that no longer exists, so the first `wix build` would have
# died on a directory rather than on anything the build did.
export ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-D:/DaShaoHuo/art-tools/android-sdk}"
export ANDROID_HOME="$ANDROID_SDK_ROOT"
WIX="${WIX:-wix}"
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
  # **Untracked files too**, because a new source file is a real thing to build and `git diff` does not mention
  # it.
  git -C "$REPO" ls-files --others --exclude-standard -z |
    while IFS= read -r -d '' f; do
      mkdir -p "$path/$(dirname "$f")"
      cp "$REPO/$f" "$path/$f"
    done

  # **And the signing material, which is ignored by git and therefore in neither of the two steps above.**
  #
  # This is the fault that produced a debug-signed "release" on 2026-10-01, and it is worth describing because
  # every guard in the chain behaved correctly. `android/key.properties` and `android/release.jks` are both in
  # `.gitignore` -- correctly, since neither belongs in a repository -- so a fresh worktree has neither. Gradle
  # then takes its documented fallback and signs with the debug key, and `packaging/android/build.sh` has a
  # post-condition that refuses exactly this: *"android/key.properties EXISTS but ... is DEBUG-SIGNED."*
  #
  # **The check passed because the file did not exist.** Its intent was read from the tree, and in this tree the
  # answer to "was a release key intended?" was no. So the build reported success, the APKs were renamed and
  # hashed and receipted like any other, and the only symptom was `INSTALL_FAILED_UPDATE_INCOMPATIBLE` on a
  # handset that already had a properly signed copy. **A guard whose question is "does the intent file exist"
  # answers "no intent" for a tree that was simply built somewhere else.**
  #
  # So the material is carried across here rather than left to be discovered. Both files are copied because the
  # guard's question is about `key.properties` while Gradle needs the keystore it names; copying only the first
  # would satisfy the check and still sign with the debug key.
  for f in android/key.properties android/release.jks; do
    if [ -f "$REPO/$f" ]; then
      mkdir -p "$path/$(dirname "$f")"
      cp "$REPO/$f" "$path/$f"
    fi
  done
}

# **Clears the state that outlives a checkout, because two of the three caches can lie about where they are.**
#
# Measured on 2026-11-28, on the first build after the worktrees moved from E: to D:. Two targets failed for
# reasons no source change could explain:
#
#   * `build/linux/x64/release/CMakeCache.txt` still said `/mnt/e/hollow-court-par/...`, and CMake refused with
#     "the current CMakeCache.txt directory ... is different than the directory ... where it was created".
#   * `windows/flutter/ephemeral/.plugin_symlinks/` held links made against the old tree, and Flutter's
#     `createPluginSymlinks` answered the attempt to re-link with `PathExistsException ... errno = 183`.
#
# **The second one names a platform you are not building.** `flutter build windows` calls
# `createPluginSymlinks` without a platform argument, so it refreshes the links for *every* desktop platform in
# that checkout -- the failure surfaced under `windows/linux/flutter/ephemeral/`, which is easy to delete the
# wrong half of. All three are cleared here.
#
# `build/` holds the platform build trees and `ephemeral/` the generated plugin links; both are git-ignored, so
# `checkout --detach --force` leaves them alone and nothing else in this script would ever remove them.
clean_every_worktree() {
  for name in android linux windows; do
    for relative in build windows/flutter/ephemeral linux/flutter/ephemeral macos/Flutter/ephemeral; do
      if [ -e "$PAR_UNIX/$name/$relative" ]; then rm -rf "$PAR_UNIX/$name/$relative"; fi
    done
  done
}

ensure_worktree android > /dev/null
ensure_worktree linux   > /dev/null
ensure_worktree windows > /dev/null

if [ "$CLEAN" -eq 1 ]; then
  clean_every_worktree
  log "==> cleared build/ and every platform's ephemeral/ in all three checkouts"
fi

log "==> three checkouts at ${REV:0:7}; nothing shared but the pub cache"

# **Logs are kept rather than discarded, and the first version got this wrong in a way worth recording.** They
# lived in a `mktemp -d` that an EXIT trap removed, so a failing run printed "the logs are worth reading" and
# then showed nothing at all. A report that offers evidence and delivers none is worse than a bare failure.
# **On D:, like everything else this repository owns.** These logs lived under
# `/e/DaShaoHuo/cache/build-logs`: E: is where the shared toolchain caches live, and a log of this
# repository's own builds is not a shared cache.
LOG_DIR="${LOG_DIR:-D:/DaShaoHuo/cache/build-logs}"
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
  # `/mnt/d/hollow-court-par/linux` -- missing the slash that makes it a path. **Measured, not reasoned about:**
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
  # **Linux now produces a bundle directory and nothing else.** The AppImage is no longer built
  # (2026-11-27): Linux readers get `build/linux/x64/release/bundle` inside the portable archive, and a
  # second single-file format that has to be regenerated, receipted and re-verified for a platform which
  # already has a working way in is work nobody asked for. `packaging/linux/build_appimage.sh` stays in
  # the tree, unused, so this is reversed by one line rather than by writing it again.
  # **The argument is passed as one word rather than interpolated into a nested string** -- the first version
  # wrapped the whole command in a quoted heredoc-ish string and the quoting did not survive.
  # **The commit crosses into WSL as data, because git over there cannot read this checkout's `.git`.**
  # The worktree's `.git` is a text file naming `E:/hollow-court/.git/worktrees/linux`, which is a Windows path to
  # a Linux git -- so every receipt written inside WSL said `src-commit : none` until 2026-10-22. This side knows
  # the commit (it checked the worktree out at it) and the tree's cleanliness, so it hands both over.
  if git -C "$REPO" diff --quiet && git -C "$REPO" diff --cached --quiet; then TREE_DIRTY=no; else TREE_DIRTY=yes; fi
  wsl -d "$WSL_DISTRO" -e bash -lc "cd '$LINUX_MNT' && SRC_COMMIT='$REV' HEAD_REV='$REV' SRC_SUBJECT='$(git -C "$REPO" log -1 --format=%s "$REV")' TREE_DIRTY='$TREE_DIRTY' SRC_DIRTY='$TREE_DIRTY' bash tool/build_linux.sh" > "$T/linux.log" 2>&1
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

# **The portable archive is assembled here because it is built from the three targets' outputs
# rather than from a source tree.** Windows contributes `build/windows/x64/runner/Release`,
# Linux its bundle, macOS a `.app` when this machine is one -- none of which exists until those
# targets have finished. It is deliberately not behind a flag: a release shipped without it has
# one fewer way in, and the omission would surface at upload time rather than at build time.
if command -v pwsh >/dev/null 2>&1; then
  REPO_WIN="$(cygpath -w "$REPO" 2>/dev/null || printf '%s' "$REPO")"
  OUT_DIR_WIN="$(cygpath -w "$OUT_DIR" 2>/dev/null || printf '%s' "$OUT_DIR")"
  if pwsh -NoProfile -File "$REPO_WIN/packaging/portable/make_portable.ps1" -Bundle "$OUT_DIR_WIN" > "$T/portable.log" 2>&1; then
    log "==> portable  $(grep -oE 'hollow-court-[^ ]+-portable\.zip \([0-9.]+ MB\)' "$T/portable.log" | tail -1)"
  else
    echo "make_portable.ps1 failed:" >&2; tail -6 "$T/portable.log" >&2
    FAILED=1
  fi
else
  echo "pwsh is not on PATH, so the portable archive was not built" >&2
  FAILED=1
fi

# The manifest is the one step that has to happen after everything, because it hashes all of it.
if [ "$MANIFEST" -eq 1 ]; then
  bash "$REPO/packaging/make_manifest.sh" > "$T/manifest.log" 2>&1 && log "==> manifest" || {
    echo "make_manifest.sh failed:" >&2; tail -5 "$T/manifest.log" >&2; }
fi

log "==> done; artifacts in $OUT_DIR"
