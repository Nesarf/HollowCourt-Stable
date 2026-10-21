import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// **A voice is allowed to be in character; it is not allowed to be a template.**
///
/// On 2026-10-21 the audit tool measured how far each marker was spread, and the number that mattered was not `本小姐`
/// in 84 of 141 lines -- an identity word that appears often is a character. It was that **thirteen of those lines
/// ended with the same closing move**: 本小姐说清楚 four times, 本小姐先说清楚 three, 本小姐说到这儿 twice, 本小姐说得
/// 够清楚了 once. That is what reads as a machine, and it is invisible to every test that checks facts, fallbacks
/// and register, because each of those thirteen lines is individually correct.
///
/// So this file holds the two shapes the rewording produced a rule against:
///
/// 1. **The closing move is not repeated.** A specific phrase with a specific job may appear once, twice if it is
///    doing different work; the list below is the set that had become filler.
/// 2. **The identity word is not said twice in one line.** Once is a character speaking about herself; twice is a
///    character reminding you who she is.
///
/// **The list is deliberately short, and adding to it needs a measurement rather than an opinion.** A test that
/// banned every repeated phrase would fail on 「……」, which is punctuation doing its job. These four earned their
/// place by being counted, and the next one has to earn its place the same way.
void main() {
  final source = File('lib/ui/theme.dart').readAsStringSync();

  Map<String, List<String>> voices() {
    final found = <String, List<String>>{};
    for (final match in RegExp(r"Voice\.(\w+):\s*'((?:[^'\\]|\\.)*)'").allMatches(source)) {
      found.putIfAbsent(match.group(1)!, () => []).add(match.group(2)!);
    }
    return found;
  }

  test('**no line closes with one of the filler moves**', () {
    const filler = <String>[
      '本小姐说清楚',
      '本小姐说到这儿',
      '本小姐先说清楚',
      '本小姐说得够清楚',
    ];
    final found = <String>[];
    for (final entry in voices().entries) {
      for (final text in entry.value) {
        for (final phrase in filler) {
          if (text.contains(phrase)) found.add('${entry.key}: $text');
        }
      }
    }
    expect(
      found,
      isEmpty,
      reason: 'these lines close with a move that was being used as filler: ${found.take(4).join(" | ")}',
    );
  });

  test('**the identity word is said at most once in a line**', () {
    final repeated = <String>[
      for (final text in voices()['heiress'] ?? const <String>[])
        if (RegExp('本小姐').allMatches(text).length > 1) text,
    ];
    expect(repeated, isEmpty, reason: 'twice in one line reads as a reminder rather than a character');
  });

  test('**the whole set is still there**', () {
    // A guard against this file passing because the parse found nothing: three voices, each covering the same set of
    // lines, which is what `voice_test` asserts from the other direction.
    final measured = voices();
    expect(measured.keys, containsAll(<String>['heiress', 'heiressJa', 'minister']));
    final counts = {for (final entry in measured.entries) entry.key: entry.value.length};
    expect(counts.values.toSet(), hasLength(1), reason: 'the three registers cover the same lines: $counts');
    expect(counts.values.first, greaterThan(100));
  });
}
