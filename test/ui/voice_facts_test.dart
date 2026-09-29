import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// **The hardest rule in Charlotte's register, made checkable.** `charlotte-voice.md` says she never withholds the
/// information: the fact stays exactly as the plain line states it, and her voice is added in front of it rather than
/// in place of it. That is a claim about twenty-two pairs of sentences, which is exactly the kind of claim that drifts
/// one careful edit at a time -- an adjective softened here, a qualifier dropped there -- with nothing to catch it.
///
/// So it is a test. For every line that carries her voice, every **number** and every **ASCII proper noun** in the
/// authored Chinese must appear in her version too. The rule is deliberately crude: it does not try to judge whether
/// she preserved the *meaning*, because that is not mechanisable, and a check that pretends to judge it would be
/// trusted past its ability. It catches the one failure that has a shape -- a fact that vanished while a sentence was
/// rewritten.
///
/// Deriving the facts from the file rather than listing them here is what keeps this from being a second copy of the
/// lines. The list of lines is not written down twice either: whatever carries a `Voice.heiress` is checked.
/// **A term whose native equivalent is the same fact.** The first run of this test failed on one line, and it was
/// right to: `firewallVerdictNoAddress` says `LAN` in the Japanese authored line and 「同じネットワーク」 in hers. That
/// is not a withheld fact -- it is the same thing said in the other of Japanese's two ways of saying it, and a check
/// that cannot tell a synonym from an omission will be switched off the first time it cries wolf.
///
/// The entry is written as a **reason rather than a ban** in this repository's usual style, and it is deliberately
/// small: it says nothing about Charlotte and everything about the language. A second entry earns its place only the
/// same way -- by being a fact about a term rather than a licence for a line.
const Map<String, List<String>> _nativeEquivalents = <String, List<String>>{
  'LAN': <String>['同じネットワーク', 'ネットワーク'],
};

void main() {
  final source = File('lib/ui/theme.dart').readAsStringSync();

  /// The facts in a sentence: numbers, and runs of ASCII letters long enough to be a name rather than a word.
  Set<String> factsIn(String text) {
    final facts = RegExp(r'[0-9]+(?:\.[0-9]+)?|[A-Za-z][A-Za-z0-9._-]{2,}')
        .allMatches(text)
        .map((match) => match.group(0)!)
        .toSet();
    return facts;
  }

  /// Every definition, found by the boundary that cannot be mistaken: the next declaration. Two earlier attempts to
  /// locate definitions in this file guessed where one ends, and both times paired a name with its neighbour's text.
  List<({String name, String body})> definitions() {
    final starts = RegExp(r'^\s*static const (\w+) = CopyLine\.', multiLine: true)
        .allMatches(source)
        .toList();
    return [
      for (var i = 0; i < starts.length; i++)
        (
          name: starts[i].group(1)!,
          body: source.substring(
            starts[i].start,
            i + 1 < starts.length ? starts[i + 1].start : source.length,
          ),
        ),
    ];
  }

  /// A single-quoted Dart string, including escaped quotes inside it.
  ///
  /// **The plain `'([^']*)'` was not enough and the reason is worth keeping.** One of the minister's sentences contains
  /// an apostrophe -- "the other's key" -- written as `\'`, and a pattern that stops at the first quote ends the match
  /// inside the word. The same class of mistake as matching `Voice.heiressJa: '` and missing the two lines whose
  /// value begins on the following line: a pattern is only as good as what it was written against.
  const stringLiteral = r"'((?:[^'\\]|\\.)*)'";

  String? capture(String body, String pattern) =>
      RegExp(pattern).firstMatch(body)?.group(1)?.replaceAll(r"\'", "'");

  /// The nth `Translated.authored('…')` in a definition, with adjacent literals joined is not attempted here: the
  /// authored text of a line is always a single literal in this file, which is a fact about the file rather than an
  /// assumption about Dart.
  String? authoredAt(String body, int index) {
    final all = RegExp('Translated\\.authored\\($stringLiteral').allMatches(body).toList();
    if (all.length <= index) return null;
    return all[index].group(1)?.replaceAll(r"\'", "'");
  }

  test('**她从不隐瞒信息**: no line of hers drops a number or a name the plain line carries', () {
    final failures = <String>[];

    for (final definition in definitions()) {
      final voiced = capture(definition.body, "Voice\\.heiress:\\s*$stringLiteral");
      if (voiced == null) continue;

      final authored = authoredAt(definition.body, 0) ?? '';
      final lost = factsIn(authored).difference(factsIn(voiced));
      if (lost.isNotEmpty) {
        failures.add('${definition.name}: ${lost.join(', ')}');
      }
    }

    expect(
      failures,
      isEmpty,
      reason: 'these lines lost a fact when they were rewritten in her voice:\n${failures.join('\n')}\n\n'
          'A lost fact is the one failure this register forbids outright, so it is a test failure rather than a\n'
          'note in a document. Either restore the number or the name, or write the fact into the authored line\n'
          'instead -- what must not happen is her sentence being the only place it was.',
    );
  });

  test('**the same rule in Japanese**: nothing is dropped between the Japanese source and あたし either', () {
    final failures = <String>[];

    for (final definition in definitions()) {
      final voiced = capture(definition.body, r"Voice\.heiressJa:\s*" "$stringLiteral");
      if (voiced == null) continue;

      final authored = capture(definition.body, r"'ja':\s*" "$stringLiteral") ?? '';
      final lost = <String>{};
      for (final fact in factsIn(authored)) {
        if (voiced.contains(fact)) continue;
        // A term written the other way round is still the same fact; see the note above the table.
        final equivalents = _nativeEquivalents[fact] ?? const <String>[];
        if (equivalents.any(voiced.contains)) continue;
        lost.add(fact);
      }
      if (lost.isNotEmpty) {
        failures.add('${definition.name}: ${lost.join(', ')}');
      }
    }

    expect(
      failures,
      isEmpty,
      reason: 'the Japanese half of the voice lost a fact:\n${failures.join('\n')}',
    );
  });

  /// The facts in an **English** line: what a paraphrase cannot absorb.
  ///
  /// The Chinese rule above is deliberately stricter -- it treats any ASCII run as a fact -- and that strictness is
  /// worth keeping, because it is what caught `1行に1組` being rewritten as 「一行に一組」 with the digit replaced by a
  /// character. It does not transfer to English, where the same rule matches every word of every sentence, and where
  /// the voice under test is one whose whole manner is the replacement of one phrase by another.
  Set<String> hardFactsIn(String text) {
    final facts = <String>{};
    facts.addAll(RegExp(r'[0-9]+(?:\.[0-9]+)?').allMatches(text).map((m) => m.group(0)!));
    facts.addAll(RegExp(r'`([^`]+)`').allMatches(text).map((m) => m.group(1)!));
    // a token with a digit or an internal capital is not a word a sentence can simply do without
    facts.addAll(RegExp(r'\b[A-Za-z0-9._-]*[0-9][A-Za-z0-9._-]*\b')
        .allMatches(text)
        .map((m) => m.group(0)!));
    facts.addAll(RegExp(r'\b[A-Za-z][a-z0-9._-]*[A-Z][A-Za-z0-9._-]*\b')
        .allMatches(text)
        .map((m) => m.group(0)!));
    return facts;
  }

  test('**and the same rule for the minister**: nothing is dropped between the English line and his', () {
    // The third voice, and the one that was outside every check until now. He is checked against the **English**
    // authored line rather than the Chinese one, because that is the language he is written in -- the same reason the
    // Japanese half is checked against the Japanese source.
    final failures = <String>[];

    for (final definition in definitions()) {
      final voiced = capture(definition.body, "Voice\\.minister:\\s*$stringLiteral");
      if (voiced == null) continue;

      final authored = authoredAt(definition.body, 1) ?? '';
      final lost = hardFactsIn(authored).difference(hardFactsIn(voiced));
      if (lost.isNotEmpty) {
        failures.add('${definition.name}: ${lost.join(', ')}');
      }
    }

    expect(
      failures,
      isEmpty,
      reason: 'the minister\'s line lost a fact the English line carries:\n${failures.join('\n')}',
    );
  });

  test('**the three voices cover the same lines, because a complete voice is complete**', () {
    // Adding eight lines to hers and not to his left them at 63, 63 and 55 -- and the status tool prints that without
    // complaint, because it reports what is there rather than what is missing. A voice that was completed is complete
    // for every line the others cover; anything else is a fault wearing the clothes of a choice.
    final withHer = definitions().where((d) => d.body.contains('Voice.heiress')).map((d) => d.name).toSet();
    final withHim = definitions().where((d) => d.body.contains('Voice.minister')).map((d) => d.name).toSet();
    final withJa = definitions().where((d) => d.body.contains('Voice.heiressJa')).map((d) => d.name).toSet();

    expect(withHim.difference(withHer), isEmpty,
        reason: 'these lines have his voice and not hers: ${withHim.difference(withHer).join(', ')}');
    expect(withHer.difference(withHim), isEmpty,
        reason: 'these lines have her voice and not his, which is how the gap above happened: '
            '${withHer.difference(withHim).join(', ')}');
    expect(withJa.difference(withHer), isEmpty,
        reason: 'Japanese without Chinese: ${withJa.difference(withHer).join(', ')}');
    expect(withHer.length, greaterThanOrEqualTo(60),
        reason: 'the parser found ${withHer.length} voiced lines, which is too few to be a coincidence');
  });

  test('the check has something to check, or it is a test that cannot fail', () {
    // A guard over an empty set passes for the worst possible reason. If the parser above stops finding voiced lines
    // -- because the file was reorganised, or a pattern changed -- the two tests above would keep reporting success
    // while checking nothing at all. This is the test that notices.
    final voiced = definitions()
        .where((definition) => definition.body.contains('Voice.heiress'))
        .length;
    final minister = definitions()
        .where((definition) => definition.body.contains('Voice.minister'))
        .length;
    expect(minister, greaterThanOrEqualTo(50),
        reason: 'the parser found $minister lines carrying the minister\'s voice; a number this low means his lines '
            'are no longer being located, which would make the test above pass by covering nothing');
    expect(voiced, greaterThanOrEqualTo(50),
        reason: 'the parser found $voiced voiced lines; Charlotte had 22 when this test was written, so a number '
            'this low means the definitions are no longer being located rather than that her voice shrank');
  });
}
