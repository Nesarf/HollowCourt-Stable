# Proofreads `data/names/names.json` against Wikipedia, and reports rather than edits.
#
#     python tool/seed_name_audit.py            # report
#     python tool/seed_name_audit.py --json     # the same, machine-readable
#
# **Why Wikipedia, and why this file exists.** The owner's instruction on 2026-09-23 was *"make sure every
# language has a complete translation, and proofread it against information on the web"*, and the same afternoon
# produced the worked example: Daiquiri, which this file had under one Chinese name in one entry and under two
# spellings of another in a second, while the Chinese Wikipedia article is 「黛綺莉」 (with 黛绮丽 as a redirect,
# so both spellings are recognised).
#
# Three kinds of finding, in the order they matter:
#
#   1. **A machine-conversion trap.** Hong Kong and Taiwan Traditional were generated from Simplified Chinese by
#      OpenCC, which cannot tell 干 (dry) from 幹 (to do) or a transliteration's 里 from 裡/裏. That produced a
#      *dry* martini named with 幹 and a Tipperary name ending in 裏. These are wrong in any context and are the
#      safest thing to fix.
#   2. **A term Wikipedia's own conversion table disagrees with.** `Module:CGroup/Food` is the table Chinese
#      Wikipedia uses to convert food and drink articles between the mainland, Taiwan, Hong Kong and Macau, so it
#      is the closest thing to an authority on regional vocabulary -- and it settled 車厘子 (HK cherry),
#      氈酒 (HK gin), 朱古力 (HK chocolate), 通寧水 (TW tonic) and the rest.
#   3. **A concept article wearing a drink's name.** The interlanguage link for *Zombie* is 喪屍 ("zombie") and for
#      *Bramble* is 悬钩子属 (the plant genus), so this kind is reported as a **candidate** and never applied:
#      an audit that renamed the Zombie 喪屍 would be worse than no audit.
#
# NETWORK: this machine reaches the internet only through the local proxy (`127.0.0.1:10090`), and
# `zh.wikipedia.org` resolves to a poisoned address, so every request here goes through the proxy. Nothing is
# written unless `--apply-traps` is passed, and even then only findings of kind 1.
import json
import os
import re
import subprocess
import sys
import urllib.parse

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROXY = 'http://127.0.0.1:10090'
UA = 'hollow-court-i18n-audit/1.0 (https://github.com/hollow-court)'

LIBRARY = os.path.join(ROOT, 'data', 'drinks', 'library.json')
NAMES = os.path.join(ROOT, 'data', 'names', 'names.json')

# The characters OpenCC gets wrong when the source character is ambiguous. Each one is a *word* error, not a
# glyph preference, which is why they are listed with what the right answer is rather than merely flagged.
TRAPS = {
    '幹': '乾 (dry)',
    '裏': '裡 or 里 (a transliteration keeps 里)',
    '週': '周',  # the week character, which OpenCC rewrites to a form Taiwan does not write
}


def fetch(url: str) -> str:
    done = subprocess.run(
        ['curl', '-sS', '--max-time', '60', '-x', PROXY, '-H', f'User-Agent: {UA}', url],
        capture_output=True, text=True, encoding='utf-8',
    )
    if done.returncode != 0:
        raise RuntimeError('curl failed: %s' % (done.stderr or '').strip())
    return done.stdout


def wiki_table() -> dict:
    """`Module:CGroup/Food` as {english term: {tag: name}}."""
    lua = fetch('https://zh.wikipedia.org/wiki/Module:CGroup/Food?action=raw')
    table: dict = {}
    for original, rules in re.findall(r"Item\(\s*'([^']*)'\s*,\s*'([^']*)'\s*\)", lua):
        if '=>' in rules:  # a conversion pair (「cookie」=>zh-cn:「biscuit」), not a term
            continue
        entry = {}
        for part in rules.split(';'):
            if ':' in part:
                tag, value = part.split(':', 1)
                entry[tag.strip().lower()] = value.strip()
        if original.strip() and entry:
            table.setdefault(original.strip().lower(), {}).update(entry)
    return table


def zh_titles(titles: list) -> dict:
    """English Wikipedia title -> its Chinese article title, in batches."""
    out = {}
    for start in range(0, len(titles), 25):
        batch = titles[start:start + 25]
        url = 'https://en.wikipedia.org/w/api.php?' + urllib.parse.urlencode({
            'action': 'query', 'format': 'json', 'prop': 'langlinks', 'lllang': 'zh',
            'redirects': '1', 'titles': '|'.join(batch),
        })
        page = json.loads(fetch(url)).get('query', {})
        chain = {r['from']: r['to'] for r in page.get('normalized', [])}
        for r in page.get('redirects', []):
            chain.setdefault(r['from'], r['to'])

        def resolve(title):
            seen = set()
            while title in chain and title not in seen:
                seen.add(title)
                title = chain[title]
            return title

        pages = {p.get('title'): p for p in page.get('pages', {}).values()}
        for our in batch:
            found = pages.get(resolve(our))
            links = found.get('langlinks') if found else None
            out[our] = links[0]['*'] if links else None
    return out


def region(entry: dict, tag: str):
    if tag == 'zh-Hans':
        return entry.get('zh-cn') or entry.get('zh-hans')
    if tag == 'zh-HK':
        return entry.get('zh-hk')
    if tag == 'zh-TW':
        return entry.get('zh-tw')
    return None


def main() -> int:
    as_json = '--json' in sys.argv
    library = json.load(open(LIBRARY, encoding='utf-8'))
    names = json.load(open(NAMES, encoding='utf-8'))

    english = {i['id']: i['name'] for i in library['ingredients']}
    english.update({r['id']: r['name'] for r in library['recipes']})
    where = {i['id']: 'ingredients' for i in library['ingredients']}
    where.update({r['id']: 'recipes' for r in library['recipes']})

    report = {'traps': [], 'table': [], 'titles': []}

    # 1. traps
    for key, section in where.items():
        for tag in ('zh-HK', 'zh-TW'):
            text = names[section].get(key, {}).get(tag, '')
            for bad, right in TRAPS.items():
                if bad in text:
                    report['traps'].append({
                        'id': key, 'tag': tag, 'text': text, 'char': bad, 'should_be': right,
                    })

    # 2. Wikipedia's regional vocabulary
    table = wiki_table()
    for key, section in where.items():
        entry = table.get((english.get(key) or '').strip().lower())
        if not entry:
            continue
        for tag in ('zh-Hans', 'zh-HK', 'zh-TW'):
            want = region(entry, tag)
            have = names[section].get(key, {}).get(tag)
            if want and have and want != have:
                report['table'].append({'id': key, 'tag': tag, 'ours': have, 'wikipedia': want})

    # 3. candidate article titles (never applied automatically)
    titles = zh_titles([n for n in english.values() if n])
    for key, section in where.items():
        zh = titles.get(english.get(key))
        ours = names[section].get(key, {}).get('zh-Hans')
        if zh and ours and zh != ours:
            report['titles'].append({'id': key, 'ours': ours, 'wikipedia': zh})

    if as_json:
        print(json.dumps(report, ensure_ascii=False, indent=2))
        return 0

    print('== machine-conversion traps (%d) ==' % len(report['traps']))
    for t in report['traps']:
        print('   %-24s %-6s %-14s  %s is %s' % (t['id'], t['tag'], t['text'], t['char'], t['should_be']))
    print('== Wikipedia term table disagrees (%d) ==' % len(report['table']))
    for t in report['table']:
        print('   %-24s %-6s ours %-12s wikipedia %s' % (t['id'], t['tag'], t['ours'], t['wikipedia']))
    print('== candidate titles, review by hand (%d) ==' % len(report['titles']))
    for t in report['titles']:
        print('   %-24s ours %-16s wikipedia %s' % (t['id'], t['ours'], t['wikipedia']))
    print('\nKind 3 includes concept articles (Zombie -> the Chinese word for a zombie, Bramble -> the\n'
          'plant genus): read before believing.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
