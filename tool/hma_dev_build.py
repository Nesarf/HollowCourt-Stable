#!/usr/bin/env python3
"""Builds the development front end headlessly, and does not claim success without checking.

**What this wraps.** Unity drives a build from a command line through `-executeMethod`, which needs an editor script
(`Assets/Editor/BuildSetup.cs`) because the scene list lives in a settings file that is unpleasant to edit by hand. That
part is written; this is the part that makes it repeatable, since the first successful build was run by hand and a
command that only exists in somebody's history is not a build system.

**Where the output goes is decided by the repository's disk rules rather than by taste**: builds are products, and
products go under the downloads directory on E:, never on C:.

**And it verifies what it built.** A build that reports success and produces no executable, or one too small to be a
Unity player, is reported as a failure -- because the whole day has been about checks that pass while being wrong, and
`BuildPipeline` is perfectly capable of saying Succeeded about something nobody can run.

    python tool/hma_dev_build.py [--out DIR]
"""

from __future__ import annotations

import io
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
PROJECT = os.path.join(REPO, 'tool', 'hma-dev')
EDITOR = os.sep.join(['E:', 'Unity', 'Hub', 'Editor', '2022.3.22f1c1', 'Editor', 'Unity.exe'])
DEFAULT_OUT = os.sep.join(['E:', 'DaShaoHuo', 'downloads', 'hma-dev'])
LOG = os.sep.join(['E:', 'DaShaoHuo', 'cache', 'tmp', 'hma-dev-build.log'])

#: A Unity player is tens of megabytes before it does anything at all. Anything smaller than this did not build.
MINIMUM_BYTES = 20 * 1024 * 1024


def main(argv: list[str]) -> int:
    out = DEFAULT_OUT
    if '--out' in argv:
        index = argv.index('--out')
        if index + 1 < len(argv):
            out = argv[index + 1]

    if not os.path.isfile(EDITOR):
        print('  找不到 Unity 编辑器：%s' % EDITOR)
        return 1

    executable = os.path.join(out, 'hma-dev.exe')
    os.makedirs(out, exist_ok=True)
    environment = dict(os.environ, HMA_BUILD_OUT=executable)

    print('  → %s' % executable)
    result = subprocess.run([
        EDITOR, '-batchmode', '-quit', '-nographics',
        '-projectPath', PROJECT,
        '-executeMethod', 'BuildSetup.Build',
        '-logFile', LOG,
    ], env=environment, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=1800)

    log = io.open(LOG, encoding='utf-8', errors='replace').read() if os.path.isfile(LOG) else ''
    for line in log.split(chr(10)):
        if 'HMA build result' in line or 'error CS' in line:
            print('  %s' % line.strip()[:120])

    # **Verify the thing rather than the report about it.** The exit code and the summary are both capable of saying
    # success about an output nobody can run, so the size of what is on disk is the check that means something.
    if not os.path.isfile(executable):
        print('  ✗ 构建报成功，但 %s 不存在' % os.path.basename(executable))
        return 1
    size = os.path.getsize(executable)
    total = sum(os.path.getsize(os.path.join(base, name))
                for base, _, names in os.walk(out) for name in names)
    if total < MINIMUM_BYTES:
        print('  ✗ 整个产物只有 %d 字节 —— 一个 Unity 播放器不会这么小' % total)
        return 1

    print('  ✓ %s（%d 字节）' % (os.path.basename(executable), size))
    print('  ✓ 目录合计 %.1f MB' % (total / 1024 / 1024))
    print('  退出码 %d；日志 %s' % (result.returncode, LOG))
    return 0 if result.returncode == 0 else 1


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
