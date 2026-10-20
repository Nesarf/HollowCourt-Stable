# Testing: what the runner does and does not honour

Written on 2026-09-30 after two runs of the full suite took **ten minutes longer than they should have**, and
after the first attempt at preventing it turned out to be a fiction.

## The fault worth knowing about first

**A widget test that awaits something the test environment cannot complete does not fail -- it waits.** No
error, no progress, no output. `flutter test` reports `DID NOT COMPLETE` only at the end, ten minutes later.

Two ways it happened here, both in a single day:

| Shape | Why it never finishes |
| --- | --- |
| A platform channel | `openInBrowser` calls one; a widget test has no platform, so the future is never completed |
| Real file I/O in the test zone | An `AssetImage` or a file read: `testWidgets` runs in a `FakeAsync` zone that never advances real I/O |

**And a leftover scratch file is enough to cause it.** Two temporary probe files were left in `test/` during
2026-09-30 (one was never deleted because a tool call was interrupted), and **each added ten minutes to every
subsequent full run** -- 10m29s instead of 54s. The suite was never slow; it was blocked.

**So: a scratch test goes in `test/`, runs, and is deleted in the same command that runs it.** The pattern that
works is one shell line -- write it, run it, `rm` it -- because a file that survives a command survives until
somebody notices.

## What actually enforces a timeout

**Per-test annotations, and only those.**

```dart
testWidgets('...', (tester) async { ... }, timeout: const Timeout(Duration(seconds: 30)));
```

**`dart_test.yaml` does not work here, and this is measured rather than assumed.** A root `dart_test.yaml`
declaring `timeout: 5s` was written, and a test that never completes was run against it: it ran for **91
seconds** until an external `timeout` killed it, and reported `did not complete`. `flutter test` does not read
that file's timeout setting. The file was deleted rather than left in place, because **a configuration that
looks like a guard and is not one is worse than no configuration** -- somebody would rely on it.

## What the suite costs, measured

| Command | Time |
| --- | --- |
| `flutter test` (whole suite, 1148 tests) | **~54 s** |
| `flutter analyze` | ~5 s |
| One test file | ~5 s |
| `flutter test` with one stuck scratch file | 10 min 29 s |

**So a full run is cheap and a hang is not.** Which is why the note above matters more than the numbers.

## Render probes

Several checks in this repository's history render a widget and write a PNG to look at it -- the convention
`art/render_icons.sh` and the icon work established: *do not say a picture is finished without looking at the
picture*. Two things about doing that in a test:

1. **Precache on the real clock.** `await tester.runAsync(() => precacheImage(...))` before pumping the frame,
   or the asset is still resolving when the image is captured and the render comes out with the shape missing --
   which reads exactly like "the feature is not wired up".
2. **Give it a timeout**, per the section above, so a mistake costs thirty seconds.

`test/ui/world_artwork_test.dart` is the worked example: it loads both rasters through `runAsync`, asserts which
shape a given window asks for, and asserts that the three worlds without a picture draw none.
