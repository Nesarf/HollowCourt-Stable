import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hollow_court/data/recipe_prices.dart';
import 'package:hollow_court/domain/pricing/price.dart';

/// The reader's menu prices: the only place a price for a recipe exists.
void main() {
  late Directory temp;
  late File file;
  const cny = Currency('CNY', 2);
  const usd = Currency('USD', 2);

  setUp(() {
    temp = Directory.systemTemp.createTempSync('recipe-prices-test');
    file = File('${temp.path}${Platform.pathSeparator}recipe_prices.json');
  });

  tearDown(() => temp.deleteSync(recursive: true));

  test('a price set is a price read, and a menu starts empty rather than wrong', () async {
    final store = RecipePriceStore(file);
    expect(await store.read(), isEmpty, reason: 'a reader who has priced nothing has no prices');

    await store.set('ibaAlexander', Money.fromMinorUnits(4800, cny), at: DateTime.utc(2026, 9, 25));
    final price = (await store.read())['ibaAlexander']!;
    expect(price.price.minorUnits, 4800);
    expect(price.setAt, DateTime.utc(2026, 9, 25));
  });

  test('**the currency travels with the number**', () async {
    // Changing the display currency does not re-price the menu: ¥48 is not $48, and a store that dropped the
    // currency would turn one into the other the next time it was read.
    final store = RecipePriceStore(file);
    await store.set('a', Money.fromMinorUnits(4800, cny));
    await store.set('b', Money.fromMinorUnits(900, usd));

    final prices = await store.read();
    expect(prices['a']!.price.currency.code, 'CNY');
    expect(prices['b']!.price.currency.code, 'USD');
  });

  test('setting again replaces, and clearing is silent the second time', () async {
    final store = RecipePriceStore(file);
    await store.set('a', Money.fromMinorUnits(4800, cny));
    await store.set('a', Money.fromMinorUnits(5200, cny));
    expect((await store.read())['a']!.price.minorUnits, 5200);

    await store.clear('a');
    expect(await store.read(), isEmpty);
    await store.clear('a'); // no error
  });

  test('an entry that cannot be parsed is dropped, not guessed at', () async {
    file.writeAsStringSync('{"a": {"minorUnits": 4800}, "b": "not an object"}');
    expect(await RecipePriceStore(file).read(), isEmpty, reason: 'no currency means no price');
  });

  test('**a damaged file is empty rather than fatal**', () async {
    file.writeAsStringSync('{ "a": ');
    expect(await RecipePriceStore(file).read(), isEmpty);
    file.writeAsStringSync('[]');
    expect(await RecipePriceStore(file).read(), isEmpty);
  });
}
