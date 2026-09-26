import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../data/barcode_registry.dart';
import '../domain/model/barcode.dart';
import '../domain/model/ingredient.dart';

/// Where the reader's barcode registry lives: beside the cellar, never inside the build.
final barcodeRegistryFileProvider = FutureProvider<File>((Ref ref) async {
  final directory = await getApplicationSupportDirectory();
  return File('${directory.path}${Platform.pathSeparator}barcodes.json');
});

/// The reader's registry, and the one place a code is resolved to an ingredient.
final barcodeRegistryProvider = FutureProvider<BarcodeRegistry>((Ref ref) async {
  return BarcodeRegistry(await ref.watch(barcodeRegistryFileProvider.future));
});

/// What a typed or scanned code turned out to be.
///
/// **The verdict is a value rather than a `bool plus a message`**, because the three answers are genuinely
/// different and the screen says something different for each: the digits are not a barcode; the check digit is
/// wrong (and which digit was meant); or the code is fine and the reader has -- or has not -- said what it is.
sealed class BarcodeResolution {
  const BarcodeResolution();
}

/// The digits are not a barcode, and why.
final class BarcodeUnusable extends BarcodeResolution {
  const BarcodeUnusable(this.problem, {this.expectedCheckDigit});
  final BarcodeProblem problem;
  final int? expectedCheckDigit;
}

/// A valid code the reader has not described yet.
final class BarcodeUnknown extends BarcodeResolution {
  const BarcodeUnknown(this.canonical, this.symbology);
  final String canonical;
  final BarcodeSymbology symbology;
}

/// A valid code the reader has already described, resolved to an ingredient when that ingredient is in the
/// library the form was handed.
final class BarcodeResolved extends BarcodeResolution {
  const BarcodeResolved(this.canonical, this.entry, this.ingredient);
  final String canonical;
  final BarcodeEntry entry;

  /// Null when the remembered ingredient is not in the library this build carries -- an ingredient from a seed
  /// the reader has since replaced, which is a case to show rather than to crash on.
  final Ingredient? ingredient;
}

/// Resolves [typed] against the reader's registry.
///
/// Kept out of the widget so it can be tested without a screen: the arithmetic and the lookup are the two places
/// this feature can be wrong, and neither needs a camera, a permission or a pump to check.
BarcodeResolution resolveBarcode(String typed, Map<String, BarcodeEntry> registry,
    Iterable<Ingredient> ingredients) {
  final parsed = parseBarcode(typed);
  if (parsed is BarcodeBad) {
    return BarcodeUnusable(parsed.problem, expectedCheckDigit: parsed.expectedCheckDigit);
  }
  final ok = parsed as BarcodeOk;
  final entry = registry[ok.canonical];
  if (entry == null) return BarcodeUnknown(ok.canonical, ok.symbology);
  Ingredient? match;
  for (final ingredient in ingredients) {
    if (ingredient.id == entry.ingredientId) match = ingredient;
  }
  return BarcodeResolved(ok.canonical, entry, match);
}
