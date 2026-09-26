import 'dart:io';

import 'package:test/test.dart';

/// **The interface's shipped languages are complete, and this is what keeps them complete.**
///
/// The measure is textual because the strings live as `static const ... = CopyLine(...)` definitions in
/// `lib/ui/theme.dart`, and the thing being asserted is exactly what the file says: every line names every
/// language this build ships. A line that does not fails here rather than reaching a reader as English in the
/// middle of a Japanese screen.
///
/// **文言文 is deliberately absent from the check**, and the reason is a decision rather than an oversight: it
/// is not a selectable language (no converter produces it, and an option that quietly showed 简中 while
/// calling itself 文言文 would be a control that lies about what it did -- see docs/DESIGN.md 15).
void main() {
  /// Every `CopyLine` definition, found by brace counting so a body containing quotes cannot end it early.
  ///
  /// **And by skipping comments, which it did not do until it broke.** A declaration's arguments may carry a
  /// comment between them, and this scanner read it as code: an apostrophe in prose -- `reader's`, in
  /// `appName`'s own note -- opened a string that never closed, so the scan ran to the end of the file and the
  /// test failed with a `RangeError` several hundred lines away from the cause. A checker that reads comments as
  /// code is a checker whose failures point at the wrong place.
  List<({String name, String body})> definitions(String source) {
    final pattern = RegExp(r"static const (\w+) = CopyLine(?:\.withLanguages)?\(");
    final found = <({String name, String body})>[];
    for (final match in pattern.allMatches(source)) {
      var index = match.end - 1;
      var depth = 0;
      while (index < source.length) {
        final character = source[index];
        if (character == '/' && index + 1 < source.length && source[index + 1] == '/') {
          while (index < source.length && source[index] != '\n') {
            index++;
          }
          continue;
        }
        if (character == '/' && index + 1 < source.length && source[index + 1] == '*') {
          index += 2;
          while (index + 1 < source.length &&
              !(source[index] == '*' && source[index + 1] == '/')) {
            index++;
          }
          index += 2;
          continue;
        }
        if (character == "'" || character == '"') {
          final quote = character;
          index++;
          while (index < source.length) {
            if (source[index] == r'\') {
              index += 2;
              continue;
            }
            if (source[index] == quote) break;
            index++;
          }
        } else if (character == '(') {
          depth++;
        } else if (character == ')') {
          depth--;
          if (depth == 0) break;
        }
        index++;
      }
      found.add((name: match.group(1)!, body: source.substring(match.start, index + 1)));
    }
    return found;
  }

  test('**every interface line names every shipped language**', () {
    final file = File('lib/ui/theme.dart');
    expect(file.existsSync(), isTrue, reason: 'run this from the repository root');

    final lines = definitions(file.readAsStringSync());
    expect(lines.length, greaterThanOrEqualTo(170), reason: 'the whole interface, not a sample');

    for (final locale in const ['ja', 'zh-HK', 'zh-TW']) {
      final missing = [for (final line in lines) if (!line.body.contains("'$locale'")) line.name];
      expect(missing, isEmpty, reason: '$locale is missing: ${missing.join(', ')}');
    }

    // English is a positional argument rather than a tagged line, so it is checked by the definition naming
    // two written sentences: the primary (Chinese) and the second.
    final thin = [
      for (final line in lines)
        if ('Translated.authored'.allMatches(line.body).length < 2) line.name,
    ];
    expect(thin, isEmpty, reason: 'no second line written for: ${thin.join(', ')}');
  });
}
