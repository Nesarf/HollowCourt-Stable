/// A liquid colour, as section 12.1 draws it.
///
/// one source proves the whole idea: a short string is enough to recognise a drink
/// at a glance.
///
/// **There are 28 of them, and the four beyond the first 24 are a correction
/// rather than an addition.** The first version of this enum was written as
/// "exactly as observed", enumerated from a list of 24 -- and the list was an
/// incomplete reading of the source. Going back over the export showed the same
/// 414 recipes producing four values the enum could not express: `pink` (11
/// recipes), `purple_light` (4), `neutral_darkest` (2) and `turquoise` (1).
/// **An enum that cannot express 18 of its own source's recipes is not a
/// faithful enumeration of that source**, so they are here.
///
/// Four of the 28 have not been observed in either source: [neutralDark],
/// [greenDark], [purple] and [purpleDark]. They are kept rather than removed,
/// because deleting a value is a larger claim than adding one, and the direction
/// that matters is asserted by a test instead: **every colour either source
/// produces can be read here.**
///
/// The tempting alternative is a `family x tone` grid -- which is tidier and
/// wrong for this purpose, because a grid makes `orange_lightest` a legal value
/// while one source never wrote one. [family] and [tone] are still exposed, because
/// the renderer wants them, but they are *derived from* the list rather than the
/// other way round.
enum LiquidColour {
  neutralLightest('neutral', Tone.lightest),
  neutralLight('neutral', Tone.light),
  neutralDark('neutral', Tone.dark),
  neutralDarkest('neutral', Tone.darkest),

  brownLight('brown', Tone.light),
  brown('brown', Tone.base),
  brownDark('brown', Tone.dark),

  yellowLight('yellow', Tone.light),
  yellow('yellow', Tone.base),
  yellowDark('yellow', Tone.dark),

  redLight('red', Tone.light),
  red('red', Tone.base),
  redDark('red', Tone.dark),

  greenLight('green', Tone.light),
  green('green', Tone.base),
  greenDark('green', Tone.dark),

  orangeLight('orange', Tone.light),
  orange('orange', Tone.base),
  orangeDark('orange', Tone.dark),

  purpleLight('purple', Tone.light),
  purple('purple', Tone.base),
  purpleDark('purple', Tone.dark),

  blueLight('blue', Tone.light),
  blue('blue', Tone.base),

  pinkLight('pink', Tone.light),
  pink('pink', Tone.base),
  pinkDark('pink', Tone.dark),

  /// A family of one. The export writes it once, for a single recipe, and
  /// neither source writes a lighter or darker form of it.
  turquoise('turquoise', Tone.base);

  const LiquidColour(this.family, this.tone);

  /// The hue, without its depth.
  final String family;

  final Tone tone;

  /// Reads one source's spelling, `orange_dark`, or returns null.
  ///
  /// one source also writes an empty string for the secondary colour, which means
  /// "there is only one colour" and is not a value here -- the caller turns
  /// that into a null.
  static LiquidColour? fromSource(String raw) {
    final key = raw.trim().toLowerCase();
    if (key.isEmpty) return null;
    for (final colour in LiquidColour.values) {
      if (colour.sourceName == key) return colour;
    }
    return null;
  }

  /// The name the data uses, which is not quite [name].
  String get sourceName {
    final buffer = StringBuffer();
    for (var i = 0; i < name.length; i++) {
      final ch = name[i];
      if (ch.toUpperCase() == ch && ch.toLowerCase() != ch && i > 0) {
        buffer.write('_');
      }
      buffer.write(ch.toLowerCase());
    }
    return buffer.toString();
  }

  @override
  String toString() => sourceName;
}

/// How light or dark a colour is, from the list above rather than from a grid.
///
/// [darkest] exists because the source contains one: `neutral_darkest`. It is
/// the only member of the scale with a single user, which is the sort of thing a
/// `family x tone` grid would have hidden by making it one of four tones every
/// family was allowed to have.
enum Tone { lightest, light, base, dark, darkest }

/// What a drink looks like in the glass, in five fields.
///
/// Straight from section 12.1, which took it straight from one source. Together with
/// [Glass] and [IceKind] this is enough to recognise a drink in a list without
/// loading a picture of it, which is why it is worth carrying in the seed at
/// all.
final class LiquidVisual {
  const LiquidVisual({
    required this.colour,
    required this.opacityPercent,
    this.colourSecondary,
    this.opacitySecondary,
    this.layered = false,
  });

  final LiquidColour colour;

  /// The second colour of a layered drink, or null when there is one colour.
  final LiquidColour? colourSecondary;

  /// Opacity, as a whole percentage. one source uses 10/25/50/75/90/100.
  ///
  /// A whole number rather than a fraction, because that is what the data
  /// carries and there is nothing to compute with it -- it goes to the renderer
  /// and no further.
  final int opacityPercent;

  final int? opacitySecondary;

  /// Whether the drink separates into visible layers.
  final bool layered;

  /// True when the two colours are both present, which is what [layered]
  /// describes and what a renderer has to be able to draw.
  bool get hasSecondColour => colourSecondary != null;

  /// Problems that make this value unusable, as sentences.
  ///
  /// A list rather than an exception, and empty when the value is sound.
  /// Section 18 asks for validation at write time and on import, and both of
  /// those want to collect every complaint in a batch rather than stop at the
  /// first -- a spreadsheet with forty bad rows should produce forty lines, not
  /// forty runs.
  List<String> validate() {
    final problems = <String>[];

    if (opacityPercent < 0 || opacityPercent > 100) {
      problems.add('opacityPercent is $opacityPercent, which is not 0 to 100');
    }
    if (opacitySecondary != null &&
        (opacitySecondary! < 0 || opacitySecondary! > 100)) {
      problems.add('opacitySecondary is $opacitySecondary, which is not 0 to 100');
    }

    // A second opacity without a second colour is a value nobody can draw.
    if (colourSecondary == null && opacitySecondary != null) {
      problems.add('opacitySecondary is set but there is no colourSecondary');
    }

    // Layered with one colour is the same problem from the other side.
    if (layered && colourSecondary == null) {
      problems.add('layered is true but there is only one colour');
    }

    return problems;
  }

  @override
  String toString() => colourSecondary == null
      ? '$colour @$opacityPercent%'
      : '$colour/$colourSecondary @$opacityPercent%/$opacitySecondary%'
            '${layered ? ' layered' : ''}';
}
