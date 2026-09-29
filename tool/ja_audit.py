"""Audit the Japanese in this repository for the defects a machine can see.

Not a substitute for a native reader, and it does not claim to be one. It looks for the classes of mistake a
translation written by a non-native speaker actually makes and that are mechanically findable.

**All three checks in this file were wrong once, and the corrections are worth more than the checks.**

1. The first version asked OpenCC's `s2t` whether a Japanese string changed, reasoning that only
   Chinese simplification changes. It reported **48** strings and every one was a false positive: 数, 体, 内,
   画, 残, 届, 称, 装, 区, 価, 携, 台 are what Japanese writes, because Japan simplified those characters
   before China did. A check whose premise is "Chinese simplification is the only simplification" finds the
   whole Japanese language guilty. What is worth checking is where the two **diverge** (濾/滤, 濃/浓, 録/录),
   which needs a curated list because no rule distinguishes 数 (both languages write it) from 滤 (Chinese only).
2. The terminology check counted **substrings**, so キュラソ matched inside キュラソー and one word looked like
   two spellings. Longest form first, each match consumed.
3. The punctuation check flagged a string mixing 。 with `.` -- which was `.courtpack`, a file extension. A
   check that cannot tell a sentence from a filename reports the filename.

Run: python tool/ja_audit.py
The two checks that need no Chinese tables live in `test/ui/japanese_review_test.dart`, so they run with the
suite rather than when somebody remembers.
"""

import io
import json
import re
import sys

THEME = r"E:\hollow-court\lib\ui\theme.dart"
NAMES = r"E:\hollow-court\data\names\names.json"

JA_IN_THEME = re.compile(r"'ja':\s*'((?:[^'\\]|\\.)*)'")

# Where Chinese simplified and Japanese diverge, so a Chinese character in a Japanese line is a leak.
DIVERGENT = {
    "滤": "濾", "浓": "濃", "录": "録", "说": "説", "读": "読", "单": "単", "关": "関", "银": "銀", "铁": "鉄",
    "让": "譲", "认": "認", "贝": "貝", "车": "車", "门": "門", "长": "長", "边": "辺", "齐": "斉", "卖": "売",
    "买": "買", "转": "転", "传": "伝", "发": "発", "对": "対", "经": "経", "缘": "縁", "觉": "覚", "图": "図",
    "团": "団", "实": "実", "变": "変", "战": "戦", "举": "挙", "继": "継", "续": "続", "织": "織", "绞": "絞",
    "绍": "紹", "纯": "純", "纸": "紙", "纷": "紛", "纲": "綱", "纵": "縦", "轮": "輪", "轻": "軽", "较": "較",
    "载": "載", "输": "輸", "过": "過", "还": "還", "进": "進", "远": "遠", "违": "違", "连": "連", "迟": "遅",
    "适": "適", "选": "選", "逻": "邏", "遗": "遺", "邮": "郵", "钢": "鋼", "钱": "銭", "针": "針", "钟": "鐘",
    "铃": "鈴", "铅": "鉛", "铜": "銅", "锅": "鍋", "键": "鍵", "镜": "鏡", "询": "詢", "诗": "詩", "诚": "誠",
    "话": "話", "诞": "誕", "语": "語", "误": "誤", "请": "請", "诸": "諸", "课": "課", "谁": "誰", "调": "調",
    "谈": "談", "谢": "謝", "负": "負", "贡": "貢", "财": "財", "责": "責", "败": "敗", "货": "貨", "质": "質",
    "贵": "貴", "费": "費", "资": "資", "赛": "賽", "赞": "賛", "赶": "趕", "轨": "軌", "摆": "擺", "摄": "摂",
    "摊": "攤", "构": "構", "样": "様", "标": "標", "树": "樹", "检": "検", "欢": "歓", "步": "歩",
}

CHINESE_PUNCTUATION = ["，", "！", "；"]

VARIANTS = {
    "whisky": ["ウイスキー", "ウィスキー"],
    "champagne": ["シャンパン", "シャンパーニュ"],
    "martini": ["マティーニ", "マルティーニ"],
    "vermouth": ["ベルモット", "ヴェルモット"],
    "curacao": ["キュラソー", "キュラソ"],
    "liqueur": ["リキュール", "リキュール"],
}

CHINESE_WORDS = ["吧勺", "酒单", "酒窖", "配方", "单位", "货币", "记录", "设置"]


def strings_in_theme(source):
    return [m.group(1) for m in JA_IN_THEME.finditer(source)]


def strings_in_names(names):
    found = []
    for section in ("ingredients", "recipes"):
        for key, langs in names.get(section, {}).items():
            if langs.get("ja"):
                found.append(("%s:%s" % (section, key), langs["ja"]))
    for key, by_locale in names.get("steps", {}).items():
        for index, step in enumerate(by_locale.get("ja", [])):
            found.append(("steps:%s[%d]" % (key, index), step))
    return found


def count_variants(text, forms):
    """Longest first, each match consumed -- see the module comment for why."""
    counts = {form: 0 for form in forms}
    rest = text
    for form in sorted(forms, key=len, reverse=True):
        while form in rest:
            counts[form] += 1
            rest = rest.replace(form, "\u0000" * len(form), 1)
    return counts


def main():
    theme = io.open(THEME, encoding="utf-8").read()
    names = json.load(io.open(NAMES, encoding="utf-8"))
    strings = [("theme", text) for text in strings_in_theme(theme)] + strings_in_names(names)
    print("japanese strings found: %d" % len(strings))
    if len(strings) < 100:
        print("too few to be real -- the extraction has gone wrong, not the translations")
        return 1

    findings = 0

    leaked = [k for k, t in strings if any(c in DIVERGENT for c in t)]
    print("\n[1] divergent Chinese glyphs in a Japanese line: %d" % len(leaked))
    for key in leaked[:20]:
        print("    %s" % key)
    findings += len(leaked)

    punctuated = [k for k, t in strings if any(p in t for p in CHINESE_PUNCTUATION)]
    print("\n[2] Chinese punctuation: %d" % len(punctuated))
    for key in punctuated[:20]:
        print("    %s" % key)
    findings += len(punctuated)

    print("\n[3] terminology:")
    for name, forms in VARIANTS.items():
        totals = {form: 0 for form in forms}
        for _key, text in strings:
            for form, count in count_variants(text, forms).items():
                totals[form] += count
        used = {form: n for form, n in totals.items() if n}
        if len(used) > 1:
            print("    INCONSISTENT %-12s %s" % (name, used))
            findings += 1
        elif used:
            print("    ok           %-12s %s" % (name, used))

    left = [(k, w) for k, t in strings for w in CHINESE_WORDS if w in t]
    print("\n[4] Chinese words inside a Japanese line: %d" % len(left))
    for key, word in left[:20]:
        print("    %-30s %s" % (key, word))
    findings += len(left)

    print("\nfindings: %d" % findings)
    return 0


if __name__ == "__main__":
    sys.exit(main())
