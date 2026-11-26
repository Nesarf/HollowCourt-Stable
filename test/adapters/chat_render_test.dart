import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hollow_court/ui/chat_render.dart';

/// **The reply, read back as shapes.**
///
/// Everything here is a pure function over a string: no pump, no provider, no network. That is deliberate -- the
/// parser is the part that can be wrong in a way nobody notices until a reader sees their answer as one run-on
/// paragraph, and a pure function is the only kind this project can check cheaply.
void main() {
  group('blocks', () {
    test('a blank line ends a paragraph and keeps the words inside it', () {
      final blocks = parseReply('第一段\n还是第一段\n\n第二段');
      expect(blocks, hasLength(2));
      expect((blocks[0] as ParagraphBlock).text, '第一段\n还是第一段');
      expect((blocks[1] as ParagraphBlock).text, '第二段');
    });

    test('**a heading is a heading, not a line that starts with #**', () {
      final blocks = parseReply('## 价格\n不便宜。');
      expect(blocks.first, isA<HeadingBlock>());
      final heading = blocks.first as HeadingBlock;
      expect(heading.level, 2);
      expect(heading.text, '价格');
      expect((blocks[1] as ParagraphBlock).text, '不便宜。');
    });

    test('a list keeps its order and its marker kind', () {
      final unordered = parseReply('- 甲\n- 乙\n- 丙');
      expect(unordered.single, isA<ListBlock>());
      expect((unordered.single as ListBlock).items, <String>['甲', '乙', '丙']);
      expect((unordered.single as ListBlock).ordered, isFalse);

      final ordered = parseReply('1. 先摇\n2. 再滤');
      expect((ordered.single as ListBlock).ordered, isTrue);
      expect((ordered.single as ListBlock).items, <String>['先摇', '再滤']);
    });

    test('**a fence becomes one block, blank lines and all**', () {
      final blocks = parseReply('看这段：\n```dart\nfinal a = 1;\n\nfinal b = 2;\n```\n就这样。');
      expect(blocks, hasLength(3));
      expect(blocks[0], isA<ParagraphBlock>());
      final code = blocks[1] as CodeBlock;
      expect(code.language, 'dart');
      expect(code.code, 'final a = 1;\n\nfinal b = 2;');
      expect(blocks[2], isA<ParagraphBlock>());
    });

    test('**a table loses its rule row and keeps the header**', () {
      final blocks = parseReply('| 酒 | 毫升 |\n| --- | --- |\n| 琴酒 | 700 |');
      final table = blocks.single as TableBlock;
      expect(table.header, <String>['酒', '毫升']);
      expect(table.rows, <List<String>>[
        <String>['琴酒', '700'],
      ]);
    });

    test('a table with no rule row is all data and no header', () {
      final blocks = parseReply('| 甲 | 乙 |\n| 丙 | 丁 |');
      final table = blocks.single as TableBlock;
      expect(table.header, isEmpty);
      expect(table.rows, hasLength(2));
    });

    test('an unterminated fence still becomes a block rather than being lost', () {
      final blocks = parseReply('```\n没有收尾');
      expect(blocks.single, isA<CodeBlock>());
      expect((blocks.single as CodeBlock).code, '没有收尾');
    });
  });

  group('charts', () {
    test('**candles are read from either the short or the long keys**', () {
      final short = parseChart('candle', '{"title":"茅台","candles":[{"o":1,"h":3,"l":0.5,"c":2}]}');
      expect(short, isA<CandleChart>());
      expect((short! as CandleChart).candles.single.close, 2);

      final long = parseChart('candle', '{"candles":[{"open":1,"high":3,"low":0.5,"close":2}]}');
      expect(long, isA<CandleChart>());
      expect((long! as CandleChart).candles.single.high, 3);
    });

    test('a number written as a string is still a number', () {
      final chart = parseChart('bar', '{"values":["1,280","1,300"]}');
      expect((chart! as BarChart).values, <double>[1280, 1300]);
    });

    test('lines, bars and pies all parse', () {
      expect(
        parseChart('line', '{"series":[{"name":"收盘","points":[1,2,3]}]}'),
        isA<LineChart>(),
      );
      expect(parseChart('chart', '{"series":[{"points":[1,2]}]}'), isA<LineChart>());
      expect(parseChart('bar', '{"values":[1,2]}'), isA<BarChart>());
      expect(
        parseChart('pie', '{"slices":[{"label":"甲","value":1},{"label":"乙","value":3}]}'),
        isA<PieChart>(),
      );
    });

    test('**anything unusable is null, so the screen can keep the source**', () {
      expect(parseChart('candle', 'not json'), isNull);
      expect(parseChart('candle', '{"candles":[]}'), isNull);
      expect(parseChart('candle', '{"candles":[{"o":"x"}]}'), isNull);
      expect(parseChart('bar', '{"values":[]}'), isNull);
      expect(parseChart('pie', '{"slices":[{"value":"?"}]}'), isNull);
      expect(parseChart('line', '{"series":[]}'), isNull);
      expect(parseChart('line', '[]'), isNull);
    });

    test('**a fence in a chart language keeps its body when the body will not parse**', () {
      final blocks = parseReply('```candle\n{"candles": oops}\n```');
      final chart = blocks.single as ChartBlock;
      expect(chart.spec, isNull);
      // The tenth answer that misbehaves must not vanish: the reader still sees what she wrote.
      expect(chart.source, '{"candles": oops}');
    });
  });

  group('inline', () {
    TextStyle style() => const TextStyle(fontSize: 14);

    test('**bold, italic and code are drawn rather than stripped**', () {
      final spans = inlineSpans('这是**重点**和*轻声*还有`代码`。', style());
      final joined = spans.map((span) => span.text).join();
      expect(joined, '这是重点和轻声还有代码。');
      final bold = spans.firstWhere((span) => span.text == '重点');
      expect(bold.style!.fontWeight, FontWeight.w700);
      final italic = spans.firstWhere((span) => span.text == '轻声');
      expect(italic.style!.fontStyle, FontStyle.italic);
      final code = spans.firstWhere((span) => span.text == '代码');
      expect(code.style!.fontFamily, 'monospace');
    });

    test('a string with no marks is one span and loses nothing', () {
      final spans = inlineSpans('一句普通的话', style());
      expect(spans, hasLength(1));
      expect(spans.single.text, '一句普通的话');
    });

    test('plainReply still flattens what a code block holds', () {
      expect(plainReply('**粗** 与 `码`'), '粗 与 码');
      expect(plainReply('## 标题'), '标题');
    });
  });
}
