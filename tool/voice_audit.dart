// ignore_for_file: avoid_print
//
// How far each marker is spread across a voice, as a number rather than an impression.
//
//     dart run tool/voice_audit.dart                  # the table
//     dart run tool/voice_audit.dart --list 本小姐     # every line carrying one marker
//
// **Why a count and not a reading.** `docs/TODO.md` recorded the impression first -- "本小姐 is laid on very wide
// while the tsundere grammar is scattered" -- and an impression cannot be acted on: it does not say whether 44 lines
// out of 141 is too many or exactly right, and it does not tell the next person whether a rewrite changed anything.
// A count does both, and it is cheap to re-run after every batch of writing.
//
// **The markers are not a style guide.** They are the ones the archetype notes name, so a voice that scores zero on
// all of them is not wrong -- it is a voice whose character is carried by something else. The number to watch is the
// top of each column: a single identity word in half the lines is the smell this exists to measure.
import 'dart:io';

class _Line {
  _Line(this.id, this.source);

  final String id;
  final String source;
}

const _voices = ['heiress', 'heiressJa', 'minister'];

const _markers = <String, List<String>>{
  'heiress': [
    '本小姐',
    '哼',
    '才不',
    '才不是',
    '又不是',
    '随便你',
    '……',
    '嘛',
    '呢',
    '吧',
  ],
  'heiressJa': [
    'ですわ',
    'ますの',
    'ことよ',
    'わたくし',
    'あたし',
    'わよ',
    'のよ',
    'かしら',
    'ふん',
    '……',
  ],
  'minister': [
    'has been',
    'It would',
    'I am afraid',
    'I should',
    'In point of fact',
    'would appear',
    'may be',
    'We are',
    'it is',
    '……',
  ],
};

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

Map<String, String> _voicesOf(String body) {
  final found = <String, String>{};
  for (final match in RegExp(r"Voice\.(\w+):\s*'((?:[^'\\]|\\.)*)'").allMatches(body)) {
    found[match.group(1)!] = match.group(2)!;
  }
  return found;
}

void main(List<String> args) {
  final all = _definitions('lib/ui/theme.dart')
      .map((line) => MapEntry(line.id, _voicesOf(line.source)))
      .where((entry) => entry.value.isNotEmpty)
      .toList();

  if (args.contains('--list')) {
    final marker = args[args.indexOf('--list') + 1];
    for (final entry in all) {
      for (final voice in _voices) {
        final text = entry.value[voice];
        if (text != null && text.contains(marker)) {
          print('${entry.key} [$voice] $text');
        }
      }
    }
    return;
  }

  if (args.contains('--overkill')) {
    // **One line, three sentence endings, and it reads as a parody.** The counts above say how many lines carry a
    // marker; they do not say that a single line can carry four. In the Japanese voice that is the actual defect:
    // ですわ / ますの / ですの / ございますの are each correct, and three of them in one sentence is a voice
    // performed rather than spoken. So this mode counts endings per line and lists the ones over two.
    const endings = [
      'ですわ',
      'ますの',
      'ですの',
      'ことよ',
      'ございますの',
      'よろしくてよ',
      'ますわ',
      'なさいな',
      'わね',
    ];
    // **Longest first, and a taken mask, because the markers overlap.** `ございますの` contains `ますの`, so the naive
    // count reported two endings where one was said. That in turn inflated the "overdone" list by roughly half -- a
    // measurement error that would have justified fifty rewrites of perfectly ordinary sentences.
    final byLength = [...endings]..sort((a, b) => b.length.compareTo(a.length));
    final rows = <List<Object>>[];
    for (final entry in all) {
      final text = entry.value['heiressJa'];
      if (text == null) continue;
      // **Split by sentence first, and that is the correction to a wrong measurement.** A CopyLine is usually two or
      // three sentences, so counting endings per line calls three perfectly ordinary sentences "overdone". What is
      // actually wrong is two endings inside one sentence.
      for (final sentence in text.split(RegExp('[。！？\\n]|——'))) {
        if (sentence.trim().isEmpty) continue;
        final hits = <String>[];
        final taken = <int>{};
        for (final ending in byLength) {
          var from = 0;
          while (true) {
            final at = sentence.indexOf(ending, from);
            if (at < 0) break;
            final overlaps = Iterable<int>.generate(ending.length).any((k) => taken.contains(at + k));
            if (!overlaps) {
              hits.add(ending);
              for (var k = 0; k < ending.length; k++) {
                taken.add(at + k);
              }
            }
            from = at + ending.length;
          }
        }
        if (hits.length >= 2) {
          rows.add([entry.key, hits.length, sentence.trim(), hits.join(' / ')]);
        }
      }
    }
    rows.sort((a, b) => (b[1] as int).compareTo(a[1] as int));
    for (final row in rows) {
      print('${row[0]} [${row[1]}] (${row[3]})');
      print('    ${row[2]}');
    }
    print('一句里两个以上句尾的：${rows.length}');
    return;
  }

  if (args.contains('--long')) {
    // **Length is the English voice's actual defect**, not its markers: the same sheet has room for a sentence and
    // the minister writes a paragraph. This lists the lines above a threshold so the rewriting has a work list rather
    // than an opinion.
    final voice = args[args.indexOf('--long') + 1];
    final threshold = args.length > args.indexOf('--long') + 2
        ? int.parse(args[args.indexOf('--long') + 2])
        : 120;
    final rows = <List<Object>>[];
    for (final entry in all) {
      final text = entry.value[voice];
      if (text == null) continue;
      if (text.runes.length >= threshold) rows.add([entry.key, text.runes.length, text]);
    }
    rows.sort((a, b) => (b[1] as int).compareTo(a[1] as int));
    for (final row in rows) {
      print('[${row[1]}] ${row[0]}');
      print('    ${row[2]}');
    }
    print('$voice 里超过 $threshold 字的：${rows.length} / ${all.length}');
    return;
  }

  print('# 声音标记分布（${all.length} 条）');
  print('');
  for (final voice in _voices) {
    final texts = [
      for (final entry in all)
        if (entry.value[voice] != null) entry.value[voice]!,
    ];
    print('## $voice — ${texts.length} 条');
    print('');
    print('| 标记 | 出现条数 | 占比 |');
    print('| --- | --- | --- |');
    final rows = <MapEntry<String, int>>[];
    for (final marker in _markers[voice]!) {
      final count = texts.where((text) => text.contains(marker)).length;
      rows.add(MapEntry(marker, count));
    }
    rows.sort((a, b) => b.value.compareTo(a.value));
    for (final row in rows) {
      final percent = texts.isEmpty ? 0.0 : row.value / texts.length * 100;
      print('| ${row.key} | ${row.value} | ${percent.toStringAsFixed(1)}% |');
    }
    print('');
    // Length, because a voice that says everything in eight characters and one that says it in forty are different
    // problems, and the count alone does not show which one this is.
    final lengths = texts.map((text) => text.runes.length).toList()..sort();
    if (lengths.isNotEmpty) {
      final median = lengths[lengths.length ~/ 2];
      final mean = lengths.reduce((a, b) => a + b) / lengths.length;
      print('长度：中位 $median 字，平均 ${mean.toStringAsFixed(1)} 字，'
          '最短 ${lengths.first}，最长 ${lengths.last}');
      print('');
    }
  }
}
