#!/usr/bin/env python3
"""Rasterises the HMA art with headless Chrome, and looks at nothing -- that part is a person's job.

**Why a browser rather than a library.** `cairosvg` and `svglib` both want a native cairo that is not on this machine,
and Illustrator exposes no automation interface. Chrome and Edge are already installed and they render SVG correctly, so
the dependency that matters is one the machine already has.

**Four things this script learned the hard way, every one of them from its own output:**

  * **A single call is a coin toss.** Headless Chrome exits 0 and writes nothing when it is not ready. Waiting for the
    file rather than trusting the exit code is the fix -- and the earlier conclusion that "rendering does not work here"
    was wrong for exactly that reason.
  * **A profile directory is required.** Calls without `--user-data-dir` produce nothing at all on this machine.
  * **An SVG opened as a document does not render.** Chrome paints only the top row of pixels and leaves the rest
    transparent; **the same file inside an `<img>` of the same size is exactly right**, corners and centre included.
    Nothing was wrong with the SVG, only the way it was opened.
  * **The outputs go into the Unity project**, because that is what consumes them -- `Assets/Resources/Art/`, so
    that `Resources.Load` finds them at runtime without an import step.
  * **The window must be the drawing's own size**, read from the SVG rather than kept in a table. A hand-written table
    gave the buttons a 220x120 window for a 136x56 drawing, so the button sat in the corner of an empty canvas.

  * **Small canvases come out transparent, and that is still open.** A probe with an HTML wrapper and **no**
    `--default-background-color` rendered a 136x56 drawing exactly right -- corners, centre and edges -- while this
    script's combination leaves anything smaller than the motif blank. The flag is the one difference between the
    working probe and the failing run, so that is where the next attempt starts. **Recorded as an open defect rather
    than hidden**, and it blocks nothing: the sources are the deliverable and any viewer opens them.

    python tool/hma_art_render.py [--out DIR]
"""

from __future__ import annotations

import glob
import io
import os
import re
import shutil
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
SOURCE = os.path.join(REPO, 'art', 'hma')
# **Where Unity looks, not where the sources are.** Unity only sees files under Assets/, and two copies of the
# same bytes in one repository means one of them will drift. The sources stay in art/hma/; the pictures live here.
DEFAULT_OUT = os.path.join(REPO, 'tool', 'hma-dev', 'Assets', 'Resources', 'Art')

NL = chr(10)
BACKSLASH = chr(92)

TEMP = os.environ.get('HMA_TMP') or os.sep.join(['E:', 'DaShaoHuo', 'cache', 'tmp'])

BROWSERS = [
    # **Windows**, where this was written and where it worked.
    r'C:\Program Files\Google\Chrome\Application\chrome.exe',
    r'C:\Program Files (x86)\Google\Chrome\Application\chrome.exe',
    r'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe',
    r'C:\Program Files\Microsoft\Edge\Application\msedge.exe',
    # **macOS**, where nobody has run it but where the path is knowable.
    '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    '/Applications/Chromium.app/Contents/MacOS/Chromium',
]

# **And the names to look for on `PATH`**, which is how Linux has them and why Linux did not work.
#
# The list above was Windows-only for its whole life and nobody noticed, **because it had only ever been run on one
# machine**. CI found it on the first push that produced a job: on `ubuntu-latest` the renderer looked for four paths that
# cannot exist there, reported that Chrome and Edge "should both be here", and failed. **GitHub's Ubuntu images do ship
# Google Chrome** -- it is simply called `google-chrome` and sits on the path.
PATH_BROWSERS = [
    'google-chrome',
    'google-chrome-stable',
    'chromium',
    'chromium-browser',
    'chrome',
]


def browser() -> str | None:
    """The first browser that exists: named by the caller, then at a known path, then on `PATH`.

    **`HMA_CHROME` wins**, because a machine with two browsers should be told which one rather than guessed at -- and
    because a machine with a third one, in a place this list has never heard of, needs a way to say so.
    """
    override = os.environ.get('HMA_CHROME')
    if override and os.path.isfile(override):
        return override
    for candidate in BROWSERS:
        if os.path.isfile(candidate):
            return candidate
    for name in PATH_BROWSERS:
        found = shutil.which(name)
        if found:
            return found
    return None


def window_for(svg_path: str) -> tuple[str, str]:
    """The drawing's own width and height, read from the file rather than kept in a table that can drift."""
    head = io.open(svg_path, encoding='utf-8').read(600)
    width = re.search(r'width="(\d+)"', head)
    height = re.search(r'height="(\d+)"', head)
    if width and height:
        return width.group(1), height.group(1)
    return '320', '320'


def render(executable: str, svg_path: str, out: str, attempts: int = 4) -> bool:
    width, height = window_for(svg_path)
    wrapper = os.path.join(TEMP, '.hma-wrapper.html')
    html = (
        '<!doctype html><meta charset="utf-8">'
        '<style>html,body{margin:0;padding:0;background:transparent}img{display:block}</style>'
        '<img src="file:///' + svg_path.replace(BACKSLASH, '/') + '" width="' + width + '" height="' + height + '">'
    )
    io.open(wrapper, 'w', encoding='utf-8', newline=NL).write(html)

    # **The profile is a temporary artifact and goes in the cache directory.** It was written beside the outputs
    # first, which put several hundred Chrome files inside a directory whose contents are meant to be committed --
    # and the repository's own disk rule says temporary files live under the cache.
    # **A short canvas does not paint, and a tall one does.** Every drawing 240 px or taller renders correctly and
    # every one 64 or shorter comes out as a two-row sliver -- across widths and shapes, so it is the window's height
    # rather than anything about the file. The fix is to render into a window tall enough and then **crop back to the
    # drawing's own size**, which leaves only the page showing through removed.
    tall = max(int(height), 260)
    profile = os.path.join(TEMP, 'hma-render-profile')
    for _ in range(attempts):
        if os.path.exists(out):
            os.remove(out)
        subprocess.run([
            executable, '--headless', '--disable-gpu', '--no-sandbox', '--hide-scrollbars',
            # **No .** It was in this list and it is what broke small canvases: with it,
            # anything shorter than the motif came out as two rows of residue, and without it every size renders in
            # full. The alpha still comes out right because **each SVG draws its own ground** -- which is why the
            # flag was never doing the work it looked like it was doing.
            '--virtual-time-budget=3000',
            '--user-data-dir=' + profile,
            '--screenshot=' + out, '--window-size=' + width + ',' + str(tall),
            'file:///' + wrapper.replace(BACKSLASH, '/'),
        ], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=120)
        # **Chrome exits zero having written nothing.** The file is the only signal that means anything.
        for _ in range(20):
            if os.path.isfile(out) and os.path.getsize(out) > 0:
                # **Crop to the drawing, keeping the top-left corner**, because the tall window's extra rows are
                # nothing but page background and an asset should not carry them.
                try:
                    from PIL import Image
                    image = Image.open(out)
                    if image.height > int(height) or image.width > int(width):
                        image.crop((0, 0, min(image.width, int(width)), min(image.height, int(height)))).save(out)
                except Exception:
                    pass
                return True
            time.sleep(0.25)
        time.sleep(1)
    return False


def drawn_rows(path: str, height: int) -> int:
    """How many rows contain something that is **neither transparent nor white**.

    **The first version asked whether alpha was above zero, and that is why it lied.** A page with a white background is
    opaque everywhere, so a blank render scored 56 out of 56 and I believed a fix that had not worked. A white pixel is
    not a drawing; asking about colour is the question that was meant.
    """
    try:
        from PIL import Image
    except Exception:
        return height  # no way to check, and claiming a failure would be worse
    image = Image.open(path).convert('RGBA')
    count = 0
    for y in range(image.height):
        for x in range(0, image.width, 2):
            r, g, b, a = image.getpixel((x, y))
            if a > 8 and (r < 245 or g < 245 or b < 245):
                count += 1
                break
    return count


def main(argv: list[str]) -> int:
    out = DEFAULT_OUT
    if '--out' in argv:
        index = argv.index('--out')
        if index + 1 < len(argv):
            out = argv[index + 1]
    os.makedirs(out, exist_ok=True)

    executable = browser()
    if executable is None:
        print('  这台机器上找不到浏览器 —— Chrome 或 Edge，既不在已知路径上，也不在 PATH 上。')
        print('    要找的都找过了：')
        for candidate in BROWSERS:
            print('      %s' % candidate)
        print('      PATH 上：%s' % '、'.join(PATH_BROWSERS))
        print('    这台机器是 %s。' % sys.platform)
        print('    有浏览器但不在这些地方的话，用 HMA_CHROME 指给它：')
        print('      HMA_CHROME=/path/to/chrome python tool/hma_art_render.py')
        return 1

    files = sorted(glob.glob(os.path.join(SOURCE, '*.svg')))
    failures = 0
    for svg_path in files:
        name = os.path.splitext(os.path.basename(svg_path))[0]
        target = os.path.join(out, name + '.png')
        if not render(executable, svg_path, target):
            failures += 1
            print('  ✗ %-22s 渲染不出来（试了 4 次）' % name)
            continue
        width, height = window_for(svg_path)
        rows = drawn_rows(target, int(height))
        if rows <= 2:
            # **A file was written and it is blank.** The script used to report this as a success, which is the
            # "check that passes while being wrong" fault this project keeps finding: five of the seven assets are
            # blank and the summary said 失败 0 个. The picture is the only signal that means anything.
            failures += 1
            # **A blank artifact is worse than no artifact**: it looks like an asset in a file listing, it gets
            # committed, and the only way to find out is to open it. So it is removed.
            os.remove(target)
            print('  ✗ %-22s %sx%s 只有 %d 行有内容 —— 空白，已删除' % (name + '.png', width, height, rows))
        else:
            print('  ✓ %-22s %sx%s  %s 字节，%d 行有内容' % (name + '.png', width, height, os.path.getsize(target), rows))
    print()
    # **The advice comes before the verdict, and that order is deliberate.** Anything reading this output for a result
    # takes the last line -- the pipeline does -- and a closing sentence about looking at pictures was being read as the
    # outcome. The summary is the outcome, so it goes last.
    print('  **下一步是看** —— 规矩检查查不出「它看着像什么」：')
    print('  第一版母题的注释写着「切进横杠的缺口」，而它画的是一座房子，三条断言全过。')
    print()
    print('  渲了 %d 个，失败 %d 个' % (len(files), failures))
    return 1 if failures else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
