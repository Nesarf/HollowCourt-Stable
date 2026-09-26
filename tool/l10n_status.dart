// ignore_for_file: avoid_print
//
// How much of the application is translated, per language, as a number.
//
//     dart run tool/l10n_status.dart
//
// **A counter rather than a test, and the distinction is deliberate.** A test that fails because 400
// strings are not translated yet would fail on every run until the work is done, which teaches people to
// ignore red; a number that goes down every session is the honest way to carry a large translation. The
// tests beside it assert *behaviour* -- that the fallback chain resolves as documented, that no line is
// empty -- and those are green now and stay green.
//
// The measure is textual on purpose: the strings live as `static const ... = CopyLine(...)` in
// `lib/ui/theme.dart`, and counting the ones that name a `'ja'` entry is exactly the question "is this
// line written in Japanese", asked of the file that holds them. A translation is added as
// `also: {'ja': '…'}` beside the authored pair, so the count is of definitions that mention the tag.
import 'dart:convert';
import 'dart:io';

void main(List<String> args) {
  final source = File('lib/ui/theme.dart').readAsStringSync();

  // Every constant defined as a CopyLine, and the text of its definition.
  final definitions = <String, String>{};
  // **Both constructors, and the first version of this only matched one of them** -- so converting a line
  // made it disappear from the count instead of counting as translated, and the counter read zero while 38
  // lines had `ja`. A measure that goes *down* when work is done is worse than no measure.
  final pattern = RegExp(
    r'static const (\w+) = CopyLine(?:\.withLanguages)?\(',
    multiLine: true,
  );
  for (final match in pattern.allMatches(source)) {
    final name = match.group(1)!;
    // The definition runs to the next `static const` or the end of the class body: enough to see which
    // locale keys it carries, which is all this counts.
    final rest = source.substring(match.end);
    final next = rest.indexOf('static const ');
    definitions[name] = next < 0 ? rest : rest.substring(0, next);
  }

  const locales = ['zh-Hans', 'zh-HK', 'zh-TW', 'lzh', 'ja', 'en'];
  stdout.writeln('CopyLine constants: ${definitions.length}');
  stdout.writeln('');
  stdout.writeln('${'locale'.padRight(10)} written   total   remaining');
  for (final locale in locales) {
    // **`zh-Hans` and `en` are carried by the authored pair**, not by a locale key: every definition has
    // them in its two `Translated.authored(...)` arguments, which is the shape the application was written
    // in. Counting only named keys reported zero for the two languages that are actually complete, which is
    // the kind of number that teaches a reader to distrust the dashboard.
    final authored = locale == 'zh-Hans' || locale == 'en';
    final written = authored
        ? definitions.length
        : definitions.values.where((body) => body.contains("'$locale'")).length;
    stdout.writeln(
      '${locale.padRight(10)} ${written.toString().padLeft(7)}   '
      '${definitions.length.toString().padLeft(5)}   '
      '${(definitions.length - written).toString().padLeft(9)}',
    );
  }
  stdout.writeln('');
  stdout.writeln(
    'A line counts as written for a locale when its definition names that tag. The three Chinese '
    'variants share one written base (`localeFallbacks` resolves zh-HK and zh-TW to zh-Hans), so the '
    'honest target is: zh-Hans 100%, en 100%, ja 100%, and the variants wherever the wording differs.',
  );
  stepStatus();
  nameCoverage();
  if (args.isNotEmpty) listMissing(args.first);
}

/// The drinks whose instructions have been translated, which is the other half of this work.
void stepStatus() {
  final source = File('data/names/names.json').readAsStringSync();
  final decoded = jsonDecode(source) as Map<String, Object?>;
  final steps = (decoded['steps'] as Map<String, Object?>?) ?? const {};
  final library = jsonDecode(File('data/drinks/library.json').readAsStringSync()) as Map<String, Object?>;
  final drinks = (library['recipes'] as List).length;

  stdout.writeln('');
  stdout.writeln('Instructions (drinks whose steps are translated, of $drinks):');
  // **The two Chinese variants are generated, not written** -- see DESIGN.md 12.4.1: OpenCC converts
  // characters, and a rhythm game's own catalogues show translators rewording sentences as well (警告！在开始关卡时
  // 你的体力就已经被消耗！ against 警告： 已經消耗了體力). So the numbers below say "delivered", and the
  // remaining work is 繁体措辞复核 rather than 繁体未翻译. Counting them as "written" would make the gap
  // invisible while looking complete.
  for (final locale in const ['zh-Hans', 'zh-HK', 'zh-TW', 'ja']) {
    final done = steps.values.where((byLocale) {
      final list = (byLocale as Map<String, Object?>)[locale];
      return list is List && list.isNotEmpty;
    }).length;
    stdout.writeln('  ${locale.padRight(8)} $done / $drinks');
  }
}

/// **The seed's own vocabulary, per language** -- drinks, ingredients, and the units they are counted in.
///
/// The CopyLine counter above answers "is the interface translated"; this answers the same question about the
/// *content*, which is a different file, a different owner and a different review ("every drink is called what
/// the bar calls it") -- and which was, for one afternoon, the thing that was wrong: the names file was complete
/// while three screens never asked for a translation. A counter that only measured `theme.dart` would have read
/// 240/240 throughout.
///
/// A locale counts as covered for a name when the file names that locale for that id, *not* when the fallback
/// chain resolves it: 港繁 falling back to 简中 is exactly the state that hid the missing labels, so measuring
/// the chain would hide it again.
void nameCoverage() {
  final names = jsonDecode(File('data/names/names.json').readAsStringSync()) as Map<String, Object?>;
  final library = jsonDecode(File('data/drinks/library.json').readAsStringSync()) as Map<String, Object?>;

  int covered(String section, String locale) {
    final entries = (names[section] as Map<String, Object?>?) ?? const {};
    return entries.values.where((value) {
      final byLocale = value as Map<String, Object?>;
      final text = byLocale[locale];
      return text is String && text.trim().isNotEmpty;
    }).length;
  }

  final drinks = (library['recipes'] as List).length;
  final ingredients = (library['ingredients'] as List).length;

  stdout.writeln('');
  stdout.writeln('Names (drinks $drinks, ingredients $ingredients):');
  for (final locale in const ['zh-Hans', 'zh-HK', 'zh-TW', 'ja']) {
    stdout.writeln('  ${locale.padRight(8)} drinks ${covered('recipes', locale)} / $drinks'
        '   ingredients ${covered('ingredients', locale)} / $ingredients');
  }

  // The unit labels are a table in Dart rather than a data file, and they are the ones that were *actually*
  // missing two languages -- found by the owner's instruction to make every language complete, not by reading.
  final units = File('lib/ui/unit_labels.dart').readAsStringSync();
  final ids = RegExp(r"^  '([A-Za-z]+)': \{", multiLine: true)
      .allMatches(units)
      .map((m) => m.group(1)!)
      .toList();
  stdout.writeln('');
  stdout.writeln('Unit labels, of ${ids.length}:');
  for (final locale in const ['zh-Hans', 'zh-HK', 'zh-TW', 'ja', 'en']) {
    final count = ids.where((id) {
      // No escaped braces: `},` is literal in a Dart string, and `dotAll` lets `.` cross newlines.
      final block = RegExp("'${RegExp.escape(id)}': (.*?)\n  },", dotAll: true).firstMatch(units);
      return block != null && block.group(1)!.contains("'$locale':");
    }).length;
    stdout.writeln('  ${locale.padRight(8)} $count / ${ids.length}');
  }
}

/// **The names a locale is missing, so the number can be acted on.** A counter that says "1 remaining" and
/// cannot say which one turns every audit into a search; this prints them when given a locale tag.
void listMissing(String locale) {
  final source = File('lib/ui/theme.dart').readAsStringSync();
  final pattern = RegExp(r"static const (\w+) = CopyLine(?:\.withLanguages)?\(");
  final missing = <String>[];
  for (final match in pattern.allMatches(source)) {
    var index = match.end - 1;
    var depth = 0;
    while (index < source.length) {
      final character = source[index];
      if (character == "'" || character == '"') {
        final quote = character;
        index++;
        while (index < source.length) {
          if (source[index] == r'') {
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
    final body = source.substring(match.start, index + 1);
    if (!body.contains("'$locale'")) missing.add(match.group(1)!);
  }
  stdout.writeln('');
  stdout.writeln('Missing in $locale (${missing.length}):');
  for (final name in missing) {
    stdout.writeln('  $name');
  }
}
