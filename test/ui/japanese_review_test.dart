import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

/// **The Japanese, checked for the defects a machine can see.**
///
/// This is not a native review and does not claim to be one -- a translation can be mechanically clean and read
/// oddly, and only a reader can say which. What it does is hold the line on the mistakes that are invisible to
/// somebody writing quickly and obvious to somebody reading, so the work a native reader is asked to do is
/// judgement rather than proofreading for punctuation.
///
/// **The first version of the check in `tool/ja_audit.py` was wrong, and the correction is the interesting
/// part.** It asked whether OpenCC's `s2t` changed a Japanese string, reasoning that only simplified-Chinese
/// glyphs change. It reported 48 strings and every one was a false positive: 数, 体, 内, 画, 残, 届, 称, 装,
/// 区, 価, 携, 台 are what **Japanese** writes, because Japan simplified those characters before China did. A
/// check whose premise is "Chinese simplification is the only simplification" finds the whole language guilty.
/// What is worth checking is where the two *diverge*, which is the curated list below.
void main() {
  /// Chinese simplified characters whose Japanese form is different -- **only** the divergent ones.
  const divergent = {
    '滤': '濾', '浓': '濃', '录': '録', '说': '説', '读': '読', '单': '単', '关': '関', '银': '銀', '铁': '鉄',
    '让': '譲', '认': '認', '贝': '貝', '车': '車', '门': '門', '长': '長', '边': '辺', '齐': '斉', '卖': '売',
    '买': '買', '转': '転', '传': '伝', '发': '発', '对': '対', '经': '経', '缘': '縁', '觉': '覚', '图': '図',
    '团': '団', '实': '実', '变': '変', '战': '戦', '举': '挙', '继': '継', '续': '続', '织': '織', '绞': '絞',
    '绍': '紹', '纯': '純', '纸': '紙', '纷': '紛', '纲': '綱', '纵': '縦', '轮': '輪', '轻': '軽', '较': '較',
    '载': '載', '输': '輸', '过': '過', '还': '還', '进': '進', '远': '遠', '违': '違', '连': '連', '迟': '遅',
    '适': '適', '选': '選', '逻': '邏', '遗': '遺', '邮': '郵', '钢': '鋼', '钱': '銭', '针': '針', '钟': '鐘',
    '铃': '鈴', '铅': '鉛', '铜': '銅', '锅': '鍋', '键': '鍵', '镜': '鏡', '询': '詢', '诗': '詩', '诚': '誠',
    '话': '話', '诞': '誕', '语': '語', '误': '誤', '请': '請', '诸': '諸', '课': '課', '谁': '誰', '调': '調',
    '谈': '談', '谢': '謝', '负': '負', '贡': '貢', '财': '財', '责': '責', '败': '敗', '货': '貨', '质': '質',
    '贵': '貴', '费': '費', '资': '資', '赛': '賽', '赞': '賛', '赶': '趕', '轨': '軌', '摆': '擺', '摄': '摂',
    '摊': '攤', '构': '構', '样': '様', '标': '標', '树': '樹', '检': '検', '欢': '歓', '步': '歩',
  };

  /// Every Japanese string this repository ships: the interface and the library, with where each came from.
  Map<String, String> japaneseStrings() {
    final found = <String, String>{};

    final theme = File('lib/ui/theme.dart');
    if (theme.existsSync()) {
      final source = theme.readAsStringSync();
      // `'ja': '...'` inside the CopyLine definitions. Read crudely on purpose: this is an audit, and a missed
      // string shows up as a smaller count rather than as a wrong verdict -- which the size assertion below
      // catches.
      final pattern = RegExp(r"'ja':\s*'((?:[^'\\]|\\.)*)'");
      var index = 0;
      for (final match in pattern.allMatches(source)) {
        found['theme[${index++}]'] = match.group(1)!;
      }
    }

    final names = File('data/names/names.json');
    if (names.existsSync()) {
      final decoded = jsonDecode(names.readAsStringSync()) as Map<String, Object?>;
      for (final section in const ['ingredients', 'recipes']) {
        final table = (decoded[section] as Map<String, Object?>?) ?? const {};
        table.forEach((key, value) {
          final ja = (value as Map<String, Object?>)['ja'];
          if (ja is String && ja.isNotEmpty) found['$section:$key'] = ja;
        });
      }
      final steps = (decoded['steps'] as Map<String, Object?>?) ?? const {};
      steps.forEach((key, value) {
        final byLocale = value as Map<String, Object?>;
        final ja = byLocale['ja'];
        if (ja is List) {
          for (var i = 0; i < ja.length; i++) {
            found['steps:$key[$i]'] = '${ja[i]}';
          }
        }
      });
    }
    return found;
  }

  test('the audit can see the strings it is auditing', () {
    // **First, proof that the extraction works.** A punctuation check that finds nothing because it is reading
    // nothing looks exactly like a clean translation, and the earlier version of this audit produced a false
    // "48 findings" precisely because nobody had checked what it was reading.
    final strings = japaneseStrings();
    expect(
      strings.length,
      greaterThan(600),
      reason: 'the interface and the library together are several hundred Japanese strings',
    );
  });

  test('**no Japanese line carries a character that only Chinese writes that way**', () {
    final offenders = <String, String>{};
    japaneseStrings().forEach((where, text) {
      final hits = [for (final character in text.split('')) if (divergent.containsKey(character)) character];
      if (hits.isNotEmpty) {
        offenders[where] = '${hits.join()} in "$text" should be '
            '${hits.map((c) => divergent[c]).join()}';
      }
    });
    expect(offenders, isEmpty, reason: offenders.toString());
  });

  test('**the punctuation is Japanese: 、 and 。, never ， or ！**', () {
    final offenders = <String, String>{};
    japaneseStrings().forEach((where, text) {
      for (final wrong in const ['，', '！', '；']) {
        if (text.contains(wrong)) offenders[where] = wrong;
      }
    });
    expect(offenders, isEmpty, reason: offenders.toString());
  });

  test('**and a word is spelled one way throughout**, longest match first', () {
    // The check counts **substrings** unless it is careful, and the first version was not: キュラソ matched
    // inside キュラソー, so one word looked like two spellings and the audit reported a defect that did not
    // exist. Longest form first, each match consumed.
    const variants = {
      'whisky': ['ウイスキー', 'ウィスキー'],
      'champagne': ['シャンパン', 'シャンパーニュ'],
      'martini': ['マティーニ', 'マルティーニ'],
      'curacao': ['キュラソー', 'キュラソ'],
    };
    final strings = japaneseStrings().values.toList();

    for (final entry in variants.entries) {
      final totals = <String, int>{for (final form in entry.value) form: 0};
      for (final text in strings) {
        var rest = text;
        for (final form in ([...entry.value]..sort((a, b) => b.length.compareTo(a.length)))) {
          while (rest.contains(form)) {
            totals[form] = totals[form]! + 1;
            rest = rest.replaceFirst(form, '\u0000' * form.length);
          }
        }
      }
      final used = {for (final e in totals.entries) if (e.value > 0) e.key: e.value};
      expect(
        used.length,
        lessThanOrEqualTo(1),
        reason: '${entry.key} is spelled more than one way: $used',
      );
    }
  });
}
