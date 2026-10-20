# HMA — from a clone to a working run

> **Every step on this page was run on this machine, and the output shown is real** (2026-09-27).
> **Why that is itself a quality method**: every fault actually found today was found by somebody running the
> thing once — looking at a picture is what showed the motif had become a house, running a build is what showed
> it starts, measuring pixels is what showed five renders were blank, and reading the push output is what showed
> the wrong branch had been pushed. **So "somebody else can follow this and it works" is not politeness. It is
> the method.**

## What you need

| | Required? | What for |
| --- | --- | --- |
| **Python 3.11+** | **required** | all six tools are standard library — the one exception is the row below |
| **Pillow** | **only for rendering the artwork** | `hma_art_render.py` uses it to count pixels and crop (`hma_art_check.py` does not need it) |
| **Unity 2022.3** | **only for building the development front end** | **none of the six tools needs it**, which is why the diagnostic side stays light |
| **An API key** | **only for `ask` and `agent`** | every step above them runs without one |

Measured on: `Python 3.14.7` with `Pillow 12.3.0`.

## Step 0: get it

    git clone -b HMA https://github.com/Nesarf/HollowCourt-Stable.git hma
    cd hma

**The `-b HMA` matters.** `main` is the product — the cellar itself — and `HMA` is this platform. The two share
one history but not one file set: the product is excluded on `HMA` (`lib`, `test`, `android`, `windows`, `linux`,
`assets`, `audio`, `packaging`).

## Step 1: ask it what state it is in

    python tool/hma.py status

**Run this one first.** It lists the six commands, its own test result, the three artwork rules, how many pieces
were rendered, and how many items remain outstanding — in one answer. **And it says plainly what it has *not*
run and why**: the product's Flutter suite is not among them, because it takes minutes and is not the question
this command exists to answer.

## Step 2: see what is on this machine

    python tool/hma.py doctor

Expected — and this output is from a real run:

```
你这家伙，果然没有人家不行呢~
先让本小姐看看这台机器上有些什么。

  ✓ 空庭的数据目录                Hollow Court
      名字是显示名（带空格），所以本小姐照实报，不猜
  ✓   Hollow Court 里的文件    display.json, preferences.json, sync-identity.json
      只列名字，不读内容——看病的不翻病人的信
  ✓ 文档目录                   …
  ✓ 事件日志（cellar.ndjson）    …
```

**If the cellar is not installed on this machine, it says so** — and that is correct rather than broken. It
reports what it can see.

*(The block above is a transcript rather than prose, so it is left exactly as the program prints it: those lines
are the tool's own wording, in the register `tool/hma_models.py` gives it, and rewriting them here would make the
page disagree with the terminal.)*

## Step 3: run its own tests

    python tool/hma_tests.py

Expected:

```
Ran 29 tests in 0.541s

OK
```

**29 tests, standard library only** — and several of them test the dangerous part: that `hma fix` writes nothing
at all without `--apply`, that the agent refuses to leave the repository (including through `docs/../..`), and
that the tool table is exactly those four read-only entries.

## Step 4: see which models are configured

    python tool/hma.py models

Expected — this runs whether or not anything has ever been configured:

```
  提供方        状态                        模型
  bailian      没有 key                     qwen-plus
  deepseek     没有 key                     deepseek-chat
  gemini       没有 key                     gemini-flash-latest
  local        留的缝（未填）                    —
```

**A key is never printed**; it reports only that one was found. There are three places a key may come from, and
none of them is this repository: an environment variable, a shared file, or each provider's own file.

**The shared file defaults to `E:\DaShaoHuo\auth\hma-keys.json`**, which is *this* machine's path. Somewhere else,
point `HMA_AUTH_DIR` at your own:

    export HMA_AUTH_DIR=~/.config/hma      # or anywhere else outside the repository

**And `local` reading 留的缝（未填） is a correct state rather than a defect.** The default tier is an API key —
no VRAM, usable by anybody — and the local model is the seam left open for somebody who can run one themselves.

## Step 5: the three artwork rules

    python tool/hma_art_check.py

Expected:

```
  检查了 7 个 SVG，问题 0 个
```

It checks three things: that each file is well-formed, that every polygon has five points (the motif is one
parameterised shape), and that only palette colours are used (one accent on one ground).

**It has already caught two real faults**: an illegal XML comment, and one of its own rules being drawn too
widely — a panel has no polygon by design.

## Step 6: render the artwork

    python tool/hma_art_render.py

Expected:

```
  ✓ button-disable.png     136x56  806 字节，56 行有内容
  …
  渲了 7 个，失败 0 个
```

**It verifies its own output when it finishes, and that was learned the hard way.** It used to report "0 failed"
while five of the seven were blank, because it was counting pixels with `alpha > 0` and a white page is opaque
everywhere. **It now asks whether there is any pixel that is neither transparent nor white** — because a white
pixel is not a drawing.

This step needs Pillow. Renders land in `tool/hma-dev/Assets/Resources/Art/`, because Unity only sees files under
`Assets/`.

## Step 7 (optional): build the development front end

    python tool/hma_dev_build.py

This needs Unity 2022.3.22f1c1. **The path in the script is this machine's** (`E:\Unity\Hub\Editor\…`), so
somewhere else it is one line to change. Measured output is 67 MB, landing in `E:\DaShaoHuo\downloads\hma-dev\`
— builds going to `downloads` is this repository's disk rule.

**And it has been trial-run rather than merely compiled**: `Player.log` shows the assemblies loading and input
initialising. **"It compiles and produced a file" and "it opens" are not the same claim**, which was confirmed
here too.

## When you want to change something

| To do this | Start here |
| --- | --- |
| Add a command | **a module in `tool/hma_commands/` that declares `COMMAND`** — it is found rather than registered, so nothing has to be edited to add one. The seven built-ins stay in `tool/hma.py`'s own table, because they are this platform's furniture rather than extensions to it. A module that will not import is reported and skipped, not fatal |
| Change what the agent may do | `TOOLS` and `HANDLERS` in `tool/hma_agent.py`, **and the assertion in `tool/hma_tests.py` at the same time** |
| Change a persona or a prompt | `CONTEXT` and `PERSONAS` in `tool/hma_models.py` |
| Change the artwork | `art/hma/*.svg` (the source) → `hma_art_render.py` → the Unity project |
| Change the artwork rules | the three assertions in `tool/hma_art_check.py` |
| See what is not done | `docs/TODO.md` and `docs/HMA.md` §四 |

## One rule for anybody changing code

**If you changed anything under `tool/`, run `python tool/hma_tests.py`.** It takes half a second for its 29
tests, and on its first run it caught a real bug: `load_keys` applied `str(v)` to every value, which destroyed
object-shaped configuration and would have sent a dictionary's `repr` as an API key.

> **A check that can only pass is worth less than one that has failed first.**
