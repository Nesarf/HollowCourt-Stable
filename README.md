# Hollow Court

A beverage cellar you actually own. Cross-platform, offline-first, and
installable on Windows, Linux and Android.

The design lives in [`docs/DESIGN.md`](docs/DESIGN.md), which is the authority
on what this is meant to be. Everything below is about building it.

## What is built so far

**P2 is finished: four screens, and the cellar is usable.** This section used to say that
nothing faced a person yet, which was true at P1 and stopped being true some time before anyone
edited this paragraph -- the same staleness the design document's roadmap had, corrected the
same way.

| | State |
| --- | --- |
| Three-platform project skeleton | done -- Windows, Linux and Android generated together |
| Domain layer: units, dosing, matching, pricing, consumption, statistics, sync | done, and pure |
| Event log: hybrid clock, append-only store, stock ledger, overlay | done |
| Stock, Recipes, Bar and Cellar screens, liquid rendering | done |
| Shelf placement, consumption curve, statistics, settings, shopping list | done |
| Pairing and sync | done end to end and tested over loopback sockets; mDNS, the QR camera and the screen that starts it are not built |
| Packaging | Android APK **used on a real device** (that run was an earlier build; the artifact has since been rebuilt from HEAD); Windows MSI **built, not installable on this machine** (its own fault, not the package's -- see below); Linux AppImage **built and run** under WSLg, never on a real Linux desktop |
| Network adapters (DeepSeek, prices, barcode) | not started, and off by default by design |

**767 tests, of which 603 are the domain and data layers on the plain Dart VM**, and the analyzer reports
nothing. Those two counts are quoted separately because they are the ones that prove the layering: neither
lib/domain nor lib/data imports Flutter, and those tests would not compile if one of them started
to. The 767 includes the widget tests, which do.

See `docs/DESIGN.md` section 14 for the roadmap with a State column, and `packaging/README.md` for
what each target is and is not -- including which of the three has actually been installed and run,
because *built* and *works* are different words and only one of them is answered by a build script.

## Language and encoding

**Everything except the copy a person reads on screen is English, and ASCII.**

That covers identifiers, comments, commit messages, test names, log lines,
event types, payload keys, configuration keys, file names, and these documents.
The user-facing layer -- labels, headings, empty states, error copy shown to a
person -- is the one place a translation belongs, and the only place this rule
does not reach.

The reason is not tidiness. Non-ASCII text keeps breaking things in ways that
are hard to see:

- A Windows console at code page 936 renders a micro sign as mojibake, and a
  script that prints to one appears to work while producing garbage. That has
  already happened on this machine, in a log file, more than once.
- Two tools that disagree about an encoding corrupt a file silently instead of
  refusing it.
- Diffs, searches and `grep` behave differently around non-ASCII, and a rename
  is easier to miss when part of the identifier is wide characters.

So `Volume.toString()` says `ul`, not the micro sign. The display layer may
render a volume however it likes -- it owns that decision. A diagnostic string
does not, because it does not choose where it ends up.

### The other half: the display layer uses real UTF-8

The rule above is about everything a person never reads. The layer a person
*does* read points the opposite way, and it is not one translation -- it is a
**localization configuration**, with locale variants that differ in vocabulary
and not only in glyphs. It therefore carries real UTF-8: the actual micro sign,
the actual Chinese, the actual accents. ASCII-fying display copy to keep the
rule tidy would be destroying the product to satisfy the rule.

The two halves meet at one question, worth asking explicitly every time a
string is added: **who reads this, and where does it end up?**

| | Encoding | Language |
| --- | --- | --- |
| Identifiers, keys, event types, log lines, diagnostics, these documents | ASCII only | English |
| Labels, headings, empty states, error copy, units as drawn on screen | Real UTF-8 | The reader's locale |

Same value, two audiences, two encodings. Nothing is implemented yet; the
locale set and the mechanism are planned in section 12.4 of the design
document.

## Building

Requires Flutter 3.47 or newer. The domain layer needs nothing else; it runs on
the plain Dart VM.

```bash
flutter pub get
dart test test/domain      # the domain layer, alone, on the plain Dart VM
flutter test               # everything, including the widget tests
```

### The three targets

```bash
flutter build windows      # build\windows\x64\runner\Release
flutter build apk          # build\app\outputs\flutter-apk
flutter build linux        # build/linux/x64/release/bundle  -- on Linux only
```

`flutter build linux` is host-only: Flutter desktop builds cannot be
cross-compiled, so the Linux artifact has to be produced on a Linux machine. On
a Windows development machine the shortest route is WSL, where the
distribution's disk image can be kept on whichever drive the project lives on.

```bash
wsl -d Nyarch -e bash tool/build_linux.sh
```

The Linux host needs `clang cmake ninja-build pkg-config libgtk-3-dev`, which
is the whole of the extra toolchain it asks for.

### Building the same tree from two operating systems

Flutter keeps **absolute paths** in `.dart_tool/package_config.json`, pointing at
the Flutter SDK and the pub cache. That directory lives in the project tree, so
the Windows copy and the WSL copy share it, and a `pub get` on either side
rewrites it for the other.

The failure this produces is worth recognising, because it looks like broken
source rather than a broken environment:

```
lib/main.dart(86,16): error GE5CFE876: The method 'Text' isn't defined for the
type '_MyHomePageState'.
```

That is one of hundreds of errors about Material widgets being undefined, in a
file whose first line is `import 'package:flutter/material.dart';`. Nothing is
wrong with the file. The compiler is looking for the Flutter SDK at a path that
belongs to the other operating system, and the build takes ten minutes instead
of one while it fails.

**So every build starts with `flutter pub get` on the platform doing the
building.** `tool/build_linux.sh` does it for the Linux side; do it by hand
before `flutter build windows` or `flutter build apk` if you have just built on
Linux.

### Windows: Developer Mode

A Flutter project that uses any plugin builds Windows plugins through symbolic
links, and creating one on Windows needs either elevation per process or
Developer Mode. Without it the build stops with:

```
Building with plugins requires symlink support.
```

A directory junction is not accepted -- the check is a capability test up
front, not an attempt per link -- so Developer Mode is the way:

```
Settings > System > For developers > Developer Mode
```

This is a property of Flutter on Windows rather than of this project, and it
applies to the Android build too when that is driven from this machine.

## The domain layer

`lib/domain/` may not import Flutter. Section 3 states that as a rule, and the
test suite enforces it rather than trusting anybody to remember: the domain
tests are written against `package:test` and run with `dart test`, so a domain
file that reached for Flutter would stop the suite from running at all. They are
written against `package:test` rather than `flutter_test` for exactly that
reason.

### Which runner, which tests

There are two runners and they cover different halves, so the suite is run with
an explicit scope:

```bash
dart test test/domain test/data   # the domain and the data layer
flutter test                      # anything that needs the Flutter framework
```

**`dart test` on the whole tree does not work, and the failure is misleading.**
It compiles `test/widget_test.dart`, which pulls in `package:flutter`, and then
fails inside Flutter's *own* source rather than in anything this repository
wrote:

```
Error: The type '_LineCaretMetrics' is not exhaustively matched by the switch
cases ... text_painter.dart:1462
```

That is the standalone Dart SDK being asked to compile a Flutter framework
pinned to a patched one. It is not a broken checkout and not a broken test --
`flutter test` on the same file passes. Scoping the run is the fix; chasing the
error is not.

Nothing in it uses floating point for arithmetic. A recipe is a ratio, and
`Rational` carries that ratio exactly from the recipe to the glass, rounding
once, when an amount becomes a whole number of microlitres.

## The event log

Section 6 asks for inventory to be recorded as **operations rather than state**:
if two devices each pour a drink while apart, the answer is the sum of both
pours, and last-write-wins would silently lose one of them. Section 2 then
points out what that buys -- the storage format *is* the sync format, so there
is no diff layer to write and no migration to plan.

That is what `lib/domain/events/` and `lib/data/` implement.

| File | What it does |
| --- | --- |
| `lib/domain/events/hlc.dart` | A hybrid logical clock. Physical time first, then a counter, then the node id. |
| `lib/domain/events/event.dart` | One log entry: a clock reading, a type, a payload. |
| `lib/domain/events/stock.dart` | The stock operations, and the fold from them to what is on the shelf. |
| `lib/data/event_store.dart` | The file: one JSON object per line, appended, never rewritten. |
| `lib/data/event_log.dart` | The seam the app talks to -- file, clock and folded state kept in agreement. |

Three decisions in there are worth knowing before changing anything:

**The clock is not the wall clock, and the wall clock is not trusted.** Two
phones whose clocks disagree by half a minute would produce a last-write-wins
verdict that is simply wrong. The clock reading also *is* the event's identity,
which is why nothing else has to be minted to name one.

**A half-written last line is expected, not corruption.** A process that dies
mid-append leaves a partial line; the reader classifies it as a torn tail and
the next append trims back to the last complete line before writing. A complete
line that cannot be read is a different thing entirely and is reported as
corruption. Conflating the two would mean either crying wolf on every crash or
quietly swallowing real damage.

**Unknown event types are carried, not dropped.** Two builds will meet during a
sync, and the older one must be able to hold the newer one's events without
understanding them. An op-log that discards what it cannot parse loses
operations every time it is used to sync.

The tests state the section 6 case directly: two devices, one bottle, a pour
each while apart, then a merge -- and both must arrive at the same cellar.

## The seed

The app's drink library is built, not committed:

```bash
dart run tools/build_seed.dart          # writes data/seed/seed.json
dart run tools/build_seed.dart --pretty # the same, indented for reading
dart run tools/seed_report.dart         # what the build could not resolve
```

**A fresh clone has no seed, and that is deliberate.** The library is derived
from two harvested sources, and section 15 keeps them out of git because the
recipes and ingredient entries belong to their authors -- so `/data/seed/` is
ignored for the same reason `/data/sources/` is. The code that produces the
artifact goes in git; the artifact does not. It is 547 kB: 164 ingredients, 502
recipes, 2238 items.

That is also why the seed tests **skip** rather than fail when the data is
absent. `dart test test/domain test/data` passes on a fresh clone and passes
with more tests once the artifact exists.

`tools/seed_report.dart` is the one to run when a number looks wrong. It prints
what each source contributed, what the alias table merged, what the assembly
could not resolve, and which recipes `validate()` rejects -- and the last group
is three recipes with a defect in the *source* rather than in this code, so it
is a list to read rather than a bug to fix.

### Where the seed comes from, and what that costs

`data/sources/` holds two harvests: another source's IBA recipes as prose and one source's
export as columns. They disagree about almost everything -- another source writes
`2 oz of rye whiskey` and no ice, one source writes a measure and a unit and no
flavour list -- and `lib/data/seed/` is the pipeline that reconciles them:
import, alias, merge, assemble.

**The compliance gate is real and it is before release.** The seed this produces
is *working reference*, not shippable content: section 15 requires the shipped
library to be written independently or replaced with openly licensed sources.
The pipeline exists so that swap is a matter of changing the input rather than
rewriting the layer.



| File | What it is |
| --- | --- |
| [`docs/DESIGN.md`](docs/DESIGN.md) | The blueprint. Normative. |
| [`docs/architecture.html`](docs/architecture.html) | The layering, as a diagram. |
| `art/` | Cup geometry, as SVG and rendered. |
| `audio/` | Generated effects and the audio project. |
| `tools/` | Scripts used while working things out. |
