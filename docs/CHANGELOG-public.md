# Hollow Court — Public release notes

**This file is for people who use the application. The development history — who decided what, which tool enforces it, what
went wrong last time — lives in `docs/CHANGELOG.md`, which is an internal document.**

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

**And the difference between this release and the previous set is visible in the application itself**: open About, where the
binary prints the commit it was built from. **Its version is `1.0.0.2880`.**

**Android names the version twice**: the displayed one is `1.0.0.2880`, and the installer compares an integer that differs
per ABI so each can be upgraded on its own. That is Android's rule, not this project's.
