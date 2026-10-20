# Build times, measured

Written on 2026-09-30 because the owner asked a direct question: **the package is under 30 MB, so why does a
release take twenty minutes?** The answer took four measurements and two corrections of my own numbers, and both
corrections are below, because they are the useful part.

## Where the time actually goes

One target at a time, on this machine, warm caches, one real source change forcing a recompile of all three:

| Stage | Time |
| --- | --- |
| `flutter build apk --release --split-per-abi` (three ABIs, three AOT passes) | 112 s |
| `flutter build windows --release` | 110 s |
| `flutter build linux --release` (under WSL) | ~145 s |
| `appimagetool` (under WSL) | ~40 s |
| **Total, one after another** | **407 s ≈ 6 min 50 s** |

Cold — after `flutter clean` — the same sequence is **497 s ≈ 8 min 20 s**. So a single release build has never
been twenty minutes. **Twenty minutes is what three of them cost**, which is what happens when each target is
built as its own run: every run pays its own cold compile.

## What the size of the package has to do with it: nothing

The intuition that a 19 MB artifact should build quickly is understandable and wrong, and the numbers say why.
Compressed, one 3939 APK is:

| | Compressed | Share |
| --- | --- | --- |
| `lib/` — Flutter's and Android's native libraries, already compiled by other people | 17.77 MB | **94.1%** |
| `assets/art/` — the fourth world's picture | 0.56 MB | 3.0% |
| **Dart AOT code — every line of this project** | **0.10 MB** | **0.6%** |
| `assets/` — the library and its translations | 0.05 MB | 0.2% |

**Ninety-four percent of the package is files nobody compiles here**, and what is compiled here is 258 Dart files
of about 160 KB. The build does not spend its time moving the 19 MB: it spends it running the Dart compiler and
then the platform toolchains, and **neither has anything to do with the size of what comes out**.

## Three suggestions that do not apply here

Recorded because they are the ones anybody would reach for, and each was checked rather than dismissed:

- **`ccache` / `sccache`.** These cache C/C++ and Rust object files. **No object file in this project is ours**:
  the only C++ is Flutter's runner templates, which are a few hundred lines and compile in seconds, and Dart does
  not go through a C compiler at all. A compiler cache with nothing to cache adds configuration and saves nothing.
- **"Cache `node_modules`, Gradle home, `.cargo`."** There is no `node_modules`; Gradle's own cache is already
  reused between runs (which is why the warm Android build is 112 s against 155 s cold); and nothing here is Rust.
- **"Turn on parallel compilation — `make -j`, `cmake --build --parallel`."** Gradle and Ninja already use every
  core; they are not the part that is slow, and there is no flag left to add.

**The time is not in a compiler that could be cached or a job that could be split. It is in three toolchains that
have to run once each, and they were running one after another.**

## The fix: build the three at once, in three checkouts

`packaging/build_all.sh` runs all three targets concurrently, each in its own `git worktree`.

**They cannot share one tree, and that is a fact about this project rather than about Flutter.**
`.dart_tool/package_config.json` holds eighty-five absolute paths into the pub cache, and the two sides of this
machine keep that cache in different places -- `E:/DaShaoHuo/cache/pub/...` on Windows and
`/home/nyarch/.pub-cache/...` under WSL. Whichever side runs `pub get` last rewrites all eighty-five for itself.
`tool/check_pub_config.py` exists to make that failure legible, and its own documentation names the three honest
fixes: *a checkout per platform, a container, or a pub cache both sides can reach.* **This is the first of them,
chosen by the owner on 2026-09-30.**

Measured, both with the same source change so both really recompiled:

| | Sequential | Parallel, three worktrees |
| --- | --- | --- |
| Wall clock | **407 s** | **192 s** |

**2.1×, and the shape of the gain is what matters**: the wall clock becomes the longest single target (Linux, at
about 185 s) rather than the sum of three. The worktrees keep `build/` and `.dart_tool/` between runs, because
both are git-ignored -- so the caches survive and only the source moves.

## The two numbers I got wrong, and how

Both are kept because each is a mistake anybody would make, and both were caught by looking rather than by
thinking.

**1. A 63-second "parallel build" that built nothing new.** The worktrees were checked out at HEAD and a
`pubspec.yaml` copied into them, which looked sufficient. It was not: **the source change being built was
uncommitted**, so all three trees compiled the previous code. Every target reported success, the artifact
timestamps looked plausible, and the only evidence was the modification time of a binary that had not moved.
`build_all.sh` now brings each worktree to the state of the working tree -- HEAD, then `git diff HEAD --binary`,
then the untracked files -- and the honest number went from 63 s to 192 s. **A build that reports success and
compiles the wrong source is the most expensive kind of fast.**

**2. "The build is not recompiling the Dart."** I checked `hollow_court.exe` and the Linux binary, saw both at
two hours old, and concluded the compiler was skipping. **The Dart output is not those files.** The executable is
the native runner, which only changes when C++ changes; the compiled Dart lives in `data/flutter_assets/`, which
was timestamped minutes earlier. The lesson is narrower than the first one and worth stating anyway: **know which
file your evidence is in before reading it.**

## What this does not fix

**The three AOT compilations are still three compilations.** The parallel build hides that by overlapping them; it
does not remove it. A single target still costs about two minutes, and a cold one costs more. That is the floor
for a Flutter release build with three platform toolchains, and everything below it would be caching compilers
that this project does not use.
