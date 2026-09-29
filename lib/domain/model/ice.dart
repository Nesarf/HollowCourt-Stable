/// How much ice, and what kind.
///
/// Section 4.4 lists this as a recipe field of its own rather than as a note,
/// and the reason is arithmetic before it is descriptive: the method decides
/// how much ice melts into the glass (section 5.5), and the amount of ice is
/// what the method has to work with.
///
/// [none] is a value rather than a null because a drink served without ice is
/// making a statement, and a null would be indistinguishable from a source that
/// simply failed to say.
enum IceKind {
  none,
  cubes,
  crushed,
  rock,
  block;

  /// Reads a source's spelling, or returns null.
  ///
  /// one source writes `none` / `cubes` / `crushed` / `rock`, and leaves the field
  /// empty on three of its 414 recipes. Empty is *not* [none] -- one is a
  /// decision the recipe made, the other is a gap -- so an empty string returns
  /// null and the importer reports it.
  static IceKind? fromSource(String raw) {
    final key = raw.trim().toLowerCase();
    if (key.isEmpty) return null;
    for (final kind in IceKind.values) {
      if (kind.name == key) return kind;
    }
    // Singular and plural are used interchangeably by every source there is.
    return switch (key) {
      'cube' => IceKind.cubes,
      'rocks' => IceKind.rock,
      'blocks' => IceKind.block,
      _ => null,
    };
  }
}
