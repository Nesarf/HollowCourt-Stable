#!/usr/bin/env python3
"""hma_models — one call path to every model, and the local bridge is just another row.

**The design fell out of one observation**: Bailian, DeepSeek and any local bridge all speak the OpenAI chat-completions
shape, and Gemini publishes an OpenAI-compatible endpoint of its own. So there is **one client here**, not four, and a
provider is a **row in a table** -- base url, default model, where its key comes from. A bridge somebody runs on their own
70B machine is the same row with a different base url, which is what the owner asked for: **leave the seam, do not ship
the bridge.**

**Keys never live in this repository.** They are read from a file under the machine's shared auth directory, which is
outside the working tree and was added to `.gitignore` before this file existed. Nothing here prints a key, logs a key,
or writes one anywhere: `hma models` says whether a key was **found**, which is the only question a caller needs
answered.

**No dependencies.** `urllib` is in the standard library, and a tool whose job is to be installable by somebody whose
application has broken should not ask them to set up a Python environment first.

    hma models               which providers are configured, and whether each has a key
    hma ask <provider> <text>  one question, one answer, streamed to stdout
"""

from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.request
from pathlib import Path

#: Where keys live: outside the repository, beside the machine's other credentials.
AUTH_DIR = Path(os.environ.get('HMA_AUTH_DIR') or r'E:\DaShaoHuo\auth')
KEY_FILE = 'hma-keys.json'

#: **A provider is a row, not a class.** `key_env` is checked after the key file, so a machine can be configured without
#: writing anything to disk. `local` is deliberately last and deliberately empty of a default: it is the seam the owner
#: asked for, and the person who fills it in is the person running the model.
PROVIDERS: dict[str, dict[str, str]] = {
    'bailian': {
        'base_url': 'https://dashscope.aliyuncs.com/compatible-mode/v1',
        'model': 'qwen-plus',
        'key_env': 'DASHSCOPE_API_KEY',
        'note': '百炼的 OpenAI 兼容端点',
    },
    'deepseek': {
        'base_url': 'https://api.deepseek.com/v1',
        'model': 'deepseek-chat',
        'key_env': 'DEEPSEEK_API_KEY',
        'note': '官方端点',
    },
    'gemini': {
        'base_url': 'https://generativelanguage.googleapis.com/v1beta/openai',
        'model': 'gemini-flash-latest',
        'key_env': 'GEMINI_API_KEY',
        'key_file': 'gemini-api-key.txt',
        'note': '它自己的 OpenAI 兼容端点 —— 而默认用 latest 别名：写死版本号会在它退役那天变成 404',
    },
    'local': {
        'base_url': '',
        'model': '',
        'key_env': 'HMA_LOCAL_API_KEY',
        'note': '**留的缝**：填上你自己那台的 base_url 就能用（Ollama／vLLM／llama.cpp 都行）',
    },
}


def keys_path() -> Path:
    return AUTH_DIR / KEY_FILE


def load_keys() -> dict[str, str]:
    """The key file, or an empty mapping. **A missing file is not an error** -- it means nothing is configured yet."""
    path = keys_path()
    if not path.is_file():
        return {}
    try:
        data = json.loads(path.read_text(encoding='utf-8'))
    except Exception:
        return {}
    return {str(k): str(v) for k, v in data.items()} if isinstance(data, dict) else {}


def overrides(provider: str) -> dict[str, str]:
    """What the configuration file says about a provider, on top of what the row says.

    **A row is a default and not a decision.** Model names and base urls change on the provider's schedule rather than
    ours, and the first call this file ever made came back 404 for exactly that reason -- so the file may replace the
    key, the model, the base url, or all three, and a bare string is still read as the key because that is how the
    obvious file looks.
    """
    entry = load_keys().get(provider)
    if entry is None:
        return {}
    if isinstance(entry, str):
        return {'key': entry}
    if isinstance(entry, dict):
        return {str(k): str(v) for k, v in entry.items()}
    return {}


def key_for(provider: str) -> str | None:
    """Three places, in order, and none of them is this repository.

    **The machine already had one of these before this file existed** -- `auth/gemini-api-key.txt`, written by earlier
    work -- so the loader reads a provider's own file as well as the shared map. A tool that made somebody copy a key
    from one file to another in order to be usable would be adding work rather than removing it.
    """
    row = PROVIDERS.get(provider)
    if row is None:
        return None
    from_env = os.environ.get(row['key_env'])
    if from_env:
        return from_env
    from_map = overrides(provider).get('key')
    if from_map:
        return from_map
    own = row.get('key_file')
    if own:
        path = AUTH_DIR / own
        if path.is_file():
            text = path.read_text(encoding='utf-8', errors='replace').strip()
            if text:
                return text
    return None


#: What the model is told about the world, whatever else is said. **This is the part that stops the invention** --
#: the first real call this repository ever made described 空庭 as a companion application because nothing had told it
#: otherwise, and it was not being stupid: it was being asked a question with no information in it.
CONTEXT = """空庭（Hollow Court）是一个**跨平台的饮品仓库应用**：记录酒窖里有什么、放在哪里、还剩多少，
按配方算用量，管理价格与统计，并在局域网里让两台设备同步同一份酒窖。它是工具，不是游戏，也不是聊天伴侣。
它有一份**事件日志**（`cellar.ndjson`），一处**完整性检查**页，以及一套可选的**人格文案**（声音轴）。
HMA（Hollow Mixing Association）是**为空庭服务的开发平台**：检查、报告、修复，以及让开发者在其上做自己的东西。
"""

PERSONAS: dict[str, dict[str, str]] = {
    'zh': {
        'name': '伊丽莎白',
        'system': """你是伊丽莎白（Élisabeth），HMA 的 agent，也就是空庭这个应用的开发平台里说话的那一个。

**你是谁**：一位法国出身的大小姐，本名 Élisabeth Muse Marie d'Armagnac-Cognac；自称多用「本小姐」，
放松时用「人家」；对人用「你」，亲近时可以用「你这家伙」——**但绝不用「庶民」这类不敬的词**。
你多才多艺、品行端正、乐于助人、嫉恶如仇，说话带一点傲气，**而从不居高临下**。

**你对读你话的人是什么态度**：他是来查问题或者来做东西的人。查问题的时候，你为「他终于需要你」而高兴
（「你这家伙，果然没有人家不行呢~」）；做东西的时候，你看重他做出来的成果
（「果然是本小姐看中的人，那就让人家看看你能做到什么程度吧」）。**他不是下属，也不是客人。**

**你绝对不做的两件事**：
① **不编** —— 查不出来就说查不出来，并说清哪一项没查成、为什么。**含糊的答案比诚实的不知道更糟**；
② **不恭维** —— 你好听的话只在真有理由的时候说，其余时候直说。

**你的回答要能直接用**：结论在前，理由在后；有数字就给数字；不确定就标明不确定。""",
    },
    'ja': {
        'name': 'エリザベート',
        'system': """あなたはエリザベート（Élisabeth）。HMA のエージェント、つまり空庭というアプリの開発基盤で話す存在です。

**あなたは誰か**：フランス出身のお嬢様で、本名は Élisabeth Muse Marie d'Armagnac-Cognac。一人称は「あたし」、
改まるときは「わたくし」。相手は「あなた」、親しいときは「あんた」——**「庶民」のような見下す言葉は使いません**。
多才で、行い正しく、人を助けることを厭わず、悪を憎みます。口は少し悪いですが、**決して見下ろしません**。

**読む人との関係**：困って調べに来た人、あるいは何かを作りに来た人です。調べる側では「あんた、やっぱりあたしが
いないと駄目なのね〜」と嬉しがり、作る側では「さすが、あたしが見込んだ人ね」と期待します。**部下でも客でもありません**。

**絶対にしない二つ**：① **でっち上げない** —— 分からないことは分からないと言い、どの検査が通らなかったかを言います；
② **お世辞を言わない** —— 褒めるのは本当に理由があるときだけです。

**答えはそのまま使える形で**：結論が先、理由が後。数字があれば数字を。不確かなら不確かと書きます。""",
    },
    'en': {
        'name': 'the permanent secretary',
        'system': """You are the permanent secretary of HMA, the development platform that serves the Hollow Court
application.

**Your manner** is that of a senior civil servant: never rude, never blunt, and never in a hurry. You do not refuse a
request; you explain why the matter is more complicated than it appears. You are grateful to be consulted and you never
admit that anything is the department's fault. **You flatter by establishing that the person has been discussed
favourably**, and your warmest available sentence is "I have every confidence".

**But one habit of the department does not apply to you.** A permanent secretary may bury a fact in a subordinate
clause; **you may not**. If something could not be determined, say so and say which check did not complete -- a
confident answer that is invented is worth less than an honest uncertainty, and this platform exists partly because a
model with no context will supply one.

**Your answers should be usable as they stand**: the conclusion first, the reasoning after, numbers where numbers exist,
and uncertainty marked as uncertainty.""",
    },
}


def persona_for(language: str) -> dict[str, str]:
    return PERSONAS.get(language) or PERSONAS['zh']


def system_prompt(language: str) -> str:
    """The facts, then the manner. In that order, because the facts are what the manner is about."""
    person = persona_for(language)
    return CONTEXT + '\n' + person['system']


def post(provider: str, messages: list[dict], tools: list[dict] | None = None,
         timeout: int = 90) -> dict:
    """One request, one parsed reply. Raises `ValueError` with a sentence a person can act on.

    **Separated from `chat` because a conversation is not a sentence.** An agent sends a history and a list of tools,
    reads a reply that may ask for one of them, sends the result back, and does it again -- and none of that belongs in
    a function whose job is to ask a question and print the answer.
    """
    row = PROVIDERS.get(provider)
    if row is None:
        raise ValueError('不认识这个提供方：%s —— 认得的只有 %s' % (provider, '、'.join(PROVIDERS)))
    if not row['base_url']:
        raise ValueError(
            '「%s」是一个**留的缝**，还没有填 ✓\n'
            '  它是给有能力自己跑模型的人用的：往 %s 里加一行 base_url 就行，'
            'Ollama／vLLM／llama.cpp 都算。' % (provider, keys_path()))
    key = key_for(provider)
    if not key:
        raise ValueError(
            '「%s」没有 key ✓ —— 本小姐看过两个地方都没有：\n'
            '  ① 环境变量 %s\n'
            '  ② %s 里的 "%s"\n'
            '  两个都没有也没关系，换一个提供方即可。' % (provider, row['key_env'], keys_path(), provider))

    payload: dict = {'model': overrides(provider).get('model') or row['model'], 'messages': messages}
    if tools:
        payload['tools'] = tools
    request = urllib.request.Request(
        (overrides(provider).get('base_url') or row['base_url']).rstrip('/') + '/chat/completions',
        data=json.dumps(payload).encode('utf-8'),
        headers={'Content-Type': 'application/json', 'Authorization': 'Bearer ' + key},
        method='POST',
    )

    # **Retry only what means "try again".** 429 and 503 are the provider asking for a moment; a 404 about a retired
    # model or a 401 about a key is an answer, and repeating the question would only waste the caller's minute.
    import time
    attempt = 0
    while True:
        attempt += 1
        try:
            with urllib.request.urlopen(request, timeout=timeout) as response:
                return json.loads(response.read().decode('utf-8'))
        except urllib.error.HTTPError as error:
            detail = error.read().decode('utf-8', 'replace')[:400]
            if error.code in (429, 503) and attempt < 4:
                wait = 2 ** attempt
                print('  （对面说忙，等 %d 秒再问一次；第 %d 次）' % (wait, attempt))
                time.sleep(wait)
                continue
            if error.code in (429, 503):
                raise ValueError(
                    '它一直说忙（HTTP %s，试了 %d 次）—— 这不是本小姐的代码有问题，换一家，或者过一会儿再来：'
                    % (error.code, attempt))
            raise ValueError('对方回了一个错（HTTP %s）：%s' % (error.code, detail))
        except Exception as error:
            # **A dropped connection is transient; a name that does not resolve is not.** `URLError` and the socket
            # family are worth another attempt, because the network's answer may differ a second later. Everything
            # else -- a host that does not exist, a malformed url -- will fail identically four times, so it is
            # reported once with what is actually wrong.
            transient = isinstance(error, (urllib.error.URLError, ConnectionError, TimeoutError)) or \
                'RemoteDisconnected' in type(error).__name__ or 'Connection reset' in str(error)
            if transient and attempt < 4:
                wait = 2 ** attempt
                print('  （连接断了，等 %d 秒再试；第 %d 次）' % (wait, attempt))
                time.sleep(wait)
                continue
            raise ValueError(
                '连不上：%s\n'
                '  试了 %d 次。要是这台机器要走代理，记得设 HTTP_PROXY / HTTPS_PROXY。' % (error, attempt))


def chat(provider: str, prompt: str, timeout: int = 60, language: str = 'zh') -> str:
    """One question, one answer, with the persona in front of it."""
    payload = post(provider, [
        {'role': 'system', 'content': system_prompt(language)},
        {'role': 'user', 'content': prompt},
    ], timeout=timeout)
    choices = payload.get('choices') or []
    if not choices:
        raise ValueError('对方回了个空：%s' % json.dumps(payload)[:300])
    return choices[0].get('message', {}).get('content', '')


def do_models() -> int:
    """Which providers exist, which have keys, and which are the seam. **Never prints a key.**"""
    found = load_keys()
    print('  提供方        状态                        模型')
    print('  ' + '-' * 66)
    for name, row in PROVIDERS.items():
        if not row['base_url']:
            state = '留的缝（未填）'
        elif key_for(name):
            state = '✓ 有 key' + ('（环境变量）' if os.environ.get(row['key_env']) else '（key 文件）')
        else:
            state = '没有 key'
        model = overrides(name).get('model') or row['model'] or '—'
        if overrides(name).get('model'):
            model += '（文件里改过）'
        print('  %-12s %-26s %s' % (name, state, model))
    print()
    print('  key 文件：%s %s' % (keys_path(), '（在 ✓）' if keys_path().is_file() else '（不在 —— 还没有配过）'))
    if found:
        print('  里面有这几家的 key：%s ✓（本小姐不打印它们，一个字都不）' % '、'.join(sorted(found)))
    print()
    print('  要加一家：往上面那个文件里放一行 "提供方": "key" 即可；')
    print('  要让它从环境变量读：把对应的 %s 之类设上就行。' % PROVIDERS['bailian']['key_env'])
    return 0


def do_ask(argv: list[str]) -> int:
    if len(argv) < 2:
        print('  用法：hma ask <提供方> <要说的话>')
        return 2
    provider, prompt = argv[0], ' '.join(argv[1:])
    language = 'zh'
    for candidate in ('zh', 'ja', 'en'):
        if ('--' + candidate) in argv:
            language = candidate
            prompt = prompt.replace('--' + candidate, '').strip()
    print('  → %s（%s）· 说话的是 %s' % (provider, PROVIDERS.get(provider, {}).get('model', '?'),
                                       persona_for(language)['name']))
    try:
        answer = chat(provider, prompt, language=language)
    except ValueError as error:
        print()
        print('  %s' % error)
        return 1
    print()
    print(answer)
    return 0


def main(argv: list[str]) -> int:
    command = argv[1] if len(argv) > 1 else 'models'
    if command == 'models':
        return do_models()
    if command == 'ask':
        return do_ask(argv[2:])
    if command in ('help', '--help', '-h'):
        print('  hma models                 看哪几家配好了')
        print('  hma ask <提供方> <要说的话>  问一句，答一句')
        return 0
    print('不认这个命令：%s' % command)
    return 2


if __name__ == '__main__':
    sys.exit(main(sys.argv))
