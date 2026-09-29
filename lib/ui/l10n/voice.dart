/// A register of speech, as opposed to a language. See [Voice] for what the owner asked for and why this is a
/// second axis rather than a sixth language.
library;

/// **A register of speech, as opposed to a language.**
///
/// The owner's request of 2026-09-25, having looked at two well-known examples of the same idea -- a Minecraft
/// resource pack that rewrites the game's Chinese into catgirl speech, and one that rewrites it into memes (梗体中文,
/// which the PCL2 launcher ships as a selectable language). Both are *the same interface in a different voice*
/// rather than a translation, and both are offered as a choice.
///
/// So this is a **second axis**, not a sixth language. [CopyLine] already resolves a language through
/// `localeFallbacks`; a voice sits on top of that and answers only if it has something written **and** speaks the
/// language being asked for -- because a voice is written in one language and cannot pretend otherwise. A line
/// with no voice falls through to the plain one, which is why adding this changes nothing for a reader who does
/// not choose a voice.
enum Voice {
  /// The application as it has always spoken. Not "no voice": the default one.
  plain('', ''),

  /// 简体中文 · 金发双马尾傲娇大小姐 -- the heiress, who is not doing this for your sake.
  /// **The name the project uses for this voice is 伊丽莎白**, which is what a reader sees on the chip; the
  /// archetype beside it in this comment is what she is, not what she is called.
  heiress('zh-Hans', '伊丽莎白'),

  /// English · a permanent secretary, who would not advise a course of action, and would be grateful if you
  /// would consider one.
  minister('en', 'Yes, Minister'),

  /// 日本語 · ツンデレお嬢様 -- the same register as [heiress], written for Japanese rather than translated into
  /// it. The owner asked for it on 2026-09-25 the moment the axis existed, and it needed no design: a voice
  /// already carries its own language, which is the rule the test forced.
  heiressJa('ja', 'ツンデレお嬢様'),
  ;

  const Voice(this.language, this.label);

  /// The BCP-47 tag this voice is written in. Empty for [plain], which is every language at once.
  final String language;

  /// How the choice is named in settings, in the voice's own language.
  final String label;

  bool get isPlain => this == Voice.plain;

  /// The voice with this name, or [plain] when the name is one this build does not carry.
  ///
  /// **By name, like the theme, and for the same reason**: a stored index would shift the day a voice is inserted
  /// in the middle, and a name that is unknown is a setting written by another build rather than an error.
  static Voice byName(String? name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return Voice.plain;
  }
}

/// **The voices a reader may choose, beside the languages they are written in.**
///
/// The owner's decision, 2026-09-29: 伊丽莎白 and Yes, Minister are choices at the same level as
/// 简中 and English, not a second axis beside them. They cannot live in `shippedLocales`, for two
/// reasons that file's own tests enforce: that catalogue must import nothing at all, and no two
/// entries may share a tag -- while a voice shares the tag of the language it is written in, which
/// is the whole point of it. So they sit here, beside the enum that defines them, and the picker
/// reads both lists into the one list a reader chooses from.
///
/// [Voice.plain] is deliberately absent: it is what every language offers on its own.
const List<Voice> offeredVoices = <Voice>[
  Voice.heiress,
  Voice.heiressJa,
  Voice.minister,
];
