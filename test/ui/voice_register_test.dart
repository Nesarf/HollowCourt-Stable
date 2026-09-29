import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// **Charlotte's register, made checkable.** `charlotte-voice.md` describes how she talks, and `charlotte-facts`'s
/// sibling test covers the rule that she never withholds a fact. This one covers the other half: that she keeps
/// sounding like herself as batches are added to her.
///
/// The failure this guards against is slow and reasonable. Every new line is written on its own, each one defensible,
/// and the collection drifts -- a 「哼」 on more and more openings until she is a tic rather than a person, a self-
/// reference from another archetype because it fitted the sentence, a line that quietly stops being hers. None of
/// those is visible in a single diff. All of them are visible in the numbers.
///
/// **The thresholds are the measurements, not guesses.** They were taken from her twenty-two lines on 2026-09-26 and
/// every one of them has headroom, so the test fails when she *changes* rather than when she has an ordinary day.
void main() {
  final source = File('lib/ui/theme.dart').readAsStringSync();

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

  String? capture(String body, String pattern) => RegExp(pattern).firstMatch(body)?.group(1);

  final lines = <({String name, String authored, String heiress, String heiressJa})>[];
  for (final definition in definitions()) {
    final heiress = capture(definition.body, r"Voice\.heiress:\s*'([^']*)'");
    if (heiress == null) continue;
    lines.add((
      name: definition.name,
      authored: capture(definition.body, r"Translated\.authored\('([^']*)'") ?? '',
      heiress: heiress,
      heiressJa: capture(definition.body, r"Voice\.heiressJa:\s*'([^']*)'") ?? '',
    ));
  }

  /// **The forms she must never use, each with the reason it is out.** Written as reasons rather than a ban list,
  /// because a ban list is what somebody deletes when it is inconvenient -- a reason is what they argue with.
  ///
  /// The first entry is the owner's own instruction of 2026-09-26 (不是很建议使用「わらわ」) and the rest follow from the
  /// same principle he was applying: a self-reference that **dates** her, or that belongs to a different archetype.
  /// わらわ and わっち are period drama; 拙者 and 朕 are the wrong person entirely; 僕 and 俺 are the wrong voice for
  /// this character; 咱, 奴家, 老娘, 妾身 and 本宫 each carry a register that is not hers -- coarse, servile, or
  /// imperial. **わたくし is not on this list**: the owner named it as one of hers.
  const forbidden = <String, String>{
    'わらわ': 'archaic; the voice of a 大名 or a princess out of a period piece, which would move her from modern '
        'tsundere into historical drama — the owner ruled it out on 2026-09-26',
    'わっち': 'archaic commoner speech; the same dating problem from the other end',
    '拙者': 'a male samurai register',
    '朕': 'an emperor',
    '僕': 'a male first person',
    '俺': 'a male first person',
    '咱': 'coarse northern register',
    '奴家': 'servile, and period-bound',
    '老娘': 'coarse, and much older than she is',
    '妾身': 'a concubine register',
    '本宫': 'an imperial consort',
    // **And the line that is not about her own voice but about the reader's standing.** The owner's ruling of
    // 2026-09-26: 除了「你」，还有「你这家伙」等，但不会用「庶民」这种不尊敬的词. Both kinds of word are rude; they are
    // rude in different directions. 你这家伙 is a familiar roughness, the way equals speak to each other. 庶民 is
    // contempt from above -- she may be sharp with the reader and may never look down on them. 傲在态度，不傲在身份.
    '庶民': 'contempt addressed downward. She may be rough -- 「你这家伙」 is sanctioned and so is 「你」 -- but she '
        'never places the reader beneath her, and this is the word that would',
    '平民': 'the same contempt with a politer face',
    '下民': 'the same contempt without the politeness',
    '贱民': 'the same contempt at its worst',
  };

  test('**nothing that dates her or belongs to another archetype appears in her lines**', () {
    final found = <String>[];
    for (final line in lines) {
      for (final entry in forbidden.entries) {
        if (line.heiress.contains(entry.key) || line.heiressJa.contains(entry.key)) {
          found.add('${line.name}: ${entry.key} — ${entry.value}');
        }
      }
    }
    expect(found, isEmpty, reason: 'these lines use a self-reference that is not hers:\n${found.join('\n')}');
  });

  test('**「哼」 stays an opening, not a tic**', () {
    // Four of twenty-two when this was written, 18%. The ceiling is deliberately far above that: this is not a test
    // that she uses it, it is a test that she has not become a character who can only begin one way.
    final openings = lines.where((line) => line.heiress.startsWith('哼')).length;
    final ratio = openings / lines.length;
    expect(ratio, lessThanOrEqualTo(0.35),
        reason: '「哼」 opens $openings of ${lines.length} lines (${(ratio * 100).round()}%). The specification says to '
            'use it and not every time; a register that opens the same way in a third of its lines is a tic.');
  });

  test('**she adds tone, so her line is not shorter than the plain one**', () {
    // Measured on 2026-09-26: the shortest ratio was 0.93, the median 1.23. So a line that falls below 0.90 has not
    // been rewritten in her voice — it has been cut, and whatever went is the reader's loss rather than her flourish.
    final short = <String>[];
    for (final line in lines) {
      if (line.authored.isEmpty) continue;
      final ratio = line.heiress.length / line.authored.length;
      if (ratio < 0.90) {
        short.add('${line.name}: ${line.authored.length} -> ${line.heiress.length} (${(ratio * 100).round()}%)');
      }
    }
    expect(short, isEmpty,
        reason: 'her version is materially shorter than the plain one in these lines, which means something was '
            'removed rather than something being said differently:\n${short.join('\n')}');
  });

  test('**she never says her whole name, because the owner gave her two ways to say it and not a third**', () {
    // 台词里主要使用昵称和「伊丽莎白」 -- the nicknames (丽莎／莉莉／干邑) and the first name. The full four-part name is for the
    // character card, and somebody writing a line who reaches for all of it at once has broken a rule that was set
    // deliberately: a tsundere does not recite her own style, she drops the name she is called by.
    const wholeNameFragments = <String>[
      "d'Armagnac",
      'Armagnac',
      'Muse Marie',
      'Élisabeth Muse',
      '达尔马尼亚克',
      'ダルマニャック',
    ];
    final found = <String>[];
    for (final line in lines) {
      for (final fragment in wholeNameFragments) {
        if (line.heiress.contains(fragment) || line.heiressJa.contains(fragment)) {
          found.add('${line.name}: $fragment');
        }
      }
    }
    expect(found, isEmpty,
        reason: 'her lines use the nicknames and the first name; the full name belongs to the character card:\n'
            '${found.join('\n')}');
  });

  test('the guard has something to check, or it is a test that cannot fail', () {
    expect(lines.length, greaterThanOrEqualTo(50),
        reason: 'the parser found ${lines.length} lines carrying her voice; a number this low means the definitions '
            'are no longer being located rather than that her voice shrank');
    expect(lines.any((line) => line.heiressJa.isNotEmpty), isTrue,
        reason: 'the Japanese half is checked by the same rules, so finding none means half of this test is asleep');
  });
}
