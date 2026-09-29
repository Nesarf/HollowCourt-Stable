/// **One entry in the list a reader chooses a writing from**, whether it is a language or a voice.
///
/// The owner's decision, 2026-09-29: 伊丽莎白 and Yes, Minister belong at the same level as 简中 and
/// English, not beside them on a second axis. They cannot be entries in [shippedLocales], for two
/// reasons that file's own tests enforce: that catalogue must import nothing at all, and no two of
/// its entries may share a tag -- while a voice shares the tag of the language it is written in,
/// which is the whole point of it. So the two lists are joined here, in a file whose only job is the
/// joining, and the picker offers the result as the one list a reader sees.
///
/// It is public because a widget test has to name the type a `DropdownButton` is parameterised by,
/// and a private class cannot be named from outside its library. `find.byType` matches the exact
/// generic, so there is no way around that from the test side.
library;

import 'locale_catalogue.dart';
import 'voice.dart';

/// A language, or a voice written in one.
final class LocaleChoice {
  const LocaleChoice(this.tag, this.label, this.voice);

  /// The BCP-47 tag this choice reads in. Two choices may share one.
  final String tag;

  /// What the reader sees, in the choice's own language.
  final String label;

  /// [Voice.plain] for a language offered as itself.
  final Voice voice;

  @override
  bool operator ==(Object other) =>
      other is LocaleChoice &&
      other.tag == tag &&
      other.label == label &&
      other.voice == voice;

  @override
  int get hashCode => Object.hash(tag, label, voice);

  @override
  String toString() =>
      voice == Voice.plain ? '$label ($tag)' : '$label ($tag, ${voice.name})';
}

/// **The five languages, each plainly, then the three voices written for one of them.**
///
/// A voice's own [Voice.label] is already in the voice's language -- that is the third field of the
/// enum, and the reason this reads as one list rather than two lists glued together.
List<LocaleChoice> localeChoices() => <LocaleChoice>[
      for (final locale in shippedLocales)
        LocaleChoice(locale.tag, locale.nativeName, Voice.plain),
      for (final voice in offeredVoices)
        LocaleChoice(voice.language, voice.label, voice),
    ];
