#!/usr/bin/env python3
"""Cuts a release: bumps the version, gates it, publishes, tags the published commit, and reports what is left.

**Dry run unless `--apply`**, which is the rule `hma fix` set and `keep_bundle.py` follows. A release is the one operation
in this repository that touches the public mirror, so it is the last place to act on a keystroke.

    python tool/release.py --version 1.0.1+1021            # say what would happen
    python tool/release.py --version 1.0.1+1021 --apply    # and do it

**The version is required and never guessed.** `pubspec.yaml` carries two things -- `1.0.0` is what a reader sees and
`+1020` is the build -- and deciding whether the next one is `1.0.1` or `1.0.0` is a judgement about what changed, which is
exactly the kind of judgement a script should not invent. See `docs/CHANGELOG.md`.

**Why the tag is made after publishing rather than before.** The mirror is a synthetic history: `publish_public.sh` builds
one snapshot commit and force-pushes it, so its SHA has nothing to do with any local commit and a tag made here first would
point at something that does not exist there. This fetches what was actually published and tags that.

**And the release itself needs a token, which this script does not have and does not go looking for.** `gh` is not installed
on this machine and the push credential lives in the Windows credential manager, which is not this program's business. So
the step that needs the API is attempted only when `GITHUB_TOKEN` is in the environment, and otherwise the script says
exactly what remains and stops -- **a release that silently stopped one step short would be worse than one that said so.**
"""
from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys

# **The one definition of "this paragraph is not for readers".** `sanitise_public.py` owns the
# markers and the snapshot path already runs it; the release notes are the other path that publishes
# this file's words, and until now it went out unfiltered. `release.py` is run from `tool/`, so this
# import finds its neighbour without a path dance.
import sanitise_public

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
PUBLISH = os.path.join(HERE, 'publish_public.sh')
VERIFY = os.path.join(HERE, 'hma_verify.py')
PUBSPEC = os.path.join(REPO, 'pubspec.yaml')
BUNDLE = os.path.join('E:' + os.sep, 'Hollow Court Bundle')
REMOTE = 'https://github.com/Nesarf/HollowCourt-Stable.git'
VERSION = re.compile(r'^\d+\.\d+\.\d+\+\d+$')


def run(arguments: list[str], **kwargs) -> subprocess.CompletedProcess:
    return subprocess.run(arguments, cwd=REPO, capture_output=True, text=True,
                          encoding='utf-8', errors='replace', **kwargs)


def current_version() -> str:
    for line in io_lines(PUBSPEC):
        if line.startswith('version:'):
            return line.split(':', 1)[1].strip()
    return ''


def io_lines(path: str):
    with open(path, encoding='utf-8') as handle:
        return handle.read().split(chr(10))


def set_version(version: str, apply: bool) -> None:
    lines = io_lines(PUBSPEC)
    for index, line in enumerate(lines):
        if line.startswith('version:'):
            lines[index] = 'version: %s' % version
            break
    if apply:
        with open(PUBSPEC, 'w', encoding='utf-8', newline=chr(10)) as handle:
            handle.write(chr(10).join(lines))
        print('  ✓ pubspec.yaml 的版本改成 %s' % version)
    else:
        print('  · 会把 pubspec.yaml 的版本从 %s 改成 %s' % (current_version(), version))


def gh_path() -> "str | None":
    """`gh`, wherever it is. **A freshly installed one is not on this shell's PATH.**

    That is not a guess: it is how this was found. Installed through winget, working, and invisible to `command -v`,
    because the shell that ran the check had been started before the installer wrote the new entry.
    """
    found = shutil.which('gh')
    if found:
        return found
    candidates = [
        os.path.join(os.environ.get('ProgramFiles', r'C:\Program Files'), 'GitHub CLI', 'gh.exe'),
        os.path.join(os.environ.get('ProgramFiles(x86)', r'C:\Program Files (x86)'), 'GitHub CLI', 'gh.exe'),
        os.path.join(os.environ.get('LOCALAPPDATA', ''), 'Programs', 'GitHub CLI', 'gh.exe'),
        '/usr/bin/gh',
        '/usr/local/bin/gh',
    ]
    for candidate in candidates:
        if candidate and os.path.isfile(candidate):
            return candidate
    return None


def gh_logged_in(gh: str) -> bool:
    done = subprocess.run([gh, 'auth', 'status'], capture_output=True, text=True,
                          encoding='utf-8', errors='replace', timeout=120)
    return done.returncode == 0


def notes_for(version: str) -> "str | None":
    """The public changelog's section for this version, so the page and the file are one text.

    **Two copies of the same words drift**, and the copy that gets read is the one on the release page. Taking them from
    the file means there is one place to write them and one place to fix them.
    """
    path = os.path.join(REPO, 'docs', 'CHANGELOG-public.md')
    if not os.path.isfile(path):
        return None
    # **Why the public file and not this repository's own.** `docs/CHANGELOG.md` is written for whoever
    # is working on the project: it says who decided what, which tool enforces it, what went wrong last
    # time, and it marks all of that with check and cross marks. The release page is read by somebody who
    # wants to know what the download is. A round ago four of those internal sentences and several hundred
    # marks were published by accident, and the fix for that is not a filter -- it is a different file.
    # This reads `docs/CHANGELOG-public.md`, which is written for a reader in the first place.
    #
    # **A version with no public section gets no notes rather than falling back to the internal text.**
    # An empty release page is a nuisance; a page that republishes the project's own conversation is not.
    with open(path, encoding='utf-8') as handle:
        text = handle.read()
    marker = '## %s ' % version
    start = text.find(marker)
    if start < 0:
        return None
    end = text.find(chr(10) + '## ', start + 1)
    section = text[start:end if end > 0 else len(text)]
    # **The same filter the snapshot runs, applied to the text that leaves as release notes.** An
    # `<!-- internal -->` block is a paragraph written for this repository and not for a reader: it says who
    # decided what, which tool enforces it, and what went wrong last time. Every one of those is worth keeping
    # in the changelog and none of them belongs on a download page -- see `docs/TODO.md` section 九 for the
    # round that found four of them published.
    return sanitise_public.INTERNAL_BLOCK.sub('', section).strip()


def newest_assets(version: str = '') -> "list[str]":
    """This version's artifacts, from the bundle.

    **It used to pick the newest `1.0.*` FOLDER and take everything in it, which would have attached the
    wrong files to a release.** The folders in the bundle are the rounds that predate the flat layout --
    `1.0.0+2184` is still sitting there -- while the packaging scripts now write into the bundle root, so
    "the newest folder" was a round from days earlier and this round's files were beside it, unread. A
    release whose page names one version and whose downloads are another is precisely the fault the
    receipt check below exists to catch, arriving through the front door instead.

    So it matches on the version being released rather than on timestamps. `version` is the pubspec pair,
    `1.0.0+2880`, and the artifacts name themselves two ways: the application's files use the four-part
    form (`1.0.0.2880`) and the installer the three-part one (`1.0.2880`), because Windows Installer
    compares only three fields. Both are accepted, and both layouts -- the root and a per-version folder --
    are searched, so the older rounds keep working and a future change of mind does too.
    """
    if not os.path.isdir(BUNDLE):
        return []
    build = version.split('+')[-1] if version else ''
    marks = ['1.0.0.%s' % build, '1.0.%s' % build] if build else []
    found = []
    for name in sorted(os.listdir(BUNDLE)):
        path = os.path.join(BUNDLE, name)
        if os.path.isdir(path):
            if marks and not any(mark in name for mark in marks):
                continue
            found += [os.path.join(path, n) for n in sorted(os.listdir(path))
                      if not n.endswith(('.commit', '.wixpdb'))]
            continue
        # **`.wixpdb` is a companion, not an artifact.** It is WiX's debug-symbol file for the installer
        # and its own receipt says "never shipped": it maps a crash report back to source, and a reader
        # downloading an application has no use for it. Left in, it would appear on the release page as a
        # fifth download whose name looks like the installer's.
        if name.endswith(('.commit', '.wixpdb')) or name == 'MANIFEST.txt':
            continue
        if not name.startswith('hollow-court-'):
            continue
        if marks and not any(mark in name for mark in marks):
            continue
        found.append(path)
    return found


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description='cut a release')
    parser.add_argument('--version', required=True, help='the new version, as X.Y.Z+NNN')
    # **`HC-Stable`, because the owner renamed the product branch on 2026-09-30 and it had been `main`.** This default
    # is not cosmetic: a release that tagged `main` would fetch a branch that no longer exists, find nothing, and put
    # the tag nowhere -- and the tag is the artifact that says which snapshot shipped.
    parser.add_argument('--branch', default='HC-Stable', help='the mirror branch (default: HC-Stable)')
    parser.add_argument('--tag', default='', help='the tag to create (default: the version without its build number)')
    parser.add_argument('--apply', action='store_true', help='actually do it')
    parser.add_argument('--skip-verify', action='store_true', help='do not run the pipeline first')
    args = parser.parse_args(argv)

    # **The tag carries the build number, and a leading `v`.** The rule this replaces said a tag should hold only
    # the version, "or every URL mentioning it carries a plus sign" -- and that is a reason about the plus, not
    # about the build number: `v1.0.0.2184` has no plus, and a dot needs no escaping anywhere a tag appears. So
    # the separators differ by reader rather than by rule -- pubspec joins with `+`, while the artifact name and
    # the tag use `.` -- and the `v` is what this repository's own earlier tags used before it went missing.
    tag = args.tag or ('v' + args.version.replace('+', '.'))

    if not VERSION.match(args.version):
        print('  版本要写成 X.Y.Z+构建号，例如 1.0.1+1021；收到的是 %r' % args.version, file=sys.stderr)
        return 2

    print('  ── 发布 %s 到 %s 的 %s 分支 ──' % (args.version, REMOTE, args.branch))
    print()

    # ① a dirty tree makes the snapshot meaningless, which is the manifest's own rule
    status = run(['git', 'status', '--porcelain']).stdout.strip()
    if status:
        print('  工作树不干净，发布出来的快照就没有意义：')
        for line in status.split(chr(10))[:8]:
            print('    %s' % line)
        print()
        print('  先把它们提交或收起来。这条规矩来自 MANIFEST.txt 自己的一句话：')
        print('    「A dirty tree makes this file meaningless, so it refuses to write one.」')
        return 1
    print('  ✓ 工作树干净')

    # ② the version, which is the one thing this will not decide
    before = current_version()
    print('  · 版本：%s → %s' % (before, args.version))
    if before == args.version:
        # **A warning, not a refusal.** The version not changing means no new build was made; it does not mean this
        # version has been released, and for a first release it is the normal case -- the artifacts and the version
        # already agree. What stops a second release of the same version is the tag below, which is a fact about what
        # was published rather than about what changed.
        print('  · 版本没变 —— 没有新的构建，但这个版本还没发布过。拦它的是标签，不是这一行。')

    # **The artifacts and the version have to agree.** A release whose name says one build and whose files say another is
    # a mismatch nobody notices until somebody downloads it.
    #
    # The version is read out of the artifact's own FILE NAME rather than out of its folder, which is what
    # this used to do: with the per-version folders gone the folder is the bundle root, whose name is the
    # same for every round, so the check would have compared "Hollow Court Bundle" against "1.0.0+2880" and
    # refused every release. An artifact's name is the thing that goes on the download page, so it is also
    # the honest thing to check.
    assets = newest_assets(args.version)
    if assets:
        names = [os.path.basename(path) for path in assets]
        build = args.version.split('+')[-1]
        agreeing = [n for n in names if build in n]
        if len(agreeing) != len(names):
            odd = [n for n in names if n not in agreeing]
            print('  ! 这些产物文件名里没有 %s：%s' % (build, ', '.join(odd)))
            print('    要么先把这一版的产物构建出来，要么把版本号写成产物那一版。')
            return 1
        print('  ✓ %d 个产物与版本一致（%s）' % (len(names), '1.0.0.%s' % build))

    # ②b **the receipts, which say which source each artifact was built from.**
    #
    # The check above reads the artifact's *name*. This reads what it was built from, and they are different questions:
    # on 2026-09-29 a release went out whose folder said 1.0.0+1020, whose pubspec said 1.0.0+1020, and whose code was 154
    # commits behind HEAD and 37 behind the commit that withdrew a feature the release notes described as withdrawn. The
    # name agreed with everything and the truth was in the file this function used to skip.
    if assets:
        head = run(['git', 'rev-parse', 'HEAD']).stdout.strip()
        stale = []
        for path in assets:
            receipt = path + '.commit'
            origin, paths = '', ''
            if os.path.isfile(receipt):
                with open(receipt, encoding='utf-8') as handle:
                    for line in handle:
                        if line.startswith('head'):
                            origin = line.split(':', 1)[1].strip()
                        elif line.startswith('src-paths'):
                            paths = line.split(':', 1)[1].strip()
            if not origin:
                stale.append((os.path.basename(path), '（没有回执）', ''))
                continue
            # **Not "must equal HEAD".** An artifact says which paths it was built from, and a later commit that touches
            # nothing in that list leaves the artifact faithful -- so the question is whether those paths changed between
            # the receipt's commit and now. Demanding equality would refuse every artifact after a documentation commit,
            # which is the same class of wrong answer as accepting one whose source is 154 commits old: both are decided by
            # the wrong field.
            if not paths:
                changed = run(['git', 'diff', '--quiet', origin, head]).returncode != 0
            else:
                changed = run(['git', 'diff', '--quiet', origin, head, '--'] + paths.split()).returncode != 0
            if changed:
                stale.append((os.path.basename(path), origin[:12], paths))
        if stale:
            print('  ! 产物不是从当前源码构建的：')
            for name, origin, paths in stale:
                print('      %-46s 来自 %s' % (name[:46], origin))
            print('      HEAD 是 %s' % head[:12])
            print()
            print('    一个来自别的提交的产物，不是「小一点的发布」，而是**名字相同的另一个程序**。')
            print('    重建它：bash packaging/android/build.sh ／ bash packaging/windows/build.sh')
            print('    想看它落后多远：bash tool/staleness.sh')
            return 1
        print('  ✓ 产物声明的路径，从它们的提交到 HEAD 都没变过（HEAD %s）' % head[:12])

    # ③ the tag must not already exist
    existing = run(['git', 'tag', '--list', tag]).stdout.strip()
    if existing:
        print('  ! 本地已经有 %s 这个标签了。' % tag)
        return 1
    print('  ✓ 标签 %s 还不存在' % tag)

    # ④ the pipeline, because a release that fails its own checks is not a release
    if args.skip_verify:
        print('  · 跳过了流水线（--skip-verify）—— 这次发布没有经过检查')
    else:
        print('  · 跑流水线（一条命令，和 CI 跑的是同一条）')
        if args.apply:
            done = run([sys.executable, VERIFY, '--render'], timeout=1800)
            tail = [line for line in (done.stdout or '').split(chr(10)) if line.strip()]
            print('    %s' % (tail[-1] if tail else '（没有输出）'))
            if done.returncode != 0:
                print('  ✗ 流水线没过，发布停下。')
                return 1
        else:
            print('    · 会跑 python tool/hma_verify.py --render')
            print('    · 它不过就停下')

    # ⑤ everything destructive below this line
    if not args.apply:
        print()
        print('  会做的剩下这些：')
        print('    · 把 pubspec.yaml 的版本写成 %s' % args.version)
        print('    · 提交这一行')
        print('    · bash tool/publish_public.sh --push   （建快照、净化、快进推 %s）' % args.branch)
        print('    · git fetch origin %s，然后在**它**那个提交上打标签 %s' % (args.branch, tag))
        print('    · git push origin %s' % tag)
        print('    · 用 gh 建一个 release，说明取自 docs/CHANGELOG.md 里这一节')
        print('    · gh 没装或没登录，就停下来说清是哪一种、以及还剩哪一步')
        print()
        print('  这是演练 —— 一个字都没动。要真做就加 --apply。')
        return 0

    # ⑥ the version, written and committed
    set_version(args.version, apply=True)
    run(['git', 'add', 'pubspec.yaml'])
    done = run(['git', '-c', 'commit.gpgsign=false', 'commit', '-q', '-m',
                'version: %s' % args.version])
    if done.returncode != 0:
        # **A first release is the normal case for this.** The version already in `pubspec.yaml` and the artifacts in the
        # bundle can agree perfectly -- that build is what is being released -- and then there is no line to change and
        # nothing to commit. Failing here would refuse a release for having nothing to do.
        if 'nothing to commit' in (done.stdout + done.stderr) or 'nothing added' in (done.stdout + done.stderr):
            print('  · 版本那一行本来就是 %s，没有要改的' % args.version)
        else:
            print('  ✗ 提交版本那一行失败了：%s' % (done.stderr or done.stdout)[:200])
            return 1
    else:
        print('  ✓ 提交了版本号')

    # ⑦ publish
    print()
    print('  · 发布（这会在镜像的 %s 上追加一个快照）' % args.branch)
    # **A relative path, because bash is not Windows.** The first version passed `PUBLISH` -- an absolute Windows path
    # with backslashes -- to git-bash, which read it as one long filename and reported that no such file existed. The
    # same failure was hit by hand earlier in this session with `bash -n`, which is the tell: a path is only a path to
    # the program that agrees with you about separators.
    # **Written with forward slashes, literally.** `os.path.join` on Windows returns `tool\\publish_public.sh`, and
    # bash read that as one long filename -- which is the third time today the same mistake has been made, after the
    # CI workflow generator and the separator fix in it. The rule: anything handed to another program is not a path,
    # it is a string that program will parse, and it must be spelled the way that program spells it.
    # **Not captured, and that is a correctness decision rather than a preference.** `capture_output=True` opens a pipe,
    # `publish_public.sh` prints several hundred "LF will be replaced by CRLF" lines, and when the pipe's buffer fills the
    # child blocks on a write while the parent blocks waiting for it to exit -- a deadlock whose only symptom is a process
    # that never finishes and a log with nothing in it. It was 18 minutes of exactly that.
    #
    # Inheriting the streams means the output goes where the caller can see it and nothing can fill up. The return code is
    # still the return code.
    published = subprocess.run(['bash', 'tool/publish_public.sh', '--push'],
                               cwd=REPO, timeout=3600)
    for line in (published.stdout or '').split(chr(10)):
        if any(word in line for word in ('main ->', 'sanitised', 'left alone', 'verified', '== done')):
            print('    %s' % line.strip()[:88])
    if published.returncode != 0:
        # **The reason, not a summary.** The first version printed only the lines it recognised, so a failure arrived as
        # "publish failed" with nothing under it -- and the reason had been in the output all along.
        print('  ✗ 发布失败，没有打标签 —— 原因就在上面它自己的输出里。')
        return 1

    # ⑧ the tag goes on what was published, not on anything local
    print()
    print('  · 取回镜像上那个提交，在它上面打标签')
    run(['git', 'remote', 'remove', 'origin'])
    run(['git', 'remote', 'add', 'origin', REMOTE])
    fetched = run(['git', '-c', 'http.proxy=http://127.0.0.1:10090',
                   '-c', 'credential.helper=manager', 'fetch', 'origin', args.branch], timeout=600)
    if fetched.returncode != 0:
        print('  ✗ 取不回来：%s' % fetched.stderr[:200])
        return 1
    run(['git', 'tag', tag, 'FETCH_HEAD'])
    pushed_tag = run(['git', '-c', 'http.proxy=http://127.0.0.1:10090',
                      '-c', 'credential.helper=manager', 'push', 'origin', tag], timeout=600)
    if pushed_tag.returncode != 0:
        print('  ✗ 标签推不上去：%s' % pushed_tag.stderr[:200])
        return 1
    print('  ✓ 标签 %s 打在镜像的提交上，并推了上去' % tag)

    # ⑨ the release itself, which needs a token this does not have
    print()
    gh = gh_path()
    if gh is None:
        print('  **还差最后一步：`gh` 找不到。**')
        print('    装一个 GitHub CLI 之后这一步就能做完；产物已经备好在 %s' % BUNDLE)
        print('    或者手动建：https://github.com/Nesarf/HollowCourt-Stable/releases/new?tag=%s' % args.version)
        return 0

    if not gh_logged_in(gh):
        print('  **还差最后一步：`gh` 还没登录。**')
        print('    它装好了 ✓，只是没有账号 —— 而那是你的账号，不是这个程序该替你输的。')
        print()
        print('      gh auth login')
        print()
        print('    登录之后再跑一次同样的命令，这一步就会做完。产物已经备好在 %s' % BUNDLE)
        return 0

    notes = notes_for(args.version)
    print('  · 建 release（用 gh ✓，release notes 取自 docs/CHANGELOG.md 里这一节）')
    if notes is None:
        print('    ! 变更日志里没有 ## %s 那一节 —— release 会没有说明，而说明是发布的核心。' % args.version)
        print('      先把那一节写进 docs/CHANGELOG.md，再跑一次。')
        return 1
    if not assets:
        print('    ! %s 里找不到这个版本的产物 —— 先构建三端，再发布。' % BUNDLE)
        return 1
    print('    产物 %d 个，来自 %s' % (len(assets), os.path.dirname(assets[0])))

    notes_file = os.path.join(REPO, 'tool', '.release-notes.md')
    with open(notes_file, 'w', encoding='utf-8', newline=chr(10)) as handle:
        handle.write(notes + chr(10))
    command = [gh, 'release', 'create', tag,
               '--repo', 'Nesarf/HollowCourt-Stable',
               '--title', '空庭 Hollow Court %s' % args.version,
               '--notes-file', notes_file,
               *assets]
    # **Inherited for the same reason as the publish above**: `gh` prints upload progress for five artifacts, and a
    # captured pipe that fills is a deadlock rather than a slow upload.
    done = subprocess.run(command, timeout=1800)
    os.remove(notes_file)
    if done.returncode != 0:
        print('  ✗ gh 建 release 失败了 —— 原因就在上面它自己的输出里。')
        return 1
    print('  ✓ release %s 建好了，产物挂上去了' % tag)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
