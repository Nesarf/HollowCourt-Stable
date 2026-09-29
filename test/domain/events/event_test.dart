import 'dart:convert';

import 'package:hollow_court/domain/events/event.dart';
import 'package:hollow_court/domain/events/hlc.dart';
import 'package:test/test.dart';

const _clock = Hlc(physicalMillis: 1789758844123, counter: 0, nodeId: 'laptop');

void main() {
  group('Event json', () {
    test('round-trips through one log line', () {
      final event = Event(
        hlc: _clock,
        type: 'stock.bottle.added',
        data: {'bottleId': 'b1', 'sku': 'gin', 'volumeMicrolitres': 700000},
      );

      final decoded = Event.decode(event.encode());
      expect(decoded, event);
    });

    test('encodes to exactly one line', () {
      final event = Event(hlc: _clock, type: 't', data: {'a': 1});
      expect(event.encode().contains('\n'), isFalse);
      expect(jsonDecode(event.encode()), isA<Map<String, Object?>>());
    });

    test('keeps an unknown event type and its payload verbatim', () {
      // The forward-compatibility case: a newer build wrote an event this one
      // has never heard of. It has to survive being read and re-encoded, or
      // syncing through an older device would quietly destroy operations.
      const line =
          '{"hlc":{"physical":5,"counter":0,"node":"newer"},'
          '"type":"cellar.bottle.hologram","data":{"wavelength":42,"tags":["a","b"]}}';

      final event = Event.decode(line);
      expect(event.type, 'cellar.bottle.hologram');
      expect(event.data['wavelength'], 42);
      expect(jsonDecode(event.encode()), jsonDecode(line));
    });

    test('refuses a line that is not an event', () {
      expect(() => Event.decode('not json'), throwsA(isA<FormatException>()));
      expect(() => Event.decode('[1,2,3]'), throwsA(isA<FormatException>()));
      expect(
        () => Event.decode('{"type":"x","data":{}}'),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => Event.decode('{"hlc":{"physical":1,"counter":0,"node":"a"},"data":{}}'),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => Event.decode('{"hlc":{"physical":1,"counter":0,"node":"a"},"type":"x"}'),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('Event payload access', () {
    test('require returns the field', () {
      final event = Event(hlc: _clock, type: 't', data: {'n': 3});
      expect(event.require<int>('n'), 3);
    });

    test('require refuses a missing or mistyped field rather than defaulting', () {
      // A default here would become a plausible wrong number in a stock ledger,
      // which is worse than an exception.
      final event = Event(hlc: _clock, type: 't', data: {'n': 'three'});
      expect(() => event.require<int>('n'), throwsA(isA<FormatException>()));
      expect(() => event.require<int>('missing'), throwsA(isA<FormatException>()));
    });

    test('optional distinguishes absent from mistyped', () {
      final event = Event(hlc: _clock, type: 't', data: {'n': 'three'});
      expect(event.optional<String>('nothing'), isNull);
      expect(() => event.optional<int>('n'), throwsA(isA<FormatException>()));
    });
  });

  group('Event immutability', () {
    test('the payload cannot be edited after the fact', () {
      final source = <String, Object?>{'n': 1};
      final event = Event(hlc: _clock, type: 't', data: source);

      source['n'] = 999;
      expect(event.data['n'], 1, reason: 'the event kept its own copy');

      expect(() => event.data['n'] = 5, throwsUnsupportedError);
    });
  });
}
