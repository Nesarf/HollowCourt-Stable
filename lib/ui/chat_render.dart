import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'chat_icons.dart';
import 'theme.dart';

/// **What a reply is made of, once it stops being one string.**
///
/// The transcript used to draw every answer with a single `Text`, which meant two losses at once: the marks a
/// model writes out of habit were either shown as asterisks or had to be stripped, and anything with a shape --
/// a list, a table, a series of prices -- arrived as a paragraph of words describing that shape.
///
/// **Parsed here rather than by a Markdown package.** A renderer is a dependency, and this project refused one
/// before for a package-size reason that also cost it a voice. What a reply actually contains is five things, and
/// five things fit in a file that can be read in one sitting.
sealed class ChatBlock {
  const ChatBlock();
}

final class ParagraphBlock extends ChatBlock {
  const ParagraphBlock(this.text);
  final String text;
}

final class HeadingBlock extends ChatBlock {
  const HeadingBlock(this.level, this.text);
  final int level;
  final String text;
}

final class ListBlock extends ChatBlock {
  const ListBlock(this.items, {this.ordered = false});
  final List<String> items;
  final bool ordered;
}

final class CodeBlock extends ChatBlock {
  const CodeBlock(this.code, {this.language = ''});
  final String code;
  final String language;
}

final class TableBlock extends ChatBlock {
  const TableBlock(this.header, this.rows);

  /// Empty when the table arrived without a header row; the first row is then data.
  final List<String> header;
  final List<List<String>> rows;
}

/// **A picture the reply asked for.** [spec] is null when the block was opened as a chart and its body could not be
/// read -- a model that writes plausible JSON nine times in ten is a model whose tenth answer must not vanish, so the
/// body is kept and drawn as text underneath the complaint.
final class ChartBlock extends ChatBlock {
  const ChartBlock(this.spec, this.source);
  final ChartSpec? spec;
  final String source;
}

/// The four shapes worth drawing here. A cellar application argues about prices over time, about how much of
/// something is left, and about how a recipe splits; that is a line, a set of candles, a bar chart and a pie.
sealed class ChartSpec {
  const ChartSpec(this.title);
  final String title;
}

final class LineChart extends ChartSpec {
  const LineChart(super.title, this.labels, this.series);
  final List<String> labels;
  final List<({String name, List<double> points})> series;
}

final class CandleChart extends ChartSpec {
  const CandleChart(super.title, this.labels, this.candles);
  final List<String> labels;
  final List<({double open, double high, double low, double close})> candles;
}

final class BarChart extends ChartSpec {
  const BarChart(super.title, this.labels, this.values);
  final List<String> labels;
  final List<double> values;
}

final class PieChart extends ChartSpec {
  const PieChart(super.title, this.slices);
  final List<({String label, double value})> slices;
}

/// **The languages that mean "draw this" rather than "print this".**
const Set<String> chartLanguages = <String>{'chart', 'line', 'candle', 'bar', 'pie'};

/// Splits a reply into blocks. Blank lines close a paragraph; a fence opens a block of its own.
List<ChatBlock> parseReply(String text) {
  final lines = const LineSplitter().convert(text);
  final blocks = <ChatBlock>[];
  final paragraph = <String>[];

  void flushParagraph() {
    if (paragraph.isEmpty) return;
    blocks.add(ParagraphBlock(paragraph.join('\n')));
    paragraph.clear();
  }

  var index = 0;
  while (index < lines.length) {
    final line = lines[index];
    final trimmed = line.trim();

    // A fence: everything to the matching one belongs to the block, blank lines included.
    if (trimmed.startsWith('```')) {
      flushParagraph();
      final language = trimmed.substring(3).trim().toLowerCase();
      final body = <String>[];
      index++;
      while (index < lines.length && !lines[index].trim().startsWith('```')) {
        body.add(lines[index]);
        index++;
      }
      index++; // the closing fence
      final source = body.join('\n');
      if (chartLanguages.contains(language)) {
        blocks.add(ChartBlock(parseChart(language, source), source));
      } else {
        blocks.add(CodeBlock(source, language: language));
      }
      continue;
    }

    if (trimmed.isEmpty) {
      flushParagraph();
      index++;
      continue;
    }

    final heading = RegExp(r'^(#{1,6})\s+(.*)$').firstMatch(trimmed);
    if (heading != null) {
      flushParagraph();
      blocks.add(HeadingBlock(heading.group(1)!.length, heading.group(2)!.trim()));
      index++;
      continue;
    }

    // A table is a run of `|`-separated rows, optionally preceded by a `|---|---|` rule.
    if (trimmed.startsWith('|') && trimmed.endsWith('|')) {
      flushParagraph();
      final rows = <List<String>>[];
      while (index < lines.length && lines[index].trim().startsWith('|')) {
        final cells = lines[index].trim();
        final inner = cells.substring(1, cells.length - 1);
        rows.add(<String>[for (final cell in inner.split('|')) cell.trim()]);
        index++;
      }
      // The rule between header and body is a row of dashes and colons, and it is not data.
      final isRule = RegExp(r'^[-: ]+$');
      final kept = <List<String>>[for (final row in rows) if (!row.every(isRule.hasMatch)) row];
      if (kept.isEmpty) continue;
      final hasHeader = kept.length > 1 && rows.length > kept.length;
      blocks.add(hasHeader
          ? TableBlock(kept.first, kept.sublist(1))
          : TableBlock(const <String>[], kept));
      continue;
    }

    final bullet = RegExp(r'^[-*+]\s+(.*)$').firstMatch(trimmed);
    final ordered = RegExp(r'^\d+[.)]\s+(.*)$').firstMatch(trimmed);
    if (bullet != null || ordered != null) {
      flushParagraph();
      final isOrdered = ordered != null;
      final items = <String>[];
      while (index < lines.length) {
        final candidate = lines[index].trim();
        final match = isOrdered
            ? RegExp(r'^\d+[.)]\s+(.*)$').firstMatch(candidate)
            : RegExp(r'^[-*+]\s+(.*)$').firstMatch(candidate);
        if (match == null) break;
        items.add(match.group(1)!);
        index++;
      }
      if (items.isNotEmpty) blocks.add(ListBlock(items, ordered: isOrdered));
      continue;
    }

    paragraph.add(line);
    index++;
  }
  flushParagraph();
  return blocks;
}

/// **The body of a chart fence, read as one small object.** Null on anything it cannot use, because a chart that
/// draws nothing and says nothing is worse than the JSON it came from.
ChartSpec? parseChart(String language, String source) {
  Object? decoded;
  try {
    decoded = jsonDecode(source);
  } on FormatException {
    return null;
  }
  if (decoded is! Map<String, Object?>) return null;
  final title = '${decoded['title'] ?? ''}';
  final labels = <String>[
    for (final label in (decoded['labels'] as List<Object?>? ?? const <Object?>[])) '$label',
  ];

  double number(Object? raw) {
    if (raw is num) return raw.toDouble();
    return double.tryParse('$raw'.replaceAll(',', '')) ?? double.nan;
  }

  switch (language) {
    case 'candle':
      final raw = decoded['candles'];
      if (raw is! List) return null;
      final candles = <({double open, double high, double low, double close})>[];
      for (final entry in raw) {
        if (entry is! Map) return null;
        final open = number(entry['o'] ?? entry['open']);
        final high = number(entry['h'] ?? entry['high']);
        final low = number(entry['l'] ?? entry['low']);
        final close = number(entry['c'] ?? entry['close']);
        if (open.isNaN || high.isNaN || low.isNaN || close.isNaN) return null;
        candles.add((open: open, high: high, low: low, close: close));
      }
      if (candles.isEmpty) return null;
      return CandleChart(title, labels, candles);

    case 'bar':
      final raw = decoded['values'];
      if (raw is! List) return null;
      final values = <double>[];
      for (final entry in raw) {
        final value = number(entry);
        if (value.isNaN) return null;
        values.add(value);
      }
      if (values.isEmpty) return null;
      return BarChart(title, labels, values);

    case 'pie':
      final raw = decoded['slices'];
      if (raw is! List) return null;
      final slices = <({String label, double value})>[];
      for (final entry in raw) {
        if (entry is! Map) return null;
        final value = number(entry['value']);
        if (value.isNaN) return null;
        slices.add((label: '${entry['label'] ?? ''}', value: value));
      }
      if (slices.isEmpty) return null;
      return PieChart(title, slices);

    default:
      final raw = decoded['series'];
      if (raw is! List) return null;
      final series = <({String name, List<double> points})>[];
      for (final entry in raw) {
        if (entry is! Map) return null;
        final pointsRaw = entry['points'];
        if (pointsRaw is! List) return null;
        final points = <double>[];
        for (final point in pointsRaw) {
          final value = number(point);
          if (value.isNaN) return null;
          points.add(value);
        }
        series.add((name: '${entry['name'] ?? ''}', points: points));
      }
      if (series.isEmpty || series.every((one) => one.points.isEmpty)) return null;
      return LineChart(title, labels, series);
  }
}

/// Take the Markdown out of a reply, for the places that still want one string: inside a code block, under a chart
/// whose data could not be read, and anywhere a caller has nothing better than a `Text`.
///
/// The model answers in Markdown by habit and the transcript now draws most of it; this remains for the parts that
/// are already a shape of their own.
String plainReply(String text) {
  var out = text;
  out = out.replaceAll(RegExp(r'^```[^\n]*$', multiLine: true), '');
  out = out.replaceAll('`', '');
  out = out.replaceAll(RegExp(r'\*\*\*|___'), '');
  out = out.replaceAll(RegExp(r'\*\*|__'), '');
  out = out.replaceAll('*', '');
  out = out.replaceAll(RegExp(r'^\s{0,3}#{1,6}\s*', multiLine: true), '');
  out = out.replaceAll(RegExp(r'^\s{0,3}>\s?', multiLine: true), '');
  out = out.replaceAll(RegExp(r'^\s*[-+]\s+', multiLine: true), '\u00b7 ');
  out = out.replaceAll(RegExp(r'^\s*\|?[-: ]+\|[-: |]*$', multiLine: true), '');
  out = out.replaceAll('|', ' ');
  out = out.replaceAllMapped(RegExp(r'\[([^\]]+)\]\([^)]*\)'), (match) => match[1] ?? '');
  out = out.replaceAll(RegExp(r'\n{3,}'), '\n\n');
  return out.trim();
}

/// **The inline marks, drawn rather than stripped.** Bold, italic and code are the three a reply uses constantly and
/// the three a plain `Text` turned into punctuation. `:name:` is the fourth, and it becomes a glyph rather than a
/// widget: a `WidgetSpan` would sit on the text baseline differently at every size and would break the line a
/// paragraph is laid out on, while a character in the icon font behaves like any other character.
final RegExp _inline = RegExp(r'\*\*([^*]+)\*\*|\*([^*]+)\*|`([^`]+)`|:([a-z0-9_]+):');

/// **`TextSpan` rather than `InlineSpan`**, so a caller -- and a test -- can read `text` and `style` back off the
/// result instead of casting at every site.
List<TextSpan> inlineSpans(String text, TextStyle style) {
  final spans = <TextSpan>[];
  var at = 0;
  for (final match in _inline.allMatches(text)) {
    if (match.start > at) spans.add(TextSpan(text: text.substring(at, match.start), style: style));
    if (match.group(1) != null) {
      spans.add(TextSpan(text: match.group(1), style: style.copyWith(fontWeight: FontWeight.w700)));
    } else if (match.group(2) != null) {
      spans.add(TextSpan(text: match.group(2), style: style.copyWith(fontStyle: FontStyle.italic)));
    } else if (match.group(3) != null) {
      spans.add(TextSpan(
        text: match.group(3),
        style: style.copyWith(
          fontFamily: 'monospace',
          backgroundColor: HollowPalette.ink.withValues(alpha: 0.07),
        ),
      ));
    } else if (match.group(4) != null) {
      final icon = chatIcon(match.group(4)!);
      if (icon == null) {
        // **A name outside the table stays as it was written.** A reply that guessed `:kitchen:` should look wrong on
        // screen rather than lose a word, and the reader is the only one who can say what was meant.
        spans.add(TextSpan(text: match.group(0), style: style));
      } else {
        spans.add(TextSpan(
          text: String.fromCharCode(icon.codePoint),
          style: style.copyWith(
            fontFamily: icon.fontFamily ?? 'MaterialIcons',
            fontSize: (style.fontSize ?? 14) * 1.12,
            color: HollowPalette.gold,
          ),
        ));
      }
    }
    at = match.end;
  }
  if (at < text.length) spans.add(TextSpan(text: text.substring(at), style: style));
  return spans;
}

/// One reply, drawn block by block.
class ReplyView extends StatelessWidget {
  const ReplyView({
    super.key,
    required this.text,
    this.brokenChart,
  });

  final String text;

  /// The sentence to show over a chart whose data could not be read, supplied by the caller so this file has no
  /// opinion about which language the screen is in.
  final String? brokenChart;

  @override
  Widget build(BuildContext context) {
    final blocks = parseReply(text);
    if (blocks.isEmpty) {
      return Text(plainReply(text), style: HollowType.body.copyWith(color: HollowPalette.ink));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (var i = 0; i < blocks.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(height: 8),
          _draw(blocks[i]),
        ],
      ],
    );
  }

  Widget _draw(ChatBlock block) {
    final body = HollowType.body.copyWith(color: HollowPalette.ink);
    switch (block) {
      case ParagraphBlock(:final text):
        return Text.rich(TextSpan(children: inlineSpans(text, body)));

      case HeadingBlock(:final level, :final text):
        final size = switch (level) { 1 => 19.0, 2 => 17.0, _ => 15.0 };
        return Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text.rich(
            TextSpan(children: inlineSpans(text, body.copyWith(fontSize: size, fontWeight: FontWeight.w700))),
          ),
        );

      case ListBlock(:final items, :final ordered):
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            for (var i = 0; i < items.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    SizedBox(
                      width: 20,
                      child: Text(
                        ordered ? '${i + 1}.' : '\u00b7',
                        style: body.copyWith(color: HollowPalette.gold),
                      ),
                    ),
                    Expanded(child: Text.rich(TextSpan(children: inlineSpans(items[i], body)))),
                  ],
                ),
              ),
          ],
        );

      case CodeBlock(:final code):
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: HollowPalette.ink.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(8),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SelectableText(
              code,
              style: body.copyWith(fontFamily: 'monospace', fontSize: 12.5),
            ),
          ),
        );

      case TableBlock(:final header, :final rows):
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Table(
            defaultColumnWidth: const IntrinsicColumnWidth(),
            border: TableBorder.all(color: HollowPalette.ink.withValues(alpha: 0.15), width: 0.7),
            children: <TableRow>[
              if (header.isNotEmpty)
                TableRow(
                  children: <Widget>[
                    for (final cell in header) _cell(cell, body, bold: true),
                  ],
                ),
              for (final row in rows)
                TableRow(
                  children: <Widget>[
                    for (var i = 0; i < row.length; i++) _cell(row[i], body, bold: false),
                  ],
                ),
            ],
          ),
        );

      case ChartBlock(:final spec, :final source):
        if (spec == null) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (brokenChart != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    brokenChart!,
                    style: HollowType.caption.copyWith(color: HollowPalette.rose),
                  ),
                ),
              _draw(CodeBlock(source)),
            ],
          );
        }
        return _Chart(spec: spec);
    }
  }

  Widget _cell(String text, TextStyle style, {required bool bold}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      child: Text.rich(
        TextSpan(
          children: inlineSpans(text, bold ? style.copyWith(fontWeight: FontWeight.w700) : style),
        ),
      ),
    );
  }
}

/// A chart, drawn with the canvas rather than a package.
class _Chart extends StatelessWidget {
  const _Chart({required this.spec});

  final ChartSpec spec;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: HollowPalette.ink.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (spec.title.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                spec.title,
                style: HollowType.caption.copyWith(color: HollowPalette.ink),
              ),
            ),
          SizedBox(
            height: 170,
            child: CustomPaint(
              painter: switch (spec) {
                CandleChart() => _CandlePainter(spec as CandleChart),
                BarChart() => _BarPainter(spec as BarChart),
                PieChart() => _PiePainter(spec as PieChart),
                LineChart() => _LinePainter(spec as LineChart),
              },
            ),
          ),
          if (spec case CandleChart(:final candles))
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '${candles.length} 根 · 高 ${_fmt(candles.map((c) => c.high).reduce(math.max))} · '
                '低 ${_fmt(candles.map((c) => c.low).reduce(math.min))}',
                style: HollowType.caption.copyWith(color: HollowPalette.ink.withValues(alpha: 0.7)),
              ),
            ),
        ],
      ),
    );
  }
}

String _fmt(double value) {
  if (value == value.roundToDouble()) return value.toStringAsFixed(0);
  return value.toStringAsFixed(2);
}

const double _leftGutter = 44;
const double _bottomGutter = 16;

/// A price axis down the left and three rules across, shared by the three cartesian charts.
({double min, double max}) _range(Iterable<double> values) {
  final list = values.where((one) => !one.isNaN).toList();
  if (list.isEmpty) return (min: 0, max: 1);
  var lo = list.reduce(math.min);
  var hi = list.reduce(math.max);
  if (hi - lo < 1e-9) {
    lo -= 1;
    hi += 1;
  }
  return (min: lo, max: hi);
}

void _drawAxes(Canvas canvas, Size size, {required double min, required double max, required Color ink}) {
  final paint = Paint()
    ..color = ink.withValues(alpha: 0.18)
    ..strokeWidth = 0.7;
  final labelStyle = TextStyle(color: ink.withValues(alpha: 0.6), fontSize: 9);
  final height = size.height - _bottomGutter;
  for (var i = 0; i <= 3; i++) {
    final y = height * i / 3;
    canvas.drawLine(Offset(_leftGutter, y), Offset(size.width, y), paint);
    final value = max - (max - min) * i / 3;
    final painter = TextPainter(
      text: TextSpan(text: _fmt(value), style: labelStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, Offset(math.max(0, _leftGutter - painter.width - 6), y - painter.height / 2));
  }
}

/// **Candles, drawn the way a price series is read**: a wick from the low to the high, a body from the open to the
/// close, and the colour saying which end came second. Gold for up and rose for down, because those are this
/// application's two colours and a green-and-red chart would be the only place they appear.
class _CandlePainter extends CustomPainter {
  _CandlePainter(this.spec) : palette = HollowPalette.current;
  final CandleChart spec;

  /// See [_LinePainter.palette] for why the theme is held rather than read at paint time.
  final HollowPaletteValue palette;

  @override
  void paint(Canvas canvas, Size size) {
    final range = _range(<double>[
      for (final candle in spec.candles) ...<double>[candle.low, candle.high],
    ]);
    _drawAxes(canvas, size, min: range.min, max: range.max, ink: HollowPalette.ink);
    final height = size.height - _bottomGutter;
    final width = size.width - _leftGutter;
    double y(double value) => height - (value - range.min) / (range.max - range.min) * height;

    final step = width / spec.candles.length;
    final bodyWidth = math.max(1.5, step * 0.55);
    final up = Paint()..color = HollowPalette.gold;
    final down = Paint()..color = HollowPalette.rose;

    for (var i = 0; i < spec.candles.length; i++) {
      final candle = spec.candles[i];
      final centre = _leftGutter + step * (i + 0.5);
      final rising = candle.close >= candle.open;
      final paint = rising ? up : down;
      canvas.drawLine(
        Offset(centre, y(candle.high)),
        Offset(centre, y(candle.low)),
        Paint()
          ..color = paint.color
          ..strokeWidth = 1,
      );
      final top = y(math.max(candle.open, candle.close));
      final bottom = y(math.min(candle.open, candle.close));
      canvas.drawRect(
        Rect.fromLTRB(centre - bodyWidth / 2, top, centre + bodyWidth / 2, math.max(bottom, top + 1)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CandlePainter old) =>
      old.spec != spec || old.palette != HollowPalette.current;
}

class _BarPainter extends CustomPainter {
  _BarPainter(this.spec) : palette = HollowPalette.current;
  final BarChart spec;

  /// See [_LinePainter.palette] for why the theme is held rather than read at paint time.
  final HollowPaletteValue palette;

  @override
  void paint(Canvas canvas, Size size) {
    final range = _range(<double>[0, ...spec.values]);
    _drawAxes(canvas, size, min: range.min, max: range.max, ink: HollowPalette.ink);
    final height = size.height - _bottomGutter;
    final width = size.width - _leftGutter;
    double y(double value) => height - (value - range.min) / (range.max - range.min) * height;

    final step = width / spec.values.length;
    final paint = Paint()..color = HollowPalette.gold.withValues(alpha: 0.75);
    for (var i = 0; i < spec.values.length; i++) {
      final centre = _leftGutter + step * (i + 0.5);
      final half = math.max(1.0, step * 0.32);
      canvas.drawRect(
        Rect.fromLTRB(centre - half, y(spec.values[i]), centre + half, y(range.min)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BarPainter old) =>
      old.spec != spec || old.palette != HollowPalette.current;
}

class _LinePainter extends CustomPainter {
  _LinePainter(this.spec) : palette = HollowPalette.current;
  final LineChart spec;

  /// **The theme in force when this painter was built.** `HollowPalette` is a getter over a value the reader can
  /// change while the transcript is open, so a `const` list would have frozen whichever theme was loaded first, and a
  /// `shouldRepaint` that compared only the spec would not notice the change.
  final HollowPaletteValue palette;

  List<Color> get _palette => <Color>[
        HollowPalette.gold,
        HollowPalette.rose,
        const Color(0xFF6E8CA0),
        const Color(0xFF8A7B5C),
      ];

  @override
  void paint(Canvas canvas, Size size) {
    final all = <double>[for (final one in spec.series) ...one.points];
    final range = _range(all);
    _drawAxes(canvas, size, min: range.min, max: range.max, ink: HollowPalette.ink);
    final height = size.height - _bottomGutter;
    final width = size.width - _leftGutter;
    double y(double value) => height - (value - range.min) / (range.max - range.min) * height;

    for (var s = 0; s < spec.series.length; s++) {
      final points = spec.series[s].points;
      if (points.isEmpty) continue;
      final paint = Paint()
        ..color = _palette[s % _palette.length]
        ..strokeWidth = 1.6
        ..style = PaintingStyle.stroke;
      final path = Path();
      for (var i = 0; i < points.length; i++) {
        final x = _leftGutter + (points.length == 1 ? width / 2 : width * i / (points.length - 1));
        final point = Offset(x, y(points[i]));
        if (i == 0) {
          path.moveTo(point.dx, point.dy);
        } else {
          path.lineTo(point.dx, point.dy);
        }
      }
      canvas.drawPath(path, paint);
      final dot = Paint()..color = paint.color;
      for (var i = 0; i < points.length; i++) {
        final x = _leftGutter + (points.length == 1 ? width / 2 : width * i / (points.length - 1));
        canvas.drawCircle(Offset(x, y(points[i])), 2.2, dot);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _LinePainter old) =>
      old.spec != spec || old.palette != HollowPalette.current;
}

class _PiePainter extends CustomPainter {
  _PiePainter(this.spec) : palette = HollowPalette.current;
  final PieChart spec;

  /// See [_LinePainter.palette] for why the theme is held rather than read at paint time.
  final HollowPaletteValue palette;

  List<Color> get _palette => <Color>[
        HollowPalette.gold,
        HollowPalette.rose,
        const Color(0xFF6E8CA0),
        const Color(0xFF8A7B5C),
        const Color(0xFF9A8AA6),
        const Color(0xFF5F7D6E),
      ];

  @override
  void paint(Canvas canvas, Size size) {
    final total = spec.slices.fold<double>(0, (sum, slice) => sum + slice.value);
    if (total <= 0) return;
    final radius = math.min(size.width, size.height) / 2 - 6;
    final centre = Offset(size.width / 2, size.height / 2);
    var start = -math.pi / 2;
    for (var i = 0; i < spec.slices.length; i++) {
      final sweep = spec.slices[i].value / total * math.pi * 2;
      canvas.drawArc(
        Rect.fromCircle(center: centre, radius: radius),
        start,
        sweep,
        true,
        Paint()..color = _palette[i % _palette.length],
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _PiePainter old) =>
      old.spec != spec || old.palette != HollowPalette.current;
}
