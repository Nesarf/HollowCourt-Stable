import 'package:hollow_court/domain/units/rational.dart';
import 'package:test/test.dart';

void main() {
  group('exactness', () {
    // The reason this type exists, in one test. Section 5.1 of the design
    // document says a recipe is a ratio and must never be accumulated in
    // floating point, because after a dozen scalings the error is visible in
    // the glass. These are the two smallest cases of that.
    test('three thirds are exactly one', () {
      final third = Rational.of(1, 3);
      final total = third + third + third;

      expect(total, Rational.one);
      expect(total.isInteger, isTrue);
      expect(total.toString(), '1');
    });

    test('a tenth plus two tenths is exactly three tenths', () {
      final sum = Rational.of(1, 10) + Rational.of(2, 10);

      expect(sum, Rational.of(3, 10));

      // What the same arithmetic does in binary floating point, recorded here
      // so the contrast lives with the test rather than only in a comment.
      expect(0.1 + 0.2 == 0.3, isFalse);
    });

    test('scaling a third a dozen times does not drift', () {
      // One and one third ounces, built the way a scaled recipe builds it:
      // by multiplying a ratio, never by adding a rounded volume.
      final third = Rational.of(1, 3);
      var total = Rational.zero;

      for (var i = 0; i < 12; i++) {
        total = total + third;
      }

      expect(total, Rational.fromInt(4));
      expect(total.toDouble(), 4.0);
    });

    test('halves and quarters stay exact through repeated halving', () {
      var half = Rational.one;
      for (var i = 0; i < 20; i++) {
        half = half / Rational.fromInt(2);
      }

      // After twenty halvings a double would still be fine and a float would
      // not be, but the point is that this is exact rather than nearly exact.
      expect(half, Rational.of(1, 1048576));
      expect(half * Rational.of(1048576, 1), Rational.one);
    });
  });

  group('normalisation', () {
    test('equal fractions are equal whatever they were written as', () {
      final a = Rational.of(1, 2);
      final b = Rational.of(2, 4);
      final c = Rational.of(-3, -6);

      expect(a, b);
      expect(b, c);
      expect(a.hashCode, b.hashCode);
      expect(a.hashCode, c.hashCode);
    });

    test('the sign lives in the numerator', () {
      expect(Rational.of(1, -2), Rational.of(-1, 2));
      expect(Rational.of(-1, -2), Rational.of(1, 2));
      expect(Rational.of(1, -2).numerator, BigInt.from(-1));
      expect(Rational.of(1, -2).denominator, BigInt.two);
    });

    test('zero is one value however it is reached', () {
      expect(Rational.of(0, 5), Rational.zero);
      expect(Rational.of(3, 7) - Rational.of(3, 7), Rational.zero);
      expect(Rational.zero.isZero, isTrue);
      expect(Rational.zero.isNegative, isFalse);
    });
  });

  group('arithmetic', () {
    test('addition, subtraction, multiplication and division', () {
      expect(Rational.of(1, 3) + Rational.of(1, 6), Rational.of(1, 2));
      expect(Rational.of(3, 4) - Rational.of(1, 4), Rational.of(1, 2));
      expect(Rational.of(2, 3) * Rational.of(3, 4), Rational.of(1, 2));
      expect(Rational.of(1, 2) / Rational.of(1, 4), Rational.fromInt(2));
    });

    test('negation', () {
      expect(-Rational.of(1, 3), Rational.of(-1, 3));
      expect(-Rational.zero, Rational.zero);
    });

    test('scaling by a whole number', () {
      expect(Rational.of(1, 3).scaleBy(3), Rational.one);
      expect(Rational.of(1, 3).scaleBy(0), Rational.zero);
      expect(Rational.of(1, 3).scaleBy(-3), Rational.fromInt(-1));
    });

    test('a zero denominator is refused rather than carried', () {
      expect(() => Rational.of(1, 0), throwsArgumentError);
      expect(() => Rational(BigInt.one, BigInt.zero), throwsArgumentError);
    });

    test('division by zero is refused', () {
      expect(() => Rational.one / Rational.zero, throwsArgumentError);
    });
  });

  group('reaching the integer base', () {
    test('floor and ceiling', () {
      expect(Rational.of(7, 2).floorToBigInt(), BigInt.from(3));
      expect(Rational.of(7, 2).ceilToBigInt(), BigInt.from(4));

      expect(Rational.of(-7, 2).floorToBigInt(), BigInt.from(-4));
      expect(Rational.of(-7, 2).ceilToBigInt(), BigInt.from(-3));

      expect(Rational.fromInt(5).floorToBigInt(), BigInt.from(5));
      expect(Rational.fromInt(5).ceilToBigInt(), BigInt.from(5));
    });

    test('rounding sends halves away from zero', () {
      expect(Rational.of(1, 2).roundHalfUpToBigInt(), BigInt.one);
      expect(Rational.of(-1, 2).roundHalfUpToBigInt(), BigInt.from(-1));

      expect(Rational.of(3, 2).roundHalfUpToBigInt(), BigInt.two);
      expect(Rational.of(-3, 2).roundHalfUpToBigInt(), BigInt.from(-2));

      // Just below and just above a half, so the boundary is pinned and not
      // merely approached.
      expect(Rational.of(4999, 10000).roundHalfUpToBigInt(), BigInt.zero);
      expect(Rational.of(5001, 10000).roundHalfUpToBigInt(), BigInt.one);
    });

    test('rounding a whole number changes nothing', () {
      for (var i = -5; i <= 5; i++) {
        expect(Rational.fromInt(i).roundHalfUpToBigInt(), BigInt.from(i));
      }
    });

    test('rounding does not accumulate a directional bias', () {
      // Ten values just under a half round to zero, ten just over round to
      // one. A rule that always truncated would land at 0; one that always
      // rounded up would land at 20. This one lands in between, which is the
      // property that keeps a long recipe from drifting.
      var below = BigInt.zero;
      var above = BigInt.zero;
      for (var i = 0; i < 10; i++) {
        below = below + Rational.of(4999, 10000).roundHalfUpToBigInt();
        above = above + Rational.of(5001, 10000).roundHalfUpToBigInt();
      }

      expect(below, BigInt.zero);
      expect(above, BigInt.from(10));
    });
  });

  group('comparison and display', () {
    test('ordering', () {
      expect(Rational.of(1, 3) < Rational.of(1, 2), isTrue);
      expect(Rational.of(-1, 3) > Rational.of(-1, 2), isTrue);
      expect(Rational.of(1, 2).compareTo(Rational.of(2, 4)), 0);
      expect(Rational.of(1, 3).compareTo(Rational.of(1, 2)), lessThan(0));
    });

    test('toDouble is exact enough to display and no more', () {
      expect(Rational.of(1, 3).toDouble(), closeTo(0.3333333333333333, 1e-15));
      expect(Rational.of(29573529, 1000).toDouble(), closeTo(29573.529, 1e-9));
    });

    test('toString shows a whole number plainly and a fraction exactly', () {
      expect(Rational.fromInt(3).toString(), '3');
      expect(Rational.fromInt(-3).toString(), '-3');
      expect(Rational.of(1, 3).toString(), '1/3');
      expect(Rational.of(-1, 3).toString(), '-1/3');
    });
  });
}
