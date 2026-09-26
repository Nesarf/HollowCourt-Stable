// ignore_for_file: avoid_print
//
// How much of the application has a *voice*, per voice, as a number and a list.
//
//     dart run tool/voice_status.dart            # the counts and the candidates
//     dart run tool/voice_status.dart --all      # every line that has no voice
//
// **The sibling of l10n_status.dart, counting the other axis.** That one asks how much is translated;
// this one asks how much is *authored* -- the same sentence said by the plain application, by the heiress,
// by her Japanese self, by the minister.
//
// **A voice is authorship and not translation**, which is why the target is not "every line". The class
// that carries them says so: they belong on the sentences a person actually reads -- an empty state, an
// explanation, an apology -- and *not* on a unit label or a button. So the number that matters is not the
// coverage of the file, it is the coverage of the prose: this tool separates the two and prints the prose
// that has no voice yet, longest first, because that is the list somebody can act on.
//
// A counter rather than a test, for the reason its sibling gives: a test that fails until a large piece of
// writing is finished teaches people to ignore red, and a number that goes down every session does not.
import 'dart:io';

/// Lines at least this long are treated as prose rather than as a label.
const proseLength = 18;

void main(List<String> args) {
  final showAll = args.contains('--all');
  final source = File('lib/ui/theme.dart').readAsStringSync();
  final lines = source.split('\n');

  final definitions = <String, String>{};
  String? current;
  var depth = 0;
  for (final line in lines) {
    final start = RegExp(r'static const (\w+) = CopyLine').firstMatch(line);
    if (start != null) {
      current = start.group(1);
      definitions[current!] = '';
      depth = 0;
    }
    if (current != null) {
      // Inside this guard `current` is already promoted to non-null, so the `!` the analyzer used to accept is
      // now reported as having no effect -- the promotion became smarter and the assertion became noise.
      definitions[current] = '${definitions[current]}$line\n';
      depth += '{:('.split('').map((c) => line.split(c).length - 1).reduce((a, b) => a + b);
      depth -= '})'.split('').map((c) => line.split(c).length - 1).reduce((a, b) => a + b);
      if (depth <= 0 && definitions[current]!.contains(');')) {
        current = null;
      }
    }
  }

  final voiced = <String, Set<String>>{};
  final unvoiced = <String, String>{};
  for (final entry in definitions.entries) {
    final body = entry.value;
    final names = RegExp(r'Voice\.(\w+):').allMatches(body).map((m) => m.group(1)!).toSet();
    if (names.isEmpty) {
      // the authored Chinese line, which is what a person would actually read
      final authored = RegExp(r"Translated\.authored\('([^']*)'").firstMatch(body);
      unvoiced[entry.key] = authored?.group(1) ?? '';
    } else {
      voiced[entry.key] = names;
    }
  }

  final counts = <String, int>{};
  for (final names in voiced.values) {
    for (final name in names) {
      counts[name] = (counts[name] ?? 0) + 1;
    }
  }

  print('Copy lines in lib/ui/theme.dart: ${definitions.length}');
  print('  with a voice:  ${voiced.length}');
  print('  without one:   ${unvoiced.length}');
  print('');
  print('Per voice:');
  for (final name in ['plain', 'heiress', 'heiressJa', 'minister']) {
    print('  ${name.padRight(11)} ${counts[name] ?? 0}');
  }

  final candidates = unvoiced.entries
      .where((e) => e.value.runes.length >= proseLength)
      .toList()
    ..sort((a, b) => b.value.runes.length.compareTo(a.value.runes.length));

  print('');
  print('Prose with no voice yet, longest first (${candidates.length}'
      '${showAll ? ', showing all' : ', showing 25'}):');
  for (final entry in candidates.take(showAll ? candidates.length : 25)) {
    print('  ${entry.key.padRight(30)} ${entry.value}');
  }
}
