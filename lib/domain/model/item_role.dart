/// What part an ingredient plays in a drink.
///
/// Section 9 scores a recipe by this rather than by counting ingredients,
/// because the roles are not equally important: a drink without its base is
/// not that drink, while a drink without its garnish is that drink with a
/// missing piece of peel.
enum ItemRole {
  /// The spirit the drink is built on. Missing means it is not this drink.
  base,

  /// Liqueurs, syrups, bitters: the things that make it *this* drink rather
  /// than another.
  modifier,

  /// Garnish. Scored apart from everything else, so that a missing twist
  /// cannot make a Negroni look impossible.
  garnish,

  /// Genuinely optional.
  optional,
}
