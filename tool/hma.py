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

import os
import platform
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


def main(argv: list[str]) -> int:
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
        return 0
    if command == "report":
        return do_report(argv[2:])
    if command == "fix":
        return do_fix(argv[2:])
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
