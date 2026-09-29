import 'dart:convert';
import 'dart:io';

import '../domain/pricing/price.dart';

/// What the reader charges for one of a recipe.
///
/// **A price is the reader's, not the recipe's.** The 103 shipped recipes carry no price and never will: a
/// suggested price would be wrong in every market the application ships to, and wrong again next year. What a
/// drink sells for is a fact about a particular bar, so it is stored beside the cellar with everything else the
/// reader owns rather than inside the library where an update could overwrite it.
final class RecipePrice {
  const RecipePrice({required this.price, this.setAt});

  /// The amount, **with its currency**. The currency travels with the number because a reader who changes their
  /// currency has not thereby re-priced every drink on the menu -- a ¥48 cocktail is not a $48 one, and the
  /// store's job is to keep that distinction rather than to erase it.
  final Money price;

  /// When it was set, so a reader can see which prices are from the old menu.
  final DateTime? setAt;

  Map<String, Object?> toJson() => {
    'minorUnits': price.minorUnits,
    'currency': price.currency.code,
    'minorUnitDigits': price.currency.minorUnitDigits,
    if (setAt != null) 'setAt': setAt!.toIso8601String(),
  };

  /// Null when the entry cannot be read, which the caller treats as "no price" rather than as an error.
  static RecipePrice? fromJson(Object? json) {
    if (json is! Map) return null;
    final minorUnits = (json['minorUnits'] as num?)?.toInt();
    final code = json['currency'] as String?;
    final digits = (json['minorUnitDigits'] as num?)?.toInt() ?? 2;
    if (minorUnits == null || code == null || code.isEmpty) return null;
    return RecipePrice(
      price: Money.fromMinorUnits(minorUnits, Currency(code, digits)),
      setAt: DateTime.tryParse((json['setAt'] as String?) ?? ''),
    );
  }
}

/// The reader's prices, keyed by recipe id.
///
/// The same store discipline as the folder styles and the barcode registry, for the same reasons: a file beside
/// `cellar.ndjson`, never touched by an update; a damaged file reads as empty rather than locking a reader out of
/// their own menu; and a value that cannot be parsed is dropped rather than guessed at.
final class RecipePriceStore {
  const RecipePriceStore(this.file);

  final File? file;

  Future<Map<String, RecipePrice>> read() async {
    final target = file;
    if (target == null || !target.existsSync()) return {};
    try {
      final decoded = jsonDecode(await target.readAsString());
      if (decoded is! Map) return {};
      return {
        // **`?value` rather than a nested `if case`**: an entry whose price cannot be read is simply not an
        // entry, which is the whole rule this store follows.
        for (final entry in decoded.entries)
          if (entry.key is String) entry.key as String: ?RecipePrice.fromJson(entry.value),
      };
    } on FormatException {
      return {};
    } on FileSystemException {
      return {};
    }
  }

  /// Sets the price of [recipeId], replacing what was there.
  Future<void> set(String recipeId, Money price, {DateTime? at}) async {
    if (recipeId.isEmpty) return;
    final prices = await read();
    prices[recipeId] = RecipePrice(price: price, setAt: at ?? DateTime.now());
    await _write(prices);
  }

  /// Takes a price off the menu. Silent when there was none, because a reader removing a price they had already
  /// removed has not made a mistake.
  Future<void> clear(String recipeId) async {
    final prices = await read();
    if (prices.remove(recipeId) == null) return;
    await _write(prices);
  }

  Future<void> _write(Map<String, RecipePrice> prices) async {
    final target = file;
    if (target == null) return;
    await target.parent.create(recursive: true);
    await target.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        for (final entry in prices.entries) entry.key: entry.value.toJson(),
      }),
    );
  }
}
