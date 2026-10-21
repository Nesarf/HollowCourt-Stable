// ignore_for_file: avoid_print
//
// Dumps every voiced line as a page somebody can read in one sitting.
//
//     dart run tool/voice_dump.dart                       # to stdout
//     dart run tool/voice_dump.dart --out ../somewhere.md # to a file
//
// **Why this exists rather than a second hand-written list.** `docs/voice-reading-copy.md` was assembled by hand
// from the same definitions, and it covers 42 of them. The judgement the voices need -- "does this sound like her" --
// is a reading job, so it needs the whole set in front of a person rather than a sample; but a hand-maintained copy
// drifts from `lib/ui/theme.dart` the first time somebody edits one and not the other, which is the fault this
// project has recorded three times in its own documentation. So the page is generated, and the generated copy says
// where it came from and is not committed.
//
// The parse is the same shape as `voice_status.dart` on purpose: both walk `lib/ui/theme.dart` as text, because the
// definitions are `const` and a `dart:mirrors` pass would need the application to build.
import 'dart:io';

class _Line {
  _Line(this.id, this.source);

  final String id;
  final String source;
}

List<_Line> _definitions(String path) {
  final lines = File(path).readAsStringSync().split('\n');
  final found = <_Line>[];
  String? current;
  var body = StringBuffer();
  var depth = 0;

  void flush() {
    if (current != null) found.add(_Line(current!, body.toString()));
    current = null;
    body = StringBuffer();
  }

  for (final line in lines) {
    final start = RegExp(r'static const (\w+) = CopyLine').firstMatch(line);
    if (start != null) {
      flush();
      current = start.group(1);
    }
    if (current == null) continue;
    body.writeln(line);
    depth += '{:('.split('').map((c) => line.split(c).length - 1).reduce((a, b) => a + b);
    depth -= '})'.split('').map((c) => line.split(c).length - 1).reduce((a, b) => a + b);
    if (depth <= 0 && body.toString().contains(');')) flush();
  }
  flush();
  return found;
}

/// The first `Translated.authored('...')` in a definition, in the order they appear.
List<String> _authored(String body) => RegExp(r"Translated\.authored\('((?:[^'\\]|\\.)*)'\)")
    .allMatches(body)
    .map((m) => m.group(1)!)
    .toList();

/// `Voice.<name>: '...'`, one entry per voice, in source order.
Map<String, String> _voices(String body) {
  final found = <String, String>{};
  for (final match in RegExp(r"Voice\.(\w+):\s*'((?:[^'\\]|\\.)*)'").allMatches(body)) {
    found[match.group(1)!] = match.group(2)!;
  }
  return found;
}

String _label(String voice) => switch (voice) {
      'heiress' => '伊丽莎白',
      'heiressJa' => 'ツンデレお嬢様',
      'minister' => 'Yes, Minister',
      _ => voice,
    };

void main(List<String> args) {
  final out = args.contains('--out') ? args[args.indexOf('--out') + 1] : null;

  final all = _definitions('lib/ui/theme.dart');
  final voiced = <_Line>[];
  final unvoicedProse = <String, String>{};

  for (final line in all) {
    final voices = _voices(line.source);
    if (voices.isEmpty) {
      final authored = _authored(line.source);
      final chinese = authored.isNotEmpty ? authored.first : '';
      if (chinese.runes.length >= 18) unvoicedProse[line.id] = chinese;
      continue;
    }
    voiced.add(line);
  }

  final buffer = StringBuffer()
    ..writeln('# 声音读样 · 全量 ${voiced.length} 件')
    ..writeln()
    ..writeln('**生成自 `lib/ui/theme.dart`**（`dart run tool/voice_dump.dart`），不是手抄的，也不要提交进仓库 ——')
    ..writeln('另存一份就会变成第二个事实源，而这份文件的价值恰恰在于它每次都能重新生成。')
    ..writeln()
    ..writeln('原句取每个定义的第一个 `Translated.authored(...)`，也就是这一行没人扮声音时会显示的中文。')
    ..writeln()
    ..writeln('**判据**：`voice_facts_test` 守「改写不许丢事实」，`voice_test` 守「不许回落」，')
    ..writeln('`voice_register_test` 守语气 —— 但它们都判断不了「像不像她」。那一条只能由读的人给。')
    ..writeln()
    ..writeln('---')
    ..writeln();

  final order = ['heiress', 'heiressJa', 'minister'];
  for (final line in voiced) {
    final voices = _voices(line.source);
    final authored = _authored(line.source);
    buffer.writeln('**`${line.id}`**');
    buffer.writeln();
    buffer.writeln('- 原句：${authored.isNotEmpty ? authored.first : '（没有 authored 原句）'}');
    for (final voice in order) {
      if (voices.containsKey(voice)) buffer.writeln('- ${_label(voice)}：${voices[voice]}');
    }
    for (final extra in voices.keys.where((key) => !order.contains(key))) {
      buffer.writeln('- ${_label(extra)}：${voices[extra]}');
    }
    buffer.writeln();
  }

  buffer.writeln('---');
  buffer.writeln();
  buffer.writeln('## 没有声音、但算散文的 ${unvoicedProse.length} 件');
  buffer.writeln();
  buffer.writeln('这些按「声音属于句子，不属于标签」的边界本来就不该有声音；列出来是为了让这个边界本身可以被读一遍。');
  buffer.writeln();
  for (final entry in unvoicedProse.entries) {
    buffer.writeln('- `${entry.key}` — ${entry.value}');
  }

  if (out == null) {
    stdout.write(buffer);
  } else {
    File(out).writeAsStringSync(buffer.toString());
    print('wrote $out (${voiced.length} voiced, ${unvoicedProse.length} unvoiced prose)');
  }
}
