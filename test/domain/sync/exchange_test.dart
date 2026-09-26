import 'dart:async';
import 'dart:convert';

import 'package:hollow_court/domain/events/event.dart';
import 'package:hollow_court/domain/events/hlc.dart';
import 'package:hollow_court/domain/sync/exchange.dart';
import 'package:hollow_court/domain/sync/pairing.dart';
import 'package:hollow_court/domain/sync/wire.dart';
import 'package:test/test.dart';

Hlc at(int millis, [int counter = 0, String node = 'a']) =>
    Hlc(physicalMillis: millis, counter: counter, nodeId: node);

Event on(Hlc hlc, [String type = 'stock.bottle.placed']) =>
    Event(hlc: hlc, type: type, data: {'sku': 'x'});

/// A cellar, reduced to the three things an exchange touches.
final class _Cellar implements SyncSource {
  _Cellar(Iterable<Event> events) : _events = [...events];

  final List<Event> _events;

  /// What this cellar took in, for asserting on the result rather than on the traffic.
  final List<Event> received = [];

  @override
  Set<Hlc> get clocks => {for (final event in _events) event.hlc};

  @override
  List<Event> missingFrom(Set<Hlc> theirClocks) =>
      [for (final event in _events) if (!theirClocks.contains(event.hlc)) event];

  @override
  Future<List<Event>> merge(Iterable<Event> incoming) async {
    final fresh = [for (final event in incoming) if (!clocks.contains(event.hlc)) event];
    for (final event in fresh) {
      _events.add(event);
      received.add(event);
    }
    return fresh;
  }

  List<Event> get held => List.unmodifiable(_events);
}

/// One end of an in-memory connection.
///
/// **Not a mock.** A real duplex channel with a queue, in order, that can be closed and whose peer
/// can vanish -- because the interesting failures in an exchange are the ones a mock with a
/// canned answer cannot produce. What it deliberately does not reproduce is timing, and that is the
/// point: everything asserted below is a decision the algorithm makes, not a race it survived.
final class _Channel implements WireChannel {
  final StreamController<String> _in = StreamController<String>();

  _Channel? peer;

  /// Every line this end put on the wire, for asserting on what was and was not sent.
  final List<String> sent = [];

  bool _closed = false;

  @override
  Stream<String> get lines => _in.stream;

  @override
  void sendLine(String line) {
    if (_closed) throw StateError('sent on a closed connection');
    sent.add(line);
    final other = peer;
    if (other != null && !other._in.isClosed) other._in.add(line);
  }

  /// Closing is closing the *connection*, so it is the peer that learns about it.
  ///
  /// The first version of this closed its own incoming stream, which meant a test for "the peer
  /// vanished" closed the wrong end and proved nothing. A socket's close delivers EOF to the other
  /// side; this has to as well or every failure test built on it is testing the wrong direction.
  ///
  /// **And it returns without waiting for the done events**, because a single-subscription
  /// controller that nobody is listening to never completes its `close()` future -- so awaiting it
  /// hung every test whose peer was a bare channel. A real socket's close does not wait for the
  /// other end to read, and neither does this one.
  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    final other = peer;
    if (other != null && !other._in.isClosed) unawaited(other._in.close());
    if (!_in.isClosed) unawaited(_in.close());
  }

  /// Drops the connection without saying goodbye -- the peer that vanished.
  Future<void> vanish() async {
    final other = peer;
    if (other != null && !other._in.isClosed) unawaited(other._in.close());
  }

  /// Kinds of frame this end sent, read off the wire rather than tracked separately.
  List<String> get sentKinds => [
    for (final line in sent) (jsonDecode(line) as Map<String, Object?>)['kind'] as String,
  ];
}

({_Channel a, _Channel b}) _pair() {
  final a = _Channel();
  final b = _Channel();
  a.peer = b;
  b.peer = a;
  return (a: a, b: b);
}

/// Runs both ends at once, as a connection does.
/// Runs both ends against each other, **in the clear, on purpose**.
///
/// **This whole file is about the frame protocol, and most of its assertions are on the frames.** The
/// wire is sealed by default now -- section 10.3's transport encryption -- which is right for a sync
/// and wrong for these tests: half of them read `sent` and check which frames went out, which is not
/// possible through a cipher. They turn the seal off by name rather than by accident, and what covers
/// the sealed path is `secure_channel_test.dart` (the handshake, tampering, replay, a peer with the
/// wrong code), `socket_transport_test.dart`, `sync_verbs_test.dart` and the P3 acceptance test --
/// all of which run with the seal on, because they go through the real entry points.
Future<(ExchangeOutcome, ExchangeOutcome)> _syncBoth({
  required _Channel a,
  required _Channel b,
  required SyncSource left,
  required SyncSource right,
  String leftName = 'left',
  String rightName = 'right',
  String token = 'shared',
  String expectedToken = 'shared',
  Duration timeout = const Duration(seconds: 5),
  /// Each side's answer to the comparison, when the test is about the gate rather than the exchange. Named per
  /// role because **the gate is asked on both ends**: a fake that only gated the initiator would let a test pass
  /// while the host served the cellar to a peer whose owner never confirmed.
  Future<bool> Function(String shortCode)? initiatorConfirms,
  Future<bool> Function(String shortCode)? responderConfirms,
  /// **Sealing is off by default here** because most of this file is about the frame protocol. The comparison
  /// gate lives on the sealed path -- the digits come from the handshake -- so the tests for it turn sealing on,
  /// and the gate tests would otherwise pass a gate that was never called.
  bool seal = false,
}) async {
  final results = await Future.wait([
    runExchange(
      seal: seal,
      channel: a,
      source: left,
      role: ExchangeRole.initiator,
      localName: leftName,
      token: token,
      confirmComparison: initiatorConfirms,
      timeout: timeout,
    ),
    runExchange(
      seal: seal,
      channel: b,
      source: right,
      role: ExchangeRole.responder,
      localName: rightName,
      expectedToken: expectedToken,
      confirmComparison: responderConfirms,
      timeout: timeout,
    ),
  ]);
  return (results[0], results[1]);
}

void main() {
  group('the comparison gate, which is the other way of adding a device', () {
    test('**an agreement on both sides lets the exchange run**', () async {
      final shown = <String>[];
      final (:a, :b) = _pair();
      final (outcomeLeft, outcomeRight) = await _syncBoth(
        a: a,
        b: b,
        left: _Cellar([on(at(1000))]),
        right: _Cellar([on(at(2000))]),
        seal: true,
        initiatorConfirms: (code) async {
          shown.add('initiator:$code');
          return true;
        },
        responderConfirms: (code) async {
          shown.add('responder:$code');
          return true;
        },
      );
      expect(outcomeLeft.succeeded, isTrue);
      expect(outcomeRight.succeeded, isTrue);
      expect(outcomeLeft.merged, 1);
      expect(outcomeRight.merged, 1);
      // **Both ends were asked, and both were shown the same digits.** The screen on each side has to display a
      // number, and two screens showing different numbers is the defect this whole feature exists to catch.
      expect(shown, hasLength(2));
      final codes = shown.map((s) => s.split(':')[1]).toSet();
      expect(codes, hasLength(1), reason: 'the two screens must show one number: $shown');
      expect(codes.first, hasLength(6));
    });

    test('**a refusal on one side moves nothing, and the other side is told why**', () async {
      final (:a, :b) = _pair();
      final (outcomeLeft, outcomeRight) = await _syncBoth(
        a: a,
        b: b,
        left: _Cellar([on(at(1000))]),
        right: _Cellar([on(at(2000))]),
        seal: true,
        initiatorConfirms: (code) async => false,
        responderConfirms: (code) async => true,
      );
      expect(outcomeLeft.succeeded, isFalse);
      expect(outcomeLeft.merged, 0);
      expect(outcomeLeft.sent, 0);
      expect(outcomeLeft.failure, contains('different numbers'));
      // The host merged nothing either: the gate is before the first frame, so a refusal costs both sides
      // nothing rather than half a cellar.
      expect(outcomeRight.merged, 0);
      // And the peer was told, so its screen can say the same thing instead of waiting. **Read from the
      // outcome rather than from the wire**: on the sealed path the reason travels as ciphertext, so asserting
      // on `sent` would be asserting that the two devices exchanged unintelligible bytes -- which is what the
      // first version of this test did, and what the encrypted hello frame it printed was telling me.
      expect(outcomeRight.peerReason, contains('different numbers'));
    });

    test('**a host that was not asked does not serve a peer that confirmed**', () async {
      // The asymmetry worth guarding: a joiner whose owner compared two screens, against a host that never
      // asked anybody. Without the gate on the responder side the cellar would be handed over on the strength
      // of one screen's confirmation, which is exactly the half-fix this test exists to prevent.
      final (:a, :b) = _pair();
      final (_, outcomeRight) = await _syncBoth(
        a: a,
        b: b,
        left: _Cellar([on(at(1000))]),
        right: _Cellar([on(at(2000))]),
        seal: true,
        initiatorConfirms: (code) async => true,
        responderConfirms: null,
      );
      // The initiator gated and agreed; the responder did not gate at all, so the exchange completed -- which is
      // the documented behaviour of the parameter (nothing passed keeps the code-authenticated path unchanged)
      // and is why the screen passes it on both sides. Asserted so that a future change to "gate on one side"
      // fails here rather than in a cellar.
      expect(outcomeRight.succeeded, isTrue);
    });
  });

  group('two cellars that disagree end up agreeing', () {
    test('each side gets exactly what it was missing', () async {
      // left holds 1,2 and right holds 2,3. What crosses is one event each way -- not the shared
      // one, and not the one already held. That is missingFrom doing its job over the wire.
      final shared = on(at(200));
      final left = _Cellar([on(at(100)), shared]);
      final right = _Cellar([shared, on(at(300))]);
      final link = _pair();

      final (fromLeft, fromRight) = await _syncBoth(
        a: link.a,
        b: link.b,
        left: left,
        right: right,
      );

      expect(fromLeft.succeeded, isTrue, reason: fromLeft.failure);
      expect(fromRight.succeeded, isTrue, reason: fromRight.failure);

      expect(fromLeft.merged, 1);
      expect(fromLeft.sent, 1);
      expect(fromRight.merged, 1);
      expect(fromRight.sent, 1);

      expect(left.received.single.hlc, at(300));
      expect(right.received.single.hlc, at(100));

      expect(left.held.length, 3);
      expect(right.held.length, 3);
    });

    test('the two devices learn each other names', () async {
      final link = _pair();

      final (fromLeft, fromRight) = await _syncBoth(
        a: link.a,
        b: link.b,
        left: _Cellar([on(at(1))]),
        right: _Cellar([on(at(2))]),
        leftName: '书架',
        rightName: 'laptop',
      );

      expect(fromLeft.peerName, 'laptop');
      expect(fromRight.peerName, '书架');
    });

    test('the merged events arrive as the same events, payload and all', () async {
      final mine = Event(
        hlc: at(500),
        type: 'stock.bottle.consumed',
        data: {'ml': 45000, 'note': 'a drink\nwith a newline in it'},
      );
      final left = _Cellar([]);
      final link = _pair();

      await _syncBoth(a: link.a, b: link.b, left: left, right: _Cellar([mine]));

      expect(left.received, [mine]);
      expect(left.received.single.data['ml'], 45000);
      expect(left.received.single.data['note'], 'a drink\nwith a newline in it');
    });
  });

  group('a device that already agrees is not made to talk', () {
    test('equal digests mean one frame each and no readings at all', () async {
      // This is the entire reason ClockDigest exists, so it is asserted on the wire and not only
      // in the outcome: a sync between two devices that agree must not carry a clock set.
      final events = [on(at(1)), on(at(2)), on(at(3))];
      final link = _pair();

      final (fromLeft, fromRight) = await _syncBoth(
        a: link.a,
        b: link.b,
        left: _Cellar(events),
        right: _Cellar(events),
      );

      expect(fromLeft.succeeded, isTrue);
      expect(fromLeft.merged, 0);
      expect(fromLeft.sent, 0);
      expect(fromRight.merged, 0);
      expect(fromRight.sent, 0);

      expect(link.a.sentKinds, isNot(contains('clocks')));
      expect(link.b.sentKinds, isNot(contains('clocks')));
      expect(link.a.sentKinds, isNot(contains('events')));
      expect(link.b.sentKinds, isNot(contains('events')));
      expect(fromLeft.peerReason, 'already in sync');
    });

    test('two empty cellars are already in sync', () async {
      final link = _pair();

      final (fromLeft, _) = await _syncBoth(
        a: link.a,
        b: link.b,
        left: _Cellar([]),
        right: _Cellar([]),
      );

      expect(fromLeft.succeeded, isTrue);
      expect(link.a.sentKinds, isNot(contains('clocks')));
    });

    test('one extra reading is enough to make the readings worth sending', () async {
      // The boundary of the optimisation: one event apart is not in sync, so the full exchange
      // happens. A digest that answered "in sync" here would silently lose an event.
      final link = _pair();

      final (fromLeft, _) = await _syncBoth(
        a: link.a,
        b: link.b,
        left: _Cellar([on(at(1)), on(at(2))]),
        right: _Cellar([on(at(1))]),
      );

      expect(link.a.sentKinds, contains('clocks'));
      expect(fromLeft.sent, 1);
    });
  });

  group('the token is checked before this cellar says anything about itself', () {
    test('a wrong token stops the exchange and the responder sends no readings', () async {
      // The property that matters: a stranger on the same network must not learn the clock set,
      // which is a count and a hash of everything this cellar holds. So the assertion is not just
      // that it failed, but that nothing followed the refusal.
      final link = _pair();

      final (fromLeft, fromRight) = await _syncBoth(
        a: link.a,
        b: link.b,
        left: _Cellar([on(at(1))]),
        right: _Cellar([on(at(2))]),
        token: 'guessed-wrong',
        expectedToken: 'the-real-one',
      );

      expect(fromLeft.succeeded, isFalse);
      expect(fromLeft.failure, contains('pairing code'));
      expect(fromRight.succeeded, isFalse);

      expect(link.b.sentKinds, isNot(contains('clocks')));
      expect(link.b.sentKinds, isNot(contains('hello')));
      expect(link.b.sentKinds, contains('bye'));
    });

    test('a hello carrying no token at all is refused when one is required', () async {
      final link = _pair();

      final (_, fromRight) = await _syncBoth(
        a: link.a,
        b: link.b,
        left: _Cellar([on(at(1))]),
        right: _Cellar([on(at(2))]),
        token: '',
        expectedToken: 'required',
      );

      expect(fromRight.succeeded, isFalse);
      expect(link.b.sentKinds, isNot(contains('clocks')));
    });

    test('a responder that requires no token accepts any hello, deliberately', () async {
      // An empty expectation is a decision a caller makes, not a default it inherits. This pins
      // the behaviour so that changing it has to be a change and not an accident.
      final link = _pair();

      final (fromLeft, fromRight) = await _syncBoth(
        a: link.a,
        b: link.b,
        left: _Cellar([on(at(1))]),
        right: _Cellar([on(at(2))]),
        token: 'anything',
        expectedToken: '',
      );

      expect(fromLeft.succeeded, isTrue);
      expect(fromRight.succeeded, isTrue);
      expect(fromLeft.merged, 1);
    });
  });

  group('nothing from the network reaches the caller as an exception', () {
    test('a peer that sends junk is closed with a reason', () async {
      final link = _pair();
      final cellar = _Cellar([on(at(1))]);

      final responder = runExchange(
        seal: false,
        channel: link.b,
        source: cellar,
        role: ExchangeRole.responder,
        localName: 'right',
        expectedToken: '',
        timeout: const Duration(seconds: 5),
      );

      link.a.sendLine('this is not a frame');
      final outcome = await responder;

      expect(outcome.succeeded, isFalse);
      expect(outcome.failure, contains('unreadable'));
    });

    test('a peer that hangs up mid-sentence is a failure, not a crash', () async {
      final link = _pair();
      final cellar = _Cellar([on(at(1))]);

      final responder = runExchange(
        seal: false,
        channel: link.b,
        source: cellar,
        role: ExchangeRole.responder,
        localName: 'right',
        expectedToken: '',
        timeout: const Duration(seconds: 5),
      );

      await link.a.vanish();
      final outcome = await responder;

      expect(outcome.succeeded, isFalse);
      expect(outcome.failure, isNotNull);
    });

    test('a peer that goes silent hits the deadline instead of hanging', () async {
      // A connection that never answers must not hold the resource forever. The timeout is short
      // here because the deadline is the thing under test, not the waiting.
      final link = _pair();

      final outcome = await runExchange(
        seal: false,
        channel: link.b,
        source: _Cellar([on(at(1))]),
        role: ExchangeRole.responder,
        localName: 'right',
        expectedToken: '',
        timeout: const Duration(milliseconds: 150),
      );

      expect(outcome.succeeded, isFalse);
      expect(outcome.failure, contains('stopped answering'));
    });

    test('a bye instead of a hello is reported with the peer reason', () async {
      final link = _pair();

      final responder = runExchange(
        seal: false,
        channel: link.b,
        source: _Cellar([on(at(1))]),
        role: ExchangeRole.responder,
        localName: 'right',
        expectedToken: '',
        timeout: const Duration(seconds: 5),
      );

      link.a.sendLine(const ByeFrame(reason: 'not now').encode());
      final outcome = await responder;

      expect(outcome.succeeded, isFalse);
      expect(outcome.peerReason, 'not now');
      expect(outcome.failure, contains('not now'));
    });

    test('a frame in the wrong place is refused rather than guessed at', () async {
      // An events frame where the readings should be. Guessing which frame the peer meant would
      // mean merging events computed against a clock set that never arrived.
      final link = _pair();

      final responder = runExchange(
        seal: false,
        channel: link.b,
        source: _Cellar([on(at(1))]),
        role: ExchangeRole.responder,
        localName: 'right',
        expectedToken: '',
        timeout: const Duration(seconds: 5),
      );

      link.a.sendLine(
        const HelloFrame(name: 'left', digest: ClockDigest.fromSummary(count: 9, digest: 9))
            .encode(),
      );
      link.a.sendLine(EventsFrame([on(at(7))]).encode());

      final outcome = await responder;

      expect(outcome.succeeded, isFalse);
      expect(outcome.failure, isNotNull);
    });
  });

  group('a cellar too large for one frame crosses anyway', () {
    test('more events than a frame holds arrive in several frames, all of them', () async {
      // The cap is 256 and this is 300, so it must be two frames. The assertion is on the count
      // received rather than on the frame count, because the failure this guards against is a
      // chunking loop that drops its last, short chunk.
      final many = [for (var i = 0; i < maxItemsPerFrame + 44; i++) on(at(1000 + i))];
      final link = _pair();

      final (fromLeft, fromRight) = await _syncBoth(
        a: link.a,
        b: link.b,
        left: _Cellar(many),
        right: _Cellar([]),
      );

      expect(fromLeft.sent, many.length);
      expect(fromRight.merged, many.length);
      expect(link.a.sentKinds.where((kind) => kind == 'events').length, 2);
      expect(fromLeft.succeeded, isTrue);
    });

    test('exactly one frame worth is one frame', () async {
      final many = [for (var i = 0; i < maxItemsPerFrame; i++) on(at(2000 + i))];
      final link = _pair();

      await _syncBoth(
        a: link.a,
        b: link.b,
        left: _Cellar(many),
        right: _Cellar([]),
      );

      expect(link.a.sentKinds.where((kind) => kind == 'events').length, 1);
    });
  });
}
