/// One primary choice and up to three secondary ones, with no repetition.
///
/// **The same shape serves both axes, which is why it is one type and not two.** The
/// instruction for money was 钱默认跟语言区走（可换），可设置副币种（最多3个，连同主币种共四个之间
/// 不得重复）and for measures 主单位1个，副单位最多3个，都可替换，都不可重复 -- and they are the
/// same sentence with a different noun. Writing it twice would mean writing the
/// uniqueness rule twice, and a rule stated in two places is a rule that will disagree
/// with itself.
///
/// **The invariants are enforced at construction and after every change**, so there is no
/// state a caller can reach where the set repeats itself or exceeds four. Everything is
/// refused loudly: this is a reader's preference, and a screen cannot be wrong about it in
/// a way anybody would notice until they saw the same unit twice in one list.
///
/// Nothing here is display copy. A choice is whatever the caller stores -- an ISO code for
/// a currency, a unit id for a measure -- and the name a person reads is composed by the UI
/// layer, as section 12.4 requires.
library;

final class ChoiceSet<T> {
  const ChoiceSet._(this.primary, this.secondary);

  /// Builds a set, refusing anything a reader could not have meant.
  ///
  /// [secondary] may be empty, may hold up to [maxSecondary], and may not contain
  /// [primary] or repeat itself.
  ///
  /// The parameter is nullable rather than defaulted to `const <T>[]`, because a `const`
  /// list cannot be written over a type variable -- the compiler is right to refuse it and
  /// the null is the honest spelling of "no alternates".
  factory ChoiceSet({required T primary, List<T>? secondary}) {
    final alternates = secondary ?? const <Never>[];
    _check(primary, alternates);
    return ChoiceSet<T>._(primary, List<T>.unmodifiable(alternates));
  }

  /// How many secondary choices the instruction allows. Three, and with the primary that
  /// is the four the money instruction names explicitly.
  static const int maxSecondary = 3;

  /// The choice used when nothing more specific is meant.
  final T primary;

  /// The alternates, in the reader's order, at most [maxSecondary] of them.
  final List<T> secondary;

  bool get isFull => secondary.length == maxSecondary;

  /// Whether this value is anywhere in the set, primary included.
  bool contains(T value) => primary == value || secondary.contains(value);

  /// Every choice, primary first. What a picker lists.
  List<T> get all => <T>[primary, ...secondary];

  /// Makes [value] the primary, **and this is the one operation with two behaviours.**
  ///
  /// If [value] is already a secondary, the two **swap**: the choice that had the primary
  /// slot takes the one that just emptied. That is what "replace" means when the thing being
  /// chosen is already present -- nothing is dropped, and a reader who promotes 欧元 to
  /// primary does not thereby lose the currency they had before, which is the behaviour that
  /// would make them distrust the setting.
  ///
  /// If [value] is not in the set, the old primary **leaves**. The set is a list of what
  /// somebody wants to see, and it is bounded; something has to go, and the thing they
  /// explicitly replaced is the least surprising candidate.
  ChoiceSet<T> promote(T value) {
    if (value == primary) return this;
    final index = secondary.indexOf(value);
    if (index < 0) return ChoiceSet<T>._(value, secondary);

    final swapped = <T>[...secondary];
    swapped[index] = primary;
    return ChoiceSet<T>._(value, swapped);
  }

  /// Puts [value] in the slot at [index], which is how a picker offers "change this one".
  ///
  /// Refuses a value that is the primary or that already sits in another secondary slot:
  /// replacing slot 2 with what slot 0 already holds is not a replacement, it is a
  /// duplicate arriving by the back door.
  ChoiceSet<T> withSecondaryAt(int index, T value) {
    if (index < 0 || index >= secondary.length) {
      throw RangeError.index(index, secondary, 'index', 'no such secondary slot', secondary.length);
    }
    if (value == primary) {
      throw ArgumentError.value(value, 'value', 'the primary cannot also be a secondary');
    }
    final existing = secondary.indexOf(value);
    if (existing >= 0 && existing != index) {
      throw ArgumentError.value(value, 'value', 'already in the set at $existing');
    }
    final replaced = <T>[...secondary];
    replaced[index] = value;
    return ChoiceSet<T>._(primary, replaced);
  }

  /// Appends a secondary, refusing when the set is full.
  ///
  /// Refusing rather than evicting: three is the instruction's number, and silently dropping
  /// the oldest choice to make room for a fourth would be a decision made on the reader's
  /// behalf about which of their choices mattered least.
  ChoiceSet<T> addSecondary(T value) {
    if (isFull) {
      throw StateError('the set already holds $maxSecondary secondary choices');
    }
    if (contains(value)) {
      throw ArgumentError.value(value, 'value', 'already in the set');
    }
    return ChoiceSet<T>._(primary, <T>[...secondary, value]);
  }

  /// Takes a secondary out. Absent is not an error -- a screen may ask twice.
  ChoiceSet<T> removeSecondary(T value) {
    if (!secondary.contains(value)) return this;
    return ChoiceSet<T>._(
      primary,
      <T>[...secondary]..removeWhere((T each) => each == value),
    );
  }

  @override
  String toString() => 'ChoiceSet($primary, secondary: $secondary)';
}

void _check<T>(T primary, List<T> secondary) {
  if (secondary.length > ChoiceSet.maxSecondary) {
    throw ArgumentError.value(
      secondary.length,
      'secondary',
      'at most ${ChoiceSet.maxSecondary} secondary choices',
    );
  }
  final seen = <T>{primary};
  for (final each in secondary) {
    if (!seen.add(each)) {
      throw ArgumentError.value(each, 'secondary', 'repeats the primary or another choice');
    }
  }
}
