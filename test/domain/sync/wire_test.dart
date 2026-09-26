import 'dart:convert';

import 'package:hollow_court/domain/events/event.dart';
import 'package:hollow_court/domain/events/hlc.dart';
import 'package:hollow_court/domain/sync/pairing.dart';
import 'package:hollow_court/domain/sync/wire.dart';
import 'package:test/test.dart';

Hlc at(int millis, [int counter = 0, String node = 'laptop']) =>
    Hlc(physicalMillis: millis, counter: counter, nodeId: node);

Event on(Hlc hlc, [String type = 'stock.bottle.placed']) =>
    Event(hlc: hlc, type: type, data: {'sku': 'ardbeg-ten'});

void main() {
  group('a frame is one line, because the framing depends on it', () {
    test('encoding a frame never produces a newline', () {
      // NDJSON is the whole framing scheme: the reader splits on newlines and nothing else. An
      // encoder that could emit a newline inside a frame would split one message into two and
      // the reader would see half a frame followed by nonsense -- so this is the property the
      // format rests on, and it is asserted rather than assumed.
      final frames = <WireFrame>[
        const HelloFrame(name: 'cellar', digest: ClockDigest.fromSummary(count: 0, digest: 0)),
        ClocksFrame([at(1), at(2)]),
        EventsFrame([on(at(3))]),
        const ByeFrame(reason: 'done'),
      ];

      for (final frame in frames) {
        final line = frame.encode();
        expect(line.contains('\n'), isFalse, reason: '${frame.kind.wire} spanned a line');
        expect(line.contains('\r'), isFalse, reason: '${frame.kind.wire} carried a return');
        expect(LineSplitter.split(line).length, 1);
      }
    });

    test('a name full of newlines and quotes still encodes to one line', () {
      // The name is display copy typed by a person, so it is exactly the field most likely to
      // contain whatever breaks a hand-rolled format. JSON escapes it, and this proves the
      // escaping rather than trusting it.
      const nasty = 'line one\nline two\t"quoted" \\backslash\\ 书架';
      final frame = const HelloFrame(
        name: nasty,
        digest: ClockDigest.fromSummary(count: 1, digest: 9),
      );

      final line = frame.encode();
      expect(LineSplitter.split(line).length, 1);

      final back = WireFrame.parse(line)! as HelloFrame;
      expect(back.name, nasty);
    });
  });

  group('every frame survives the round trip', () {
    test('hello carries a name, a digest and no token by default', () {
      final digest = ClockDigest.of([at(1), at(2)]);
      final back = WireFrame.parse(
        HelloFrame(name: '书房', digest: digest).encode(),
      )! as HelloFrame;

      expect(back.name, '书房');
      expect(back.digest, digest);
      expect(back.token, isEmpty);
    });

    test('a hello from a connecting side carries the token it was given', () {
      final back = WireFrame.parse(
        const HelloFrame(
          name: 'phone',
          digest: ClockDigest.fromSummary(count: 2, digest: 7),
          token: 'k7fq2m',
        ).encode(),
      )! as HelloFrame;

      expect(back.token, 'k7fq2m');
    });

    test('a digest that crossed the wire still answers likelyInSyncWith', () {
      // The reason HelloFrame exists: two devices that agree should discover it from one frame
      // each. A digest that survived the trip but no longer compared equal would make that
      // impossible while every field still looked right -- so the comparison is the assertion.
      final clocks = [at(10, 0, 'a'), at(20, 1, 'b'), at(30, 0, 'c')];

      final round = WireFrame.parse(
        HelloFrame(name: 'peer', digest: ClockDigest.of(clocks)).encode(),
      )! as HelloFrame;

      expect(round.digest.likelyInSyncWith(ClockDigest.of(clocks)), isTrue);
      expect(
        round.digest.likelyInSyncWith(ClockDigest.of([at(10, 0, 'a')])),
        isFalse,
      );
    });

    test('clocks carry the readings themselves, in order', () {
      final clocks = [at(10, 0, 'a'), at(20, 1, 'a'), at(30, 0, 'b')];
      final back = WireFrame.parse(ClocksFrame(clocks).encode())! as ClocksFrame;

      expect(back.clocks, clocks);
    });

    test('events come back as the same events, payload included', () {
      final events = [
        Event(hlc: at(1), type: 'stock.bottle.placed', data: {'sku': 'x', 'slot': 3}),
        Event(hlc: at(2), type: 'stock.bottle.consumed', data: {'ml': 45000}),
      ];

      final back = WireFrame.parse(EventsFrame(events).encode())! as EventsFrame;

      expect(back.events, events);
    });

    test('bye carries a reason when there is one and nothing when there is not', () {
      expect((WireFrame.parse(const ByeFrame(reason: 'in sync').encode())! as ByeFrame).reason,
          'in sync');

      final bare = ByeFrame().encode();
      expect(bare.contains('reason'), isFalse, reason: 'an absent reason should not be sent');
      expect((WireFrame.parse(bare)! as ByeFrame).reason, isEmpty);
    });

    test('the kind round-trips for every kind there is', () {
      // Driven off the enum rather than a hand-written list, so a kind added later without a
      // parser case fails here instead of failing on somebody's phone.
      final samples = <WireKind, WireFrame>{
        WireKind.hello:
            const HelloFrame(name: 'n', digest: ClockDigest.fromSummary(count: 0, digest: 0)),
        WireKind.clocks: ClocksFrame([at(1)]),
        WireKind.events: EventsFrame([on(at(1))]),
        WireKind.bye: const ByeFrame(reason: 'r'),
      };

      expect(samples.length, WireKind.values.length);
      for (final entry in samples.entries) {
        expect(WireFrame.parse(entry.value.encode())!.kind, entry.key);
      }
    });
  });

  group('a frame from the network is a claim, so parsing returns null', () {
    test('anything that is not a frame is null rather than an exception', () {
      // Every one of these is something else on the port: a port scanner, an HTTP request, a
      // leftover line from a half-closed connection. Throwing would make any of them a crash.
      for (final junk in [
        '',
        '   ',
        'not json at all',
        '{"unterminated": ',
        '[1,2,3]',
        '"a string"',
        '42',
        'null',
        '{"kind":"hello"}',
        '{"no":"kind"}',
        '{"kind":42}',
      ]) {
        expect(WireFrame.parse(junk), isNull, reason: 'accepted: $junk');
      }
    });

    test('a frame from a newer version is refused rather than guessed at', () {
      // Forward compatibility has one safe answer. A frame whose kind we do not know could mean
      // anything, and the failure that matters is not "we could not read it" but "we read it as
      // something else", so an unknown kind is null and the caller closes the connection.
      expect(WireFrame.parse('{"kind":"events.v2","events":[]}'), isNull);
    });

    test('a well-named frame with an unreadable body is still unreadable', () {
      for (final broken in [
        '{"kind":"hello","count":1,"digest":2}', // no name
        '{"kind":"hello","name":"x","count":"1","digest":2}', // count is a string
        '{"kind":"hello","name":"x","count":1}', // no digest
        '{"kind":"hello","name":"x","count":1,"digest":2,"token":5}', // token is not text
        '{"kind":"clocks"}',
        '{"kind":"clocks","clocks":"nope"}',
        '{"kind":"clocks","clocks":[1,2]}',
        '{"kind":"clocks","clocks":[{"physical":1}]}',
        '{"kind":"events"}',
        '{"kind":"events","events":[{"type":"t"}]}',
        '{"kind":"bye","reason":7}',
      ]) {
        expect(WireFrame.parse(broken), isNull, reason: 'accepted: $broken');
      }
    });

    test('a reading that cannot be parsed does not become a default one', () {
      // The log refuses to guess a clock and so does this, for the same reason: an event placed
      // at an invented reading is history silently reordered. Hlc.fromJson throws, the frame
      // turns that into null, and nothing is merged.
      expect(
        WireFrame.parse(
          '{"kind":"clocks","clocks":[{"physical":1,"counter":0}]}',
        ),
        isNull,
      );
    });
  });

  group('the limits are enforced on the way in', () {
    test('a clocks frame past the cap is refused', () {
      // The receiver allocates per frame, so an unbounded frame is an allocation decided by the
      // other end of a socket. The cap is checked before the items are built, not after.
      final tooMany = [
        for (var i = 0; i <= maxItemsPerFrame; i++) {'physical': i, 'counter': 0, 'node': 'a'},
      ];

      final line = jsonEncode({'kind': 'clocks', 'clocks': tooMany});
      expect(WireFrame.parse(line), isNull);
    });

    test('an events frame past the cap is refused', () {
      final tooMany = [
        for (var i = 0; i <= maxItemsPerFrame; i++)
          {'hlc': {'physical': i, 'counter': 0, 'node': 'a'}, 'type': 't', 'data': <String, Object?>{}},
      ];

      expect(WireFrame.parse(jsonEncode({'kind': 'events', 'events': tooMany})), isNull);
    });

    test('a frame exactly at the cap is accepted, because the cap is the limit', () {
      // Off-by-one in the safe direction is still an off-by-one: a sender that chunks to exactly
      // maxItemsPerFrame would have every last frame refused if the check were `>=`.
      final exact = [
        for (var i = 0; i < maxItemsPerFrame; i++) {'physical': i, 'counter': 0, 'node': 'a'},
      ];

      final back = WireFrame.parse(jsonEncode({'kind': 'clocks', 'clocks': exact}))!;
      expect((back as ClocksFrame).clocks.length, maxItemsPerFrame);
    });
  });
}
