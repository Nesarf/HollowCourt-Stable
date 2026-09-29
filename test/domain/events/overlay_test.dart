import 'package:hollow_court/domain/events/event.dart';
import 'package:hollow_court/domain/events/hlc.dart';
import 'package:hollow_court/domain/events/overlay.dart';
import 'package:hollow_court/domain/events/stock.dart';
import 'package:hollow_court/domain/overlay/overlay_key.dart';
import 'package:hollow_court/domain/units/quantity.dart';
import 'package:test/test.dart';

Hlc at(int millis, {int counter = 0, String node = 'a'}) =>
    Hlc(physicalMillis: millis, counter: counter, nodeId: node);

void main() {
  group('OverlayEvents', () {
    final key = OverlayKey.recipe('negroni12345');

    test('a set carries the key in three fields and the value beside it', () {
      final event = OverlayEvents.fieldSet(hlc: at(1), key: key, value: '减半');
      expect(event.type, OverlayEvent.fieldSet);
      expect(event.data, {
        'kind': 'recipe',
        'id': 'negroni12345',
        'field': 'note',
        'value': '减半',
      });
    });

    test('a clear carries the key and nothing else', () {
      final event = OverlayEvents.fieldCleared(hlc: at(1), key: key);
      expect(event.type, OverlayEvent.fieldCleared);
      expect(event.data.containsKey('value'), isFalse);
    });

    test('an empty value is refused, and the refusal names the operation meant', () {
      // "Set to nothing" and "removed" are the same state to a reader and different
      // operations to a log, and a layer that allowed both would leave every screen
      // guessing which one it was looking at. So the empty one is refused here and
      // the caller is pointed at the one they actually meant.
      expect(
        () => OverlayEvents.fieldSet(hlc: at(1), key: key, value: ''),
        throwsArgumentError,
      );
    });

    test('the value is the user\'s own text and is not trimmed or inspected', () {
      final event = OverlayEvents.fieldSet(
        hlc: at(1),
        key: key,
        value: '  两片柠檬  ',
      );
      expect(event.data['value'], '  两片柠檬  ');
    });
  });

  group('OverlayOp.tryParse', () {
    test('reads a set back with its key and its value', () {
      final event = OverlayEvents.fieldSet(
        hlc: at(7),
        key: OverlayKey.ingredient('gin'),
        value: '我的金酒',
      );
      final op = OverlayOp.tryParse(event);
      expect(op, isA<OverlayFieldSet>());
      final set = op! as OverlayFieldSet;
      expect(set.key, OverlayKey.ingredient('gin'));
      expect(set.value, '我的金酒');
      expect(set.hlc, at(7));
    });

    test('reads a clear back as a clear', () {
      final op = OverlayOp.tryParse(
        OverlayEvents.fieldCleared(hlc: at(8), key: OverlayKey.recipe('r1')),
      );
      expect(op, isA<OverlayFieldCleared>());
    });

    test('returns null for a type it does not own, rather than throwing', () {
      // The log is shared and a device routinely meets events written by a build
      // that knows more than it does. Refusing to read the line would be refusing to
      // carry it, and an op-log that drops what it does not understand loses
      // operations -- a bottle that was drunk, a price that was paid, a note.
      final stock = StockEvents.bottleAdded(
        hlc: at(9),
        bottleId: 'b1',
        sku: 'gin',
        volume: Volume.fromMillilitres(700),
      );
      expect(OverlayOp.tryParse(stock), isNull);
    });

    test('but a drifted payload of its own type does throw', () {
      // A peer from the future is carried untouched; an event of this build's own
      // type whose payload does not fit is drift, and drift worth surfacing is what
      // `require`'s strictness exists for.
      final broken = Event(
        hlc: at(10),
        type: OverlayEvent.fieldSet,
        data: {'kind': 'recipe', 'id': 'r1', 'field': 'note'}, // no value
      );
      expect(() => OverlayOp.tryParse(broken), throwsFormatException);
    });

    test('and a key that cannot be built counts as drift too', () {
      final broken = Event(
        hlc: at(11),
        type: OverlayEvent.fieldSet,
        data: {'kind': 'Recipe', 'id': 'r1', 'field': 'note', 'value': 'x'},
      );
      expect(() => OverlayOp.tryParse(broken), throwsFormatException);
    });
  });
}
