import 'package:hollow_court/domain/events/event.dart';
import 'package:hollow_court/domain/events/hlc.dart';
import 'package:hollow_court/domain/events/overlay.dart';
import 'package:hollow_court/domain/events/stock.dart';
import 'package:hollow_court/domain/overlay/overlay.dart';
import 'package:hollow_court/domain/overlay/overlay_key.dart';
import 'package:hollow_court/domain/units/quantity.dart';
import 'package:test/test.dart';

Hlc at(int millis, {int counter = 0, String node = 'a'}) =>
    Hlc(physicalMillis: millis, counter: counter, nodeId: node);

Event set(int millis, OverlayKey key, String value, {String node = 'a'}) =>
    OverlayEvents.fieldSet(hlc: at(millis, node: node), key: key, value: value);

Event clear(int millis, OverlayKey key, {String node = 'a'}) =>
    OverlayEvents.fieldCleared(hlc: at(millis, node: node), key: key);

void main() {
  final note = OverlayKey.recipe('negroni12345');

  group('Overlay.of', () {
    test('an empty log is an empty overlay', () {
      final overlay = Overlay.of(const []);
      expect(overlay.isEmpty, isTrue);
      expect(overlay.length, 0);
      expect(overlay.has(note), isFalse);
      expect(overlay.value(note), isNull);
    });

    test('a set is readable, and carries the clock that set it', () {
      final overlay = Overlay.of([set(1, note, '减半')]);
      expect(overlay.value(note), '减半');
      expect(overlay.entries[note]!.setAt, at(1));
      expect(overlay.appliedEvents, 1);
      expect(overlay.ignoredEvents, 0);
    });

    test('the later of two sets wins', () {
      final overlay = Overlay.of([set(1, note, 'first'), set(5, note, 'second')]);
      expect(overlay.value(note), 'second');
      expect(overlay.length, 1);
    });

    test('and it wins whatever order the two arrive in', () {
      // **The property that makes two devices agree.** The fold sorts by clock, so
      // the answer is a function of the *set* of events and not of the order they
      // happened to reach this device.
      final events = [set(1, note, 'first'), set(5, note, 'second')];
      expect(
        Overlay.of(events).value(note),
        Overlay.of(events.reversed).value(note),
      );
      expect(Overlay.of(events).value(note), 'second');
    });

    test('two nodes writing in the same millisecond still resolve, by node id', () {
      // The clock is total, so there is no tie left over for arrival order to
      // decide -- which is the whole reason section 10.4 uses an HLC.
      expect(
        Overlay.of([
          set(3, note, 'from b', node: 'b'),
          set(3, note, 'from a', node: 'a'),
        ]).value(note),
        'from b',
      );
      expect(
        Overlay.of([
          set(3, note, 'from a', node: 'a'),
          set(3, note, 'from b', node: 'b'),
        ]).value(note),
        'from b',
      );
    });

    test('a clear removes the entry rather than blanking it', () {
      final overlay = Overlay.of([set(1, note, '减半'), clear(2, note)]);
      expect(overlay.has(note), isFalse);
      expect(overlay.value(note), isNull);
      expect(overlay.length, 0);
    });

    test('and a clear beats an older set that arrives afterwards', () {
      // **This is the test the no-tombstone decision rests on.** A peer that still
      // holds the older `set` hands it back after the clear was recorded, and it
      // must not resurrect the value the user threw away. It does not, because the
      // fold sorts by clock and the clear is later -- which is why a tombstone in
      // the state would be a second copy of a fact the sorted log already carries.
      final overlay = Overlay.of([clear(9, note), set(2, note, 'resurrected')]);
      expect(overlay.has(note), isFalse);
      expect(overlay.value(note), isNull);
    });

    test('a clear can be followed by a new value', () {
      final overlay = Overlay.of([
        set(1, note, '减半'),
        clear(2, note),
        set(3, note, '换成金酒'),
      ]);
      expect(overlay.value(note), '换成金酒');
    });

    test('a repeated clock is applied once and changes nothing', () {
      // A sync sends everything the other side is missing, and a device missing a
      // stretch of the log will happily send one event twice.
      final events = [set(1, note, '减半')];
      final overlay = Overlay.of([...events, ...events]);
      expect(overlay.value(note), '减半');
      expect(overlay.appliedEvents, 1);
      expect(overlay.length, 1);
    });

    test('events of another kind are carried and counted, not dropped', () {
      final stock = StockEvents.bottleAdded(
        hlc: at(4),
        bottleId: 'b1',
        sku: 'gin',
        volume: Volume.fromMillilitres(700),
      );
      final overlay = Overlay.of([stock, set(5, note, 'x')]);
      expect(overlay.appliedEvents, 1);
      expect(overlay.ignoredEvents, 1);
      expect(overlay.value(note), 'x');
    });

    test('an empty value from another build is surfaced and read as a removal', () {
      // `fieldSet` refuses an empty value, so one in the log can only have been
      // written by a build that does not check. Reported rather than smoothed over,
      // and read as a removal because that is the only thing an empty value can
      // mean to a reader -- the alternative is a screen drawing a blank line where
      // a note used to be and calling it a value.
      final foreign = Event(
        hlc: at(6),
        type: OverlayEvent.fieldSet,
        data: {
          'kind': 'recipe',
          'id': 'negroni12345',
          'field': 'note',
          'value': '',
        },
      );
      final overlay = Overlay.of([set(1, note, '减半'), foreign]);
      expect(overlay.emptySets, hasLength(1));
      expect(overlay.emptySets.single.key, note);
      expect(overlay.has(note), isFalse);
    });

    test('different fields of one entity are independent', () {
      // Section 10.4's field-level LWW: two devices that each edited a different
      // field of one thing both keep their edit, and only a genuine collision on
      // the same field is resolved by clock.
      final overlay = Overlay.of([
        set(1, note, '减半'),
        set(2, OverlayKey.recipe('negroni12345', 'glass'), '换成古典杯'),
      ]);
      expect(overlay.fieldsOf('recipe', 'negroni12345'), {
        'note': '减半',
        'glass': '换成古典杯',
      });
    });
  });

  group('section 8\'s dimensions', () {
    test('extras are ordinary fields with the prefix taken off', () {
      final overlay = Overlay.of([
        OverlayEvents.fieldSet(
          hlc: at(1),
          key: OverlayKey.extra('ingredient', 'gin', 'glass'),
          value: '古典杯',
        ),
        OverlayEvents.fieldSet(
          hlc: at(2),
          key: OverlayKey.extra('ingredient', 'gin', 'shelf'),
          value: '上排',
        ),
        set(3, OverlayKey.ingredient('gin'), '我的金酒'),
      ]);
      expect(overlay.extrasOf('ingredient', 'gin'), {
        'glass': '古典杯',
        'shelf': '上排',
      });
      // The alias is not an extra, and the prefix is what tells them apart.
      expect(overlay.extrasOf('ingredient', 'gin').containsKey('alias'), isFalse);
      expect(overlay.ingredientAlias('gin'), '我的金酒');
    });

    test('a note is a note on the recipe it was written on', () {
      final overlay = Overlay.of([set(1, note, '减半')]);
      expect(overlay.recipeNote('negroni12345'), '减半');
      expect(overlay.recipeNote('somewhereelse1'), isNull);
    });

    test('an entry names a key and a value and nothing else', () {
      // **The shape is the guarantee.** Nothing in an entry refers to the seed's
      // contents -- no name, no title, no position -- which is what makes "the
      // overlay never gets lost when the seed is replaced" a property of the type
      // rather than a promise about the update code.
      final entry = Overlay.of([set(1, note, '减半')]).entries[note]!;
      expect(entry.key, note);
      expect(entry.value, '减半');
      expect(entry.setAt, at(1));
    });
  });
}
