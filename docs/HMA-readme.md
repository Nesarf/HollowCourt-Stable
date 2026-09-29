# HMA — Hollow Mixing Association

**A development platform for Hollow Court.** This branch is where it lives; `HC-Stable` is the application itself, and the two
are deliberately separate, because **a product should not have to carry a platform around with it.** Every change to a
development tool would otherwise become a change to the product.

HMA's job, in the owner's words, is 综合本机工具链，提高工程内自制比例 — **to gather what this machine can already do and
raise the share of the work the project does for itself.**

## The name

**HMA — Hollow Mixing Association.**

**Hollow** comes from the application it serves. **Mixing** is what a cellar is for. And **Association** is the register of
a governing body, which is the tone the platform wanted: not a toolkit, and not a service — **an association that a
project is a member of.**

**Where the name came from, in the owner's note, is two things.** The first is **URA**, a fictional racing association,
which is the register a governing body has and the tone this project's copy is already written in. The second is
**HMS Warspite**, the fast battleship whose name means "weary of war" and which fought in more actions than any other
ship of her navy, earning the nickname the Grand Old Lady. **A thing called war-weary that would not stop fighting is a
good name for a development platform**, and the irony is the part worth keeping.

**The real organisation behind the first of those is deliberately not cited.** An institution that exists now can answer
back, so naming it invites a relationship nobody asked for, while a fictional association and a historical ship cannot.
The rule the project applies is one sentence either way: **cite only what cannot be mistaken for an endorsement.**

## What it is made of

| Piece | What it does |
| --- | --- |
| **`tool/hma.py`** | `status` · `doctor` · `report` · `fix` · `models` · `ask` · `agent` — the light front end, for somebody whose application has broken |
| **`tool/hma_models.py`** | one call path to every model provider, and the persona that speaks through it |
| **`tool/hma_agent.py`** | the agent, with four read-only tools and a bounded loop |
| **`tool/hma-dev/`** | the development front end, in Unity — for somebody building on the product |
| **`tool/hma_art_check.py`** · **`tool/hma_art_render.py`** | the rules HMA's own art obeys, and the renderer that checks them |
| **`art/hma/`** | the sources: a wedge motif, three button states, a nine-slice panel, a wash and a divider |
| **`docs/HMA.md`** | the design, including what is still undecided |

## Two tiers of model access, and the first one costs nothing to run

**API keys are the default.** No VRAM, nothing to install, and any developer can use the platform on a laptop.

**A local model is an optional seam** for people who can drive a large model themselves — Ollama, vLLM, llama.cpp, any of
them, because **HMA only speaks the endpoint and does not care what is behind it.** The seam is deliberately left open and
the bridge is deliberately not shipped: whoever can run the model can point HMA at it in one line, and the concept is
documented in `docs/HMA.md`.

## Two front ends, because one window cannot serve both audiences

A bartender whose cellar has gone wrong needs something installable in an afternoon with no development environment on
the machine. A developer building on the product may have a game engine already. **A user will not install Unity to
troubleshoot a drink log**, so the light side stays light — a command line that reads, reports and repairs — and the heavy
side is where Unity lives.

## Running it

**A step-by-step page, every step of which has been run and whose output is real**: [`HMA-getting-started.md`](HMA-getting-started.md). It is written for somebody who has just cloned this branch and wants to know whether it works.


    python tool/hma.py doctor          # what is on this machine
    python tool/hma.py report          # a diagnostic bundle, without the log's contents
    python tool/hma.py fix             # dry run; add --apply to actually move anything
    python tool/hma.py models          # which providers are configured (keys are never printed)
    python tool/hma.py ask gemini "…"  # one question, one answer, in HMA's own voice

    python tool/hma_tests.py           # the tools' own tests

## What is not finished

**The art's short canvases used to render blank, and that is fixed.** Five of the seven pictures came out as a two-row
sliver because headless Chrome will not paint a very short window; the renderer now asks for a taller one and crops back.
The check that had said they were fine was asking whether a pixel was opaque, and a white page is opaque everywhere —
**a check that passed while being wrong**, which turned out to be the theme of the day it was found on.

**The rest is in `docs/HMA.md` under 还没定的** — kept as a list rather than as prose, so that a reader can tell what has
been decided from what has not.
