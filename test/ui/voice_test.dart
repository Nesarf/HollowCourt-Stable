import 'package:flutter_test/flutter_test.dart';
import 'package:hollow_court/ui/l10n/dual_copy.dart';
import 'package:hollow_court/ui/l10n/voice.dart';

/// **The voice axis, and the two things it must never do**: change a line for a reader who chose no voice, or let
/// a voice answer in a language it was not written in.
///
/// The owner's request of 2026-09-25 was for something like 猫娘语言包 or 梗体中文 -- the same interface in a
/// different register, offered as a choice. The examples are other people's; the writing here is ours.
void main() {
  const cellarEmpty = CopyLine.withLanguages(
    Translated.authored('这里还是空的。记下第一瓶酒，配方就知道能为你做什么。'),
    Translated.authored('Still empty here. Record the first bottle, and the recipes will know what they can do.'),
    also: {'ja': 'ここはまだ空です。'},
    voices: {
      Voice.heiress: '哼，这里空空如也呢。……才、才不是催你，只是记下第一瓶的话，配方就知道该怎么伺候你了。',
      Voice.minister:
          'With respect, Minister, the cellar is, as matters stand, somewhat under-utilised.',
    },
  );

  test('**a reader who chose no voice reads exactly what they read yesterday**', () {
    expect(cellarEmpty.textFor('zh-Hans'), startsWith('这里还是空的'));
    expect(cellarEmpty.textFor('en'), startsWith('Still empty here'));
    expect(cellarEmpty.textFor('ja'), 'ここはまだ空です。');
  });

  test('a voice answers, in its own language', () {
    expect(cellarEmpty.textFor('zh-Hans', voice: Voice.heiress), startsWith('哼，这里空空如也'));
    expect(cellarEmpty.textFor('en', voice: Voice.minister), startsWith('With respect, Minister'));
  });

  test('**and says nothing in a language it was not written in**', () {
    // A Chinese heiress in an English interface, or an English civil servant in a Chinese one, is not a voice --
    // it is a bug. Both fall through to the plain line rather than speaking out of turn.
    expect(cellarEmpty.textFor('en', voice: Voice.heiress), startsWith('Still empty here'));
    expect(cellarEmpty.textFor('zh-Hans', voice: Voice.minister), startsWith('这里还是空的'));
    expect(cellarEmpty.textFor('ja', voice: Voice.heiress), 'ここはまだ空です。');
  });

  test('a line nobody has written in a voice is unchanged by the choice', () {
    // The design is deliberate about coverage: almost every line has no voice, and those lines are not a gap to
    // be filled in later so much as a line where the plain wording is already the right one -- a unit label, a
    // button, a nav bar's five characters.
    const unitLabel = CopyLine(Translated.authored('ml'), Translated.authored('ml'));
    expect(unitLabel.textFor('zh-Hans', voice: Voice.heiress), 'ml');
    expect(unitLabel.textFor('en', voice: Voice.minister), 'ml');
  });

  test('a voice knows which language it speaks, and the plain one speaks all of them', () {
    expect(Voice.heiress.language, 'zh-Hans');
    expect(Voice.minister.language, 'en');
    expect(Voice.plain.isPlain, isTrue);
    expect(Voice.plain.language, isEmpty);
  });

  test('**a second voice in the same register, for another language**', () {
    // The owner asked for a Japanese tsundere the moment the axis existed, and it needed no design change: a
    // voice already carries the language it speaks. What it must still do is stay out of everybody else's way.
    const line = CopyLine.withLanguages(
      Translated.authored('这里还是空的。'),
      Translated.authored('Still empty here.'),
      also: {'ja': 'ここはまだ空です。'},
      voices: {
        Voice.heiress: '哼，这里空空如也呢。',
        Voice.heiressJa: 'ふん、ここはまだ空っぽよ。',
      },
    );

    expect(line.textFor('ja', voice: Voice.heiressJa), 'ふん、ここはまだ空っぽよ。');
    expect(line.textFor('ja', voice: Voice.heiress), 'ここはまだ空です。',
        reason: 'the Chinese heiress does not speak Japanese');
    expect(line.textFor('zh-Hans', voice: Voice.heiressJa), '这里还是空的。',
        reason: 'nor does the Japanese one speak Chinese');
    expect(line.textFor('en', voice: Voice.heiressJa), 'Still empty here.');
  });
}
