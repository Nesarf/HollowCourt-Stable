# Tools

Scripts that do work *on* this project or *for* it, kept together so the next session does not rewrite one. Each
file's own header says why it exists and what it got wrong first; this page is the index, and the rule for it is
the same as everywhere else here -- **a line that is not true is worse than no line**.

## The name of the platform these tools belong to

**HMA — Hollow Mixing Association.** The development platform around this project is called HMA: *Hollow* from the
product's own name, *Mixing* for what the application is about and for what the platform does with the machine's
toolchain, and *Association* for the register.

**The register is borrowed on purpose, and the owner's note on where the name came from names two things**: **URA**
— a fictional racing association, which is the register a governing body has and the tone this application's copy is
already written in — and **HMS Warspite**, the fast battleship whose name means "weary of war" and which fought in more
actions than any other ship of her navy, earning the nickname the Grand Old Lady. **A thing called war-weary that would
not stop fighting is a good name for a development platform**, and the irony is the part worth keeping.

**The real organisation behind the first of those is deliberately not cited**, on the owner's reasoning of 2026-09-26:
**an institution that exists now can answer back**, so naming it invites a relationship nobody asked for, while a
fictional association and a historical ship cannot — **even though the ship appears in a game that is still running, the
exposure is not comparable, because the exposure is about who can answer.** The principle the project applies is the
same one either way: cite only what cannot be mistaken for an endorsement.

**Naming these two is the one place this project allows a source to be named**, and it is allowed because **the origin
of a name is exactly what a name owes to its sources**. Everywhere else describes a genre rather than a work — which is
why the art direction in `docs/HMA.md` says "a rhythm game" where a study note would say the title.

**HMA is not a product; it is the ground this project is built on, and it travels with it.** The owner's decision of
2026-09-26 is that these tools ship **inside** the Hollow Court repository, for two audiences:

* **Somebody whose installation has gone wrong.** HMA is what they can reach for — and most of the checking is
  already in the application itself, in 设置 → 检查完整性 (`lib/ui/integrity_section.dart`), which reads the event log
  and lists what it finds rather than making the reader guess. The tools here are for the cases the screen cannot
  reach: a build that will not start, a missing seed, a `.courtpack` that will not import.
* **Somebody building on this project rather than using it** — a side branch, a different drink, a similar product.
  That is a larger audience than it sounds: the same packaging, the same audit scripts and the same publishing
  pipeline are the parts of a project that are almost never written down, and here they are in the repository
  already.

**HMA's default persona is Charlotte -- 伊丽莎白.** The owner's decision of 2026-09-26: when this platform speaks, it
speaks as her, and her documents under `docs/art/` are therefore not only a character's paperwork but the platform's
own default register. She was designed as an LLM-usable agent before she was anything else, so the two readings of her
-- the app's voice and a development platform's manner -- are the same document read for two purposes.

**And it is meant to be portable, so here is what is not yet.** Ten files name this machine's own paths; most of
them already take an override with this machine as the fallback, which is why the work left is documentation rather
than code:

| Set this | To | Used by |
| --- | --- | --- |
| `FLUTTER_BIN` | a Flutter SDK's `bin` | `tool/probe.sh`, `packaging/android/build.sh` |
| `ANDROID_SDK` | an Android SDK | `packaging/android/build.sh` |
| `ADB` | `platform-tools/adb` | `tool/capture_screens.sh`, `tool/phone-content-copy.sh` |
| `WORK` | a scratch directory | `tool/publish_public.sh`, `tool/push_public.sh` |

**The rule the name carries** is the one the owner stated on 2026-09-26 when he refused a dependency for a
four-line feature: **if it can be done with what is already here, do not reach for somebody else's.** It is the
same discipline the project applies to its own assets and its own copy, and it is why `about_section.dart` opens a
browser with `dart:io` and a `MethodChannel` rather than with `url_launcher`.

## The application

| Tool | What it does |
| --- | --- |
| `l10n_status.dart` | `dart run tool/l10n_status.dart`: how much of the interface is translated, per language, as a number. A counter rather than a test, on purpose -- a test that always fails until 400 strings are done teaches people to ignore it. |
| `sync_probe.dart` | Drives the production sync code from a command line, so two real processes on two real machines can meet without anybody clicking anything. |
| `probe.sh` | Runs `sync_probe.dart` with the package config this platform needs (the Windows tree and the WSL tree share `.dart_tool/package_config.json`, and one of them is always wrong for the other). |
| `generate_chinese_variants.py` | Adds 港繁 and 台繁 to every `CopyLine` that has a 简中 line, converting with OpenCC rather than falling back. Python in a Dart repository because the conversion needs OpenCC's table set; needs `PYTHONPATH=E:/DaShaoHuo/Python/opencc_lib`. |
| `traditional_wording_audit.py` | The 繁体措辞复核 of DESIGN.md 12.4.2: flagged glyphs and mainland vocabulary in the `zh-HK`/`zh-TW` lines. Its first check was wrong on 17 of its first 18 hits (`台 → 臺` is a variant, not a defect) and the whitelist that separates them is a claim, not a fact. |
| `ja_audit.py` | Audits the Japanese for the defects a machine can see. Not a substitute for a native reader, and it does not claim to be one; all three of its checks were wrong once and the corrections are recorded in the file. |
| `build_linux.sh` | Builds the Linux target, from inside WSL (`wsl -d Nyarch -e bash tool/build_linux.sh`). |

## a rhythm game (`.csb`, cocos2d-x)

`.csb` is FlatBuffers and cocos2d-x's `CSParseBinary` schema is MIT, so this half is fully readable.

| Tool | What it does |
| --- | --- |
| `csb_dump.py` | Walks a `.csb` **without** its schema -- FlatBuffers names nothing on the wire, but every table points back at its vtable, which is enough for structure. |
| `csb_geometry.py` | Reads geometry once the field order is known, from `CSParseBinary_generated.h`: `WidgetOptions` 0:name 7:position 8:scale 9:anchorPoint 10:color 11:size. |
| `csb_viewer.py` | Draws a layout as a picture. This is the point of the exercise: a picture is how spacing, alignment and overlap get studied. |
| `batch_views.py` | Renders every layout in the extracted assets and writes an index. A file rather than a shell heredoc, because this session lost `\n`, `\a` and `\` to the shell's handling of backslashes. |
| `capture_screens.sh` | Captures every distinct screen a rhythm game shows while somebody taps through it; the screenshot is hashed **on the phone** so only changed frames are pulled. |

## a mobile game (Unity, IL2CPP, NGUI)

| Tool | What it does |
| --- | --- |
| `ba_ui_export.py` | Exports UI textures, **one bundle per asset path -- the newest**, because the bundles carry both the original asset path and the build date. |
| `ba_prefab_layout.py` | The first prefab reader, looking for uGUI fields. **Superseded** by `ba_prefab_tree.py` and kept as the record of what was tried: it reports "no root rect transforms" on a bundle holding 727 GameObjects, which is the reader being wrong rather than the layer being absent. |
| `ba_prefab_tree.py` | Walks a prefab's node tree for real: plain `Transform`s linked to their GameObjects **by the back-reference**, `m_LocalPosition` accumulated down the chain, rigs scaled x100 skipped, and the component **field shapes** reported because the class names are not in the bundle (IL2CPP). |

## a mobile game (Unity)

| Tool | What it does |
| --- | --- |

## Character models (VRM / PMX / Blender / Unity)

| Tool | What it does |
| --- | --- |
| `model_inventory.py` | Counts what a model holds: `.vrm` (glTF 2.0, no dependency), `.pmx` (binary, community-specified) and `.unitypackage` (a gzipped tar). **Three of its readings were wrong first and are recorded in the header**: materials carry two name fields and not four, the IK block exists and its angle limit is 24 bytes, and a morph's offset size is a count of records rather than a number of bytes. |
| `blend_probe.py` | The same counts for `.blend` and `.fbx`, by opening them in **Blender in background mode** -- because a `.blend` is an application's memory dump, not a format with a specification, and an FBX importer already exists. |

## Operations

| Tool | What it does |
| --- | --- |
| `phone-content-copy.sh` | Copies an app's content directory off a phone in **one stream** (`tar` on the device plus a single `adb pull`), because 44,673 individual pulls pay a per-file cost. Proven at 11.56 GiB, verified path by path. |
| `watermark_check.py` | Runs DESIGN.md §20.4.1's watermark check over an asset set: **names, container metadata, sidecar markers, and every byte on request**. It reports and does not judge -- a clean check says nothing about what the licence permits. |

## Conventions these follow

- **Logic in English**, comments and headers in English; the repository's own interface text is the only thing
  that carries other languages.
- **A tool's header records what it got wrong first.** Several of these had a wrong first version, and the
  correction is the part worth keeping: `csb_viewer.py` read scalars as offsets until bounds guards were added,
  `ba_prefab_layout.py` searched for a field set the game does not use, and `ja_audit.py` had all three of its
  checks wrong before they were right.
- **Extraction never runs twice.** `downloads/` holds archives and `tools/` holds extracted trees; check both
  before unpacking anything, because extracting Ghidra and AssetRipper a second time cost about 1 GB of
  duplicates.
- **Backslashes are hostile here.** This is git-bash on Windows: heredocs and Python literals have eaten `\n`,
  `\a` (which became a real BEL byte inside a document, twice) and lone backslashes. Write a file; do not build
  one through the shell.
