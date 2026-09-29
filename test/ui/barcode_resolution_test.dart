import 'package:flutter_test/flutter_test.dart';
import 'package:hollow_court/data/barcode_registry.dart';
import 'package:hollow_court/domain/model/barcode.dart';
import 'package:hollow_court/domain/model/ingredient.dart';
import 'package:hollow_court/ui/barcode_providers.dart';

/// The resolver: the one place a typed number becomes an ingredient.
///
/// Deliberately testable with no screen, no camera and no permission -- which is the whole argument for doing the
/// manual entry before the scanner. Every case below is one the form has to say something different about.
void main() {
  const gin = Ingredient(id: 'gin', name: 'Gin');
  const vodka = Ingredient(id: 'vodka', name: 'Vodka');
  const library = [gin, vodka];

  test('a number that is not a barcode says so, and says which kind of wrong', () {
    final short = resolveBarcode('12345', const {}, library) as BarcodeUnusable;
    expect(short.problem, BarcodeProblem.length);

    final typo = resolveBarcode('3017620422004', const {}, library) as BarcodeUnusable;
    expect(typo.problem, BarcodeProblem.checkDigit);
    expect(typo.expectedCheckDigit, 3, reason: 'the form tells the reader the digit they meant');
  });

  test('a valid code nobody has described is unknown, not an error', () {
    final result = resolveBarcode('3017620422003', const {}, library) as BarcodeUnknown;
    expect(result.canonical, '03017620422003');
    expect(result.symbology, BarcodeSymbology.ean13);
  });

  test('**a remembered code resolves to its ingredient, which is what makes the field useful**', () {
    const registry = {'03017620422003': BarcodeEntry(ingredientId: 'gin', name: 'Bombay Sapphire')};
    final result = resolveBarcode('3017 6204 22003', registry, library) as BarcodeResolved;
    expect(result.ingredient?.id, 'gin', reason: 'typing it with spaces is not a different code');
    expect(result.entry.name, 'Bombay Sapphire');
  });

  test('a remembered ingredient this build does not carry resolves with nothing, rather than throwing', () {
    // A seed the reader has since replaced. The screen shows the code and the name; nothing crashes.
    const registry = {'03017620422003': BarcodeEntry(ingredientId: 'absinthe')};
    final result = resolveBarcode('3017620422003', registry, library) as BarcodeResolved;
    expect(result.ingredient, isNull);
    expect(result.entry.ingredientId, 'absinthe');
  });

  test('a UPC-A typed in one country and its EAN-13 scanned in another are one entry', () {
    const registry = {'00012345678905': BarcodeEntry(ingredientId: 'whiskey')};
    final typed = resolveBarcode('012345678905', registry, const [Ingredient(id: 'whiskey', name: 'Whiskey')]);
    final scanned = resolveBarcode('0012345678905', registry, const [Ingredient(id: 'whiskey', name: 'Whiskey')]);
    expect(typed, isA<BarcodeResolved>());
    expect(scanned, isA<BarcodeResolved>());
  });
}
