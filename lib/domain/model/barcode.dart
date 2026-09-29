/// A barcode number, and what is actually true about one.
///
/// **Why this is a type rather than a `String`.** A barcode is not free text: it has a length that depends on its
/// symbology, and eleven of its digits determine the twelfth. A reader typing twelve digits by hand gets the last
/// one wrong often enough that a bare string field would silently create a second "ingredient" for a bottle they
/// already own -- and the whole point of scanning is to stop making duplicates.
///
/// **And the equivalence is real.** A UPC-A is an EAN-13 with a leading zero, which is why they scan the same at a
/// till. The canonical form here is **GTIN-14** (fourteen digits, zero-padded), so `012345678905` and
/// `0012345678905` are one key rather than two -- which matters because a European bottle and an American one of
/// the same product must not become two ingredients.
library;

/// What kind of number this is, as far as its length can say.
enum BarcodeSymbology {
  ean8(8, 'EAN-8'),
  upcA(12, 'UPC-A'),
  ean13(13, 'EAN-13'),
  gtin14(14, 'GTIN-14');

  const BarcodeSymbology(this.digits, this.label);

  final int digits;
  final String label;

  static BarcodeSymbology? forLength(int length) {
    for (final value in values) {
      if (value.digits == length) return value;
    }
    return null;
  }
}

/// Why a typed number was not accepted, in the words a screen can use.
enum BarcodeProblem {
  /// Nothing but digits survives normalisation.
  empty,

  /// Not eight, twelve, thirteen or fourteen digits.
  length,

  /// The last digit is not the one the others determine.
  checkDigit,
}

/// A barcode that has been accepted, or the reason it was not.
///
/// **[decision] The module computes the check digit rather than trusting it.** GTIN's rule is mod-10 with weights
/// 3 and 1 alternating from the right; a wrong last digit is the single most common hand-typing mistake, and
/// catching it here means a typo cannot become an ingredient nobody can ever match.
sealed class BarcodeResult {
  const BarcodeResult();
}

/// The number, normalised and validated.
final class BarcodeOk extends BarcodeResult {
  const BarcodeOk._(this.canonical, this.symbology);

  /// Fourteen digits: the canonical key, whatever was typed or scanned.
  final String canonical;

  /// What the *input* was, kept so the interface can say "EAN-13" rather than "GTIN-14" about a bottle that
  /// carries an EAN-13.
  final BarcodeSymbology symbology;

  /// The digits as the reader typed them, which for a twelve-digit UPC is not the canonical form.
  String get asEntered => switch (symbology) {
    BarcodeSymbology.ean8 => canonical.substring(6),
    BarcodeSymbology.upcA => canonical.substring(2),
    BarcodeSymbology.ean13 => canonical.substring(1),
    BarcodeSymbology.gtin14 => canonical,
  };
}

/// The number was not accepted, with the reason and, when there is one, the digit that would have been right.
final class BarcodeBad extends BarcodeResult {
  const BarcodeBad(this.problem, {this.expectedCheckDigit});

  final BarcodeProblem problem;

  /// Set when the length is right and only the check digit is wrong: what the digit should have been.
  final int? expectedCheckDigit;
}

/// Strips the separators people type and keeps the digits.
///
/// A barcode printed under a label or read off a receipt arrives with spaces, and some people write them in
/// groups, so normalising first and complaining about length second is the order that produces the useful error.
String normaliseBarcode(String input) =>
    input.replaceAll(RegExp(r'[^0-9]'), '');

/// The GTIN check digit for [digits], which must be the payload *without* its check digit.
int gtinCheckDigit(String digits) {
  var sum = 0;
  // Weights alternate 3 and 1, counted from the right of the payload.
  for (var i = 0; i < digits.length; i++) {
    final digit = digits.codeUnitAt(digits.length - 1 - i) - 0x30;
    sum += digit * (i.isEven ? 3 : 1);
  }
  return (10 - (sum % 10)) % 10;
}

/// Reads [input] as a barcode.
BarcodeResult parseBarcode(String input) {
  final digits = normaliseBarcode(input);
  if (digits.isEmpty) return const BarcodeBad(BarcodeProblem.empty);

  final symbology = BarcodeSymbology.forLength(digits.length);
  if (symbology == null) return const BarcodeBad(BarcodeProblem.length);

  final expected = gtinCheckDigit(digits.substring(0, digits.length - 1));
  final actual = digits.codeUnitAt(digits.length - 1) - 0x30;
  if (expected != actual) {
    return BarcodeBad(BarcodeProblem.checkDigit, expectedCheckDigit: expected);
  }

  // Sixteen minus the length: 6 for EAN-8, 2 for UPC-A, 1 for EAN-13, none for GTIN-14.
  return BarcodeOk._(digits.padLeft(14, '0'), symbology);
}

/// The canonical key for a code already known to be valid, for use as a map key.
String canonicalBarcode(String input) {
  final result = parseBarcode(input);
  return result is BarcodeOk ? result.canonical : normaliseBarcode(input);
}
