import 'package:test/test.dart';

import 'package:hollow_court/domain/events/event.dart';
import 'package:hollow_court/domain/events/hlc.dart';
import 'package:hollow_court/domain/pricing/cellar_value.dart';
import 'package:hollow_court/domain/pricing/price.dart';
import 'package:hollow_court/domain/units/quantity.dart';

/// Section 7's total cellar value, and the half of the answer that is not the figure.
Hlc at(int millis) => Hlc(physicalMillis: millis, counter: 0, nodeId: 'laptop');

Event bought(String sku, {required int minorUnits, required int microlitres, int millis = 0}) =>
    Event(
      hlc: at(millis),
      type: 'stock.bottle.added',
      data: <String, Object?>{
        'bottleId': 'bottle-$sku-$millis',
        'sku': sku,
        'volumeMicrolitres': microlitres,
        'priceMinor': minorUnits,
      },
    );

({String sku, Volume onHand}) holding(String sku, int millilitres) =>
    (sku: sku, onHand: Volume.fromMillilitres(millilitres));

void main() {
  test('sums volume on hand against the current price', () {
    // 12000 minor units for 700 ml, half of it left: 6000 of the 700 ml still there.
    final value = cellarValueOf(
      <({String sku, Volume onHand})>[holding('gin', 350)],
      <Event>[bought('gin', minorUnits: 12000, microlitres: 700000)],
    );

    expect(value.total, Money.fromMinorUnits(6000, Currency.cny));
    expect(value.priced, 1);
    expect(value.unpriced, 0);
    expect(value.isComplete, isTrue);
  });

  test('a shelf nobody has priced is unknown rather than worthless', () {
    final value = cellarValueOf(
      <({String sku, Volume onHand})>[holding('gin', 350)],
      <Event>[
        // A bottle with no price recorded: a fact, and not a price of zero.
        Event(
          hlc: at(0),
          type: 'stock.bottle.added',
          data: const <String, Object?>{
            'bottleId': 'bottle-gin-0',
            'sku': 'gin',
            'volumeMicrolitres': 700000,
          },
        ),
      ],
    );

    expect(value.total, isNull);
    expect(value.isKnown, isFalse);
    expect(value.unpriced, 1);
  });

  test('one unpriced bottle does not hide inside a total', () {
    // The failure this type exists to prevent: a figure built from the priced bottles
    // looks complete, and it goes up when somebody enters a price -- which reads as the
    // cellar becoming more valuable rather than as the estimate becoming less wrong.
    final value = cellarValueOf(
      <({String sku, Volume onHand})>[holding('gin', 350), holding('vermouth', 350)],
      <Event>[bought('gin', minorUnits: 12000, microlitres: 700000)],
    );

    expect(value.total, Money.fromMinorUnits(6000, Currency.cny));
    expect(value.priced, 1);
    expect(value.unpriced, 1);
    expect(value.isComplete, isFalse);
  });

  test('an empty bottle is worth nothing, which is not the same as unpriced', () {
    final value = cellarValueOf(
      <({String sku, Volume onHand})>[holding('gin', 0), holding('vermouth', 350)],
      <Event>[
        bought('gin', minorUnits: 12000, microlitres: 700000),
        bought('vermouth', minorUnits: 8000, microlitres: 700000, millis: 1),
      ],
    );

    expect(value.total, Money.fromMinorUnits(4000, Currency.cny));
    expect(value.priced, 1, reason: 'the empty bottle contributes nothing and is not missing');
    expect(value.unpriced, 0);
    expect(value.isComplete, isTrue);
  });

  test('two currencies are refused rather than silently added', () {
    expect(
      () => cellarValueOf(
        <({String sku, Volume onHand})>[holding('gin', 350), holding('bourbon', 350)],
        <Event>[
          bought('gin', minorUnits: 12000, microlitres: 700000),
          Event(
            hlc: at(1),
            type: 'price.paid',
            data: const <String, Object?>{
              'sku': 'bourbon',
              'minorUnits': 4000,
              'currency': 'USD',
              'microlitres': 700000,
              'source': 'manual',
            },
          ),
        ],
      ),
      throwsArgumentError,
    );
  });

  test('an empty shelf is unknown and complete at the same time', () {
    final value = cellarValueOf(
      const <({String sku, Volume onHand})>[],
      const <Event>[],
    );
    expect(value.total, isNull);
    expect(value.priced, 0);
    expect(value.unpriced, 0);
    expect(value.isComplete, isTrue,
        reason: 'there is nothing left to price, so nothing is missing');
  });
}
