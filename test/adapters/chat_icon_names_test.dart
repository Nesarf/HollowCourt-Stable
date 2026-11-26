import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hollow_court/adapters/elizabeth_prompt.dart';
import 'package:hollow_court/ui/chat_icons.dart';
import 'package:hollow_court/ui/chat_render.dart';

/// **Two lists that have to say the same thing, and nothing that would notice if they stopped.**
///
/// The prompt offers names and the renderer holds glyphs. They live in different layers -- `adapters` has no Flutter
/// dependency, which is why the table cannot be imported there -- so the only thing standing between a reader and a
/// `:kitchen:` that prints as punctuation is this file.
void main() {
  test('**the prompt offers exactly the icons the renderer knows**', () {
    expect(replyIconNames.toSet(), chatIcons.keys.toSet());
  });

  test('every offered name appears in the prompt, written the way a reply would write it', () {
    for (final name in replyIconNames) {
      expect(elizabethSystemPrompt, contains(':$name:'), reason: 'the prompt must show $name as a reply writes it');
    }
  });

  test('**a name outside the table prints as written rather than disappearing**', () {
    // The failure this prevents is silent: a span dropped instead of drawn would read as a sentence with a hole.
    // Both names here are deliberately absent from `chatIcons`; `kitchen` is in it, which is how the first version
    // of this test managed to assert the opposite of what the code does.
    final spans = inlineSpans('看图:not_an_icon:和:also_missing:', const TextStyle(fontSize: 14));
    expect(spans.map((span) => span.text).join(), '看图:not_an_icon:和:also_missing:');
  });

  test('a known name becomes one glyph in the icon font', () {
    final spans = inlineSpans('一杯:cocktail:就好', const TextStyle(fontSize: 14));
    final glyph = spans.firstWhere((span) => span.style?.fontFamily == 'MaterialIcons');
    expect(glyph.text, String.fromCharCode(Icons.local_bar.codePoint));
    // The words either side survive, which is the part a careful implementation gets wrong.
    expect(spans.map((span) => span.text).join(), '一杯${String.fromCharCode(Icons.local_bar.codePoint)}就好');
  });

  test('the table has no name that is not in the prompt, and no empty entry', () {
    for (final entry in chatIcons.entries) {
      expect(entry.key.trim(), isNotEmpty);
      expect(entry.value.fontFamily, isNotNull, reason: '${entry.key} must come from the icon font');
    }
    expect(chatIconNames, orderedEquals(chatIconNames.toList()..sort()));
  });
}
