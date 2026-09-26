# Packaging, and what each target is for

Section 14's P4 asks for an installable build on three platforms, **and the three are named here because the
phrase appears a dozen times below without ever saying which ones**: **Windows** (an `.msi`, built by
`packaging/windows/build.sh`), **Linux** (an `.AppImage`, built by `packaging/linux/build_appimage.sh`) and
**Android** (three `.apk` files, one per ABI, built by `packaging/android/build.sh`). No fourth target is
implied anywhere; where this file says "all three" it means those three, and where it says a platform has not
been verified it means one of them has not.

| Target | Artifact | State |
| --- | --- | --- |
| **Android** | `hollow-court-<version>-arm64-v8a.apk` / `-armeabi-v7a.apk` / `-x86_64.apk`, where <version> is the **APK's own `versionName`** | **1.0.0.1014 built, installed, running and used** on `a physical device`: `versionCode=3014`（monotonic from 2523）, `versionName=1.0.0.1014`, signed by the new **S.M.Y.T.** identity (`CN=Hollow Court, OU=S.M.Y.T., O=S.M.Y.T.`, SHA-256 `64cca05a...a16d`). The previous copy had to be uninstalled once, because a different signer cannot update in place. A bottle was recorded by hand on the release build and photographed: `packaging/android/apk-1.0.0.1014-used-gin-700ml.png` |
| **Windows** | `hollow-court-<msi version>.msi` | **1.0.527 built, installed over 1.0.0.526 with `exit=0`, running, and reading the whole library** -- `hollow_court.exe` reports `1.0.0+527`; the cellar renders (在架 · 2, the two bottles the sync tests left) and the recipes screen reads **共 103 条** across **New Era 35 / The Unforgettables 33 / Contemporary Classics 35**, photographed at `packaging/windows/msi-1.0.527-recipes-103.png`. Those three counts are what the fifteen added IBA drinks produce, so the shipped MSI is carrying the finished library. See the notes below about the build that failed first, and about input |
| **Linux** | `hollow-court-<version>-x86_64.AppImage` | **1.0.0.527 built from HEAD (`head: c5f1a18`, receipt in the bundle), running, and photographed** -- `packaging/linux/appimage-ui-wslg-x11-1356x817-1.0.0.527.png` shows the Cellar tab, both bottles, the five-tab bar and 记一瓶. The four traps between "running" and "photographed" are in the note below |

This table and the acceptance table below it say the same three things on purpose. When they
disagreed by one round, the top table still read "never run" while the lower one recorded a
successful run -- so if you change one, change both.

Artifacts land in the bundle directory (`OUT_DIR`), and `MANIFEST.txt` there says which source each one
came from. All four rows currently read `ok`.

**Two versions now sit side by side in that bundle, and that is the new arrangement rather than a
leftover.** Until 1.0.0.514 the file name came from `pubspec`'s `build-name`, which cannot hold the
four-part version the owner names a round by -- so every round produced the same
`hollow-court-1.0.0-*.apk` names and each build script overwrote or deleted its predecessor, leaving
nothing to roll back to. Names now come from what the artifact itself reports: the APK's own
`versionName`, the AppImage's four-part version, the MSI's three-field product version. `1.0.0`,
`1.0.0.514` and `1.0.514` coexist, and the older set is the rollback.

### Connection test ①: wireless + the share code, and the firewall was the whole story

**Run 2026-09-23 on the laptop and `a physical device`, and it works.** The short code
`GAXAR34LUYWPCVD9` was shown on the laptop, typed into the phone, and the merge completed. Two
independent records agree, and neither is a screenshot:

* the phone's attempt that failed first reported `could not reach 192.168.31.157:10838 -- SocketException:
  Connection timed out (errno = 110)`, which is the network and not the format -- **the compact code had
  been parsed correctly**, host and port out of ten base32 characters;
* the laptop's `sync-identity.json` went from **68 to 178 bytes at 14:35**, i.e. its `trusted` array
  gained a device, and `_remember` is the only thing that ever writes it.

**The advice on how to unblock it was wrong twice before it was right**, which is the part worth keeping:

| what was tried | why it did nothing |
| --- | --- |
| `-Profile Private` | this WLAN is classified **Public**, so the rule never applied |
| relying on the existing `Hollow Court sync probe` rule | it is scoped to the **probe's** program, so it never covered `hollow_court.exe` |
| **`-Program <hollow_court.exe> -Profile Any -Direction Inbound -Protocol TCP`** | works, and it is narrower than opening the port: the listener's port is **dynamic** (10838 this time), so a port rule would have to be redone every session |

**And this session's PowerShell is elevated**, which is how the rule was added from the agent side at
all. Worth remembering before asking anybody to elevate a shell by hand.

**One question this leaves open**, recorded as a question rather than a finding: the laptop's cellar
reads **1400 ml** where the phone has **700** -- exactly twice. Either the same bottle was applied twice
or there were two of them, and the application already has the row that answers it: Settings -> Check
integrity -> 「同一瓶子被记了两次」.

### Connection test ②: a tap asks first, and the host says what its own door looks like

**Run 2026-09-23 against 1.0.516** on the laptop and `a physical device`, which is what §10.3.2 asked for. Two
things were built and both were photographed on the real machines, because both are things a reader sees:

| what | where the photograph is | what it shows |
| --- | --- | --- |
| the confirmation a tap goes through | `packaging/android/tap-1.0.0.516-connect-box.png` | 连这台设备？with **NesarFDX**, **192.168.31.157:13992**, the fingerprint grouped in fours (**2B99-RU9F-5B5V-XGDX**), **陌生——这台机器没见过它**, and the note that both screens will be compared |
| this device is reachable, and on which port | `packaging/android/tap-1.0.0.516-listen-port.png` and `packaging/windows/sync-1.0.516-nearby-and-listen-port.png` | 附近的设备现在可以点到这台机器 **:32823** (phone) — the same number the laptop's nearby list had just read out of the announcement |
| the nearby list, with the port the announcement carries | `packaging/windows/sync-1.0.516-nearby-first-seen.png` | Android 设备 · **192.168.31.240:32823** · 977T-G · 新设备 |
| the host's one-sentence verdict, covered | `packaging/windows/firewall-1.0.516-covered.png` | 一句话结论：这台机器现在能被局域网里的设备连上 + 程序 `E:\Hollow Court Win\hollow_court.exe` + 网络类别 **Public** + 覆盖这个程序的入站规则 `Hollow Court app (inbound TCP)` |
| the same verdict, not covered, with the command to copy | `packaging/windows/firewall-1.0.516-no-rule.png` | 一句话结论：入站被防火墙挡住了——没有一条入站规则覆盖这个程序, then the program path, Public, 「（没有）」, and `netsh advfirewall firewall add rule name="Hollow Court LAN sync" dir=in action=allow program="…" enable=yes profile=any protocol=TCP` |

**The uncovered row was produced honestly rather than by breaking something.** The installed build already has a
rule, so the second photograph is of an *unruled copy* of the same build (a directory copy run from elsewhere);
nothing was added to or removed from the firewall for this round, and the row read-only behaviour that makes that
possible is itself the feature.

**And the finding that turned out to be the precondition for ①: the announced port had no socket behind it.**
`discovery_providers.dart` announced the constant `defaultDiscoveryPort + 1` (48125) while the sync listener has
always been ephemeral (10838 on the day ① was run). A tap could therefore never have connected, box or no box.
The announcement now carries the port of a listener the screen actually holds — which is why the two photographs
above show **32823** on both sides — and a device with no listener announces nothing at all.

**Three defects were reported from the phone while this round was running**, and all three are recorded here
because a feature that was written and verified in a test can still be broken in the hand:

| reported | what it actually was | the fix |
| --- | --- | --- |
| 无法点击「一致」 | agreeing *worked* and showed nothing: the screen kept drawing the same digits because the exchange waits for the **other** device's person as well | agreeing moves the screen off the question into the working state (`answerComparison`); refusing needs no new state, the exchange ends at once |
| the device was not remembered | two causes: the "already in sync" outcome carried no `peerIdentity` (and `_remember` keys off it), and the device that *accepted* a connection did not know the peer's address, so 再同步一次 had nothing to dial | the identity is on every successful outcome including the idle one, and `ExchangeOutcome.peerAddress` comes off the accepted socket, read before the exchange closes it |
| — (found by the same run) | a tap-able listener answered **once**: `ServerSocket` is a single-subscription stream, so the second `acceptForSync` threw `Bad state: Stream was already listened to` and the device stopped accepting anybody | the service owns the one subscription and queues arrived sockets; `runAccepted` runs the exchange over each |
| the list said 新设备 about a device it had met (found on this round's screen, from the label) | a fingerprint has **two spellings** -- the announcement carries the grouped one a person reads, the store keeps the digest -- and comparing them directly never matched. Three faces: the label, the tap taking the *stranger* path, and the box saying 陌生. Two display bugs came with it: the box regrouped an already-grouped string (`2B99 -RU9 F-5B 5V-X GDX`), and the row's short form was five characters and a hyphen | one comparison spelling (`DeviceIdentity.fingerprintKey`) used by the roster, the tap and the box; `grouped` and the row's short form normalise first. 1.0.0.519 |

**The comparison was then run for real against a second process, and the receipt is in this directory.**
`tool/sync_probe.dart` gained a `beacon` verb: it announces itself, holds a listener, prints the six digits it
derives, and agrees only when told to -- the second screen §10.3.2 describes, as a process on the laptop rather
than a second handset.

| what | where |
| --- | --- |
| the nearby list, with the port the announcement carried | `windows/nearby-1.0.518-real-port.png` -- probe-laptop · 192.168.31.157:**11903** |
| the box, for a device this machine has never met | `windows/connect-box-1.0.518-probe-peer.png` |
| the digits on the application's screen | `windows/compare-1.0.518-six-digits.png` -- **117 106** |
| the peer's own stdout, at the same moment | `windows/probe-peer-1.0.518.log` -- `COMPARE : 117 106` |
| the result | `windows/synced-1.0.518-zero-five.png` -- 同步完成 · 收到/送出 **0 / 5** · 对方 probe-laptop |
| and the peer remembered, address included | `windows/remembered-1.0.518-with-address.png` -- probe-laptop · **192.168.31.157:11903** |

One side agreed first and **nothing moved** until the other did: the log shows `waiting 30 s before agreeing`, the
application's screen kept asking, and only after 一致 was pressed on the application did the beacon report
`outcome : merged=5 sent=0` and `cellar now : 5 events, 2 bottles`. That is the requirement -- both screens, both
people -- observed rather than asserted.

**Both paths were then re-run on 1.0.0.519**, because the fingerprint fix could have failed in the other
direction -- recognising *too much*, so that a stranger is treated as a known device and no digits are ever
compared. A peer the application had never met: listed as 新设备 with the unknown icon
(`windows/nearby-1.0.519-stranger-label.png`), its box saying 陌生 and 两台设备各显示六位数字
(`windows/connect-box-1.0.519-stranger.png`), **968 852** on the application's screen
(`windows/compare-1.0.519-968-852.png`) and `COMPARE : 968 852` in the peer's stdout
(`windows/probe-peer-1.0.519-stranger.log`), then both agreed and `merged=5`. Two devices this machine had met --
the new one included -- are then listed **with their own addresses**
(`windows/remembered-1.0.519-both-with-addresses.png`), which is the positive form of the report that a device was
not remembered.

**And the remembered path, which needs no digits at all.** With the same beacon at the address the application had
stored (`--port 11903`), 附近的设备 now labels it with a gold shield and no 新设备
(`windows/nearby-1.0.519-remembered-label.png`), the box says **已记住——上次见面学过它的密钥** with
**直接用上次学到的密钥同步，不用再对数字** (`windows/connect-box-1.0.519-remembered.png`), and the peer's own
stdout records `outcome : merged=0 sent=0` with **no `COMPARE` line**
(`windows/probe-peer-1.0.519-remembered.log`). The remembered rule -- a device whose key was learned is not asked
to compare -- observed rather than argued.

**What that is not.** It is not a second *phone*: the application's own side was driven, and the other end was the
project's protocol in a second process on the same machine. The phone half of this round is its box and its
listening-port row (`android/tap-1.0.0.516-*`); the handset had left adb by the time the comparison ran. And two
processes on **one** machine hear each other only intermittently, because Windows delivers a datagram on a
twice-bound UDP port to a single socket -- which is why the remembered path was exercised by dialling the stored
address rather than by discovery.

**One thing on that row is covered by a test rather than by a photograph**: the 复制放行命令 button. The command's
*display* is photographed on a real screen, and the button's behaviour -- that what reaches the clipboard is that
exact string -- is asserted in `test/ui/firewall_row_test.dart` against a mocked platform channel. Pressing it on a
real screen was not driven: it sits below the check button on the same row, and that region of the page refused
synthetic clicks in this session in the way the navigation bar never did. Recorded as a gap with its reason.

**Why the second end was a process and not the handset**, since that is the difference between this and a
two-phone receipt: this host would not drive the last step on the phone. `adb shell input tap` on a row was
intermittently delivered as a scroll (a tab-bar tap lands correctly, so it is the app's scrollable winning the
gesture race against synthetic input), and the handset left adb before the comparison could be finished. The
phone's own half of the round is still photographed — its box and its listening-port row — and
`test/p3_acceptance_test.dart` drives two screens through the real `runExchange` with both gates, so the code path
has three kinds of evidence and only one of them is a second handset.

**One process can silently starve discovery, and it cost a round of this session.** `flutter test` leaves
`flutter_tester` running with UDP 48124 still bound (two of them did), and on Windows a UDP port bound twice
delivers each datagram to **one** socket only — so the application announced, listened, and heard nothing, with no
error anywhere. `netstat -ano -p udp | findstr 48124` is the command that showed it. It is the same platform fact
`data/sync/discovery_socket.dart` already records for two instances of the application, arriving this time from
the test suite.

### A stale build was opened by hand, and was read as a build that had lost features

**2026-09-23.** The owner opened a copy of the application that predated the LAN sync work, found no
local-network or USB section on 记录, and reasonably reported the Windows build as missing them. The
current build has both, and the check that settled it was on the artifacts rather than on the screen:
eight named feature strings, including two added that same afternoon, are present in **both** the
installed `data/app.so` and the APK's `libapp.so`.

**Why this belongs next to the other staleness entries.** This repository has now been bitten by a
stale artifact four times: a stale icon render, a stale Linux binary, an APK from the previous round
left in the bundle beside a new one, and a build file that installed "successfully" without replacing
anything. This is the first time the stale copy was opened *by a person* rather than shipped, and the
symptom was reported as a product defect.

**And the answer was already built in that afternoon.** 关于空庭 shows **version and built-from
commit**, and until that day it showed a hardcoded default that no script supplied -- so the row that
exists to answer "which build is this" answered `1.0.0+1` for every build ever made. A reader with two
copies on one machine now has a way to tell them apart, which is worth more than the fix itself:
`1.0.0.515 / 69a74e251` is the current one, and anything else is not.

**What to check first next time somebody reports a missing feature**: the version and commit on the
About screen of the copy in front of them, before anything is compared with the tree.

## The build shipped 88 drinks while the library held 103 (found 2026-09-23)

The stable-release acceptance pass is what found this, and it is the kind of defect only running the artifact
finds. `data/drinks/library.json` is where the library is authored, edited and cross-checked -- every guard in
`test/data/seed/` reads it from there. **The application cannot read `data/`**: it loads
`assets/drinks/library.json`, a second copy. The two were kept in step by hand, and after fifteen drinks were
added they were fifteen drinks apart.

Nothing failed, and that is the point: the tests read one file, the app read the other, and the recipes screen
said **共 88 条** on a build whose library had 103. The APK built in the same round carried the same stale copy.

Two mechanisms now, of different kinds:

* `packaging/sync_assets.sh` -- the **action**: copies `data/drinks/library.json` and `data/names/names.json`
  into `assets/`. It is called by `packaging/windows/build.sh`, `packaging/android/build.sh` and
  `tool/build_linux.sh`, so a build cannot ship a stale copy.
* `test/data/seed/shipped_assets_match_the_data_test.dart` -- the **guard**: it fails the suite the moment the
  copies differ, and its message names both counts and the command to fix it
  (*"103 drinks authored, 88 shipped. Run: bash packaging/sync_assets.sh"*). The guard was checked by making
  the asset stale on purpose: it fails, and it says why.

## The stable-release acceptance pass, 2026-09-23 (1.0.0.525)

Run across the three platforms. What it produced, in the order it was found:

**Windows — installed, started, and used, and it caught a release-blocking defect.** Covered above: the build
shipped 88 drinks while the library held 103. With that fixed, 1.0.0.525 installs (`exit=0`), starts, and the
recipes screen reads **共 103 条**; the cellar screen shows the two bottles the sync tests left there.

**Linux — built from HEAD for the first time in several rounds, and the build itself was broken twice.** Both
faults were in the tooling rather than the application, and neither could be seen from Windows:

  * every shell script in the repository was **CRLF**, so bash inside WSL read `set -euo pipefail
` and exited
    (`invalid option name`). Fixed by `*.sh text eol=lf` plus a conversion in place;
  * `pubspec.yaml` was CRLF, so all four build scripts carried a carriage return into the version string and
    flutter read `--dart-define=APP_VERSION=1.0.0.525
` as a **positional target**
    (`Target file "..." not found`). Fixed by `| tr -d '
'` at every extraction, and by pinning pubspec to LF.

After those, `tool/build_linux.sh` + `build_appimage.sh` both succeed and
`hollow-court-1.0.0.525-x86_64.AppImage` is written to the bundle. **It starts under WSLg** -- the process stays
alive and Impeller initialises -- but **this round did not capture it**: the app renders through Wayland, so it
does not appear in the X window tree (`xwininfo -root -children` lists only Weston's own windows), and the
`import -window <id>` recipe this file recorded earlier therefore no longer applies as written. The Linux UI
photograph in this directory is from 1.0.0. Fixing that recipe is the next Linux step, not a claim about the
artifact: what is verified is *built and started*, not *photographed*.

**Android — built, not installed.** All three APKs are built and receipted for 1.0.0.525, but the handset was
disconnected for the whole pass (`adb devices` empty), so the install → run → use column is unchanged from
1.0.0.523, which is installed and was used on the device earlier in this session.

## What stable covers, and the three modes it does not claim (2026-09-23)

`SyncLink` is four modes -- wired, wireless, usb, tunnel -- and only one of them has been driven on real
hardware. That is stated here so a reader does not have to find out:

| Mode | Claim for stable | Why |
| --- | --- | --- |
| wireless | **verified on real hardware** | two physical devices have shared a cellar: 2026-09-22, and again on 2026-09-23 (phone ↔ laptop, both screens reporting 同步完成) |
| wired | selectable, logic tested, **not hardware-verified** | this machine has one network. The mode's promise is *which* interface is used -- that promise is what has not been exercised, not the transport underneath it |
| usb | selectable, carrier tested, **not hardware-verified** | `adb_carrier.dart` runs `adb forward` and nothing else; its command line is asserted in `test/data/sync/adb_carrier_test.dart` through an injected runner, because a test cannot have a phone plugged into it |
| tunnel | selectable, logic tested, **not hardware-verified** | there is no tunnel on this machine. Its one behavioural difference -- a broadcast does not cross it, so the pairing code or a remembered key is the way in -- is the same tested path the wireless mode uses |

**`.courtpack` is not in that list because it needs no second machine.** It carries a cellar in a file, it is
wired into the device section, and its round trip has a test (`test/data/sync/courtpack_service_test.dart`).

## What each artifact has actually been through

Building is not the same as working, and this table is the difference. It is the honest version of
"installable and usable on three platforms".

| Artifact | Built | Installed | Run | Used for real work |
| --- | --- | --- | --- | --- |
| APK | yes -- **1.0.0.1014**, and 1.0.0.527/523/514 before it | **yes** -- installed after a one-time uninstall (new signing identity) | **yes** -- launched, empty cellar, five tabs | **yes** -- a bottle recorded on the device and photographed |
| MSI | yes -- **1.0.527**, and 1.0.0.526/525/514 before it | **yes** -- 1.0.527 installed over 1.0.0.526, `exit=0`, `FileVersion` reports `1.0.0+527` | **yes** -- running; the cellar renders, and the recipes screen reads 共 103 条 with the three category counts | **read** -- two screens of the installed build, one of them the whole library. A *write* on Windows is still unverified: see the input note below |
| AppImage | yes -- **1.0.0.527** (`head: c5f1a18`), and 1.0.0.525/514 before it | n/a, it is the executable | **yes** -- 1.0.0.527 under WSLg, software rendering, alive past 40 s, and the window photographed | **read** -- the photograph is the Cellar screen rendering that installation's own two bottles; a *write* on Linux is unverified |

### Windows screenshots in this repository are missing the bottom bar, and that is the capture method

`packaging/windows/*.png` are taken with `PrintWindow`, and on a Flutter window `PrintWindow` returns only the
region the application has painted through its own surface. The **navigation bar and anything in the last
hundred pixels are simply absent** from every one of them -- which reads, if you do not know, as a Windows
build that has no navigation bar. It does: a screen capture of the same window shows all five tabs, the 记一瓶
button at the top right, and the ornament behind them.

The two methods disagree in opposite directions, which is worth having written down:

| Method | What it gives |
| --- | --- |
| `PrintWindow` (what `drive.ps1`/`shot.ps1` use) | the window's own surface, cropped to what it painted -- reliable for text and layout at the top of a page, blind to the bottom |
| `CopyFromScreen` (a desktop capture) | everything the screen shows, including the navigation bar -- and also whatever window happens to be in front |

So the Windows photographs in this directory are not wrong, they are **partial**, and a claim about the bottom
of the window should not be made from one.

### Driving the Windows build: the mouse works on the navigation and not on the button, the keyboard works

Trying to *use* the installed build rather than look at it -- pressing 记一瓶 and filling the sheet -- turned
into a study of synthetic input, and the findings are worth having because the next attempt starts here:

| Input | What it did |
| --- | --- |
| `mouse_event` at the navigation bar | **works**: the tab changes, and a vertical sweep found the bar at logical y = 500 rather than the 444 the arithmetic suggested |
| `mouse_event` on 记一瓶 | **does nothing**, at six positions covering the button's drawn area (x 812-852, y 46-56) |
| `SendKeys` Tab / Enter | **works**: focus moves and activates -- one Tab then Enter reached the Recipes tab |
| `SendKeys` Escape | did nothing visible |

**And the button does not leave a modal behind.** The first guess was that it *had* opened its sheet off-screen
and the barrier was swallowing later clicks -- so the check was run in the right order: click the button, then
try the navigation. **The navigation still worked**, which rules the modal out and left two possibilities: the
hit area is not where the button is drawn, or it does not take synthetic input.

**Resolved the next round, and it is the second one -- so there is no defect here.** The repository's own test
taps this button: `test/ui/translated_names_test.dart` does `tester.tap(find.text(Copy.stockAddBottle.primary.text))`
and then types into the sheet that opens, and the suite is green. The button works; what does not reach it is a
synthetic `mouse_event` from outside the process. That is worth separating clearly, because "the primary action
does not respond" is a release blocker and "my input harness cannot press this particular widget" is not.

**Repeated clicks do not help either**, and the check is worth recording because it produced a false
positive: three clicks in a row on the button *did* change the captured frame -- and the change was the
**navigation indicator** moving, not a sheet opening. The page was still the Cellar. A hash comparison that
does not also look at the picture is a check that can be satisfied by the wrong thing.

**The keyboard is therefore the route**, and it also produced this round's most useful picture: one Tab and
Enter reached the recipes screen, which reads **共 103 条** with **35 / 33 / 35** across the three categories --
exactly the distribution the fifteen added IBA drinks produce. That is the shipped MSI carrying the finished
library, photographed.

### `packaging/windows/touch.ps1`, rescued from a temporary directory (2026-09-24)

Found while looking for a way to press a button that synthetic mouse input would not press: a previous session
had already written **injected-touch input for a Flutter window**, and left it in `E:\DaShaoHuo\cache	mp\`,
which is a directory that gets cleaned. It is now in the repository with its reasoning intact.

Its own note is the useful part: *"a mouse drag is not a drag to Flutter -- `ScrollBehavior.dragDevices` does not
include the mouse on desktop, so dragging selects text instead of scrolling. A touch pointer IS a drag, and
Windows lets a process inject one."* The round that rescued it added the second half: `mouse_event` reaches the
navigation bar but not 记一瓶, and the button is fine -- this repository's own test taps it -- so synthetic mouse
input is not a substitute for a real pointer everywhere. `adb shell input tap/text` is the same idea on Android.

**And the caveat that cost three rounds.** A window belongs to whoever is in front of it. Every "the button does
not respond" in those rounds happened on a machine that somebody was using, with a browser in the foreground;
an injected touch goes where the pointer is, not to the application. Check what is in front before concluding
anything about a widget.

### What is inside each artifact, checked by opening it (2026-09-24)

The acceptance tables above are about *running* the artifacts. This is the other half: **opening them and
reading their payload**, which needs no UI, no handset and no window manager, and which answers a question the
screenshots cannot -- whether the thing that shipped contains the finished content or only looks as if it does.

| Artifact | The library inside it | The icons inside it |
| --- | --- | --- |
| `hollow-court-1.0.0.527-arm64-v8a.apk` | `assets/flutter_assets/assets/drinks/library.json`: **103 drinks, 189 ingredients**, 33 Unforgettables / 35 New Era / 35 Contemporary Classics | pixel-identical to `art/render/icon-hc-{48,72,96,144}.png` -- **0 differing pixels**, measured with `magick compare -metric AE` |
| the installed MSI (`E:\Hollow Court Win`) | `data/flutter_assets/assets/drinks/library.json`: **103 / 189**, the same three counts | the executable carries the rebuilt `.ico` (32x32 reads back through `ExtractAssociatedIcon`) |
| `hollow-court-1.0.0.527-x86_64.AppImage` | `data/flutter_assets/assets/drinks/library.json`, extracted with `--appimage-extract`: **103 / 189**, the same three counts | `hollow_court.png`, 192x192 -- the desktop entry's icon, and the full-density drawing, which the tiered rework deliberately left unchanged |

**And one lesson worth keeping, because the first test was the wrong one.** Comparing the APK's icons to the
repository by **hash** reports four mismatches and means nothing: the Android toolchain re-encodes the PNGs, so
the bytes differ while the pixels are identical. The check that answers the question is a pixel difference
(`magick compare -metric AE`, which printed `0` for all four). A byte comparison of a file that a build step is
allowed to re-compress is not a test of the content.

### Android: done, and one thing about this handset worth knowing (2026-09-25)

The last acceptance cell is filled: **1.0.0.1014 installed, running, and used** -- a bottle recorded by hand on
the release build, `packaging/android/apk-1.0.0.1014-used-gin-700ml.png`. Three things came out of doing it.

**The signing identity changed, so the old copy had to go first.** `adb install -r` refuses an update signed by a
different key, and the handset's 1.0.0.523 was signed by the retired one -- so it was uninstalled deliberately
(its two bottles of test data went with it, and were recorded here rather than quietly lost) and 1.0.0.1014 went
on clean.

**MIUI blocks injected input, so the phone side cannot be driven from `adb`.** `adb shell input tap` and
`input keyevent` reach the system but not the application: the navigation bar does not respond, the 记一瓶 button
does not respond, and nothing appears in the app at all. The device's real resolution (`wm size`: 1220x2712)
matches the screenshots exactly, so the coordinates were never the problem. This repository's own README has said
all along that *the only screen a person has to touch is the phone's* -- which turns out to be not a preference
but a hardware fact on this handset. The one write that proves the build works was therefore made by hand.

**And the install itself needed two settings flipped.** `INSTALL_FAILED_USER_RESTRICTED: Install canceled by user`
is MIUI's "install via USB" guard; clearing `verifier_verify_adb_installs`, `install_non_market_apps` and
`adb_install_need_confirm` let the streamed install through.

### Android: the handset is the only thing missing, and everything else is checked

The one remaining acceptance step on any platform is Android's install-run-use, and it needs a cable rather
than an investigation. What was verified on 2026-09-24 so that the step is one command when the handset
appears:

| Check | Result |
| --- | --- |
| `apksigner verify --print-certs` | `CN=Hollow Court, OU=S.M.Y.T., O=S.M.Y.T.`, SHA-256 **`37d16696…d49cd2576`** -- the release key this file already records, so `adb install -r` updates the existing application **in place and keeps the cellar** rather than installing a second product |
| `aapt2 dump badging` | `com.nesarf.hollow_court`, `versionCode 2527`, `versionName 1.0.0.527`, label 空庭 / Hollow Court |
| the receipt beside the artifact | `head` = the commit this was built from, in `*.commit` in the bundle directory |

**And the harness that would drive it is ready too**, which the last two rounds learned the hard way: the
keyboard reaches controls that synthetic mouse events do not (`SendKeys` Tab/Enter works on the installed
Windows build, `mouse_event` reaches the navigation bar but not 记一瓶 -- see the input note above). A phone
attached over ADB takes `adb shell input tap/text` instead, which is a different and better-behaved path.

### The Windows build failed once, and it was a stale plugin directory (2026-09-24)

The first 1.0.527 Windows build died in CMake, and the message named a dependency rather than the fault:

```
error MSB8066: "…\windows\flutter\ephemeral\.plugin_symlinks\jni\src\CMakeLists.txt" 的自定义生成已退出，代码为 1
```

`jni` is not a dependency anybody added: it is **transitive under `path_provider_android`**, and it declares a
Windows implementation, so the Windows build compiles a native target for it. `pubspec.lock` was untouched --
verified, because a changed dependency set was the first thing worth ruling out -- so the fault was the build
tree's own state, not the sources. Deleting the generated plugin directories and rebuilding was the whole fix:

```
rm -rf build/windows/x64/plugins/jni build/windows/flutter/ephemeral/.plugin_symlinks/jni
bash packaging/windows/build.sh        # rc=0
```

Recorded because the message points at a third-party `CMakeLists.txt` and says nothing about a stale directory:
the next person to see MSB8066 with a plugin path in it should try this before reading the plugin's CMake.

### The AppImage photograph, and the four things that had to be learned (2026-09-24)

**It has one now**: `packaging/linux/appimage-ui-wslg-x11-1356x817-1.0.0.527.png` -- the Cellar tab, the two
bottles that installation happens to hold, the five-tab bar and the 记一瓶 button, on 1.0.0.527.

The round before this wrote that the photograph was an open task and that the route was "a screenshot tool that
understands Wayland". **That was wrong**, and the correction is worth more than the picture: the application is
an **X11** client all along (`libEGL warning: DRI3 error` is an X11 extension being asked for, and the window is
in `xwininfo`'s tree the whole time). The real obstacles were four smaller things, each of which produced a
misleading symptom:

| Symptom | What was actually wrong |
| --- | --- |
| `import: missing an image filename <the real output path>` | **ImageMagick reads a `0x` window id as the output file name**, then reports the real path as an unexpected extra argument. The error reads like a quoting fault; the fix is the decimal id (`$((0x200028))` = `2097192`) |
| `import: no window with specified ID exists` | correct, for the id it was given: the *selection* had picked one of XWayland's `10x10` stubs |
| the wrong window selected, every time | `xwininfo` prints a name for some windows and not others, so `$4`/`$5` are the geometry in one case and in the middle of the name in the other. The dimensions have to be found by pattern on the line |
| "the largest window" being an `8192x8192` root | an upper bound is needed as much as a lower one: Weston's own root is the largest thing on that server and captures nothing useful |
| a capture reported as successful while nothing was written | a failed `import` leaves the **previous** file in place, and the script was reporting `ls` rather than the exit status |

And one thing that was right and is worth keeping: the earlier desktop capture *did* find a Hollow Court
window -- and killing the Windows build made it vanish, so it was the Windows one. That check was run in that
order deliberately, and running it is why the count of platforms that had been photographed was not inflated
by one.

### The AppImage runs, and what that does and does not prove

**From an earlier round, kept as the record of what starting it proved the first time.** It had never been
started; it has now been, under WSLg (`DISPLAY=:0`, Wayland present, `/dev/fuse` present so no
`--appimage-extract-and-run` was needed) -- and it has since been photographed, which is the section above:

* the process **stayed alive past 18 seconds** instead of exiting,
* GTK **created a window** -- `Gdk-Message: Unable to load from the cursor theme` is a window
  existing, not a crash,
* Impeller initialised: `Using the Impeller rendering backend (OpenGLESSDF)`,
* the EGL/MESA warnings (`failed to get driver name for fd -1`, `ZINK: failed to choose pdev`)
  are WSLg having no GPU to hand, i.e. **software rendering**, which is why the Windows-side
  window title is prefixed `[WARN:COPY MODE]`,
* Windows sees the window: the `msrdc` process carries `MainWindowTitle` of
  `[WARN:COPY MODE] Hollow Court (Nyarch)`.

**A picture of it now exists**: `packaging/linux/appimage-ui-wslg-printwindow-1080x670.png`, 1080x670,
sha256 `5090155c...bc8396`, from the rebuilt AppImage launched from
`~/.local/bin/hollow-court` via `packaging/linux/install_appimage.sh`. It shows the Cellar tab --
酒窖 / Cellar, 在架 · 1 with the Vermouth the earlier round entered, and the wine-gold rule under the
row -- so **the UI renders**, in the palette, with section 12.4's two lines per string.

**The file name used to say `x11-1280x720`, and it was 1080x670.** The earlier photograph was taken
by forcing X11 and measuring the window that came up; this one is the window's own size, which is
whatever WSLg gives it. Renamed rather than left, because a name that states a size is a claim, and
this one no longer matched what the file contains. The method changed with it: it is
`PrintWindow(PW_RENDERFULLCONTENT)` on the WSLg window, the same call the Windows photograph uses,
because **a process started from a background shell cannot raise its window** -- the first attempt
here photographed the browser sitting on top of that rectangle instead of the application.

**Why it took three attempts, and the second one was the mistake worth recording.** The first two
captured the Windows desktop and caught the DSH browser window instead, because Windows would not
raise the WSLg window from a non-foreground process. The lesson was not "raise the window" but
**stop photographing the desktop**: capture from inside Linux, where the only thing to see is this
window. `import -window <id>` on the window X11 reports does it.

**And `xwd` -- the obvious tool -- does not work here.** `xwd -root` and `xwd -id <window>` both
fail with `X Error of failed request: BadMatch ... Major opcode of failed request: 73 (X_GetImage)`,
and a root capture through ImageMagick hits the same error; `import -window` succeeds where they
fail. That cost a round of its own.

**What the picture still does not establish**: it is software rendering, and `GDK_BACKEND=x11` was
forced to make an X11 client out of a GTK application that WSLg otherwise runs as a Wayland one. So
it is the real UI, drawn by the real build, through a different backend than the default, on a
machine with no GPU to hand.

Anyone can see for themselves by running the AppImage on a Linux desktop, which is also the only
way to find out how it behaves with a real GPU.
So P4 is one third of the way to its own acceptance criterion, and the other two thirds are not
waiting on code: the MSI needs a machine where `msiexec` does something, and the AppImage needs a
Linux desktop. Neither is a defect in the artifact, and neither is evidence that the artifact
works. The row says what was done, not what seems likely.


### The translation table nothing asked for (1.0.0.521)

Reported from the owner against the shipped build: IBA cocktail names stayed English in the Chinese interface,
and an ingredient could be *found* by its Chinese name while the row it was found in still said the English one.

**The translations were already there** -- all 88 drink names and all 187 ingredient names in zh-Hans, zh-HK,
zh-TW and ja, plus the instruction text, in `data/names/names.json` since the owner asked for them. The screens
never asked for them: the recipes page consulted the table for its *steps* and drew `recipe.name` for the title;
the sheet's ingredient rows drew `ingredientById(id).name` while the Cellar tab's bottle rows had been
translating all along; and the ingredient picker drew English while the *search* had already been given the
translations, which is the asymmetry in the report exactly.

1.0.0.521 for all three targets, installed on the host and on `a physical device`, with the drinks list
photographed on the handset (`android/recipes-translated-1.0.0.521.png`: 蜂之膝, 荆棘, 坎昌查拉, 查特斯威泽,
黑风暴 where the English names used to be). The three drawing sites are held by
`test/ui/translated_names_test.dart`, and the data by `test/data/seed/seed_translation_coverage_test.dart` --
which also refuses a "translation" that equals the English, because the fallback chain ends there and a
coverage test on its own would accept it. The defect itself is recorded in `docs/DESIGN.md` §15.1.

### Every language complete, and proofread against Wikipedia (1.0.0.522)

The owner's instruction: *"要保证所有语言都有完整翻译，并使用网络信息做校对"*. Two findings, one of them a gap
that had been shipping:

1. **`lib/ui/unit_labels.dart` had no 港繁 or 台繁 labels at all** -- 26 units each, so a Hong Kong or Taiwan
   reader got the 简中 base for every one of them through the fallback chain. The test that claimed "every
   shipped language" listed three locales by hand while `shippedLocales` had five; it now asks the catalogue.
   The labels were written from Wikipedia's own terms (公克 redirects to 克, 安士 to 盎司, 忌廉 to 鮮奶油).
2. **The 港繁/台繁 columns of `data/names/names.json` were OpenCC conversions that had never been proofread** --
   the same state DESIGN.md 12.4.1 recorded for the interface copy. Proofreading against Chinese Wikipedia's
   own conversion table (`Module:CGroup/Food`) and its article titles produced 17 regional corrections
   (車厘子, 氈酒/琴酒, 朱古力, 雪糕, 萊姆, 柳橙汁, 鳳梨, 通寧水, 莫希托, 忌廉/鮮奶油) and three classes of
   defect: 幹 for 乾 (dry), 裏 inside a transliteration, and one English name translated two ways in one file
   (Daiquiri as 得其利 in one entry and 代基里 in another).

`tool/seed_name_audit.py` is the repeatable half -- it reports, never edits, and it refuses to apply the third
kind of finding (identical English titles lead to concept articles: Zombie → 喪屍). `tool/l10n_status.dart` now
answers the whole question in one run: copy 240/240, steps 88/88, names 88+187, units 26, per language.

**A machine fact this depends on**: `zh.wikipedia.org` resolves to a poisoned address here (2001::1 and a Twitter
range), and this host reaches the internet only through the proxy at `127.0.0.1:10090`. `curl -x` that proxy and
Wikipedia answers normally.

### `GLib-GIO-CRITICAL` on every Linux launch: one string was doing two jobs

Running it for the picture produced a warning on stdout that nobody had read, because nobody had run
the artifact and looked:

```
GLib-GIO-CRITICAL: g_application_set_application_id: assertion
  'application_id == NULL || g_application_id_is_valid (application_id)' failed
```

**Measured rather than assumed**, with PyGObject in Nyarch:

| Candidate | `Gio.Application.id_is_valid` |
| --- | --- |
| `hollow_court` | **False** |
| `com.nesarf.hollow_court` | True |
| `com.nesarf.hollowcourt` | True |

GLib requires an application id to contain a dot, and this one did not -- because of the icon fix
described in `linux/CMakeLists.txt`, which chose a **dotless** id to satisfy WSLg's key derivation.
The assertion is GLib refusing the value inside the setter, so **the application then ran with no
application id at all**, and the WSLg lookup that made the icon work was falling back to the program
name. The fix that looked like a choice of id was half an accident.

**The two constraints are on two different strings, and they are now two variables.** The application
id is `com.nesarf.hollow_court` -- valid, and the same string Android's `applicationId` uses -- while
the program name stays dotless `hollow_court`, which is what the desktop file, the icon names and
`.DirIcon` are all built around. `linux/runner/my_application.cc` takes them separately.

Measured after the change:

* **the critical is gone** -- 0 occurrences across three launches, where it was 1 per launch before,
* the window's class is still `("hollow_court" "Hollow_court")`, i.e. the string WSLg's lookup used,
* and under forced X11 the application now maps a real **1280x720** window titled `Hollow Court`,
  where the same forced-X11 run on the previous build showed only a 10x10 window. That is **two
  single readings on two different builds**, so it is recorded as an observation and not as a
  demonstrated cause.

**What was not re-measured, stated because it is the one gap**: WSLg's own icon lookup after this
change. Its log line (`app_list_monitor_thread: loadIconEvent is signalled. hollow_court`) appears
only when WSLg actually loads the icon, and it caches the result -- so the evidence that was used to
verify the icon cannot be re-produced on demand, and `wsl --shutdown` does not restore it. The
WM_CLASS equality above is the reason to expect the icon is unchanged, and it is not proof.

### An artifact is a claim about the source it was built from

"The APK is installable and usable on a device" was demonstrated once, on the APK built at
2026-09-20 17:59. By 09:39 the next morning **28 files under `lib/` were newer than that APK**. So
the demonstrated thing and the current source were no longer the same program, and the sentence
above -- read as a statement about the tree -- was false while every fact in it was true.

The APK has since been rebuilt from HEAD, so the two agree again. The rule this leaves behind is
narrower than "rebuild often":

> An acceptance result belongs to one artifact, and an artifact belongs to one commit. Record which
> commit; a result that does not name its commit silently transfers itself to code it never ran on.

That is the same mistake as reading a substring where the whole word was meant. There, a name
stood in for the thing; here, an old success stood in for the current build.

### What key signs the release APK -- measured, not assumed

**This heading used to read "The release APK is signed with the debug key", and the fingerprint below
is what it carried at the time. Both halves are now out of date, and the correction is worth reading
because the stale version stayed believable for a day while `signing.sh` had the answer in one line.**

*What it was*, read out of the APK rather than out of the build log:

```
signer DN: C=US, O=Android, CN=Android Debug
SHA-256  : 3c0068bc250e8be705438002f38efce1f644f2897529bd0e4a88f5cac97182f1
verdict  : DEBUG-SIGNED -- an installation of this can never be updated
```

*What it is now*, measured on 2026-09-23:

```
android/key.properties + android/release.jks    present, written 2026-09-22 05:42
hollow-court-1.0.0-arm64-v8a.apk                CN=Hollow Court, OU=S.M.Y.T., O=S.M.Y.T.
                                                SHA-256 64cca05ac54e3c22138ad99c3e31246be19cc48f84c4a95faf615e64ffafa16d
                                                verdict: signed by a release key
the copy installed on a physical device          the same SHA-256 -- the same artifact
```

**So `make_keystore.sh` has been run**, which this page said had deliberately not happened, and the
sentence that followed it ("the mechanism is now in place; the key is still not") stopped being true
the moment it was. The hazard did not go away, it moved: a debug key is deleted with the build
directory, and a **real key is lost by whoever holds it** -- which is why `android/key.properties` and
`android/release.jks` together are the application's identity and belong in a backup that outlives
this machine.

**And one consequence deserves a paragraph, because it is the difference between a routine install and
losing a cellar.** The copy on the test device carries **the same release key**, so a new APK installs
*over* it and the data in it survives. Had that copy still been the older debug-signed build,
`adb install -r` would have failed with `INSTALL_FAILED_UPDATE_INCOMPATIBLE`, and the only way forward
would have been an uninstall -- taking the shelves with it. It is a one-command check before any
device round, and it should be run *before* the round rather than discovered during it:

    adb shell pm path com.nesarf.hollow_court     # then pull that file and run signing.sh on it

The choice this section used to pose, now that one has been made:

| | Consequence |
| --- | --- |
| keep the debug key | right for a test device and for the sideloading this is actually for today; the moment a copy is out in the world, no update can ever reach it |
| **make a real keystore** | **what was done on 2026-09-22** -- the app now has an identity someone owns, and both files must be backed up somewhere that outlives this repository, because losing them is indistinguishable from never updating |
| ship unsigned / let the store sign it | defers the decision to whoever accepts the build; fine if that is a person, not fine if it is nobody |

An artifact is a claim about its source, and on Android it is also a claim about its key -- which is why
`packaging/android/build.sh` puts the signer's fingerprint in the receipt beside the APK and refuses to
call a build a release when `key.properties` exists but the artifact came out debug-signed.

### A `pub get` before every build, on whichever platform you are on

`.dart_tool/package_config.json` lives in the project tree and is **shared** between the Windows and
the Linux copies of this project, so a `pub get` on one side rewrites every package path for the other.
The failure does not look like a path problem: it looks like hundreds of errors saying that `Offset`,
`Paint` and `Rect` are undefined in a file that plainly imports them.

It has now happened in **both directions**. Linux was first, and `tool/build_linux.sh` has carried the
note since. Android was second: `flutter build apk --release` failed on `lib/ui/price_chart.dart`
while `flutter analyze` on the same tree reported no issues -- because analyze had run *before* the
Linux build rewrote the file, and the APK build *after* it. The timestamp on
`.dart_tool/package_config.json` was 19:37, which is when the Linux side last ran.

So `packaging/android/build.sh`, `packaging/windows/build.sh` and `tool/build_linux.sh` all begin with
one. It costs seconds; not running it costs an hour of reading a compiler's opinion about code that is
fine.


## Windows

    packaging/windows/build.sh

Runs `flutter build windows --release` and then WiX. The installer is **perUser**: the
cellar is one person's bottles in their own folder, a machine-wide install would ask for
elevation to put a private notes app on a shared machine, and section 1 positions this
as a cellar a reader owns. It also means the installer never needs administrator rights,
which is the difference between an install and an interruption.

**In practice on an elevated shell it registered per-machine anyway.** `msiexec` run from an
administrator session put the product's Add-or-Remove entry under `HKLM` while still installing the
files into `%LOCALAPPDATA%`: the files follow the scope, the registration followed the elevation.
Both are real and the uninstall works from either, but the label `Scope="perUser"` is a statement
about the files rather than about the registry.

The same script begins by running `packaging/windows/check_comments.sh`, which refuses a `.wxs`
containing a double hyphen inside an XML comment. WiX reports that as `WIX0104` with a line and
position pointing at the comment rather than at the mistake, and it cost this project a build
twice: the second time after the rule had been written down here. **A rule in prose is not a
check.** Writing the check then found a second occurrence that a manual search had missed, because
the search was `grep` piped into `grep -v` to drop the comment delimiters, so the offending line
began with `<!--` and was dropped whole.

### What the validator says, counted rather than summarised

**Five findings, and this table has now been wrong twice** -- first claiming "ICE91 warnings and
nothing else", then carrying a count of 51 that belonged to an earlier shape of the package. Both
were written from memory of a previous run. Counted on the shipping package:

| Check | Count | What it is saying |
| --- | --- | --- |
| `ICE43` | 1 | the shortcut component has a non-advertised shortcut, and wants a registry key under `HKCU` as its key path |
| `ICE48` | 1 | `INSTALLFOLDER` looks hardcoded to a local drive -- it is, and `.wxs` argues for it at length |
| `ICE57` | 1 | `StartMenuShortcut` holds per-user data (the shortcut) and per-machine data (the executable outside the profile) |
| `ICE60` | 2 | a file is not versioned and is not a font |

**Where the 46 that disappeared went, because the difference is the interesting part.** The old
table listed ICE38 (18), ICE64 (11) and ICE91 (17) -- all three of which are rules about files
installed into the *user profile*. The install location was moved to a fixed `E:\Hollow Court Win`
to keep 78 MB off `C:`, and those checks stopped having anything to complain about. The table was
not updated when the location changed, so it described a package that no longer existed. A count in
prose is a claim about an artifact, and this is what happens to one that nobody re-measures.

**ICE43 and ICE57 are the same root cause and they are `error` severity, not warnings**: one
component holds both the Start Menu shortcut (per-user) and the executable (outside the profile), so
its key path is per-machine while half its contents are not. The ICE tells you the standard repair --
give the component a `RegistryValue` key path under `HKCU` -- and that has **not** been done, because
it changes install and repair semantics and cannot be verified here without an install to verify
against. It is now verifiable, so it is a candidate rather than a mystery.

**ICE48 is a decision, not a defect.** The fixed path is what keeps the app's 78 MB out of `C:`, and
the property is public precisely so an installer can override it. A package with no findings here
would mean the install had gone back into the user profile.

**`RemoveFolder` entries exist for the two folders this package creates by name** (`INSTALLFOLDER`
and the Start Menu folder), which is what the old ICE64 paragraph was about. The hashed
sub-directories that `<Files Include>` generates still have no removal entries of their own, so an
uninstall may leave an empty folder tree under the install location. Recorded rather than fixed:
authoring those components by hand trades a folder for several hundred lines of generated markup.

**The build script now counts them rather than asserting them.** `packaging/windows/build.sh` runs
the validator into `build/windows/wix-validation.txt`, prints the per-code counts, and puts the
measured numbers in the artifact's receipt. It used to hand the receipt a hard-coded sentence --
"51 ICE findings, only ICE64 has a real consequence" -- which was wrong in both halves by the time
anybody read it. **A receipt is a claim about an artifact, so it is built from the artifact.**

Three things cost time and are recorded so they do not cost it twice:

1. **WiX v4+ syntax, not v3.** The `wix` dotnet tool is v5 and the v3 vocabulary is gone:
   `<Package>` rather than `<Product>`, and `<Files Include>` harvesting a folder instead
   of one `<Component>` per file. v3 source fails on its first element.
2. **An XML comment cannot contain a doubled hyphen.** This project's prose uses `--` as
   a dash throughout, so a comment lifted from a design document is invalid XML. It fails
   with the line and column, which is the only mercy in it.
3. **A relative path in a `.wxs` resolves against the working directory**, not against the
   file. The release folder is passed as `$(ReleaseDir)` from the build script instead.

### The MSI is installed, and getting there found a real defect in the package

**It was blocked by the host and then broken in the package, in that order**, and both are worth
keeping, because the first made the second invisible for a while: an installer that does nothing
at all cannot show you that the thing it would have installed is wrong.

The host half first. Every attempt produced this:

| Checked | Result |
| --- | --- |
| the package contains the app | **yes** -- the `File` table has 19 rows: the 18 harvested files plus the explicit launcher |
| `msiexec /i ... /qn /norestart /l*v <log>` | **no log file, no install directory, nothing on disk** -- not slow, not failed, inert |
| `msiserver` | was **STOPPED**; started it by hand, reached Running, retried | 
| with `msiserver` Running | **the same: no log, no install** |
| `DisableMSI` policy | **absent** in both `HKLM` and `HKCU` |
| `%LOCALAPPDATA%\Hollow Court` | absent, as is every plausible alternative under the profile |

#### The blocker now has a name: error 1604, ERROR_INSTALL_SERVICE_FAILURE

Two further facts, found after the first write-up, turn this from unexplained into diagnosed:

**1. This machine has done it before, to somebody else's installer.** Two logs on disk end with
`MainEngineThread is returning 1604` -- `MSI86b8e.LOG` (2026-09-20 05:13, product
`{4E5E212E-...}`, not this app) and `genuine-uninstall.log`. **1604 is
`ERROR_INSTALL_SERVICE_FAILURE`**: the Windows Installer service could not be accessed. So the
failure predates this package and is not specific to it.

**2. The two hung `msiexec` processes were mine, and what they did is the diagnosis.** They sat for
15 minutes with `/qn`, which is fully silent and should show **no window at all**, while carrying a
visible `Windows Installer` window. And `/l*v <path>` produced **not one byte of log** -- the log
is opened by the engine, so the engine had not started. Blocked before it could write its own
first line.

**The sharp end of it:** `Start-Service msiserver` **succeeds** and the service reaches `Running`;
its config is ordinary (`DEMAND_START`, `LocalSystem`, depends on `rpcss`). And the retry with the
service already `Running` still hung the same way. So the anomaly is not "the service is stopped".
It is that **the service is startable while the client cannot reach it** -- which is exactly what a
1604 looks like from the outside.

This is a fault in this Windows installation, not in the MSI. What the package contains was
verified independently (the File table's 19 rows), and nothing in that check depends on the
service. **Fixing it is a machine repair, not a packaging change** -- and it is the same class of
obstruction as the social platform 30007 fault earlier in this work, where the failing component also
turned out to be the host's, not the app's.

#### Resolved: a reboot cleared it, and the package was wrong anyway

`bcdedit /set testsigning off` fixed the EAC problem and, as a side effect, the installer problem:
after the reboot `msiexec /i` wrote a 143 KB log and returned 0, where before it wrote nothing and
returned nothing. So the 1604 was a machine state the reboot reset, exactly as diagnosed above, and
nothing about the MSI's *contents* was ever the issue.

**What the first successful install then revealed is a defect in the package**, and it is the kind
this whole file exists to catch:

| | install folder | Start Menu folder |
| --- | --- | --- |
| first successful install | 17 files, **no executable** | `hollow_court.exe` (88.5 KB) **and** the shortcut |
| after the fix | 18 files, executable present | the shortcut only |

The install *reported success*. `Shortcuts`, the `ComponentGroup` holding the executable, carried
`Directory="AppShortcutFolder"`, and a `Component` inherits its group's directory when it does not
say otherwise, so the executable was laid down in the Start Menu folder while its own shortcut
pointed `WorkingDirectory` at an install folder with no executable in it. One attribute. The app
installed, registered, uninstalled, and could not be started.

**Being able to install it is what found it.** The earlier round could not install anything, so it
recorded "not demonstrated" and moved on, and a package that lays down 17 of its 19 files would
have kept that label indefinitely.

Re-verified after the fix, by installing and launching: the executable is in the install folder,
the shortcut's target exists, and the process stays up with a window titled `Hollow Court`.

#### A correction to an earlier claim in this file's own history

The commit that fixed the directory attribute also claimed the product was "absent from HKCU's
Add-or-Remove list, so it cannot be uninstalled from Settings". **That was a wrong search, not a
finding**: the entries were enumerated and filtered by name, and the registration is under `HKLM`,
where the filter never looked. By exact ProductCode it is there, named `空庭 Hollow Court` 1.0.0,
with an uninstall string that works. A filter stood in for the thing itself.

**A contradiction in the event log that is not resolved**: `MsiInstaller` contains two
"successfully completed the installation" entries timestamped 08:52, and **nothing on disk
corresponds to either**. They may be from an ICE validation pass during `wix msi validate`, which
is run by the build script; that was not determined, and it is written here as a contradiction
rather than explained away.

#### Resolved: those entries are the validator's, and the second "hang" was our own quoting

Two things were settled by experiment after this section was written, and both of them replace a
belief with a mechanism.

**1. `wix msi validate` installs the product, and that is where the phantom successes come from.**
Timed on purpose:

```
07:10:28  wix msi validate <the shipping MSI>
07:10:33  MsiInstaller 1033  "Windows Installer installed the product ... 空庭 Hollow Court"
07:10:33  MsiInstaller 11707 "产品: 空庭 Hollow Court -- 成功地完成了安装。"
          and nothing new under %LOCALAPPDATA%, E:\Hollow Court Win, or the registry
```

Five seconds, two success entries, no files: the validator performs a real install into a scratch
context and rolls it back. So **the event log is not evidence that this product is installed** --
the build script writes the same two entries on every run, and a reader who took them as proof would
conclude the app was installed on a machine that has never had it. The contradiction above is closed,
and the lesson is the general one: an entry in a log is evidence about the process that wrote it, and
that process is not always the one being asked about.

**2. The "msiexec hangs on this host" finding was true once and false the second time, and the second
time was our fault.** After the reboot the service fault was gone, and the next round's failures had
a different cause entirely: **the artifact path contains a space, and every wrapper quoted it
wrongly.**

| How it was invoked | What msiexec actually received |
| --- | --- |
| `bash -c 'msiexec //i "E:\...\hollow-court-1.0.0.msi"'` | `"<bundle>\..."` -- the backslashes survived into the command line, so the argument had literal quotes in it |
| `powershell Start-Process -ArgumentList @('/i','<bundle>\...msi')` | `/i <bundle>\...msi` -- PowerShell joins the array with spaces and **adds no quotes**, so the path split at `E:\Hollow` |

In both cases msiexec was handed a package path that does not exist. It then does what it does with
an unopenable package: it puts up an error box. With `/qn` there is no visible UI, and a background
shell cannot raise a window, so the box waited in a session nobody was looking at -- **no log (the
engine never started), no files, no exit code, forever.** That is exactly the shape that had been
read as a machine fault.

`packaging/windows/install_test.cmd` is the fix, and it is a batch file rather than a documented
command line because a batch file has no shell in the middle to misquote. It takes the package and
log paths as arguments, runs the install, and prints the exit code:

```
cmd /c "E:\hollow-court\packaging\windows\install_test.cmd"
  package: "<bundle>\hollow-court-1.0.0.msi"
  log    : "E:\DaShaoHuo\cache\msi-install.log"
  exit=0
```

**Measured with it: 19 files, 82.6 MB, into `E:\Hollow Court Win`; a Start Menu shortcut `空庭.lnk`;
a registration under `HKLM` as `空庭 Hollow Court` 1.0.0; and the installed `hollow_court.exe`
launched, titled `Hollow Court`, 28 threads, 165 MB resident.** The window is photographed in
`packaging/windows/msi-installed-run.png` -- captured with `PrintWindow(PW_RENDERFULLCONTENT)` rather
than a screen grab, because a process started from a background shell cannot raise its window and the
first attempt photographed the browser that happened to be on top of that rectangle.

**And a rebuilt package cannot uninstall the version it replaces, which costs an hour the first
time.** Measured on the current artifact:

| Command | Result |
| --- | --- |
| `msiexec /i <rebuilt msi>` over the installed same version | **1638** -- another version of this product is already installed |
| `msiexec /x <rebuilt msi>` | **1638** as well, and the log says it *reconfigured* the product rather than removing it |
| `msiexec /x {A5F04187-A392-4883-A717-C9612D088BCD}` (by product code) | **0**, and the install directory is gone |
| `msiexec /i <rebuilt msi>` after that | **0**, 19 files |

The middle row is the one that misleads, because `/x` with a package path is the natural thing to type
and it answers with a version conflict rather than with what it actually did. **Uninstall by product
code**; the code is the one pinned in the `.wxs` and it is in the Add-or-Remove entry as well.

  (What the pinning *did* fix, one row up: with an auto-generated product code each rebuild was a
different product, so an install-over was not a repair but a second product beside the first -- and
that is the state that produces two entries nobody can tell apart.)

**So the honest state of P4's Windows row is now: built, installed, launched, and photographed.**
Both halves of the earlier belief were needed to get here -- the service fault was real and the
quoting fault was real -- and keeping them apart is what stops either from being applied to the wrong
failure next time.

## How to check that an artifact really contains your change

Size and timestamp are not evidence, and this was learned the straightforward way: two AppImage
builds came out at **exactly the same byte count** (23 538 168) with different hashes, which is a
coincidence of squashfs block alignment rather than a sign that one of them was stale -- but it is
also exactly what a stale rebuild looks like.

The check that settles it is to look for a string you just added, **in the right encoding**:

```
wsl -d Nyarch -e bash -lc "cd /tmp && rm -rf aie && mkdir aie && cd aie   && '$OUT_DIR/hollow-court-1.0.0-x86_64.AppImage' --appimage-extract >/dev/null   && python3 -c \"
import glob
data = open(glob.glob('squashfs-root/**/libapp.so', recursive=True)[0], 'rb').read()
print('设置'.encode('utf-16-le') in data)\""
```

**Three things about that command are the point.**

1. **`libapp.so`, not `kernel_blob.bin`.** A release build is AOT-compiled, so the Dart code is in the
   libapp snapshot; `kernel_blob.bin` is the JIT image for debug runs and contains none of your
   release strings. Grepping it and finding nothing looks exactly like a stale artifact.
2. **UTF-16, not UTF-8.** The AOT snapshot stores non-Latin1 strings as two-byte strings, so `grep`
   for the UTF-8 bytes of 设置 finds nothing while `grep` for `Settings` finds that. A search that
   fails on a Chinese string and succeeds on an English one is telling you about the encoding, not
   about the build.
3. **The Android equivalent is different again**, and it worked: the launcher icon inside the APK was
   compared **pixel by pixel** against `art/render/icon-hc-192.png` after AGP shrank and renamed the
   resource to `res/o-.png`. Matching by name is impossible there; matching by pixels is exact.

## One APK per ABI, because the size budget is a constraint and not a preference

A plain `flutter build apk --release` produces one **universal** APK, and this project shipped that for
weeks. What it actually contained:

    52.8 MB total  ->  lib/x86_64 18.81 MB + lib/arm64-v8a 17.39 MB + lib/armeabi-v7a 14.97 MB

**Fifty-two megabytes downloaded to install seventeen**, and `x86_64` is not even a phone -- it is
emulators and a handful of Intel tablets. Section 14.1 says the budget is a hard constraint because the
number is paid by every user; a universal APK pays it three times over.

    bash packaging/android/build.sh              # three files, ~18 / ~16 / ~20 MB, all release-signed
    UNIVERSAL=1 bash packaging/android/build.sh  # one file for every device, 53 MB

The universal build is kept behind a flag for the one honest reason to want it: handing a single file to
a device whose architecture you do not know. That is what the phone round needed, which is why the mode
exists rather than the flag being deleted once it was done. The permission check and the signing
post-condition now run **per file**, since either can pass for one ABI and fail for another.

## P3 done: two physical devices, one cellar (2026-09-22)

**Run, and it found something no test could have.** A Xiaomi phone (`192.168.31.240`) and this machine
(`192.168.31.157`), the phone joining with the pairing code, then a second sync with no code at all.

| | first sync | second sync |
| --- | --- | --- |
| phone reports | 同步完成, 收到 / 送出 **2 / 2**, 对方 **laptop** | 同步完成, 收到 / 送出 **1 / 0** |
| host reports | `OUTCOME ok`, `merged 2`, `sent 2` | `OUTCOME ok`, `merged 0`, `sent 1` |
| authentication | the pairing code | **the remembered key** (same peer key both times) |
| evidence | `android/p3-two-devices-1-code.png` | `android/p3-two-devices-2-no-code.png` |

After the first sync the phone's 已记住的设备 lists `laptop` at `192.168.31.157:48123` with 再同步一次 and
忘记这台设备, and its own fingerprint `NER7-84L5-8DCN-B9VK` beside 这台设备. The second sync was one tap on
再同步一次: no code, and the host recognised the same key it had learned.

### Three things stood between the release APK and a working socket

1. **`android.permission.INTERNET` was never declared in `src/main/AndroidManifest.xml`.** Flutter's
   template puts it in `src/debug/AndroidManifest.xml` alone, because a debug build needs it for the Dart
   VM service, so **every release APK had no network access at all**. On the phone the failure was

       SocketException: Connection failed (OS Error: Operation not permitted, errno = 1)

   which is EPERM and names no permission. Every sync test passes in a debug build, which is exactly why
   this reached a release APK: the desktop builds have no manifest and no permission system, so nothing
   in this repository could have caught it. `build.sh` now refuses to finish if the APK it just wrote does
   not declare the permission.
2. **Windows Firewall drops the inbound connection**, and the phone reports it as
   `Connection timed out, errno = 110`. The fix on this machine was one rule:
   `netsh advfirewall firewall add rule name="Hollow Court sync probe" dir=in action=allow protocol=TCP localport=48123 profile=any`.
   Without it the phone's SYN goes nowhere and *nothing* appears on the host side -- the failure looks
   identical to a wrong address.
3. **Typing the code on the phone is the hard part.** `adb shell input text` goes through the active IME,
   and this phone's two input methods are Chinese ones whose punctuation is fullwidth: the code arrived as
   `、 、 192。168。31。157：47654、FNF4M9?` with an apostrophe the IME invented in `name`. `input keyevent`
   is intercepted too. What works is `adb shell ime disable <the IME>` (restore it afterwards), and then
   `input text`. Coordinates should come from `uiautomator dump` rather than from a screenshot: the layout
   scrolls when the keyboard appears, and `KEYCODE_BACK` does not hide the keyboard in this application,
   it **exits** it.

## P3 on two real devices: the procedure, written before it is run

Section 14's P3 acceptance is *phone and computer share one cellar*, and the one thing it has never had
is two physical devices. Everything else is in place -- a sealed transport, devices recognised by key,
every verb proved over a real socket -- so what is left is a procedure rather than a feature. Written
down here so the round that does it is ten minutes rather than an afternoon.

**What is already proven, so that the device round is about the device.** `test/data/sync/` runs real
loopback sockets: every stock verb crosses, a retraction arriving alone lands, a device is recognised by
its remembered key on the second connection, an impostor is refused. `test/p3_acceptance_test.dart`
drives two *screens* against each other over a memory channel. What none of them can prove is that a
phone and a laptop on one network reach each other, which is a fact about two radios and a router.

    # 0. BEFORE PLUGGING ANYTHING IN: does the installed copy carry the same key as the new APK?
    #    If it does not, `install -r` fails with INSTALL_FAILED_UPDATE_INCOMPATIBLE and the only way
    #    forward is an uninstall -- which takes the cellar on that device with it.
    adb shell pm path com.nesarf.hollow_court     # pull that file, then: bash packaging/android/signing.sh <it>

    # 1. the phone gets the current build
    # The per-ABI file for the phone, not the universal one: 18 MB instead of 53.
    # The version in the file name is the APK's own versionName -- read it from the bundle rather than
    # from pubspec, which cannot hold a four-part version.
    adb install -r "<bundle>\hollow-court-1.0.0.514-arm64-v8a.apk"
    adb shell dumpsys package com.nesarf.hollow_court | grep -E 'versionName|versionCode'   # expect 1.0.0.514 / 2514
    # And 关于空庭 shows the same string, because the build scripts pass it as APP_VERSION:
    #   Settings -> 关于空庭 -> 版本 1.0.0.514, 提交 <sha>
    # Worth checking on the first round after the change: until 2026-09-23 nothing passed that define,
    # so the row showed a hardcoded default and the compile-time value was never a fact about the build.

    # 2. both on the same network, and the laptop hosting
    #    Windows: launch E:\Hollow Court Win\hollow_court.exe, Cellar tab -> 设备与同步 -> 显示配对码
    #    the code looks like hollowcourt://192.168.x.x:47999/K7FQ2M?name=<host>

    # 3. the phone joins: type the code into the same section and press 连接并同步
    adb shell input text 'hollowcourt://192.168.x.x:47999/K7FQ2M?name=laptop'

    # 3b. THE ABOUT PAGE, WHICH IS THE ONE ROW THAT PROVES THE DEFINES REACHED THE BUILD
    #     Before 2026-09-23 this row showed a hardcoded '1.0.0+1' that no script supplied. It is also
    #     where a bug report gets its two facts, so it is photographed rather than assumed:
    #     Settings -> 关于空庭 -> 版本 / 构建自提交, expected 1.0.0.514 and the receipt's src-commit.
    adb exec-out screencap -p > packaging/android/apk-1.0.0.514-about.png

    # 4. evidence, from the phone's side, because that is the side with a screenshot tool
    adb exec-out screencap -p > packaging/android/p3-two-devices.png

**The host side does not need a person either.** `tool/sync_probe.dart` drives the production sync code
from a command line -- the same `EventLog`, the same socket, the same handshake, the same identity store
-- and it can host:

    dart run tool/sync_probe.dart host --dir <cellar> --name laptop --port 47654

It prints the code and waits, so the only screen a person has to touch is the phone's. That is not a
substitute for the application: the probe is what proved the code-less second sync between two real
processes, and the pair of them (probe as host, app on the phone) exercises both entry points at once.

**Measured on this machine before the round, so the host side is not the unknown:** the only
non-loopback IPv4 is `WLAN 192.168.31.157`, the chooser selects it, and the reachability check passes.
No virtual adapter is enumerated here at all -- which is why the ranking (below) is a defence that costs
nothing rather than a fix for a known fault. **If the phone is on a different subnet, the code will still
name this address and will still be right about it**; the joining screen now says the address inside a
code can be corrected by hand, and the token can be kept.

**What to look for, in this order, because each one rules out a different failure.**

| Check | If it fails, the cause is |
| --- | --- |
| The host's code names a `192.168.` or `10.` address rather than `127.0.0.1` | the laptop is on a different interface, or the address chooser picked a virtual adapter (WSL, a VPN, Hyper-V) -- **it now ranks them and says so on screen**, so the code would carry a warning rather than a wrong address |
| The phone's screen says **配对码不对** | the code was mistyped, or the handshake authenticated against a different secret -- and the message is the code's because the handshake says so |
| It says **对方没有说话** | the phone reached something that is not the host: a firewall dropping the SYN looks exactly like this |
| It says **对方没有用密封握手开场** | something else answered on that port -- a port scanner, or a browser |
| Sync finishes and the counts are non-zero | then look at the shelf: both cellars must hold the same bottles |
| **A second sync shows 两边已经一样了** | that is the pass condition for the second round, and it is also where the remembered key is exercised: revoke the app's data on one side and it must ask for a code again |

**And the second sync is the interesting one, because of this session's work.** The first meeting is
authenticated by six characters; each side learns the other's key during it; the second meeting should
need no code at all -- 已记住的设备 lists the peer with its fingerprint, and 再同步一次 reaches it. If
the second sync asks for a code, the key was not stored, and `%APPDATA%\com.nesarf\Hollow Court\sync-identity.json`
(or its Android equivalent) is where to look.

## Linux

> **The distribution changed after this section was written.** Everything below was measured in
> `Ubuntu-24.04`, which has since been migrated into **Nyarch** and unregistered. The measurements
> are kept because they are still what was measured and the paths they name are the same; what
> changed is which distribution those paths live in. `tool/build_linux.sh` and
> `build_appimage.sh` now say `wsl -d Nyarch`, and `/opt/flutter` was carried across intact:
> `flutter --version` reports the identical revision, `9584c6713b`.

**The toolchain is installed, and the work is ready to run rather than blocked.** Measured in
Ubuntu-24.04 rather than assumed:

| | |
| --- | --- |
| **`/opt/flutter`** | **a native Linux SDK, fully provisioned** -- `linux-x64`, `linux-x64-profile` and `linux-x64-release` engine artifacts are all present, and so is `dart-sdk` |
| `clang`, `cmake`, `ninja`, `pkg-config`, `gcc`, `curl` | present |
| `gtk+-3.0` | 3.24.41, which is the one Flutter's Linux desktop build must have |
| free space in the distribution | 937 GB |
| `unzip` | missing, and Flutter's Linux setup can want it |

**`tool/build_linux.sh` already exists and is the way in**, and it documents the trap that makes
this target more than a command: `.dart_tool/package_config.json` holds *absolute* paths, and it
lives in the project tree, so the Windows and Linux sides share it and a `pub get` on either side
rewrites it for the other. The failure looks like broken source -- hundreds of errors about
Material widgets being undefined in a file that plainly imports them -- so the script begins with
`pub get` on the side doing the building, every time.

Two corrections to an earlier version of this file, both from measuring rather than reasoning:

1. It said the Linux engine artifacts were absent. That was true of the **Windows** SDK's cache
   and false of the machine: the native `/opt/flutter` has them, which is exactly why
   `build_linux.sh` defaults `FLUTTER_ROOT` to `/opt/flutter` and not to the mounted Windows copy.
2. It framed the target as "the next step" on the strength of that. It has now been run to
   completion: `flutter build linux --release` succeeded in Ubuntu-24.04 and
   `packaging/linux/build_appimage.sh` wrapped the bundle, so **all three targets exist**.

### `[WARN:COPY MODE]` in the window title is WSLg's, not ours

A window started from inside WSL can come up titled `[WARN:COPY MODE] Hollow Court (Nyarch)`, which
reads like the app failed. It is WSLg's own annotation, and WSLg's own log says so:

    RDP backend: enable_copy_warning_title = 1        <- WSLg turns this on itself
    RDP backend: use_gfxredir = 0                     <- no GPU graphics redirection
    rdp_allocate_shared_memory: Failed to open "/mnt/shared_memory/{uuid}"
        with error: Input/output error

and `/mnt/shared_memory` did not exist at all. With neither the shared-memory frame buffer nor
gfxredir, WSLg copies every frame and says so in the title.

**`wsl --shutdown` and start again clears it.** Afterwards the log reads `use_gfxredir = 1`, the
shared-memory failure is gone, and the title is plain `Hollow Court (Nyarch)`.
`/mnt/shared_memory` is still absent after the restart, so what recovered was gfxredir and not the
mount. `/etc/wsl.conf` is not involved; it contains nothing that disables a mount.

**It is not caused by this application, and not by the distribution.** The same prefix appeared on
an Ubuntu-24.04 window in this same session, before any migration, so it is a host-level WSL
condition that affects every GUI program equally.

#### And a separate thing that is the app's own, still unfixed

The launcher also logs

    libEGL warning: failed to get driver name for fd -1
    libEGL warning: MESA-LOADER: failed to retrieve device information

which is the GL stack failing to find a GPU device and falling back to software rendering. `/dev/dxg`
exists, `/usr/lib/wsl/lib` carries `libd3d12.so` and `libdxcore.so`, `ld.wsl.conf` registers that
path, and mesa ships `d3d12_dri.so` -- and an EGL/DRI2 screen still cannot be created. Measured
three ways:

| Launch | EGL/MESA warnings |
| --- | --- |
| default | 5 |
| `MESA_LOADER_DRIVER_OVERRIDE=d3d12 GALLIUM_DRIVER=d3d12` | 4, and different ones |
| `LIBGL_ALWAYS_SOFTWARE=1` | **0, clean start** |

So they are the noise of failed GPU attempts, and telling mesa not to try silences them.
**That is deliberately not baked into the AppImage or the .desktop file**: it would force software
rendering on machines that do have a working GPU path. It is a per-machine workaround, not a
default, and the app runs correctly either way.

### Three things about the AppImage that are not obvious

1. **`appimagetool` ships AS an AppImage**, so running it needs FUSE. As root it fails to mount
   itself, and `--appimage-extract-and-run` is the supported way round that -- it unpacks itself
   and runs, which is all that is wanted.
2. **The AppDir root holds the Flutter bundle as it is**, because `hollow_court` looks for `lib/`
   and `data/` beside itself. The usual AppImage layout would put the binary in `usr/bin` and
   break the launcher.
3. **The scratch AppDir is in `/tmp`**, which is inside the WSL distribution's virtual disk -- and
   that disk is `E:\DaShaoHuo\wsl\...`, so nothing lands on `C:`.

`appimagetool` itself is not on this machine and was fetched to `E:\DaShaoHuo\downloads`
through the local proxy, which is where downloads belong.

**After ANY Linux build, run `flutter pub get` on Windows before building Windows again.** That
is not advice, it is the other half of the shared file, and the README's two-operating-systems
section says the same thing from the other direction. It was done after this one, and the Windows
suite is green at 724.

### `make_manifest.sh`

    packaging/make_manifest.sh [bundle-dir]

Writes `MANIFEST.txt` next to the artifacts, recording the commit they came from. It **refuses to
run on a dirty tree**, because a manifest for artifacts built from a half-committed tree would
record a commit that does not describe them -- which is the same failure as the APK above, with
extra paperwork.

The rule it enforces is the cheap version of the one at the top of this section: instead of
remembering which build a success belonged to, the bundle says so.

### Receipts, because the timestamp check was also a proxy

The first version of `make_manifest.sh` asserted that every artifact came from `HEAD`. It was wrong
on its first run -- the MSI and the AppImage both predated the commit it named.

The second version compared each artifact's mtime against the commit time and marked rows
`ok`/`STALE`. That was **not wrong, but also not useful**: every row read STALE, because an
artifact recorded by a commit made after it was built can never satisfy the test. An alarm that
is always on is not a signal, and the reason it was always on is that mtime-versus-commit-time is
**another proxy** for "was this built from this source" -- the third one in this file.

So provenance is now **recorded at build time** instead of inferred afterwards:

    packaging/write_receipt.sh <artifact> [note]     # writes <artifact>.commit

Both build scripts call it at the end. `make_manifest.sh` reads the receipts:

| Receipt | Meaning |
| --- | --- |
| `ok` | the source this was built from **is** the source in the tree now |
| `src-dirty` | built from uncommitted source, so no commit fully describes it |
| `OTHER:<sha>` | built from different source -- rebuild it |
| `unrecorded` | no receipt. **Unknown, and unknown is not fine** -- unknown and fine are different words |

**And the receipt records `src-commit`, not `HEAD`.** That distinction is not pedantry: the first
version recorded HEAD, and the APK immediately read `OTHER:9ab486c` because a later commit had
changed one `echo` in the manifest script and not one compiled byte. `HEAD` is a proxy for "the
source that went into this artifact", and a commit that touches only docs moves HEAD while
changing nothing that is built. So the receipt names the last commit touching the paths the
artifact is actually built from, and the manifest **recomputes that from the same paths** and
compares. A docs-only commit leaves the verdict alone, which is the whole point.

The two failure modes this avoids, both of which were reached by accident on the way here:

| Version | Flaw |
| --- | --- |
| assert everything came from `HEAD` | **wrong immediately** -- the MSI and AppImage predated it |
| mtime vs commit time | **always STALE**, so the alarm was on permanently and therefore unreadable |
| verdict on `HEAD` | correct-looking, and quietly wrong in the safe-seeming direction |
| verdict on the source paths | decidable, and stable under commits that change no compiled byte |

`unrecorded` is the honest word for an artifact built before this mechanism existed, and it is
deliberately not the same as `ok`.
