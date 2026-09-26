#!/usr/bin/env python3
"""hma_agent — the agent that can look things up, and the boundaries that make it safe to point at a question.

**What changed from the previous commit.** That one handed a model a constant containing the facts somebody had thought
to write down. This one lets it go and read: the repository, its documents, the application's own data, the machine's
environment. **A constant answers the questions that were anticipated; a tool answers the one that was not**, and the
difference is the entire reason to have an agent rather than a longer prompt.

**Four boundaries, and they are the design rather than the caution.**

1. **Nothing writes.** There is no tool that changes a file, and the list is the whole surface -- so the worst outcome of
   pointing this at a question is a slower answer.
2. **Every path is resolved and checked.** A tool argument that walks out of the repository with `..` is refused, and so
   is an absolute path, because an agent reading `/etc` is not what anybody asked for.
3. **The loop is capped**, so a model that keeps asking for tools gets an answer to its last call and then a sentence
   saying the budget ran out, rather than a bill.
4. **Every call is printed before it runs**, with its arguments, because a person watching this should be able to see
   what it decided to look at.

    hma agent "docs/HMA.md 里美术方向是哪几条？"
    hma agent --lang en "which files describe the voice axis?"
"""

from __future__ import annotations

import json
import os
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import hma_models  # noqa: E402  (the sibling module, not a package)

REPO = Path(__file__).resolve().parent.parent

#: Printed when a tool is asked for something outside the repository, or for a file that is not there. **Said as a
#: sentence rather than raised**, because a model can often recover from being told no and cannot recover from a crash.
REFUSED = '这个工具只在本仓库内活动，这个请求被拒绝了：%s'

TOOLS = [
    {
        'type': 'function',
        'function': {
            'name': 'read_file',
            'description': '读本仓库里的一个文本文件，返回其内容（过长会被截断）。路径相对于仓库根目录。',
            'parameters': {
                'type': 'object',
                'properties': {'path': {'type': 'string', 'description': '相对路径，例如 docs/HMA.md'}},
                'required': ['path'],
            },
        },
    },
    {
        'type': 'function',
        'function': {
            'name': 'list_files',
            'description': '列出本仓库某个目录下的文件与子目录名（只一层）。',
            'parameters': {
                'type': 'object',
                'properties': {'path': {'type': 'string', 'description': '相对路径，缺省为仓库根'}},
            },
        },
    },
    {
        'type': 'function',
        'function': {
            'name': 'search',
            'description': '在本仓库里按正则搜索文本，返回命中的文件与行（最多 40 条）。',
            'parameters': {
                'type': 'object',
                'properties': {
                    'pattern': {'type': 'string', 'description': '正则表达式'},
                    'path': {'type': 'string', 'description': '搜索起点，缺省为仓库根'},
                },
                'required': ['pattern'],
            },
        },
    },
    {
        'type': 'function',
        'function': {
            'name': 'doctor',
            'description': '看这台机器上空庭的数据目录、事件日志与导出包在哪、状态如何。不读内容。',
            'parameters': {'type': 'object', 'properties': {}},
        },
    },
]

MAX_ROUNDS = 8
MAX_FILE_BYTES = 40_000


# --------------------------------------------------------------------------------------------------------------
# The tools themselves


def _inside(path: str) -> Path | None:
    """The path if it resolves inside the repository, `None` otherwise. **The check is `resolve`, not a string prefix**,
    because `docs/../..` is a prefix match for `docs` and a directory walk for the filesystem."""
    candidate = (REPO / path).resolve() if not os.path.isabs(path) else Path(path).resolve()
    try:
        candidate.relative_to(REPO)
    except ValueError:
        return None
    return candidate


def tool_read_file(path: str = '', **_) -> str:
    target = _inside(path)
    if target is None:
        return REFUSED % path
    if not target.is_file():
        return '仓库里没有这个文件：%s' % path
    text = target.read_text(encoding='utf-8', errors='replace')
    if len(text) > MAX_FILE_BYTES:
        return text[:MAX_FILE_BYTES] + '\n…（还有 %d 字节，本小姐截断了）' % (len(text) - MAX_FILE_BYTES)
    return text


def tool_list_files(path: str = '.', **_) -> str:
    target = _inside(path)
    if target is None or not target.is_dir():
        return REFUSED % path
    entries = sorted(p.name + ('/' if p.is_dir() else '') for p in target.iterdir()
                     if not p.name.startswith('.git'))
    return '\n'.join(entries[:200]) or '（空目录）'


def tool_search(pattern: str = '', path: str = '.', **_) -> str:
    target = _inside(path)
    if target is None:
        return REFUSED % path
    try:
        matcher = re.compile(pattern)
    except re.error as error:
        return '这个正则本小姐看不懂：%s' % error
    hits: list[str] = []
    for base, dirs, names in os.walk(target):
        dirs[:] = [d for d in dirs if d not in ('.git', 'build', '.dart_tool')]
        for name in names:
            full = Path(base) / name
            if full.suffix.lower() not in ('.md', '.dart', '.py', '.json', '.yaml', '.yml', '.txt', '.sh'):
                continue
            try:
                for number, line in enumerate(full.read_text(encoding='utf-8', errors='replace').split('\n'), 1):
                    if matcher.search(line):
                        hits.append('%s:%d: %s' % (full.relative_to(REPO), number, line.strip()[:160]))
                        if len(hits) >= 40:
                            return '\n'.join(hits) + '\n…（还有更多，本小姐到 40 条就停了）'
            except Exception:
                continue
    return '\n'.join(hits) or '没有命中'


def tool_doctor(**_) -> str:
    """Delegates to the troubleshooting tool, because the environment check already exists and duplicating it would
    make two answers that can disagree."""
    import hma
    rows = []
    for finding in hma.inspect():
        rows.append('[%s] %s → %s（%s）' % (finding['state'], finding['what'], finding['where'], finding['why']))
    return '\n'.join(rows)


HANDLERS = {
    'read_file': tool_read_file,
    'list_files': tool_list_files,
    'search': tool_search,
    'doctor': tool_doctor,
}


# --------------------------------------------------------------------------------------------------------------
# The loop


def run(provider: str, question: str, language: str = 'zh', quiet: bool = False) -> str:
    persona = hma_models.persona_for(language)['name']
    if not quiet:
        print('  → %s（%s）· 说话的是 %s' % (
            provider, hma_models.PROVIDERS.get(provider, {}).get('model', '?'), persona))
        print('  工具：%s' % '、'.join(HANDLERS))
        print()

    messages = [
        {'role': 'system', 'content': hma_models.system_prompt(language)},
        {'role': 'user', 'content': question},
    ]

    for round_number in range(1, MAX_ROUNDS + 1):
        payload = hma_models.post(provider, messages, tools=TOOLS)
        choices = payload.get('choices') or []
        if not choices:
            raise ValueError('对方回了个空：%s' % json.dumps(payload)[:300])
        message = choices[0].get('message', {})
        calls = message.get('tool_calls') or []

        if not calls:
            return message.get('content', '')

        messages.append(message)
        for call in calls:
            function = call.get('function', {})
            name = function.get('name', '')
            try:
                arguments = json.loads(function.get('arguments') or '{}')
            except ValueError:
                arguments = {}
            print('  [%d] %s(%s)' % (round_number, name, json.dumps(arguments, ensure_ascii=False)[:120]))
            handler = HANDLERS.get(name)
            result = handler(**arguments) if handler else '没有这个工具：%s' % name
            print('      → %d 字' % len(result))
            messages.append({
                'role': 'tool',
                'tool_call_id': call.get('id', ''),
                'content': result,
            })

    return '（工具调用到了上限 %d 次，本小姐先停下来 —— 上面每一次看了什么都在上面写着。）' % MAX_ROUNDS


def main(argv: list[str]) -> int:
    if not argv or argv[0] in ('help', '--help', '-h'):
        print('  hma agent "<问题>"          让 agent 去仓库里查了再回答')
        print('     --lang zh|ja|en           换一个说话的人（中文与日文都是伊丽莎白）')
        print('  它只有四件工具，都是只读的，而且只在本仓库内活动。')
        return 0
    language = 'zh'
    for candidate in ('zh', 'ja', 'en'):
        if ('--' + candidate) in argv:
            language = candidate
            argv = [a for a in argv if a != '--' + candidate]
    question = ' '.join(argv)
    try:
        answer = run('gemini', question, language=language)
    except ValueError as error:
        print()
        print('  %s' % error)
        return 1
    print()
    print(answer)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
