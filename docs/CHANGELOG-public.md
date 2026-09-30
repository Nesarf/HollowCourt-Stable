# Hollow Court — Public release notes

**This file is for people who use the application. The development history — who decided what, which tool enforces it, what
went wrong last time — lives in `docs/CHANGELOG.md`, which is an internal document.**

---

## 1.0.0.3939 — A fourth world, and a screen that reads

**2026-09-30**

### The text and the interface now have contrast

**If captions and warnings were hard to read before, that was a real fault and it is fixed.** The colours used for
warnings were measured against the surfaces they are actually drawn on and two of them were **just under** the
readability floor — 3.98:1 and 4.02:1 where 4.5:1 is the minimum. Both were raised, and the check that should have
caught them now covers them.

### A fourth theme: 永遠の歌姫

**Its accent is `#39C5BB` and its build number is `3939`, and the two say the same thing.** `39` reads ミク — three
is ミ, nine is ク — so the number written twice is the reading written twice, and the colour carries `39` in its
first two digits. The world is named for what the number says.

**It is the first theme with its own artwork.** Two pieces drawn from an original picture and redrawn as flat
vector, in one ink and no other, appear behind every screen while this theme is chosen: a tall one on a phone and
a wide one on a desktop, because a single picture cropped two ways would be the wrong drawing on one of them.

**And that artwork is not covered by this project's software licence.** It depicts 初音ミク, a character of Crypton
Future Media, INC., and is used under the Piapro Character Licence; 关于空庭 credits it, and `art/LICENSE` states
the terms. The source code is MIT and always was.

### Two settings that used to do nothing now work

**The text size** had been stored, drawn, and read by nothing since it was written — choosing a step changed a file
and left every letter the size it already was. It now multiplies your own system setting rather than replacing it,
so a reader who has already made their system fonts larger keeps that baseline.

**The second language** was being looked up by the *primary* line's register, so with 伊丽莎白 chosen as the
primary writing, English showed as `en (this build does not know it)` — for a language the build ships.

### Smaller, and worth knowing about

- **The shelf placement view is off the cellar page.** It is still in the application and one word brings it back.
- **Windows now has a `setup.exe`** as well as the `.msi`, for people who expect to double-click an installer.
- **The shopping list knows what you paid.** Each line shows the last price you recorded for that ingredient, with
  the volume it was for, and the list totals what it can.
- **Takings**, on the 记录 screen: what was spent over a day, a week, a month and a quarter, and how that compares
  with what you have counted in the till. It says plainly that the income side cannot be recorded yet — nothing in
  the record states that a drink was sold.
- **A note about the voice writing**: 伊丽莎白 and the minister now have their own wording in more of the
  interface, including the error messages.

### How to check which build you have

**Open About.** The binary prints the version it was built as and the commit it was built from.

**Its version is `1.0.0.3939`.** Android names the version twice: that is the displayed one, and the installer
compares an integer that differs per ABI so each can be upgraded on its own — Android's rule, not this project's.

---

## 1.0.0.3028 — Two settings that did nothing

**2026-09-30**

### The text size setting works now

**It had never done anything.** The four steps were stored and drawn in the settings page, and nothing read
them: choosing one wrote a file and left every string the size it already was. If you turned the text size up
in an earlier version and saw no difference, that was not you — it was the setting.

**It now multiplies your own system setting rather than replacing it.** If you have already made your
system's fonts larger, that stays your baseline and this steps up or down from it, so the middle option is
exactly what your platform asked for rather than a reset of it.

### A language this build ships no longer reads as one it does not

With the heiress register chosen as the primary writing, the second-language control drew `en (this build does not
know it)` — for English, which is in the build. The second language was being looked up by the *primary line's*
register, which it has nothing to do with.

### The shelf is off the cellar page

**The placement view — dragging bottles onto a shelf — is not drawn any more.** A shelf answers "where is the
vermouth", and it can only answer that if you can tell one bottle from another at a glance; every ingredient
still looks the same, so it could not. The code is still here and one word brings it back, but this build does
not show it. Everything else on the cellar page is where it was.

### And what this version does not claim

- The two marks are still two marks: a picture at 256 pixels and the letter at 16.
- The network layer, the tunnels and the peripherals are as they were.

### How to check which build you have

**Open About.** The binary prints the version it was built as and the commit it was built from.

**Its version is `1.0.0.3028`.** Android names the version twice: that is the displayed one, and the installer
compares an integer that differs per ABI so each can be upgraded on its own — Android's rule, not this project's.

---

## 1.0.0.2880 — The mark changes

**2026-09-30**

### The application has a new icon

**It is no longer the medallion.** The mark is now drawn from a picture of bar equipment — a pour-over, a cup, a
shaker, a moka pot, a bottle, a glass — flattened to solid colour blocks with the separators kept, and rendered at
fifteen sizes.

**Below 48 pixels the letter A takes its place**, and that is a measurement rather than a preference: at 48 the
picture is a field of blocks from which no object can be named, and at 32 and below it is mottled colour. The A is
the publisher's mark, drawn at each size it ships at rather than enlarged from one drawing, so it stays legible at
16 pixels — which the picture is not.

**Every size is drawn from a drawing whose blocks land on whole pixels.** Android asks for 48, 72, 96, 144 and 192
pixels, and three of those are not multiples of the size the picture was worked out at, so rendering them from one
drawing gave half-pixel cells and visible seams. There is now one drawing per size that needs one.

### What this version does not claim

- **The mark is a picture at 256 pixels and a letter at 16, and those are two different marks.** That is the
  arrangement, not a limitation to be removed later.
- Everything else in the list below about the first release still holds: the network layer is partial, tunnels are
  not usable, and the peripherals are waiting on their protocols.

### How to check which build you have

**Open About**, where the binary prints the version it was built as and the commit it was built from. 

---

## 1.0.0.2184 — First public release

**2026-09-28**

### What it is

**A drinks cellar that is actually yours.** Cross-platform, offline-first, with no account and no server.
It installs on Windows, Linux and Android.

### What is already there

| **Foundations** | The domain layer: units, ratios, match scoring — all tested |
| **Usable alone** | Event log, seed import, the stock and recipe screens, liquid colour |
| **Visually complete** | Shelf layout, the bar, prices and statistics — complete enough to mix a drink while using it |
| **On a LAN** | Pairing, star-shaped sync, log merging — a phone and a computer share one cellar |
| **Packaged** | An `.msi` for Windows, an `.AppImage` for Linux, and three `.apk` files for Android |

### Also in this version

- **Four themes** — each a world of its own rather than a recolouring
- **A voice axis** — the same language written in a different register, or in another one
- **Device discovery** — find the other machine on your network by name, the way Bluetooth does
- **`.courtpack`** — a line-delimited JSON bundle you can export a cellar to and check
- **Honest localisation** — the Traditional Chinese variants are generated, and the half a machine cannot do is stated

### What this version does not claim

**Said plainly, rather than left for you to find out.**

- **The network layer is partial.** Price comparison and barcode scanning are declarations in this build, off by design.
- **New devices pair by code.** A better way — both screens show six digits and you compare them — is not settled yet.
- **VPN tunnels are not usable yet.** A tunnel is settled as its own kind of link; the implementation is not written.
- **Bluetooth scales, IMUs and gamepads are not usable yet.** Each is waiting on its device's protocol.
- **Nothing coffee-related is done.**

### How it was verified

**Two jobs, both on GitHub's machines, both green:**

| **Four stages for the tooling** | Syntax, the tools' own tests, the art rules, art rendering |
| **The product** | Dependencies, static analysis, and all 116 test files run by directory and by file |

**That is the thing worth saying about this release.** Before it, the pipeline had never once run: it had been triggered
thirteen times and produced no jobs at all, and that only became visible on a machine that was not ours. Once it ran, it
found seven defects in a row, every one of them the kind that only a second machine can see.

**Which is this release's definition of done**: not "it works here", but *it can be shown to work on somebody else's machine*.

### The artifacts

**Each platform has its own two ways in**: an `.msi` for Windows, an `.AppImage` for Linux, and three `.apk` files for
Android, one per ABI. **Every artifact carries a record beside it** naming the commit it was built from, when it was built,
and its sha256 — so "is this file the one that was published" is a question you can answer yourself.

**This section no longer states a version for you to check**, because it described the 1.0.0.2184 release and the version
facts now live in the section of the release they belong to — every release below this one states its own.
