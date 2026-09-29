# Adds 港繁 and 台繁 to every CopyLine that has a 简中 line, converting rather than falling back.
#
#     PYTHONPATH=E:/DaShaoHuo/Python/opencc_lib python tool/generate_chinese_variants.py [--dry]
#
# **Why this is Python in a Dart repository.** The conversion needs OpenCC -- the table set the rest of the
# Chinese-speaking world uses, and the only reliable way to get *settings*, *software*, *network* into the
# Taiwan and Hong Kong words rather than merely swapping glyphs. There is no Dart port worth trusting for this,
# and hand-writing 163 lines twice is 326 chances to write the mistaken variant of a character. `opencc-python-reimplemented` is
# installed under `E:\DaShaoHuo\Python\opencc_lib`; this script is the record of exactly what was generated,
# so the result can be reproduced, reviewed, or corrected.
#
# **What it does NOT do: literary Chinese.** Literary Chinese is a register rather than a script and no
# converter produces it, so `lzh` is left to be authored by hand -- a translation project of its own, and
# deliberately not faked here.
#
# The rules, and why each exists:
#
#   * `zh-HK` from OpenCC's `s2hk`; `zh-TW` from `s2twp`, the phrase-aware Taiwan table.
#   * **A line that already names the variant is left alone.** A hand-written translation always wins over a
#     generated one, and running this twice must not overwrite somebody's correction.
#   * Edits are collected first and applied **from the end backwards**, so no position shifts while the file
#     is being rewritten. The first version of this re-scanned after every edit and would have been one bug
#     away from corrupting the file it was editing.
import io
import re
import sys

THEME = r'E:\hollow-court\lib\ui\theme.dart'
QUOTE = chr(39)
BACKSLASH = chr(92)

DEFINITION = re.compile(r'static const (\w+) = CopyLine(?:\.withLanguages)?\(')
HAN = re.compile(r'[\u4e00-\u9fff]')


def end_of_call(text: str, open_paren: int) -> int:
    """Index just past the matching ')', skipping string literals and their escapes."""
    depth = 0
    i = open_paren
    while i < len(text):
        ch = text[i]
        if ch == QUOTE or ch == '"':
            quote = ch
            i += 1
            while i < len(text):
                if text[i] == BACKSLASH:
                    i += 2
                    continue
                if text[i] == quote:
                    break
                i += 1
        elif ch == '(':
            depth += 1
        elif ch == ')':
            depth -= 1
            if depth == 0:
                return i + 1
        i += 1
    raise ValueError('unbalanced parentheses at %d' % open_paren)


def main() -> int:
    dry = '--dry' in sys.argv
    from opencc import OpenCC  # noqa: PLC0415 -- optional dependency, reported if missing

    to_hk = OpenCC('s2hk')
    to_tw = OpenCC('s2twp')

    text = io.open(THEME, encoding='utf-8').read()

    edits = []  # (start, end, replacement)
    added_hk = added_tw = skipped = 0

    for match in DEFINITION.finditer(text):
        close = end_of_call(text, match.end() - 1)
        body = text[match.start():close]
        literals = re.findall(r"'([^']*)'", body)
        if not literals or not HAN.search(literals[0]):
            # A definition with no Chinese at all (a few are English-first), or one this script cannot
            # read. Skipping is reported rather than silent.
            skipped += 1
            continue

        simplified = literals[0]
        want = {}
        if "'zh-HK'" not in body:
            want['zh-HK'] = to_hk.convert(simplified)
        if "'zh-TW'" not in body:
            want['zh-TW'] = to_tw.convert(simplified)
        if not want:
            skipped += 1
            continue

        entries = ', '.join("'%s': '%s'" % (key, value) for key, value in want.items())
        if 'also: {' in body:
            new_body = body.replace('also: {', 'also: {%s, ' % entries, 1)
        else:
            head = body[:-1].rstrip()
            separator = '' if head.endswith(',') else ','
            new_body = head + ('%s also: {%s})' % (separator, entries))
            new_body = new_body.replace('= CopyLine(', '= CopyLine.withLanguages(', 1)

        edits.append((match.start(), close, new_body))
        added_hk += 1 if 'zh-HK' in want else 0
        added_tw += 1 if 'zh-TW' in want else 0

    # Backwards, so every earlier position stays valid.
    for start, end, replacement in reversed(edits):
        text = text[:start] + replacement + text[end:]

    print('zh-HK added: %d, zh-TW added: %d, skipped: %d' % (added_hk, added_tw, skipped))
    if dry:
        print('--dry: nothing written.')
    else:
        io.open(THEME, 'w', encoding='utf-8', newline='').write(text)
        print('written: lib/ui/theme.dart')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
