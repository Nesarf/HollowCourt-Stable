# hma-dev — the development front end

**This is the heavy half of HMA's two front ends** (`docs/HMA.md`, 三之二). The light half is `tool/hma.py`, which
somebody whose application has broken runs; this one is for somebody building on the product, and it is allowed to weigh
as much as a game engine **because the person installing it already has one**.

**Unity 2022.3.22f1c1**, which this machine already had. The project is deliberately the minimum the editor will open --
version file, package manifest, `.gitignore` -- because a project nobody has opened is a project nobody has verified,
and `Library/` is tens of thousands of generated files that must not enter a Flutter repository.

**It runs the same commands a person would.** `Assets/Scripts/Hma.cs` is the only place that knows where the tools are,
and every window goes through it, so there is no second implementation to drift: a fix to `hma.py` reaches this window
without being ported. `HmaDoctorPanel.cs` is the first window and the shape of the rest -- a button that runs a tool and
a panel that shows what it said, unparaphrased.

**Opened headlessly for verification**, which is how a project like this should be checked from a command line:

    "E:\Unity\Hub\Editor\2022.3.22f1c1\Editor\Unity.exe" -batchmode -quit -projectPath tool\hma-dev
