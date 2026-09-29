#!/usr/bin/env python3
"""hma doctor — the first piece of the troubleshooting front end.

**What this is for.** Before anything can be repaired, somebody has to be able to say what is on the machine and what
state it is in. That is all this does: it looks for the application's data and its library and reports — **including when
it cannot tell**, which is the point. A doctor that guesses is worse than one that says which check it could not finish
and why.

**The first version looked in the wrong place, and the machine said so.** It assumed the directory would be named
`com.nesarf.hollow_court` after the identifier; the application actually keeps its files in
`%APPDATA%\\com.nesarf\\Hollow Court` — the **display name**, with a space in it. So this version does not assume a
name: it looks inside the organisation's directory and reports whatever it finds there, which works whether the folder
is called one thing or another and would have been right the first time.

**Where it may look is deliberately narrow.** It reads the organisation directory and the documents folder, it never
walks the disk, and it never writes: a diagnostic that changes the thing it diagnoses is not a diagnostic.

**The voice is HMA's, not the application's.** The application defaults to `plain`; HMA has no neutral register and
speaks as her — Chinese here, with the Japanese and English table left in place so the other two voices are a matter of
filling them in.
"""

from __future__ import annotations

import io
import os
import platform
import re
import subprocess
import sys
from pathlib import Path

ORG = "com.nesarf"

VOICE: dict[str, dict[str, str | None]] = {
    "zh": {
        "greeting": "你这家伙，果然没有人家不行呢~",
        "looking": "先让本小姐看看这台机器上有些什么。",
        "report_lead": "这一趟看下来：",
        "all_found": "该有的都在——那就说不上是它坏了。",
        "somethings_missing": "有几样不在它该在的地方，上面写着。",
        "cannot_tell": "有几样本小姐查不出来——理由写在它们旁边，不会替它们编一个答案。",
    },
    "ja": {},
    "en": {},
}


def say(key: str, language: str = "zh") -> str:
    """The sentence in the requested voice, falling back to Chinese rather than to nothing."""
    text = VOICE.get(language, {}).get(key)
    return text if text else VOICE["zh"].get(key, key)


# --------------------------------------------------------------------------------------------------------------
# Where the application keeps things


def organisation_dir() -> tuple[Path | None, str]:
    system = platform.system()
    home = Path.home()
    if system == "Windows":
        base = os.environ.get("APPDATA")
        if not base:
            return None, "APPDATA 没有设置，所以本小姐不知道它该在哪儿"
        return Path(base) / ORG, "Windows 上在 %APPDATA% 下面"
    if system == "Darwin":
        return home / "Library" / "Application Support" / ORG, "macOS 上在 Application Support 下面"
    if system == "Linux":
        base = os.environ.get("XDG_DATA_HOME") or str(home / ".local" / "share")
        return Path(base) / ORG, "Linux 上在 XDG_DATA_HOME 下面"
    return None, "%s 不是这三端之一，本小姐不知道它把东西放哪儿" % system


def documents_dir() -> tuple[Path | None, str]:
    system = platform.system()
    home = Path.home()
    if system == "Windows":
        base = os.environ.get("USERPROFILE")
        if not base:
            return None, "USERPROFILE 没有设置"
        return Path(base) / "Documents", "Windows 上由 USERPROFILE 决定"
    if system in ("Darwin", "Linux"):
        return home / "Documents", "%s 上就在主目录下" % system
    return None, "%s 上本小姐不知道它把文档放哪儿" % system


def inspect() -> list[dict[str, str]]:
    """One entry per thing looked for. `why` always says something true about *this* result."""
    findings: list[dict[str, str]] = []

    org, why_org = organisation_dir()
    if org is None:
        findings.append({"what": "组织目录", "state": "unknown", "where": "—", "why": why_org})
    elif not org.is_dir():
        findings.append({
            "what": "组织目录", "state": "missing", "where": str(org),
            "why": "这一层不在，说明空庭在这台机器上还没跑过，或者跑的是别的构建",
        })
    else:
        # **Do not assume the folder's name.** It is the display name and it contains a space.
        apps = sorted(p for p in org.iterdir() if p.is_dir())
        findings.append({
            "what": "空庭的数据目录", "state": "found" if apps else "missing",
            "where": ", ".join(p.name for p in apps) if apps else "组织目录下没有子目录",
            "why": "名字是显示名（带空格），所以本小姐照实报，不猜" if apps else "跑过一次就该有一个",
        })
        for app in apps:
            files = sorted(p.name for p in app.iterdir() if p.is_file())
            findings.append({
                "what": "  %s 里的文件" % app.name,
                "state": "found" if files else "missing",
                "where": ", ".join(files[:10]) if files else "空目录",
                "why": "只列名字，不读内容——看病的不翻病人的信",
            })
            log = next((n for n in files if "log" in n.lower() or "event" in n.lower()), None)
            if log:
                findings.append({
                    "what": "  事件日志", "state": "found", "where": log,
                    "why": "应用里「检查完整性」读的就是它",
                })

    docs, why_docs = documents_dir()
    findings.append({
        "what": "文档目录",
        "state": "unknown" if docs is None else ("found" if docs.is_dir() else "missing"),
        "where": str(docs) if docs else "—", "why": why_docs,
    })
    if docs is not None and docs.is_dir():
        # **The log is not in the support directory, and the first version assumed it was.** `library.dart` opens
        # `getApplicationDocumentsDirectory()/cellar.ndjson`, so a doctor that only looked beside the preferences
        # reported "no log file" on a machine that had one. Reported as missing here only when it is.
        cellar = docs / "cellar.ndjson"
        findings.append({
            "what": "事件日志（cellar.ndjson）", "state": "found" if cellar.is_file() else "missing",
            "where": str(cellar) if cellar.is_file() else "文档目录下没有 cellar.ndjson",
            "why": "应用里「检查完整性」读的就是它" if cellar.is_file()
                   else "还没有这个文件，说明这台机器上还没发生过要记的事",
        })
        packs = sorted(p.name for p in docs.glob("*.courtpack"))
        findings.append({
            "what": "导出的包（.courtpack）", "state": "found" if packs else "missing",
            "where": ", ".join(packs[:6]) if packs else "一个都没有",
            "why": "有包说明导出这条路走得通" if packs else "还没有导出过，不是毛病",
        })

    return findings


# --------------------------------------------------------------------------------------------------------------
# hma report -- what a diagnosis needs, and nothing that is not


def _summarise_log(path: Path) -> dict[str, object]:
    """Counts and a time range, never the contents.

    The log is the thing a diagnosis is actually about, and it is also somebody's cellar. So this reads it to count
    and to find its span, and reports that -- **what is in the bottles is not what is being asked about.**
    """
    import json

    kinds: dict[str, int] = {}
    first = last = None
    total = 0
    with path.open('r', encoding='utf-8', errors='replace') as handle:
        for line in handle:
            line = line.strip()
            if not line:
                continue
            total += 1
            try:
                record = json.loads(line)
            except ValueError:
                kinds['(读不出的一行)'] = kinds.get('(读不出的一行)', 0) + 1
                continue
            kinds[str(record.get('type', '(没有 type)'))] = kinds.get(str(record.get('type', '(没有 type)')), 0) + 1
            clock = record.get('hlc') or {}
            stamp = clock.get('physical') if isinstance(clock, dict) else None
            if isinstance(stamp, (int, float)):
                first = stamp if first is None else min(first, stamp)
                last = stamp if last is None else max(last, stamp)
    return {'总条数': total, '按类型': kinds, '最早': first, '最晚': last}


def _stamp(millis: object) -> str:
    if not isinstance(millis, (int, float)):
        return '查不出来'
    import datetime
    return datetime.datetime.fromtimestamp(millis / 1000).strftime('%Y-%m-%d %H:%M:%S')


def do_report(argv: list[str]) -> int:
    import zipfile

    with_log = '--with-log' in argv
    out: Path | None = None
    if '--out' in argv:
        index = argv.index('--out')
        if index + 1 < len(argv):
            out = Path(argv[index + 1])

    print(say('greeting'))
    print('本小姐把这次要看的东西收一收。')
    print()

    findings = inspect()
    lines: list[str] = []
    lines.append('HMA report -- %s' % datetime_now())
    lines.append('')
    lines.append('系统')
    lines.append('  平台        %s %s' % (platform.system(), platform.release()))
    lines.append('  架构        %s' % platform.machine())
    lines.append('  Python      %s' % sys.version.split()[0])
    lines.append('')
    lines.append('找到的东西')
    for f in findings:
        lines.append('  [%s] %-24s %s' % (f['state'], f['what'], f['where']))

    # the log, summarised rather than quoted
    docs, _ = documents_dir()
    log_path = docs / 'cellar.ndjson' if docs else None
    if log_path is not None and log_path.is_file():
        summary = _summarise_log(log_path)
        lines.append('')
        lines.append('事件日志（只统计，不抄内容）')
        lines.append('  总条数      %s' % summary['总条数'])
        lines.append('  最早        %s' % _stamp(summary['最早']))
        lines.append('  最晚        %s' % _stamp(summary['最晚']))
        for kind, count in sorted(dict(summary['按类型']).items(), key=lambda kv: -kv[1]):
            lines.append('  %-10s %s' % (kind, count))
    else:
        lines.append('')
        lines.append('事件日志      这台机器上没有，所以没什么可统计的')

    lines.append('')
    lines.append('没有拿走的东西（这不是遗漏，是规矩）')
    lines.append('  sync-identity.json   里面是设备身份的秘密和配过对的设备，与诊断无关')
    lines.append('  preferences.json     只是界面偏好，看一眼没有用')
    lines.append('  display.json         同上')
    if not with_log:
        lines.append('  cellar.ndjson 的原文  只统计了类型与时间；要带原文请用 --with-log')

    name = 'hma-report-%s.zip' % datetime_now('%Y%m%d-%H%M%S')
    if out is None:
        out = (docs if docs else Path.cwd()) / name
    elif out.is_dir():
        out = out / name

    with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as bundle:
        bundle.writestr('README.txt', chr(10).join(lines) + chr(10))
        if with_log and log_path is not None and log_path.is_file():
            bundle.write(log_path, 'cellar.ndjson')

    print('  ✓ 报告写好了：%s' % out)
    print('  里面是一份 README.txt%s。' % ('和日志原文' if with_log else ''))
    print()
    print('  本小姐没有拿的：设备身份的 seed、配过对的设备、界面偏好——与诊断无关的东西一律不带。')
    return 0


# --------------------------------------------------------------------------------------------------------------
# hma fix -- the writing half, and deliberately the smallest one


def _parse_problem(path: "Path") -> str:
    """`ok`, `missing` or `unreadable`. Nothing else is inspected: whether the contents make sense is the
    application's business, and a tool that has opinions about somebody's preferences is a tool that will one day
    overwrite them."""
    import json

    if not path.is_file():
        return 'missing'
    try:
        json.loads(path.read_text(encoding='utf-8'))
    except Exception:
        return 'unreadable'
    return 'ok'


# --------------------------------------------------------------------------------------------------------------
# The journal -- what was done, so that it can be undone and so that it is on the record


def cache_dir() -> "Path":
    """Where HMA keeps its own operational files. **Not the repository, and not a clone's business.**

    `HMA_CACHE_DIR` moves it; otherwise it sits under the machine's own E: cache, which is this project's disk rule -- a
    platform that filled up a system drive while diagnosing somebody else's problem would be no use to them.
    """
    override = os.environ.get('HMA_CACHE_DIR')
    if override:
        return Path(override)
    return Path('E:') / 'DaShaoHuo' / 'cache' / 'hma'


def journal_path() -> "Path":
    return cache_dir() / 'journal.ndjson'


def journal_append(entry: dict) -> None:
    """Adds one line. **Append-only: nothing here ever rewrites what is already written.**

    A journal that could be edited is a journal that will be, and then it is not evidence of anything.
    """
    import json as _json
    import time as _time
    path = journal_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    entry = dict(entry)
    entry.setdefault('when', _time.strftime('%Y-%m-%dT%H:%M:%S'))
    entry.setdefault('version', HMA_VERSION)
    with io.open(str(path), 'a', encoding='utf-8', newline=chr(10)) as handle:
        handle.write(_json.dumps(entry, ensure_ascii=False) + chr(10))


def journal_read() -> list:
    """Every line, oldest first. A line that does not parse is kept as a marker rather than skipped quietly."""
    import json as _json
    path = journal_path()
    if not path.is_file():
        return []
    entries = []
    with io.open(str(path), encoding='utf-8') as handle:
        for line in handle:
            line = line.strip()
            if not line:
                continue
            try:
                entries.append(_json.loads(line))
            except Exception:
                entries.append({'op': '(读不出这一行)', 'raw': line[:80]})
    return entries


def do_undo(argv: list[str]) -> int:
    """Reverses the most recent operation that has not been reversed yet."""
    import time as _time

    print(say('greeting'))
    entries = journal_read()
    if not entries:
        print('  这本账是空的 —— 本小姐没动过任何东西，也就没什么可撤。')
        print('  账本在 %s' % journal_path())
        return 0

    # **A move is undone by a later entry naming it**, so the search walks backwards for the newest move that no undo
    # has claimed. Anything else on the record -- renders, builds -- is not reversible and is not offered.
    undone = {entry.get('undoes') for entry in entries if entry.get('op') == 'undo'}
    target = None
    for entry in reversed(entries):
        if entry.get('op') == 'move-aside' and entry.get('id') not in undone:
            target = entry
            break

    if target is None:
        print('  没有可撤的了 —— 账上 %d 条，全部已经撤过，或者本来就不是能撤的那类。' % len(entries))
        return 0

    source = Path(target['to'])
    destination = Path(target['from'])
    print('  最近一次动的是：')
    print('    %s' % target.get('when', '?'))
    print('    %s' % destination.name)
    print('    → 让开到了 %s' % source)

    if '--apply' not in argv:
        print()
        print('  这是演练 ✓ —— 一个字都没动。要真搬回去就加 --apply。')
        return 0

    if not source.exists():
        print()
        print('  ✗ 原件不在 %s —— 本小姐不假装搬回去了。' % source)
        return 1
    if destination.exists():
        print()
        print('  ✗ %s 已经有东西了 —— 本小姐不覆盖它。' % destination)
        return 1

    # **The record is written before the move**, so a process killed in between is still accounted for.
    journal_append({'op': 'undo', 'undoes': target.get('id'), 'from': str(source), 'to': str(destination)})
    destination.parent.mkdir(parents=True, exist_ok=True)
    source.rename(destination)
    print()
    print('  ✓ 搬回去了：%s' % destination)
    return 0





# --------------------------------------------------------------------------------------------------------------
# Extension: commands that live outside this file


def command_directory() -> "Path":
    '''Where a command module may be dropped in. **Adding one no longer means editing the dispatch above.**

    第 19 条，用它自己的话：加第七个命令要改 `hma.py` 的分发表。七个内置的留在这里，因为它们是这个平台自己的家具；其余的靠发现。
    '''
    return Path(__file__).resolve().parent / 'hma_commands'


def load_commands(directory: "Path | None" = None) -> dict:
    '''Every module in the command directory that declares a `COMMAND`.

    **A module that will not import is reported and skipped, not fatal.** A platform whose whole command line disappears because one extension has a syntax error is a platform nobody extends twice.
    '''
    import importlib.util
    found = {}
    # **The directory is a parameter so that a test can point it somewhere harmless.** Deriving it always from
    # `__file__` would mean the only way to test this was to write into the shipped directory and clean up after. It is
    # coerced, because a caller with a string in hand should not have to know that this wants a `Path`.
    directory = Path(directory) if directory else command_directory()
    if not directory.is_dir():
        return found
    for path in sorted(directory.glob('*.py')):
        if path.name.startswith('_'):
            continue
        try:
            spec = importlib.util.spec_from_file_location('hma_cmd_%s' % path.stem, str(path))
            module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(module)
        except Exception as error:
            print('  ! 扩展 %s 读不进来：%s' % (path.name, str(error)[:70]))
            continue
        declaration = getattr(module, 'COMMAND', None)
        if not isinstance(declaration, dict) or 'name' not in declaration or 'run' not in declaration:
            print('  ! 扩展 %s 没有声明 COMMAND（name 与 run）' % path.name)
            continue
        found[declaration['name']] = declaration
    return found


def do_scaffold(argv: list[str]) -> int:
    '''Writes a new command module that already follows the house rules.'''
    name = next((a for a in argv if not a.startswith('-')), None)
    if not name:
        print('  用法：hma scaffold <命令名>')
        return 2
    if not name.replace('-', '').replace('_', '').isalnum():
        print('  命令名只能用字母、数字、下划线和连字符。')
        return 2

    directory = command_directory()
    directory.mkdir(parents=True, exist_ok=True)
    target = directory / ('%s.py' % name)
    if target.exists():
        print('  %s 已经在了 —— 本小姐不覆盖它。' % target)
        return 1

    template = """
'''The `%(name)s` command.

**What it does.** （一句话说清它回答什么问题。）

**Why it exists rather than being a flag on something else.** （说清它为什么不属于已有命令 —— 如果它其实属于，那它就该是那个命令的一个参数，而不是这里的一个新命令。）
'''


def run(argv: list[str]) -> int:
    '''Returns an exit code: 0 for success, non-zero for a failure worth noticing.

    **argv is what followed the command name**, already split. A missing argument is reported rather than guessed, and anything destructive is a dry run unless `--apply` is passed -- the rule `fix` follows.
    '''
    print('''  %(name)s 还没有写完 —— 这是脚手架留下的骨架。''')
    return 0


COMMAND = {
    'name': '%(name)s',
    'summary': '（一行说明，会出现在 hma help 里）',
    'run': run,
}
"""
    io.open(str(target), 'w', encoding='utf-8', newline=chr(10)).write(template % {'name': name})
    print('  ✓ 写了 %s' % target)
    print('  现在 `hma %s` 就能用了 —— 扩展不需要改分发。' % name)
    return 0



def do_fix(argv: list[str]) -> int:
    apply_changes = '--apply' in argv

    print(say('greeting'))
    print('本小姐先只看，不动手——要看真动的，加 --apply。')
    print()

    org, _ = organisation_dir()
    targets: list["Path"] = []
    if org is not None and org.is_dir():
        for app in sorted(p for p in org.iterdir() if p.is_dir()):
            targets += [app / name for name in ('preferences.json', 'display.json')]

    docs, _ = documents_dir()
    log_path = docs / 'cellar.ndjson' if docs else None

    broken = []
    print('  能看的东西：')
    for path in targets:
        problem = _parse_problem(path)
        mark = {'ok': '✓', 'missing': '·', 'unreadable': '✗'}[problem]
        print('    %s %-34s %s' % (mark, path.name, {
            'ok': '读得出', 'missing': '不在', 'unreadable': '**读不出**（这个会让应用起不来）',
        }[problem]))
        if problem == 'unreadable':
            broken.append(path)

    if log_path is not None and log_path.is_file():
        print('    ✓ %-34s %s' % ('cellar.ndjson', '在（日志本小姐一个字都不改）'))
    print()

    # The packs are verified and never repaired, **and they are verified as what they are**. The first version of
    # this assumed a zip and called two healthy files broken: `.courtpack` is JSON, and it says so in its own first
    # byte. Read the file rather than the extension -- the same rule as reading bytes rather than rendering.
    if docs is not None and docs.is_dir():
        import json as _json
        packs = sorted(docs.glob('*.courtpack'))
        if packs:
            print('  导出的包（只验，不修 —— 坏了的包重建不出自己）：')
            for pack in packs:
                try:
                    lines = [l for l in pack.read_text(encoding='utf-8').split(chr(10)) if l.strip()]
                    header = _json.loads(lines[0])
                    version = header.get('courtpack')
                    records = 0
                    for index, line in enumerate(lines[1:], 2):
                        _json.loads(line)
                        records += 1
                    if isinstance(version, int):
                        print('    ✓ %-30s 头是第 %s 版，来自 %s，后面 %d 条记录'
                              % (pack.name[:30], version, header.get('source', '没有写'), records))
                    else:
                        print('    ? %-30s 读得出，但头里没有版本号' % pack.name[:30])
                except Exception as error:
                    print('    ✗ %-30s 读不出：%s' % (pack.name[:30], error))

    if not broken:
        print('  没有需要修的东西 ✓')
        print()
        print('  本小姐不会为了显得有用而去改没坏的文件。')
        return 0

    print('  本小姐打算这么做：')
    for path in broken:
        print('    把 %s' % path.name)
        print('      改名为 %s.bma-broken-<时间戳>' % path.name)
        print('      ——**改回去就等于没发生** ✓；应用下次会自己写一份新的 ✓')
    print()
    print('  本小姐不改的：日志 ✓（它坏了也该留着看）／偏好内容 ✓（看不懂就不碰）／坏的包 ✗（它重建不出自己）')
    print()

    if not apply_changes:
        print('  这是演练 ✓ —— 一个字都没动。要真动就加 --apply。')
        return 0

    stamp = datetime_now('%Y%m%d-%H%M%S')
    for path in broken:
        destination = path.with_name('%s.hma-broken-%s' % (path.name, stamp))
        path.rename(destination)
        print('  ✓ 让开了：%s' % destination)
    print()
    print('  行了 ✓ —— 再开一次应用，它自己会写新的。')
    print('  要是想撤回，把上面的名字改回原名就行。')
    return 0


def datetime_now(fmt: str = '%Y-%m-%d %H:%M:%S') -> str:
    import datetime
    return datetime.datetime.now().strftime(fmt)


# --------------------------------------------------------------------------------------------------------------
# hma status -- what state the platform is in, in one screen


def _run_tool(arguments: list[str]) -> tuple[int, str]:
    """Runs one of the sibling tools and returns its exit code and its last few lines."""
    here = os.path.dirname(os.path.abspath(__file__))
    try:
        done = subprocess.run([sys.executable, *arguments], capture_output=True, text=True,
                              encoding='utf-8', errors='replace', cwd=here, timeout=600)
    except Exception as error:
        return 1, str(error)
    # **Both streams, because `unittest` writes its verdict to stderr.** Reading only stdout made the tests' line
    # print an empty result, which reads like a failure that said nothing.
    both = (done.stdout or '') + chr(10) + (done.stderr or '')
    tail = [line for line in both.split(chr(10)) if line.strip()]
    return done.returncode, (tail[-1].strip() if tail else '')


def _todo_counts() -> dict[str, int]:
    """How many items are open in each section of the outstanding-work file, read rather than guessed.

    **The count is the point.** `docs/TODO.md` was written so that the open work would be in one place; a file nobody can
    query is still a file somebody has to read.
    """
    here = os.path.dirname(os.path.abspath(__file__))
    path = os.path.join(os.path.dirname(here), 'docs', 'TODO.md')
    if not os.path.isfile(path):
        return {}
    text = io.open(path, encoding='utf-8').read()
    counts: dict[str, int] = {}
    section = '（开头）'
    for line in text.split(chr(10)):
        if line.startswith('## '):
            # The heading carries markdown emphasis and a parenthetical; the count wants the plain title.
            plain = line[3:].split('（')[0].replace('**', '').strip()
            section = plain[:14]
            counts.setdefault(section, 0)
        elif re.match(r'^\| ~?~?\*\*\d+', line) or re.match(r'^\| \*\*\d+', line):
            counts[section] = counts.get(section, 0) + 1
    return counts


def do_status(argv: list[str]) -> int:
    here = os.path.dirname(os.path.abspath(__file__))
    root = os.path.dirname(here)

    print(say('greeting'))
    print('本小姐把这边的情况看一眼。' + chr(10) + '（HMA %s）' % HMA_VERSION)
    print()

    # the tools themselves
    tools = sorted(name for name in os.listdir(here) if name.startswith('hma') and name.endswith('.py'))
    print('  工具        %s' % '、'.join(tools))

    # the tests
    code, line = _run_tool([os.path.join(here, 'hma_tests.py')])
    mark = '✓' if code == 0 else '✗'
    print('  自己的测试   %s %s' % (mark, line[:64]))

    # the art's rules
    art_check = os.path.join(here, 'hma_art_check.py')
    if os.path.isfile(art_check):
        code, line = _run_tool([art_check])
        mark = '✓' if code == 0 else '✗'
        print('  美术规矩     %s %s' % (mark, line[:64]))

    # the rendered art, counted rather than assumed
    rendered = os.path.join(here, 'hma-dev', 'Assets', 'Resources', 'Art')
    if os.path.isdir(rendered):
        files = [name for name in os.listdir(rendered) if name.endswith('.png')]
        sources = [name for name in os.listdir(os.path.join(root, 'art', 'hma')) if name.endswith('.svg')] \
            if os.path.isdir(os.path.join(root, 'art', 'hma')) else []
        mark = '✓' if len(files) == len(sources) and files else '✗'
        print('  渲染产物     %s %d 张 / %d 个源' % (mark, len(files), len(sources)))

    # the outstanding work
    counts = _todo_counts()
    if counts:
        parts = ['%s %d' % (name, number) for name, number in counts.items() if number]
        print('  待办         docs/TODO.md —— %s' % ' ／ '.join(parts))
    else:
        print('  待办         ? docs/TODO.md 读不到')

    # what this checkout is
    is_product = os.path.isdir(os.path.join(root, 'lib'))
    print('  这是         %s' % ('空庭本体所在的检出（含 lib/）' if is_product else 'HMA 分支的检出（没有 lib/）'))
    if is_product:
        print('               **产品的 Flutter 套件没有跑** —— 它要几分钟，而且不属于这条命令要回答的问题；')
        print('               要跑就 `flutter test`，要快就 `flutter test test/data/principles_test.dart`。')

    print()
    print('  「查不出来」会写在对应那一行 ✓ —— 本小姐不替没有的事编一个数字。')
    return 0



# **The platform's own version.** It lives here rather than in a file beside the tools, because a version in its
# own file drifts from the code it names the moment somebody edits one and not the other.
HMA_VERSION = "0.1.0"

def main(argv: list[str]) -> int:
    # **`argv[1]`, not `argv[0]`.** `main` is handed `sys.argv` whole, so the first element is the script path and the
    # command is the second -- the same indexing the dispatch below uses. Reading the wrong one meant the flag fell
    # through to the help text and returned a failure.
    if len(argv) > 1 and argv[1] in ("--version", "-V", "version"):
        print("HMA %s" % HMA_VERSION)
        return 0

    command = argv[1] if len(argv) > 1 else "doctor"
    if command in ("help", "--help", "-h"):
        print("  hma doctor    看看这台机器上有些什么")
        print("  hma report    把要诊断的东西收成一个包（默认不带日志原文）")
        print("                  --with-log    连日志原文一起带")
        print("                  --out <路径>  写到别处")
        print("  hma fix       只看不动；加 --apply 才真动（坏文件只让开，不改写）")
        print("  hma models    看哪几家模型配好了（key 从不打印）")
        print("  hma ask <家> <话>   问一句，答一句")
        print("  hma agent \"<问题>\"   让 agent 去仓库里查了再回答（只读四件工具）")
        print("  hma status    这边现在什么状态（测试 ✓ 美术 ✓ 待办计数 ✓）")
        print("  hma undo      把最近一次让开的文件搬回去（默认演练，加 --apply 才真动）")
        print("  hma scaffold  写一个新命令的骨架（扩展住在 tool/hma_commands/）")
        found = load_commands()
        if found:
            print()
            print("  扩展（住在 tool/hma_commands/）：")
            for name, declaration in sorted(found.items()):
                print("    hma %-11s %s" % (name, declaration.get('summary', '')))
        return 0
    if command == "report":
        return do_report(argv[2:])
    if command == "fix":
        return do_fix(argv[2:])
    if command == "status":
        return do_status(argv[2:])
    if command == "undo":
        return do_undo(argv[2:])
    if command == "scaffold":
        return do_scaffold(argv[2:])

    # **Then the extensions**, so a command living outside this file is reachable by the same name. Built-ins win on a
    # collision: the platform's own seven are furniture and an extension should not be able to shadow them.
    extensions = load_commands()
    if command in extensions:
        return extensions[command]['run'](argv[2:])
    if command == "agent":
        sys.path.insert(0, str(Path(__file__).parent))
        import hma_agent
        return hma_agent.main(argv[2:])
    if command in ("models", "ask"):
        # delegated rather than duplicated: the model layer is its own file because it is its own subject
        sys.path.insert(0, str(Path(__file__).parent))
        import hma_models
        return hma_models.main([argv[0]] + argv[1:])
    if command != "doctor":
        print("不认这个命令：%s" % command)
        print("  hma doctor    看看这台机器上有些什么")
        return 2

    print(say("greeting"))
    print(say("looking"))
    print()

    findings = inspect()
    marks = {"found": "✓", "missing": "✗", "unknown": "?"}
    for f in findings:
        print("  %s %-22s %s" % (marks[f["state"]], f["what"], f["where"]))
        print("      %s" % f["why"])
    print()

    print(say("report_lead"))
    states = [f["state"] for f in findings]
    if "unknown" in states:
        print("  " + say("cannot_tell"))
    elif all(s == "found" for s in states):
        print("  " + say("all_found"))
    else:
        print("  " + say("somethings_missing"))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
