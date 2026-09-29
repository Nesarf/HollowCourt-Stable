#!/usr/bin/env python3
"""One command that does what CI does, so that local and CI cannot drift apart.

**The reason this exists rather than a longer workflow file.** A pipeline written twice -- once in YAML for the server and
once in a shell history for the developer -- is two pipelines, and the one that runs is always the one that was written
last. So the workflow calls **this**, and this is the only place the steps are listed.

**And it says what it skipped, with the reason.** The quick set is seconds; rendering needs Pillow and the build needs
Unity and several minutes. A pipeline that silently did less than the reader expected would be the same fault as a status
command that hides what it did not check.

    python tool/hma_verify.py             # syntax, tests, art rules -- the fast set
    python tool/hma_verify.py --render    # and rasterise the art (needs Pillow)
    python tool/hma_verify.py --all       # and build the front end (needs Unity, minutes)
"""

from __future__ import annotations

import glob
import io
import os
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)

# **The extensions are compiled too**, or a broken one would be discovered by a user rather than by this.
EXTENSIONS = sorted(glob.glob(os.path.join(HERE, 'hma_commands', '*.py')))

TOOLS = [
    'hma.py', 'hma_models.py', 'hma_agent.py',
    'hma_art_check.py', 'hma_art_render.py', 'hma_dev_build.py',
    'hma_tests.py', 'hma_verify.py',
]


# **The stages, named once.** A caller can ask for one of these with `--stage`; CI does, because a step name is
# the only part of a GitHub Actions failure that is readable without a token.
STAGES = ('syntax', 'tests', 'art', 'render', 'build', 'product')


def step(label: str, arguments: list[str], timeout: int = 900) -> tuple[bool, str]:
    """Runs one step and returns whether it passed, with the line that says why."""
    started = time.time()
    try:
        done = subprocess.run([sys.executable, *arguments], capture_output=True, text=True,
                              encoding='utf-8', errors='replace', cwd=HERE, timeout=timeout)
    except Exception as error:
        return False, str(error)[:90]
    # **Both streams**, because `unittest` writes its verdict to stderr -- which is how the status command once printed an
    # empty result for a passing suite.
    both = (done.stdout or '') + chr(10) + (done.stderr or '')
    lines = [line.strip() for line in both.split(chr(10)) if line.strip()]
    # **The last line is not always the verdict.** The renderer ends with advice about looking at the picture,
    # so the line that says what happened is chosen rather than assumed.
    wanted = ('渲了', 'Ran ', 'OK', '问题', '失败', 'passed', '全过', '✓')
    preferred = [line for line in lines if any(key in line for key in wanted)]
    tail = (preferred[-1] if preferred else (lines[-1] if lines else '（没有输出）'))
    seconds = time.time() - started
    return done.returncode == 0, '%s  （%.1f 秒）' % (tail[:76], seconds)


def main(argv: list[str]) -> int:
    do_render = '--render' in argv or '--all' in argv
    do_build = '--all' in argv

    # **One stage by name, for a caller that needs to know which one broke.** See the module docstring: a red step says
    # which stage it was, and the list of stages still lives only here.
    only = None
    for index, argument in enumerate(argv):
        if argument == '--stage' and index + 1 < len(argv):
            only = argv[index + 1]
    if only is not None and only not in STAGES:
        print('  不认识的阶段：%s' % only, file=sys.stderr)
        print('  有的是：%s' % '、'.join(STAGES), file=sys.stderr)
        return 2
    wants = (lambda name: only is None or only == name)

    results: list[tuple[str, bool, str]] = []

    # ① can the tools even be parsed
    if wants('syntax'):
        problems = []
        for name in TOOLS + [os.path.join('hma_commands', os.path.basename(p)) for p in EXTENSIONS]:
            path = name if os.path.isabs(name) else os.path.join(HERE, name)
            if not os.path.isfile(path):
                continue
            code = subprocess.run([sys.executable, '-m', 'py_compile', path],
                                  capture_output=True, text=True)
            if code.returncode != 0:
                problems.append(name)
        results.append(('语法', not problems,
                        '全部通过 ✓' if not problems else '写坏了：%s' % '、'.join(problems)))

    # ② the tools' own tests -- the thing that catches most of what a change breaks
    if wants('tests'):
        ok, note = step('测试', [os.path.join(HERE, 'hma_tests.py')])
        results.append(('工具测试', ok, note))

    # ③ the art obeys its own three rules
    if wants('art'):
        ok, note = step('美术规矩', [os.path.join(HERE, 'hma_art_check.py')], timeout=240)
        results.append(('美术规矩', ok, note))

    # ④ optional: rasterise, which needs Pillow and a browser
    if wants('render'):
        if do_render:
            ok, note = step('渲染', [os.path.join(HERE, 'hma_art_render.py')], timeout=900)
            results.append(('美术渲染', ok, note))
        else:
            results.append(('美术渲染', True, '跳过 —— 加 --render（需要 Pillow 与一个浏览器）'))

    # ⑤ optional: build the front end, which needs Unity and several minutes
    if wants('build'):
        if do_build:
            ok, note = step('构建', [os.path.join(HERE, 'hma_dev_build.py')], timeout=2400)
            results.append(('前端构建', ok, note))
        else:
            results.append(('前端构建', True, '跳过 —— 加 --all（需要 Unity，数分钟）'))

    # ⑥ the product, when this checkout is the product's
    if wants('product'):
        if os.path.isfile(os.path.join(REPO, 'pubspec.yaml')):
            results.append(('产品 Flutter', True,
                            '**没有跑** —— 它要几分钟，而且这条命令的职责是 HMA 自己；'
                            '要跑就 `flutter test`'))
        else:
            results.append(('产品 Flutter', True, '不适用 —— 这是 HMA 分支的检出，没有 pubspec.yaml'))

    failed = [name for name, ok, _ in results if not ok]
    print()
    for name, ok, note in results:
        print('  %s %-12s %s' % ('✓' if ok else '✗', name, note))
    print()
    if failed:
        print('  %d 项没过：%s' % (len(failed), '、'.join(failed)))
        return 1
    if only is not None:
        print('  这一阶段过了 ✓')
        return 0
    print('  全过 ✓ —— 而这一步本身与 CI 跑的是同一条命令，所以两边不会走偏。')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
