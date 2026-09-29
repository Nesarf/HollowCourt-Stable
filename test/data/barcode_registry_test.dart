import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hollow_court/data/barcode_registry.dart';

/// The registry is where the feature becomes useful offline, and where a reader's own naming of their bottles
/// lives -- so the two ways it can go wrong both matter: a file that cannot be read must not take the library with
/// it, and the keys must be canonical, or the same tin bought in two countries becomes two ingredients.
void main() {
  late Directory temp;
  late File file;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('barcode-registry-test');
    file = File('${temp.path}${Platform.pathSeparator}barcodes.json');
  });

  tearDown(() => temp.deleteSync(recursive: true));

  test('a code remembered is a code found, and what the reader called it survives', () async {
    final registry = BarcodeRegistry(file);
    await registry.remember('3017620422003', 'gin', name: 'Bombay Sapphire', at: DateTime.utc(2026, 9, 25));

    final found = await registry.lookup('3017620422003');
    expect(found, isNotNull);
    expect(found!.ingredientId, 'gin');
    expect(found.name, 'Bombay Sapphire');
    expect(found.addedAt, DateTime.utc(2026, 9, 25));
  });

  test('**the same tin in two countries is one entry**', () async {
    final registry = BarcodeRegistry(file);
    // Typed as a UPC-A in one place, scanned as an EAN-13 in another: one product, one ingredient.
    await registry.remember('012345678905', 'whiskey');
    expect((await registry.lookup('0012345678905'))!.ingredientId, 'whiskey');
    expect((await registry.read()).length, 1, reason: 'canonical keys mean one entry, not two');
  });

  test('changing your mind replaces the entry rather than being refused', () async {
    final registry = BarcodeRegistry(file);
    await registry.remember('3017620422003', 'gin');
    await registry.remember('3017620422003', 'vodka');
    expect((await registry.lookup('3017620422003'))!.ingredientId, 'vodka');
    // And the first sighting is not forgotten: addedAt belongs to the code, not to the correction.
    expect((await registry.lookup('3017620422003'))!.addedAt, isNotNull);
  });

  test('forgetting removes it, and forgetting twice is silent', () async {
    final registry = BarcodeRegistry(file);
    await registry.remember('3017620422003', 'gin');
    await registry.forget('3017620422003');
    expect(await registry.lookup('3017620422003'), isNull);
    await registry.forget('3017620422003'); // no error
  });

  test('an unreadable code is never stored under an empty key', () async {
    final registry = BarcodeRegistry(file);
    await registry.remember('not a barcode', 'gin');
    expect(await registry.read(), isEmpty);
  });

  test('**a damaged file is empty rather than fatal**', () async {
    file.writeAsStringSync('{ "3017620422003": ');
    expect(await BarcodeRegistry(file).read(), isEmpty);
    file.writeAsStringSync('42');
    expect(await BarcodeRegistry(file).read(), isEmpty);
  });
}
