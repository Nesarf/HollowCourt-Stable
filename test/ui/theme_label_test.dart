import 'package:flutter_test/flutter_test.dart';

import 'package:hollow_court/ui/theme.dart';

/// **Every world this build ships has a name, in every language it speaks.**
///
/// ## The defect this exists for
///
/// `docs/memo-themes.md` settled on **2026-10-01** that 白庭 was deleted and `CL` took its place. The palette value
/// was renamed to `cosmicLatte`; **`Copy.themeWhiteCourt` was not touched**, and the label switch in
/// `display_section.dart` kept matching `'whiteCourt'`. So for ten days the one light world fell through to the id
/// fallback and its chip in 设置 read **`cosmicLatte`** -- a camelCase key, in no language, with no case to it.
///
/// **The interface never showed an error, and nothing failed.** The fallback is deliberate -- a setting written by a
/// build that carried a world this one does not still has to open -- and that is exactly what made it invisible: a
/// name that is wrong looks the same as a name that is right.
///
/// ## What is asserted, and why it is not a list of names
///
/// **It walks `HollowPalette.all`.** A test that listed the five names it expects would pass for ever while a sixth
/// world shipped an id, which is the same defect one release later. What is checked instead is the property the
/// fallback breaks: **the label a theme resolves to is not its own key.**
void main() {
  const languages = ['zh-Hans', 'zh-HK', 'zh-TW', 'ja', 'en'];

  test('**no shipped world falls through to the id fallback**', () {
    for (final theme in HollowPalette.all) {
      final label = Copy.themeLabelFor(theme);
      for (final tag in languages) {
        final text = label.textFor(tag);
        expect(text.trim(), isNotEmpty, reason: '${theme.name} has nothing to say in $tag');
        // **The one assertion that would have caught it.** The fallback answers with the theme's own key, so a chip
        // reading `cosmicLatte` is a chip whose label equals the name it was looked up by.
        expect(
          text,
          isNot(theme.name),
          reason: '${theme.name} resolves to its own key in $tag, which means the label switch has no case for it',
        );
      }
    }
  });

  test('**and the count is asserted, so a sixth world cannot arrive unannounced**', () {
    // The failure this prevents is not in the code, it is in the *test*: a walk over `HollowPalette.all` grows by
    // itself, so a world added with a proper name passes without anybody deciding it should. The count is where that
    // decision is recorded.
    expect(HollowPalette.all, hasLength(5), reason: 'a world was added or removed; decide its name and say so here');
  });

  test('**the light world is named, and named in three languages**', () {
    // The one that was broken, asserted directly as well as through the walk -- because a regression here is a
    // regression in the world a reader sees when they want a light room, and the walk alone would not say which.
    final label = Copy.themeLabelFor(HollowPaletteValue.cosmicLatte);
    expect(label.textFor('zh-Hans'), isNot('cosmicLatte'));
    expect(label.textFor('ja'), isNot('cosmicLatte'));
    expect(label.textFor('en'), isNot('cosmicLatte'));
    // **And the English has case to it.** The owner's words: 英文部分要有大小写 -- a name, not a key.
    expect(label.textFor('en'), isNot(label.textFor('en').toLowerCase()));
    expect(label.textFor('en'), isNot(label.textFor('en').toUpperCase()));
  });

  test('**no world is still called a court**', () {
    // 庭 was a taxonomy the theme list no longer has -- `display_section.dart` records the rename that removed it --
    // and 白庭 was the last of it, surviving as a copy line ten days after the world it named was deleted. A bare
    // string check, which is the right weight for "a word we stopped using".
    for (final theme in HollowPalette.all) {
      for (final tag in languages) {
        expect(
          Copy.themeLabelFor(theme).textFor(tag),
          isNot(contains('庭')),
          reason: '${theme.name} is still named as a court in $tag',
        );
      }
    }
  });
}
