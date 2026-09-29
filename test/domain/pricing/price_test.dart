import 'package:test/test.dart';

import 'package:hollow_court/domain/events/event.dart';
import 'package:hollow_court/domain/events/hlc.dart';
import 'package:hollow_court/domain/events/price.dart';
import 'package:hollow_court/domain/pricing/price.dart';
import 'package:hollow_court/domain/units/quantity.dart';
import 'package:hollow_court/domain/units/rational.dart';

/// Section 7's price time series.
///
/// **This file is written against `package:test` and not `flutter_test`, which is
/// itself one of the assertions.** Section 3 forbids the domain layer from importing
/// Flutter, and the way that rule is enforced is that these tests run on the plain Dart
/// VM: the moment `pricing/price.dart` reaches for `package:flutter`, the suite stops
/// running at all. So there is no test below asserting the domain is pure -- the fact
/// that any of them execute is the proof, and a comment could not do the job.
Hlc at(int millis, {int counter = 0, String node = 'laptop'}) =>
    Hlc(physicalMillis: millis, counter: counter, nodeId: node);

Money cny(int minorUnits) => Money.fromMinorUnits(minorUnits, Currency.cny);

PricePoint point(int millis, int minorUnits, int microlitres,
        {PriceSource source = PriceSource.manual}) =>
    PricePoint(
      hlc: at(millis),
      paid: cny(minorUnits),
      volume: Volume.fromMicrolitres(microlitres),
      source: source,
    );

void main() {
  group('Currency', () {
    test('knows that not every minor unit is a hundredth', () {
      expect(Currency.cny.minorUnitDigits, 2);
      expect(Currency.jpy.minorUnitDigits, 0,
          reason: 'one yen is one minor unit; a model assuming 2 would '
              'report a Japanese price a hundred times too high');
      expect(Currency.krw.minorUnitDigits, 0);
    });

    test('matches a code without regard to case, and invents nothing', () {
      expect(Currency.byCode('cny'), Currency.cny);
      expect(Currency.byCode('CNY'), Currency.cny);
      expect(Currency.byCode('XYZ'), isNull);
      expect(Currency.byCode(''), isNull);
      expect(Currency.byCode(null), isNull);
    });

    test('keeps the code ASCII, because it is a key and not display copy', () {
      final ascii = RegExp(r'^[A-Z]{3}$');
      for (final currency in Currency.all) {
        expect(ascii.hasMatch(currency.code), isTrue, reason: currency.code);
      }
    });
  });

  group('Money', () {
    test('adds and subtracts within one currency', () {
      expect((cny(1000) + cny(250)).minorUnits, 1250);
      expect((cny(1000) - cny(250)).minorUnits, 750);
      expect((-cny(250)).minorUnits, -250);
      expect(cny(0).isZero, isTrue);
    });

    test('refuses to add two currencies, the way a volume refuses a mass', () {
      expect(
        () => cny(1000) + Money.fromMinorUnits(1000, Currency.usd),
        throwsArgumentError,
      );
      expect(
        () => cny(1000).compareTo(Money.fromMinorUnits(1, Currency.eur)),
        throwsArgumentError,
      );
    });

    test('rounds half up, once, at the edge', () {
      // 3 x 1/2 = 1.5 -> 2. Half up, not banker's, and not truncated.
      expect(cny(3).times(Rational.of(1, 2)).minorUnits, 2);
      // 1 x 1/2 = 0.5 -> 1
      expect(cny(1).times(Rational.of(1, 2)).minorUnits, 1);
      // 1 x 1/3 = 0.33 -> 0
      expect(cny(1).times(Rational.of(1, 3)).minorUnits, 0);
      // 1 x 2/3 = 0.66 -> 1
      expect(cny(1).times(Rational.of(2, 3)).minorUnits, 1);
    });

    test('scales by a whole number without rounding at all', () {
      expect(cny(1250).scaleBy(4).minorUnits, 5000);
      expect(cny(1250) * 3, cny(3750));
    });

    test('compares and hashes by value', () {
      expect(cny(100), cny(100));
      expect(cny(100).hashCode, cny(100).hashCode);
      expect(cny(100) < cny(101), isTrue);
      expect(cny(100) >= cny(100), isTrue);
      expect(cny(100), isNot(Money.fromMinorUnits(100, Currency.usd)));
    });
  });

  group('PricePoint', () {
    test('keeps the price per microlitre exact rather than rounding it', () {
      // 1000 minor units for half a litre: 1000/500000 = 1/500 of a minor unit per ul.
      final p = point(100, 1000, 500000);
      expect(p.perMicrolitre, Rational.of(1, 500));
    });

    test('a purchase with no volume is kept but is not a rate', () {
      final p = point(100, 500, 0);
      expect(p.isUsable, isFalse,
          reason: 'dividing by it would be a division by zero');
      expect(p.paid, cny(500), reason: 'what was paid is still a fact');
    });

    test('carries the source, so a screen can say how the number is known', () {
      expect(point(100, 1, 1000).source, PriceSource.manual);
      expect(
        point(100, 1, 1000, source: PriceSource.comparison).source,
        PriceSource.comparison,
      );
    });
  });

  group('PriceSeries', () {
    test('orders by the clock reading, not by the order it was given', () {
      final series = PriceSeries(<PricePoint>[
        point(300, 300, 1000000),
        point(100, 100, 1000000),
        point(200, 200, 1000000),
      ]);
      expect(series.points.map((p) => p.paid.minorUnits).toList(), [100, 200, 300]);
      expect(series.current!.paid, cny(300));
    });

    test('counts an observation once, however often a sync sends it', () {
      final series = PriceSeries(<PricePoint>[
        point(100, 100, 1000000),
        point(100, 100, 1000000),
        point(200, 200, 1000000),
      ]);
      expect(series.points.length, 2);
    });

    test('an empty series knows nothing rather than knowing zero', () {
      final series = PriceSeries(const <PricePoint>[]);
      expect(series.isEmpty, isTrue);
      expect(series.current, isNull);
      expect(series.perMicrolitre, isNull);
      expect(series.change, isNull);
      expect(series.costOf(Volume.fromMicrolitres(50000)), isNull,
          reason: 'an unpriced bottle costs an unknown amount, not nothing');
    });

    test('a series with an unusable point keeps it and sets it aside', () {
      final series = PriceSeries(<PricePoint>[
        point(100, 500, 0),
        point(200, 900, 500000),
      ]);
      expect(series.points.length, 2);
      expect(series.usable.length, 1);
      expect(series.perMicrolitre, Rational.of(900, 500000));
    });

    test('change is the first usable point against the last, as section 7 says',
        () {
      final series = PriceSeries(<PricePoint>[
        point(100, 1000, 500000),
        point(200, 1200, 500000),
        point(300, 1500, 500000),
      ]);
      final change = series.change!;
      expect(change.from, cny(1000));
      expect(change.to, cny(1500));
      expect(change.absolute, cny(500));
      expect(change.ratio, Rational.of(3, 2));
      expect(change.isCheaper, isFalse);
      expect(change.fromHlc, at(100));
    });

    test('one observation is not a change', () {
      expect(PriceSeries(<PricePoint>[point(100, 1000, 500000)]).change, isNull);
    });

    test('a first price of zero has no ratio, and says so instead of dividing',
        () {
      final series = PriceSeries(<PricePoint>[
        point(100, 0, 500000),
        point(200, 3000, 500000),
      ]);
      final change = series.change!;
      expect(change.ratio, isNull,
          reason: 'free then three yuan is a category change, not a percentage');
      expect(change.absolute, cny(3000));
    });

    test('reports a fall as well as a rise', () {
      final series = PriceSeries(<PricePoint>[
        point(100, 2000, 500000),
        point(200, 1500, 500000),
      ]);
      expect(series.change!.isCheaper, isTrue);
      expect(series.change!.absolute, cny(-500));
    });

    test('cost per glass multiplies first and rounds once', () {
      // 1000 minor units per 500000 ul = 1/500 per ul. 250000 ul x 1/500 = 500 exactly.
      final series = PriceSeries(<PricePoint>[point(100, 1000, 500000)]);
      expect(series.costOf(Volume.fromMicrolitres(250000)), cny(500));
      // A tenth of that volume is 50 exactly here, but the rounding rule is what is
      // being asserted when it is not: 1 minor unit per 1000 ul, 333 ul -> 0.333 -> 0.
      final coarse = PriceSeries(<PricePoint>[point(100, 1, 1000)]);
      expect(coarse.costOf(Volume.fromMicrolitres(333)), cny(0));
      expect(coarse.costOf(Volume.fromMicrolitres(667)), cny(1));
    });

    test('cellar value is the same arithmetic under the name a caller expects',
        () {
      final series = PriceSeries(<PricePoint>[point(100, 1000, 500000)]);
      expect(series.valueOf(Volume.fromMicrolitres(250000)),
          series.costOf(Volume.fromMicrolitres(250000)));
    });
  });

  group('PricePaid and the fold', () {
    test('round-trips through the log without losing a field', () {
      const op = PricePaid(
        hlc: Hlc(physicalMillis: 100, counter: 0, nodeId: 'laptop'),
        sku: 'gin',
        minorUnits: 1250,
        currency: Currency.cny,
        microlitres: 700000,
        source: PriceSource.manual,
      );
      final read = PriceOp.tryParse(op.toEvent());
      expect(read, isA<PricePaid>());
      final paid = read! as PricePaid;
      expect(paid.minorUnits, 1250);
      expect(paid.currency, Currency.cny);
      expect(paid.microlitres, 700000);
      expect(paid.source, PriceSource.manual);
      expect(paid.hlc, op.hlc);
    });

    test('writes ASCII keys, because a payload is not display copy', () {
      final event = const PricePaid(
        hlc: Hlc(physicalMillis: 1, counter: 0, nodeId: 'n'),
        sku: 'gin',
        minorUnits: 1,
        currency: Currency.jpy,
        microlitres: 1,
        source: PriceSource.manual,
      ).toEvent();
      expect(event.data.keys.toSet(), {'sku', 'minorUnits', 'currency', 'microlitres', 'source'});
      expect(event.type, 'price.paid');
    });

    test('folds the log into a series and ignores everything else', () {
      final events = <Event>[
        const PricePaid(
          hlc: Hlc(physicalMillis: 200, counter: 0, nodeId: 'laptop'),
          sku: 'gin',
          minorUnits: 1500,
          currency: Currency.cny,
          microlitres: 500000,
          source: PriceSource.manual,
        ).toEvent(),
        // Somebody else's event, which this build understands and must not eat.
        Event(
          hlc: at(100),
          type: 'stock.bottle.added',
          data: const <String, Object?>{'sku': 'gin'},
        ),
        // An event from a newer build. Carried across, not understood, not an error.
        Event(hlc: at(150), type: 'price.future.thing', data: const <String, Object?>{}),
      ];

      final series = priceSeriesOf(events);
      expect(series.points.length, 1);
      expect(series.current!.paid, cny(1500));
    });

    test('a source written by a newer build is read as manual, not refused', () {
      final event = Event(
        hlc: at(100),
        type: PriceEventTypes.paid,
        data: const <String, Object?>{
          'sku': 'gin',
          'minorUnits': 100,
          'currency': 'CNY',
          'microlitres': 1000,
          'source': 'telepathy',
        },
      );
      final op = PriceOp.tryParse(event)! as PricePaid;
      expect(op.source, PriceSource.manual,
          reason: 'manual is the reading that claims nothing about provenance');
    });

    test('a price in an unknown currency is not silently read as two digits', () {
      final event = Event(
        hlc: at(100),
        type: PriceEventTypes.paid,
        data: const <String, Object?>{
          'sku': 'gin',
          'minorUnits': 100,
          'currency': 'XYZ',
          'microlitres': 1000,
          'source': 'manual',
        },
      );
      expect(() => PriceOp.tryParse(event), throwsArgumentError);
    });

    test('a duplicate event across a sync is not counted twice', () {
      final one = const PricePaid(
        hlc: Hlc(physicalMillis: 100, counter: 0, nodeId: 'laptop'),
        sku: 'gin',
        minorUnits: 1000,
        currency: Currency.cny,
        microlitres: 500000,
        source: PriceSource.manual,
      ).toEvent();
      final series = priceSeriesOf(<Event>[one, one]);
      expect(series.points.length, 1);
    });
  });
}
