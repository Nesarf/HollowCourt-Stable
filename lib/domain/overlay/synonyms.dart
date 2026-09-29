/// **Equivalent names: the reader's own statement that two words mean one thing.**
///
/// The owner asked for this on 2026-09-22, with the examples that make the need concrete:
///
/// > 在记录一栏里加入一个"批量自定义"功能，例如利口酒和力娇/力娇酒指的是同一个东西，安高天娜和安哥斯图拉也是如此，
/// > 马天尼和马提尼同理，类似的还有菲士与菲兹、金酒与琴酒、蓝柑与蓝橙......这时候就要允许用户自定义了，否则会出问题。
///
/// **Why this is a real problem rather than a nicety.** Every name in this application comes from somewhere
/// else -- a bottle's label, a bar's menu, a translated list -- and Chinese has two or three well-established
/// renderings for most imported drinks. Liqueur is 利口酒 and 力娇 and 力娇酒; Angostura is 安高天娜 and
/// 安哥斯图拉; Martini is 马天尼 and 马提尼. An application that treats those as different substances does
/// not merely look untidy: it tells somebody they cannot make a drink they can make, and it does so with an
/// air of authority.
///
/// THE SHAPE OF A GROUP, and why it is a *group* rather than an alias field. Section 8's `ingredient` alias
/// says "call this ingredient something else" -- one word for one thing, which is what a shelf label is. A
/// synonym group says "these words are the same word", which is what a *dictionary* is, and the difference
/// shows up the moment somebody types: an alias renames the thing you already picked, and a group finds the
/// thing you were trying to name.
///
/// **[decision] The first name in a line is the canonical one.** `金酒 = 琴酒, 杜松子酒` means the entry is
/// Gin and those are other ways of saying it -- so the reader's own vocabulary decides which word the
/// application shows, and the ingredient's id is looked up from the first name. A format with no first name
/// (`金酒 琴酒 杜松子酒`) would leave the application choosing, and it would choose the seed's English.
library;

/// One line of the bulk editor, parsed.
final class SynonymGroup {
  const SynonymGroup({required this.canonical, required this.also});

  /// The name the reader wants to see.
  final String canonical;

  /// Every other name that means the same thing. Never contains [canonical].
  final List<String> also;

  /// All the names in the group, canonical first.
  List<String> get all => [canonical, ...also];

  @override
  String toString() => '$canonical = ${also.join(', ')}';
}

/// A line that could not be read, and why -- reported rather than skipped.
///
/// **A bulk editor that silently drops a line is worse than one that refuses it.** The reader pasted twenty
/// names, sees a success message, and the one that mattered is not there; the failure surfaces weeks later as
/// a drink that cannot be made. So every line is either a group or a complaint with its number.
final class SynonymProblem {
  const SynonymProblem(this.line, this.text, this.reason);

  /// 1-based, and 1-based in the *reader's* numbering: the first line they see is line 1.
  final int line;

  /// What they typed, so the complaint can point at it.
  final String text;

  final String reason;
}

/// What the bulk editor made of a pasted block.
final class SynonymParse {
  const SynonymParse({required this.groups, required this.problems});

  final List<SynonymGroup> groups;
  final List<SynonymProblem> problems;

  bool get ok => problems.isEmpty;
}

/// Reads a pasted block of `canonical = also, also` lines.
///
/// The grammar, in full:
///
/// * one group per line;
/// * `=` separates the canonical name from the rest -- `:` and `＝` are accepted because a person typing
///   quickly on a Chinese keyboard produces the full-width form;
/// * `,` `，` and `、` separate the alternatives, because all three are how somebody writing Chinese lists
///   things;
/// * blank lines and lines beginning with `#` are ignored, so a block can carry its own notes;
/// * a line with no separator is a single name with no alternatives -- accepted, because a group of one is
///   what a reader gets when they start typing, and refusing it would be pedantry.
///
/// **Nothing is trimmed of meaning and everything is trimmed of space**: a name with a leading space is a
/// typo, not a different substance.
SynonymParse parseSynonymBlock(String block) {
  final groups = <SynonymGroup>[];
  final problems = <SynonymProblem>[];
  final lines = block.split('\n');

  for (var i = 0; i < lines.length; i++) {
    final raw = lines[i];
    final text = raw.trim();
    if (text.isEmpty || text.startsWith('#')) continue;

    final parts = _splitOn(text, const ['=', '＝', ':', '：']);
    if (parts == null) {
      // No separator at all: a name on its own. Real, and not an error.
      groups.add(SynonymGroup(canonical: text, also: const []));
      continue;
    }

    final canonical = parts.$1.trim();
    if (canonical.isEmpty) {
      problems.add(SynonymProblem(i + 1, text, 'the line has no name before the "="'));
      continue;
    }

    final also = <String>[];
    for (final piece in _splitAll(parts.$2, const [',', '，', '、'])) {
      final name = piece.trim();
      if (name.isEmpty) continue;
      if (name == canonical) continue; // A group naming itself once is what a person does while typing.
      if (also.contains(name)) continue;
      also.add(name);
    }

    groups.add(SynonymGroup(canonical: canonical, also: also));
  }

  return SynonymParse(groups: groups, problems: problems);
}

/// The same table, rendered back as the text the editor shows.
///
/// Round-tripping matters: the reader opens the editor, sees what they wrote last time, edits it, and saves.
/// A screen that showed a different format from the one it accepts would make every visit a small translation
/// the reader has to do themselves.
String renderSynonymBlock(Iterable<SynonymGroup> groups) =>
    groups.map((group) => group.toString()).join('\n');

/// **The lookup the rest of the application asks.** Given a name typed or stored, which canonical name does
/// this reader mean by it?
///
/// Matching is case-insensitive and space-insensitive, because `Blue Curaçao` and `blue curaçao` are not two
/// things; it is *not* fuzzy, because a dictionary that guessed would answer confidently about a name nobody
/// defined, which is the failure this whole file exists to prevent.
String? canonicalNameOf(String typed, Iterable<SynonymGroup> groups) {
  final needle = _fold(typed);
  if (needle.isEmpty) return null;
  for (final group in groups) {
    for (final name in group.all) {
      if (_fold(name) == needle) return group.canonical;
    }
  }
  return null;
}

/// Every name in [groups] that is equivalent to [name], or an empty list when it is in none.
List<String> synonymsOf(String name, Iterable<SynonymGroup> groups) {
  final needle = _fold(name);
  for (final group in groups) {
    if (group.all.any((candidate) => _fold(candidate) == needle)) {
      return [for (final candidate in group.all) if (_fold(candidate) != needle) candidate];
    }
  }
  return const [];
}

String _fold(String text) =>
    text.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '');

/// Splits on the first occurrence of any of [separators], returning both sides, or null.
(String, String)? _splitOn(String text, List<String> separators) {
  var best = -1;
  for (final separator in separators) {
    final at = text.indexOf(separator);
    if (at >= 0 && (best < 0 || at < best)) best = at;
  }
  if (best < 0) return null;
  // The separator may be one character or more; all of them here are one.
  return (text.substring(0, best), text.substring(best + 1));
}

Iterable<String> _splitAll(String text, List<String> separators) {
  var pieces = <String>[text];
  for (final separator in separators) {
    pieces = [
      for (final piece in pieces) ...piece.split(separator),
    ];
  }
  return pieces;
}
