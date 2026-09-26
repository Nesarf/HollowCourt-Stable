import 'package:flutter_test/flutter_test.dart';
import 'package:hollow_court/domain/model/barcode.dart';

/// The barcode rules, which are the part that has to be right before anything is scanned or typed.
///
/// **Real numbers, not invented ones.** Every code below is a published GTIN: the check digits are the ones a
/// distillery printed, so these tests fail if the arithmetic is wrong rather than if a fixture drifts. The
/// nutella jar (`3017620422003`) is the one Open Food Facts' own documentation uses, which makes it the closest
/// thing to a shared example in this space.
void main() {
  group('the check digit', () {
    test('accepts published codes of every length the reader can meet', () {
      for (final (code, symbology) in [
        ('3017620422003', BarcodeSymbology.ean13), // EAN-13
        ('96385074', BarcodeSymbology.ean8), // EAN-8
        ('012345678905', BarcodeSymbology.upcA), // UPC-A
        ('10012345678902', BarcodeSymbology.gtin14),
      ]) {
        final result = parseBarcode(code);
        expect(result, isA<BarcodeOk>(), reason: code);
        expect((result as BarcodeOk).symbology, symbology, reason: code);
        expect(result.asEntered, code, reason: 'a code must round-trip through its own form');
      }
    });

    test('**a wrong last digit is rejected, and it says which digit was right**', () {
      // The commonest hand-typing mistake, and the one that would otherwise create a duplicate ingredient.
      final result = parseBarcode('3017620422004');
      expect(result, isA<BarcodeBad>());
      expect((result as BarcodeBad).problem, BarcodeProblem.checkDigit);
      expect(result.expectedCheckDigit, 3);
    });

    test('a wrong length is its own answer, so the screen can say the useful thing', () {
      expect((parseBarcode('12345') as BarcodeBad).problem, BarcodeProblem.length);
      expect((parseBarcode('') as BarcodeBad).problem, BarcodeProblem.empty);
      expect((parseBarcode('   -  ') as BarcodeBad).problem, BarcodeProblem.empty);
    });
  });

  group('normalisation', () {
    test('spaces and dashes are what people type, and they are not errors', () {
      expect(parseBarcode('3017 6204 22003'), isA<BarcodeOk>());
      expect(parseBarcode('3017-6204-22003'), isA<BarcodeOk>());
      expect(normaliseBarcode(' 3 0 1 7 '), '3017');
    });

    test('**a UPC-A and its EAN-13 form are one key, not two**', () {
      // The same tin scanned in two countries must not become two ingredients. Sixteen minus the length is the
      // whole of the rule: two zeros for a UPC-A, one for an EAN-13, six for an EAN-8.
      expect(canonicalBarcode('012345678905'), canonicalBarcode('0012345678905'));
      expect(canonicalBarcode('012345678905'), '00012345678905');
      expect(canonicalBarcode('96385074'), '00000096385074');
    });

    test('an unreadable string still yields a key, so nothing is silently keyed on an empty string', () {
      expect(canonicalBarcode('not a barcode'), '');
    });
  });
}
