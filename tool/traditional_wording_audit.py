"""Audit the Hong Kong and Taiwan Traditional wording in the interface, mechanically.

    PYTHONPATH=E:/DaShaoHuo/Python/opencc_lib python tool/traditional_wording_audit.py [--fix]

**What this is for.** DESIGN.md 12.4.1 records the position that `zh-HK` and `zh-TW` are **delivered rather than
localised**: OpenCC converts the characters, and no converter reworks a sentence. The remaining work was named
there as a Traditional-Chinese wording review -- and a review needs to start from a list rather than from 207
lines.

**Two checks, and they are different kinds of thing.**

1. **A simplified glyph inside a Traditional line is a defect, and it is *almost* exact.** Asked of OpenCC
   itself: a character is flagged when `s2t(c)` returns something else, so the check needs no hand-written table.
   **It is not exact, and the first run proved it**: 17 of its first 18 hits were `台 -> 臺`, which is not a defect
   at all -- `台` is a traditional character in its own right (一台電腦, 台灣) and `s2t` merely normalises a
   variant.
   So the flagged set is *variant forms plus simplified glyphs*, and the judgement that separates them is the
   whitelist below. A checker's whitelist is a claim, and this one claims only that these are written this way
   in Taiwan and Hong Kong.
2. **Mainland vocabulary is a candidate, not a defect.** "video", "software", "default" -- the same characters
   can be correct in one region and read as foreign in another, and only a reader decides. The table below is a
   starting list with the Taiwan/Hong Kong equivalent beside each entry, and a hit means "look at this line",
   nothing stronger.

**And the table is not a converter.** `s2twp` already carries a phrase table, which is why most hits are zero;
what this finds is what survives it. Anything applied by `--fix` is applied **only inside `zh-HK`/`zh-TW`
strings**, and the result is still the delivered register, not a localised one.
"""

import io
import os
import re
import sys

THEME = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'lib', 'ui', 'theme.dart')
QUOTE = chr(39)
BACKSLASH = chr(92)

DEFINITION = re.compile(r'static const (\w+) = CopyLine')

# Mainland term -> the Taiwan/Hong Kong term. `zh-HK` and `zh-TW` differ among themselves on some of these and
# the pair given is the common one; a line that reads better another way is the reader's call.
TERMS = [
    ('视频', '影片'), ('音频', '音訊'), ('摄像头', '攝影機'), ('分辨率', '解析度'),
    ('软件', '軟體'), ('硬件', '硬體'), ('固件', '韌體'), ('程序', '程式'),
    ('代码', '程式碼'), ('变量', '變數'), ('函数', '函式'), ('数组', '陣列'),
    ('字符串', '字串'), ('缓存', '快取'), ('端口', '連接埠'), ('网络', '網路'),
    ('服务器', '伺服器'), ('数据库', '資料庫'), ('端口号', '連接埠號'),
    ('内存', '記憶體'), ('硬盘', '硬碟'), ('文件夹', '資料夾'), ('文件', '檔案'),
    ('进程', '行程'), ('删除', '刪除'), ('加载', '載入'), ('保存', '儲存'),
    ('设置', '設定'), ('默认', '預設'), ('配置', '設定'), ('信息', '資訊'),
    ('数据', '資料'), ('用户', '使用者'), ('界面', '介面'), ('打印', '列印'),
    ('屏幕', '螢幕'), ('显示器', '螢幕'), ('鼠标', '滑鼠'), ('键盘', '鍵盤'),
    ('剪贴板', '剪貼簿'), ('光标', '游標'), ('向导', '精靈'), ('复选框', '核取方塊'),
    ('选项卡', '索引標籤'), ('对话框', '對話方塊'), ('下拉菜单', '下拉式選單'),
    ('在线', '線上'), ('登录', '登入'), ('登陆', '登入'), ('注册', '註冊'),
    ('账号', '帳號'), ('账号名', '帳號名稱'), ('短信', '簡訊'), ('邮件', '郵件'),
    ('搜索', '搜尋'), ('支持', '支援'), ('项目', '專案'), ('质量', '品質'),
    ('检测', '偵測'), ('反馈', '回饋'), ('蓝牙', '藍牙'), ('备份', '備份'),
    ('恢复', '還原'), ('算法', '演算法'), ('开源', '開源'), ('编译', '編譯'),
    ('移动端', '行動版'), ('智能手机', '智慧型手機'), ('视频通话', '視訊通話'),
    ('视频会议', '視訊會議'), ('命令行', '命令列'), ('自动化', '自動化'),
    ('笔记本电脑', '筆記型電腦'), ('智能', '智慧'), ('驱动', '驅動程式'),
    ('文件系统', '檔案系統'), ('网络连接', '網路連線'), ('截屏', '螢幕截圖'),
]

# Characters `s2t` rewrites that are not defects: the left form is ordinary traditional writing and the right is
# the variant OpenCC normalises to. `台` is the one that matters here -- it is how Taiwan writes 台灣 and 一台電腦,
# and flagging it 17 times is what taught the difference between a variant and a simplified glyph.
VARIANT_FORMS = set('台里着么并于才只后冲志松谷采布划御弥脉凶污决况凉净减凑准几凭床沈注泄涂涌')


def dart_string(text, start):
    """Read the single-quoted Dart literal beginning at `start`. Returns (value, index past it)."""
    assert text[start] == QUOTE, text[start - 20:start + 20]
    out = []
    i = start + 1
    while i < len(text):
        ch = text[i]
        if ch == BACKSLASH:
            out.append(text[i:i + 2])
            i += 2
            continue
        if ch == QUOTE:
            return ''.join(out), i + 1
        out.append(ch)
        i += 1
    return ''.join(out), i


def locale_strings(source, name, block, locale):
    """Every literal attached to `locale` inside one CopyLine definition."""
    found = []
    for match in re.finditer("'%s'" % locale, block):
        after = match.end()
        while after < len(block) and block[after] in ' :\t\n':
            after += 1
        if after < len(block) and block[after] == QUOTE:
            value, _ = dart_string(block, after)
            found.append((match.start(), match.end(), value))
    return found


def simplified_glyphs(text):
    """Characters `s2t` would change, minus the variant forms that are correct traditional writing.

    **A line that quotes Japanese keeps Japanese glyphs**, which is why the one remaining hit was in
    `aboutNaming`: its Japanese arm is a quotation of the Japanese title, and replacing `虚` with `虛` would
    misquote it. Kana in the same line is the signal that this is a quotation rather than a mistranslation, so
    such lines are skipped whole rather than the character being whitelisted -- a whitelisted character would be
    missed in a line that really did spell it wrong.
    """
    from opencc import OpenCC

    if any('\u3040' <= c <= '\u30ff' for c in text):
        return []
    converter = OpenCC('s2t')
    out = []
    for character in set(text):
        if not '\u4e00' <= character <= '\u9fff':
            continue
        if character in VARIANT_FORMS:
            continue
        converted = converter.convert(character)
        if converted != character:
            out.append((character, converted))
    return sorted(out)


def main():
    fix = '--fix' in sys.argv
    source = io.open(THEME, encoding='utf-8').read()

    definitions = []
    for match in DEFINITION.finditer(source):
        name = match.group(1)
        rest = source[match.start():]
        next_definition = rest.find('static const ', 10)
        definitions.append((name, rest if next_definition < 0 else rest[:next_definition]))

    glyph_hits = []
    term_hits = []
    reviewed = 0
    for name, block in definitions:
        for locale in ('zh-HK', 'zh-TW'):
            for _start, _end, value in locale_strings(source, name, block, locale):
                reviewed += 1
                for bad, good in simplified_glyphs(value):
                    glyph_hits.append((name, locale, bad, good, value))
                for mainland, regional in TERMS:
                    if mainland in value:
                        term_hits.append((name, locale, mainland, regional, value))

    print('CopyLine definitions: %d' % len(definitions))
    print('zh-HK/zh-TW strings reviewed: %d' % reviewed)
    print('')
    print('1. simplified glyphs inside a Traditional line: %d' % len(glyph_hits))
    for name, locale, bad, good, value in glyph_hits[:20]:
        print('   %-24s %-6s %s -> %s   %s' % (name, locale, bad, good, value[:50]))
    print('')
    print('2. mainland vocabulary: %d candidates' % len(term_hits))
    seen = {}
    for name, locale, mainland, regional, value in term_hits:
        seen.setdefault((mainland, regional), []).append(name)
    for (mainland, regional), names in sorted(seen.items(), key=lambda kv: -len(kv[1])):
        print('   %-10s -> %-10s %2d lines   %s' % (mainland, regional, len(names), ', '.join(names[:4])))
    if term_hits:
        print('')
        for name, locale, mainland, regional, value in term_hits:
            print('   %-22s %-6s %s -> %s' % (name, locale, mainland, regional))
            print('      %s' % value[:120])
    return 0 if not glyph_hits else 1


if __name__ == '__main__':
    sys.exit(main())
