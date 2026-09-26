import 'package:hollow_court/domain/events/hlc.dart';
import 'package:test/test.dart';

void main() {
  group('Hlc comparison', () {
    test('orders by physical time first', () {
      const a = Hlc(physicalMillis: 100, counter: 9, nodeId: 'z');
      const b = Hlc(physicalMillis: 101, counter: 0, nodeId: 'a');
      expect(a < b, isTrue);
    });

    test('breaks a shared millisecond by counter', () {
      const a = Hlc(physicalMillis: 100, counter: 0, nodeId: 'a');
      const b = Hlc(physicalMillis: 100, counter: 1, nodeId: 'a');
      expect(a < b, isTrue);
    });

    test('breaks a shared millisecond and counter by node id', () {
      const a = Hlc(physicalMillis: 100, counter: 0, nodeId: 'a');
      const b = Hlc(physicalMillis: 100, counter: 0, nodeId: 'b');
      expect(a < b, isTrue);
      expect(b < a, isFalse);
    });

    test('is a total order, so two devices cannot disagree about ties', () {
      const readings = [
        Hlc(physicalMillis: 2, counter: 0, nodeId: 'a'),
        Hlc(physicalMillis: 1, counter: 5, nodeId: 'b'),
        Hlc(physicalMillis: 1, counter: 5, nodeId: 'a'),
        Hlc(physicalMillis: 1, counter: 0, nodeId: 'c'),
      ];
      final sorted = [...readings]..sort();
      expect(sorted.map((r) => r.toString()).toList(), [
        '1.0@c',
        '1.5@a',
        '1.5@b',
        '2.0@a',
      ]);
    });

    test('refuses a reading with no node id', () {
      expect(
        () => Hlc(physicalMillis: 1, counter: 0, nodeId: ''),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('Hlc json', () {
    test('round-trips', () {
      const reading = Hlc(physicalMillis: 1789758844123, counter: 7, nodeId: 'laptop');
      expect(Hlc.fromJson(reading.toJson()), reading);
    });

    test('refuses a line whose clock cannot be read', () {
      expect(
        () => Hlc.fromJson({'physical': 'soon', 'counter': 0, 'node': 'a'}),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => Hlc.fromJson({'physical': 1, 'counter': 0}),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => Hlc.fromJson({'physical': 1, 'counter': 0, 'node': ''}),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('HlcClock.next', () {
    test('follows the wall clock and resets the counter', () {
      var now = 1000;
      final clock = HlcClock(nodeId: 'a', nowMillis: () => now);

      expect(clock.next().toString(), '1000.0@a');
      now = 2000;
      expect(clock.next().toString(), '2000.0@a');
    });

    test('counts within one millisecond rather than repeating itself', () {
      final clock = HlcClock(nodeId: 'a', nowMillis: () => 1000);

      expect(clock.next().toString(), '1000.0@a');
      expect(clock.next().toString(), '1000.1@a');
      expect(clock.next().toString(), '1000.2@a');
    });

    test('never goes backwards when the machine clock does', () {
      var now = 5000;
      final clock = HlcClock(nodeId: 'a', nowMillis: () => now);

      expect(clock.next().toString(), '5000.0@a');
      now = 4000; // someone corrected the machine clock, or a DST bug
      expect(clock.next().toString(), '5000.1@a');
      now = 4500;
      expect(clock.next().toString(), '5000.2@a');
      now = 6000;
      expect(clock.next().toString(), '6000.0@a');
    });
  });

  group('HlcClock.observe', () {
    test('returns a reading strictly after both sides', () {
      final clock = HlcClock(nodeId: 'a', nowMillis: () => 1000);
      clock.next(); // 1000.0@a

      final remote = Hlc(physicalMillis: 1000, counter: 5, nodeId: 'b');
      final observed = clock.observe(remote);

      expect(observed > remote, isTrue);
      expect(observed.nodeId, 'a');
      // Both sides were already in this millisecond, so the counter clears the
      // higher of the two rather than only the local one.
      expect(observed.toString(), '1000.6@a');
    });

    test('jumps to a peer that is ahead, and stays ahead afterwards', () {
      var now = 1000;
      final clock = HlcClock(nodeId: 'a', nowMillis: () => now);
      clock.next(); // 1000.0@a

      final ahead = Hlc(physicalMillis: 5000, counter: 0, nodeId: 'b');
      expect(clock.observe(ahead).toString(), '5000.1@a');

      // The local wall clock is still behind. The next local event must not
      // look older than the peer's event we just saw.
      now = 1200;
      expect(clock.next().toString(), '5000.2@a');
    });

    test('is monotonic across a long mixed sequence', () {
      var now = 1000;
      final clock = HlcClock(nodeId: 'a', nowMillis: () => now);
      Hlc previous = clock.last;

      for (var i = 0; i < 200; i++) {
        // Feed it a peer that is sometimes ahead, sometimes behind, sometimes
        // in the same millisecond.
        final remote = Hlc(
          physicalMillis: 1000 + (i % 7) * 300 - 600,
          counter: i % 4,
          nodeId: 'node${i % 3}',
        );
        final reading = i.isEven ? clock.next() : clock.observe(remote);
        expect(reading > previous, isTrue, reason: 'iteration $i');
        previous = reading;
        now += (i % 5) - 2; // the wall clock wanders, including backwards
      }
    });
  });
}
