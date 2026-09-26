import 'package:hollow_court/domain/pricing/price.dart';
import 'package:test/test.dart';

/// **The four regions this application is for have their currencies, and the picker offers them.**
///
/// The owner asked for this by name on 2026-09-22: *"货币栏记得加上英国/日本/香港/台湾这四个地区的基础
/// 货币"*. All four were already in the table -- this test is the "记得" part made durable, because a list
/// that happens to contain something today is a list that can lose it in an edit nobody looks at.
void main() {
  test('**the British, Japanese, Hong Kong and Taiwan currencies are all present**', () {
    expect(Currency.byCode('GBP'), isNotNull, reason: 'the United Kingdom');
    expect(Currency.byCode('JPY'), isNotNull, reason: 'Japan');
    expect(Currency.byCode('HKD'), isNotNull, reason: 'Hong Kong');
    expect(Currency.byCode('TWD'), isNotNull, reason: 'Taiwan');
  });

  test('and they are in the list the settings picker offers, not only in the table', () {
    // `Currency.all` is the one table `byCode` reads *and* the one the picker offers -- a second list is how
    // the two came to disagree once already (see the comment on `all`).
    for (final code in const ['GBP', 'JPY', 'HKD', 'TWD']) {
      expect(Currency.all.map((c) => c.code), contains(code));
    }
  });

  test('the minor units are right, which is the part that is easy to get wrong', () {
    // Yen and won have no minor unit in practice: 1250 JPY is 1250 yen, not 12.50. A two-digit table would
    // silently divide every Japanese price by a hundred.
    expect(Currency.byCode('JPY')!.minorUnitDigits, 0);
    expect(Currency.byCode('GBP')!.minorUnitDigits, 2);
    expect(Currency.byCode('HKD')!.minorUnitDigits, 2);
    expect(Currency.byCode('TWD')!.minorUnitDigits, 2);
  });
}
