/// Prices, as a time series rather than a field.
///
/// **Section 7's first line decides this file's whole shape**: *"A price is not a
/// field, it is a time series."* Store only a current `price` and none of the metrics
/// the section lists can be computed -- no change to report, no value to total, no
/// rate to extrapolate a restock point from. So nothing here stores a price as a
/// property of anything. A [PricePoint] is an *observation*, and a [PriceSeries] is
/// what you get by collecting them.
///
/// **The integer base is minor units, and the reason is the same one section 5.1
/// gives for microlitres.** Money is a quantity, a quantity is exact, and a `double`
/// that has been through three multiplications is not. So [Money] holds a whole
/// number of minor units, every multiplication goes through [Rational], and the single
/// place a fraction becomes a whole number again is [Money.times] -- which is
/// `roundHalfUp` and is called once, at the edge, exactly as section 5.3 requires of
/// volumes.
///
/// **Two traps are carried in the types rather than left to comments**, both of which
/// are the sort of thing that produces a plausible wrong number instead of an error:
/// a currency whose minor unit is not 1/100 ([Currency.minorUnitDigits], and JPY is the
/// case that matters), and a first observation of zero, which has no ratio to report
/// ([PriceChange.ratio] is nullable for that one reason).
///
/// Nothing here formats anything. Section 3 keeps display text out of the domain
/// layer, and "¥12.50" against "12.50" is a decision a screen makes.
library;

import '../events/hlc.dart';
import '../units/quantity.dart';
import '../units/rational.dart';

/// **[decision] The pour a "cost per glass" is quoted for.**
///
/// Section 7 names the metric and gives no size, and the domain has no such thing to
/// borrow: `Glass` is a shape rather than a capacity, and the real answer is the
/// recipe's own amount of this ingredient. So this is a **display default for a
/// shelf-level figure**, named rather than written as a literal at the call site so
/// that the day a recipe supplies its own pour, this is the thing that gets replaced
/// and there is one place to find it.
///
/// 45 ml is one Japanese single measure (`1 合`), which is also what a bar means by
/// "a shot" in most of the places this project's locales cover. It is a choice and not
/// a standard, which is why it is written down as one.
const Volume standardPour = Volume.fromMicrolitres(45000);

/// A currency, and the one fact about it that changes arithmetic rather than
/// presentation.
///
/// [minorUnitDigits] is not decoration. A hundredth is the common case and *not* the
/// universal one: JPY and KRW have no subdivision, so one yen is `1` minor unit and
/// not `100`. A model that assumed two digits would report a Japanese price as one
/// hundred times what was paid, and it would do it consistently, which is what makes
/// it dangerous.
final class Currency {
  const Currency(this.code, this.minorUnitDigits);

  /// ISO 4217, three ASCII letters. A key, so section 12.4's first rule applies:
  /// a person never reads this, the UI prints a symbol instead.
  final String code;

  /// How many decimal places the minor unit sits below the major one.
  final int minorUnitDigits;

  /// [decision] Section 7 says nothing about currencies, so this list is this file's.
  ///
  /// It is the set the shipped locales in section 12.4 need, and it is short on
  /// purpose: a currency is not something to guess at, and an unknown code returns
  /// null from [byCode] rather than being invented with two digits.
  static const Currency cny = Currency('CNY', 2);
  static const Currency hkd = Currency('HKD', 2);
  static const Currency twd = Currency('TWD', 2);
  static const Currency jpy = Currency('JPY', 0);
  static const Currency krw = Currency('KRW', 0);
  static const Currency eur = Currency('EUR', 2);
  static const Currency usd = Currency('USD', 2);
  static const Currency gbp = Currency('GBP', 2);
  static const Currency rub = Currency('RUB', 2);

  /// Every currency this build knows, for a picker that has to offer them.
  ///
  /// **One list, and it used to be two.** `all` and `known` held the same nine currencies, with
  /// `byCode` reading one and the settings picker offering the other. Adding a currency to the
  /// wrong one produced the worst shape available: the picker would offer a code that `byCode`
  /// refuses, so a price entered in it would be *unreadable* by the fold that has to read it
  /// back -- and `_currencyOfBottle` throws rather than substituting, so the symptom would be a
  /// crash on a chart rather than a wrong number. Nothing kept the two in step, so they were one
  /// typo away from disagreeing. This is the table; keep it the only one.
  static const List<Currency> all = [cny, hkd, twd, jpy, krw, eur, usd, gbp, rub];

  static Currency? byCode(String? code) {
    if (code == null || code.isEmpty) return null;
    final wanted = code.toUpperCase();
    for (final currency in all) {
      if (currency.code == wanted) return currency;
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is Currency && other.code == code && other.minorUnitDigits == minorUnitDigits;

  @override
  int get hashCode => Object.hash(code, minorUnitDigits);

  @override
  String toString() => code;
}

/// An amount of money, as a whole number of minor units.
///
/// The same shape as [Volume] and for the same reason: the base is an integer, the
/// arithmetic is whole, and the only exit is [times], which rounds once.
///
/// **Two currencies do not add.** The check is the one `quantity.dart` makes when it
/// refuses to add a volume to a mass -- *"a volume and a mass are not the same kind of
/// thing"* -- and it is here for the identical reason. Summing 10 CNY and 10 USD gives
/// 20 of nothing, and no screen would ever show that the number stopped meaning
/// anything.
final class Money implements Comparable<Money> {
  const Money.fromMinorUnits(this.minorUnits, this.currency);

  /// The exact whole number of minor units. `1250` in CNY is twelve yuan fifty.
  final int minorUnits;

  final Currency currency;

  static Money zero(Currency currency) => Money.fromMinorUnits(0, currency);

  bool get isZero => minorUnits == 0;
  bool get isNegative => minorUnits < 0;

  Rational toRational() => Rational.fromInt(minorUnits);

  Money _sameCurrency(Money other) {
    if (other.currency != currency) {
      throw ArgumentError.value(
        other.currency.code,
        'other',
        'cannot combine ${currency.code} with it',
      );
    }
    return other;
  }

  Money operator +(Money other) =>
      Money.fromMinorUnits(minorUnits + _sameCurrency(other).minorUnits, currency);

  Money operator -(Money other) =>
      Money.fromMinorUnits(minorUnits - _sameCurrency(other).minorUnits, currency);

  Money operator -() => Money.fromMinorUnits(-minorUnits, currency);

  Money scaleBy(int factor) => Money.fromMinorUnits(minorUnits * factor, currency);

  Money operator *(int factor) => scaleBy(factor);

  /// The **one** place a price becomes a whole number again, and the reason this
  /// type exists. `roundHalfUp` is section 5.3's rule, applied to money because money
  /// is a quantity like any other.
  Money times(Rational factor) => Money.fromMinorUnits(
        (toRational() * factor).roundHalfUpToBigInt().toInt(),
        currency,
      );

  @override
  int compareTo(Money other) {
    _sameCurrency(other);
    return minorUnits.compareTo(other.minorUnits);
  }

  bool operator <(Money other) => compareTo(other) < 0;
  bool operator <=(Money other) => compareTo(other) <= 0;
  bool operator >(Money other) => compareTo(other) > 0;
  bool operator >=(Money other) => compareTo(other) >= 0;

  @override
  bool operator ==(Object other) =>
      other is Money && other.minorUnits == minorUnits && other.currency == currency;

  @override
  int get hashCode => Object.hash(minorUnits, currency);

  @override
  String toString() => '$minorUnits ${currency.code}';
}

/// Where a price came from.
///
/// Section 7 lists three sources and says the first version implements only the
/// first. **The source is carried in the type rather than assumed**, which is the same
/// move `UnitFactor.isEstimate` and `TextOrigin` make: a screen that shows a
/// compared-from-the-internet price beside a hand-entered one without saying which is
/// which is presenting a guess as a fact, and here the guess costs money.
enum PriceSource {
  /// Typed in by the person who paid. The only one version one produces.
  manual,

  /// From the phase-two comparison adapter. Nothing produces this yet.
  comparison,

  /// From a receipt. Long term, per section 7.
  receipt,
}

/// One observation: what was paid, for how much, when, and how it is known.
final class PricePoint {
  const PricePoint({
    required this.hlc,
    required this.paid,
    required this.volume,
    required this.source,
  });

  /// When and where this was recorded. Doubles as the identity, so syncing two
  /// devices cannot count one purchase twice.
  final Hlc hlc;

  final Money paid;

  final Volume volume;

  final PriceSource source;

  /// Section 7's `current price per ul`, kept exact.
  ///
  /// A `Rational` and not a [Money], because a price per microlitre is almost never a
  /// whole minor unit and rounding it here would lose the digits that the *next*
  /// multiplication needs. Section 7's cost-per-glass is this value times a volume, so
  /// the rounding belongs after the multiplication and not before it.
  Rational get perMicrolitre => paid.toRational() / volume.toRational();

  /// Whether this observation can be divided by at all.
  ///
  /// A receipt line with no volume, or a hand entry where the volume was skipped,
  /// would otherwise divide by zero. The point is still kept -- what was paid is a
  /// fact -- it is simply not usable as a *rate*, and [PriceSeries] leaves it out of
  /// the rate calculations rather than refusing the whole series.
  bool get isUsable => volume.microlitres > 0;

  @override
  String toString() => '$paid for $volume ($source)';
}

/// The difference between two observations, in both senses a person means.
final class PriceChange {
  const PriceChange({
    required this.from,
    required this.to,
    required this.fromHlc,
    required this.toHlc,
    required this.ratio,
  });

  final Money from;
  final Money to;
  final Hlc fromHlc;
  final Hlc toHlc;

  /// `to / from`, or **null when the first price was zero**.
  ///
  /// A nullable ratio and not an infinity, because "free, then three yuan" has no
  /// percentage: it is not a large increase, it is a category change, and a screen
  /// that divided by it would print a wall of digits that looks like data.
  final Rational? ratio;

  Money get absolute => to - from;

  bool get isCheaper => to < from;
  bool get isUnchanged => to == from;

  @override
  String toString() => '$from -> $to';
}

/// A price over time, ordered, deduplicated, and asked the questions section 7 asks.
///
/// **Ordering and deduplication are not conveniences.** Section 10.4 reduces a sync to
/// sending everything the other device is missing, and a device missing a stretch of
/// the log rather than a single event will happily send one twice -- so a series that
/// did not dedupe by [Hlc] would report a purchase as having happened twice, and
/// section 7's "change" would compare against the wrong first point. `StockLedger.of`
/// solves the same problem the same way.
final class PriceSeries {
  PriceSeries._(this.points);

  /// The observations, oldest first, one per [Hlc], unusable ones kept but set aside.
  final List<PricePoint> points;

  /// Builds a series from observations in any order, discarding duplicates.
  factory PriceSeries(Iterable<PricePoint> observations) {
    final ordered = observations.toList()
      ..sort((PricePoint a, PricePoint b) => a.hlc.compareTo(b.hlc));

    final seen = <Hlc>{};
    final kept = <PricePoint>[];
    for (final point in ordered) {
      if (!seen.add(point.hlc)) continue;
      kept.add(point);
    }
    return PriceSeries._(List<PricePoint>.unmodifiable(kept));
  }

  bool get isEmpty => points.isEmpty;
  bool get isNotEmpty => points.isNotEmpty;

  /// The currency of the most recent observation, or null when there is nothing.
  Currency? get currency => points.isEmpty ? null : points.last.paid.currency;

  /// Whether every observation in this series is in one currency.
  ///
  /// **A series that mixed currencies would be a chart of nothing.** Two rates, one in
  /// CNY and one in USD, can be compared as numbers and mean nothing by it, and the
  /// mistake would be invisible: the candles would draw, the axis would be plausible,
  /// and the only symptom would be a spike that happens to line up with a holiday
  /// abroad. So the fact is exposed rather than assumed, and `candlesOf` refuses a
  /// series where it is false.
  bool get isSingleCurrency {
    final first = currency;
    if (first == null) return true;
    return points.every((PricePoint point) => point.paid.currency == first);
  }

  /// Section 7's `current`: the most recent observation, not the first one entered.
  PricePoint? get current => points.isEmpty ? null : points.last;

  /// The observations that can be divided by, which is what every rate uses.
  List<PricePoint> get usable =>
      points.where((PricePoint point) => point.isUsable).toList(growable: false);

  /// The current price per microlitre, exact, or null when there is nothing usable.
  Rational? get perMicrolitre => usable.isEmpty ? null : usable.last.perMicrolitre;

  /// Section 7's `Change`: *"first PricePoint compared against last"*.
  ///
  /// Null below two usable observations, because one price is not a change and
  /// reporting zero would say "the price held steady" about a series that has only
  /// ever been measured once.
  PriceChange? get change {
    final series = usable;
    if (series.length < 2) return null;

    final first = series.first;
    final last = series.last;
    return PriceChange(
      from: first.paid,
      to: last.paid,
      fromHlc: first.hlc,
      toHlc: last.hlc,
      ratio: first.paid.isZero
          ? null
          : last.paid.toRational() / first.paid.toRational(),
    );
  }

  /// Section 7's `Cost per glass`: amount (ul) x current price per ul.
  ///
  /// Rounded once, here, after the multiplication -- which is the whole reason
  /// [PricePoint.perMicrolitre] is a [Rational].
  ///
  /// Null when there is no usable rate, and null is not zero: an unpriced bottle costs
  /// an unknown amount, not nothing.
  Money? costOf(Volume volume) {
    final rate = perMicrolitre;
    if (rate == null) return null;
    return Money.fromMinorUnits(
      (rate * volume.toRational()).roundHalfUpToBigInt().toInt(),
      current!.paid.currency,
    );
  }

  /// Section 7's `Total cellar value`: sum of volume on hand x current unit price.
  ///
  /// **The same arithmetic as [costOf], and kept as a separate name because it is a
  /// different question.** One glass and one whole cellar are multiplied identically;
  /// what differs is what gets summed over, and a caller reading `valueOf` should not
  /// have to work out that a glass is the unit case of a cellar. The summing itself
  /// belongs to whoever holds the bottles -- a series knows a price, not an inventory.
  Money? valueOf(Volume onHand) => costOf(onHand);

  @override
  String toString() => 'PriceSeries(${points.length} points)';
}
