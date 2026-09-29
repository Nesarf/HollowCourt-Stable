/// Exact rational arithmetic.
///
/// The design document is blunt about why this type exists: a recipe is a
/// ratio, and scaling a ratio a dozen times with binary floating point turns
/// `0.1 + 0.2` into a difference somebody can taste. A third of an ounce is a
/// third, not 0.3333; three of them are one ounce, not 0.9999.
///
/// So nothing here goes through `double`. Numerator and denominator are
/// `BigInt`, because a scale factor applied repeatedly to a denominator
/// accumulates digits faster than a fixed-width integer can hold them.
///
/// The one conversion out is [toDouble], which is for showing a number to a
/// person and for nothing else. Every quantity in the domain layer is built
/// from [Rational] and materialises to the integer base only at the edge, in
/// [roundHalfUp] and its neighbours.
library;

/// A fraction, always kept in lowest terms with a positive denominator.
///
/// The normalisation happens in the constructor, so two rationals that describe
/// the same number are always `==` and always hash alike. That is what lets a
/// recipe written `1/3 oz` and one written `2/6 oz` be recognised as the same
/// drink.
final class Rational implements Comparable<Rational> {
  /// Creates `numerator / denominator`, reduced.
  ///
  /// Throws [ArgumentError] when [denominator] is zero. A zero denominator is
  /// not a value this type can represent, so it is refused at the door rather
  /// than carried around as a special case every caller has to remember.
  factory Rational(BigInt numerator, BigInt denominator) {
    if (denominator == BigInt.zero) {
      throw ArgumentError.value(
        denominator,
        'denominator',
        'a rational cannot have a zero denominator',
      );
    }

    // Normalise the sign into the numerator, so that canonical form is unique.
    var n = numerator;
    var d = denominator;
    if (d.isNegative) {
      n = -n;
      d = -d;
    }

    final divisor = n.gcd(d);
    if (divisor > BigInt.one) {
      n = n ~/ divisor;
      d = d ~/ divisor;
    }

    return Rational._(n, d);
  }

  const Rational._(this.numerator, this.denominator);

  /// The whole number [value].
  factory Rational.fromInt(int value) =>
      Rational._(BigInt.from(value), BigInt.one);

  /// The exact fraction [numerator] / [denominator], given as plain integers.
  factory Rational.of(int numerator, int denominator) =>
      Rational(BigInt.from(numerator), BigInt.from(denominator));

  /// Reads a decimal written as text, exactly.
  ///
  /// `0.75` becomes three quarters, not the nearest double to it. Which matters:
  /// the whole point of this type is that a recipe scaled a dozen times does not
  /// drift, and taking the value through `double.parse` on the way in would put
  /// the drift back at the front door.
  ///
  /// Accepts an integer, or a decimal point with digits on either side. A comma
  /// is accepted as a decimal separator too -- the sources are American but a
  /// person typing in a recipe should not have to know that.
  ///
  /// Throws [FormatException] rather than returning null: a number that cannot
  /// be read is a bug worth seeing, and a caller with a fallback would use it.
  factory Rational.parse(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      throw FormatException('not a number: "$text"');
    }
    final normalised = trimmed.replaceAll(',', '.');
    final dot = normalised.indexOf('.');

    if (dot < 0) {
      final whole = BigInt.tryParse(normalised);
      if (whole == null) throw FormatException('not a number: "$text"');
      return Rational(whole, BigInt.one);
    }

    final wholePart = normalised.substring(0, dot);
    final fractionPart = normalised.substring(dot + 1);
    if (!RegExp(r'^\d*$').hasMatch(wholePart) ||
        !RegExp(r'^\d+$').hasMatch(fractionPart) ||
        normalised.indexOf('.', dot + 1) >= 0) {
      throw FormatException('not a number: "$text"');
    }

    final digits = '${wholePart.isEmpty ? '0' : wholePart}$fractionPart';
    final numerator = BigInt.tryParse(digits);
    if (numerator == null) throw FormatException('not a number: "$text"');

    return Rational(numerator, BigInt.from(10).pow(fractionPart.length));
  }

  /// This as the whole number [value].
  static Rational fromBigInt(BigInt value) => Rational(value, BigInt.one);

  static final Rational zero = Rational.fromInt(0);
  static final Rational one = Rational.fromInt(1);

  /// The numerator. Carries the sign.
  final BigInt numerator;

  /// The denominator. Always greater than zero.
  final BigInt denominator;

  bool get isZero => numerator == BigInt.zero;
  bool get isNegative => numerator.isNegative;
  bool get isInteger => denominator == BigInt.one;

  Rational operator +(Rational other) => Rational(
    numerator * other.denominator + other.numerator * denominator,
    denominator * other.denominator,
  );

  Rational operator -(Rational other) => Rational(
    numerator * other.denominator - other.numerator * denominator,
    denominator * other.denominator,
  );

  Rational operator *(Rational other) =>
      Rational(numerator * other.numerator, denominator * other.denominator);

  Rational operator /(Rational other) {
    if (other.isZero) {
      throw ArgumentError.value(other, 'other', 'division by zero');
    }
    return Rational(numerator * other.denominator, denominator * other.numerator);
  }

  Rational operator -() => Rational._(-numerator, denominator);

  /// This fraction multiplied by the whole number [factor].
  Rational scaleBy(int factor) => Rational(numerator * BigInt.from(factor), denominator);

  /// The largest integer not greater than this fraction.
  ///
  /// Not `numerator ~/ denominator`: that truncates toward zero, so it gives
  /// the floor only for non-negative values and lands a whole unit too high
  /// below zero. The remainder is subtracted first, which makes the division
  /// exact and the result a true floor in both directions.
  BigInt floorToBigInt() {
    final remainder = numerator % denominator;
    return (numerator - remainder) ~/ denominator;
  }

  /// The smallest integer not less than this fraction.
  ///
  /// The ceiling is the negation of the floor of the negation, which keeps one
  /// definition of rounding in this class instead of two that can disagree.
  BigInt ceilToBigInt() {
    final negated = -numerator;
    final remainder = negated % denominator;
    return -((negated - remainder) ~/ denominator);
  }

  /// The nearest integer, halves going away from zero.
  ///
  /// This is the rounding used to reach the integer base, and it is named
  /// rather than left to a default because the choice is visible: rounding a
  /// half microlitre down every time biases a long recipe in one direction.
  BigInt roundHalfUpToBigInt() {
    // floor((2|n| + d) / 2d), with the sign reapplied. Written as a single
    // expression rather than by inspecting a remainder, because the first
    // version of this did the latter and doubled the numerator twice -- it
    // agreed with itself at exactly one half and was wrong either side of it.
    final magnitude = numerator.abs();
    final rounded =
        (magnitude * BigInt.two + denominator) ~/ (denominator * BigInt.two);
    return numerator.isNegative ? -rounded : rounded;
  }

  /// The value as a `double`, for display.
  ///
  /// Deliberately the only way out of exact arithmetic, so that a caller who
  /// reaches for it is making a visible choice rather than a quiet one. Do not
  /// feed the result back into a quantity.
  double toDouble() => numerator.toDouble() / denominator.toDouble();

  /// A short exact form: `3`, or `1/3`.
  @override
  String toString() =>
      isInteger ? '$numerator' : '$numerator/$denominator';

  @override
  bool operator ==(Object other) =>
      other is Rational &&
      numerator == other.numerator &&
      denominator == other.denominator;

  @override
  int get hashCode => Object.hash(numerator, denominator);

  @override
  int compareTo(Rational other) =>
      (numerator * other.denominator).compareTo(other.numerator * denominator);

  // Comparable gives compareTo and nothing else, so the operators are spelled
  // out. Every comparison is exact: comparing 1/3 against 1/2 cross-multiplies
  // rather than converting either side to a double, which is the same reason
  // the arithmetic does not.
  bool operator <(Rational other) => compareTo(other) < 0;
  bool operator <=(Rational other) => compareTo(other) <= 0;
  bool operator >(Rational other) => compareTo(other) > 0;
  bool operator >=(Rational other) => compareTo(other) >= 0;
}
