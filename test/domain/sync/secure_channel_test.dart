import 'dart:async';
import 'dart:convert';

import 'package:hollow_court/domain/sync/device_identity.dart';
import 'package:hollow_court/domain/sync/exchange.dart';
import 'package:hollow_court/domain/sync/secure_channel.dart';
import 'package:test/test.dart';

/// One end of an in-memory connection, in the shape `exchange_test.dart` uses.
///
/// Not a mock: a real duplex pair with a queue, so what is asserted below is what actually crossed.
final class _Channel implements WireChannel {
  final StreamController<String> _in = StreamController<String>();

  _Channel? peer;

  /// Every line this end put on the wire, so a test can look for plaintext.
  final List<String> sent = [];

  bool _closed = false;

  static (_Channel, _Channel) pair() {
    final a = _Channel();
    final b = _Channel();
    a.peer = b;
    b.peer = a;
    return (a, b);
  }

  @override
  Stream<String> get lines => _in.stream;

  @override
  void sendLine(String line) {
    if (_closed) throw StateError('sent on a closed connection');
    sent.add(line);
    final other = peer;
    if (other != null && !other._in.isClosed) other._in.add(line);
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    final other = peer;
    if (other != null && !other._in.isClosed) unawaited(other._in.close());
    if (!_in.isClosed) unawaited(_in.close());
  }
}

void main() {
  /// Runs both handshakes against each other.
  ///
  /// **The raw channels come back with the results**, because two of the tests below play the part of
  /// an attacker and an attacker writes to the wire rather than through a sealed channel -- a
  /// `SecureChannel` cannot produce a frame with a counter it has already used or a tag it did not
  /// compute, which is exactly what those tests need to send.
  Future<(SecureHandshake, SecureHandshake, _Channel, _Channel)> meet({
    String initiatorSecret = 'ABC123',
    String responderSecret = 'ABC123',
  }) async {
    final (a, b) = _Channel.pair();
    final results = await Future.wait([
      SecureChannel.handshake(
        a,
        role: ExchangeRole.initiator,
        secret: initiatorSecret,
      ),
      SecureChannel.handshake(
        b,
        role: ExchangeRole.responder,
        secret: responderSecret,
      ),
    ]);
    return (results[0], results[1], a, b);
  }

  test('**both ends of a real handshake show the same six digits**', () async {
    // The comparison the owner chose to offer (2026-09-22) rests on this: two devices that met without
    // interference derive the same number from the transcript each of them signed, so a person looking at both
    // screens sees one number. It is asserted over a real pair rather than over `ShortCode` alone, because the
    // interesting risk is not the hash -- it is the two ends building different transcripts from the same
    // conversation, which is exactly what the initiator/responder asymmetry could cause.
    final (a, b, _, _) = await meet();
    expect(a.shortCode, isNotEmpty);
    expect(a.shortCode, b.shortCode);
    expect(a.shortCode.length, 6);
  });

  test('and two different handshakes do not show the same digits, even with the same code', () async {
    // Same pairing code, two connections: different ephemeral keys, so different transcripts, so different
    // numbers. This is what a relay cannot fake -- it cannot make two spliced halves agree.
    final (first, _, _, _) = await meet();
    final (second, _, _, _) = await meet();
    expect(first.shortCode, isNot(second.shortCode));
  });

  /// Both handshakes over one pair, with identities and expectations where the tests need them.
  Future<(SecureHandshake, SecureHandshake)> meetWith({
    DeviceIdentity? initiator,
    DeviceIdentity? responder,
    String initiatorSecret = 'ABC123',
    String responderSecret = 'ABC123',
    String initiatorExpected = '',
    String responderExpected = '',
  }) async {
    final (a, b) = _Channel.pair();
    final results = await Future.wait([
      SecureChannel.handshake(
        a,
        role: ExchangeRole.initiator,
        secret: initiatorSecret,
        identity: initiator,
        expectedIdentity: initiatorExpected,
      ),
      SecureChannel.handshake(
        b,
        role: ExchangeRole.responder,
        secret: responderSecret,
        identity: responder,
        expectedIdentity: responderExpected,
      ),
    ]);
    return (results[0], results[1]);
  }

  group('two devices that know the same code seal the connection', () {
    test('the handshake completes on both sides and a frame travels sealed', () async {
      final (phone, laptop, phoneWire, laptopWire) = await meet();

      expect(phone.succeeded, isTrue, reason: phone.failure);
      expect(laptop.succeeded, isTrue, reason: laptop.failure);
      expect(phone.authenticated, isTrue);
      expect(laptop.authenticated, isTrue);

      // Both directions, because the two keys are derived independently: a bug that used one key
      // twice would still let one direction work.
      final heard = <String>[];
      final subscription = laptop.lines!.listen(heard.add);

      phone.channel!.sendLine('from the phone');
      // The seal is asynchronous, so the test yields rather than assuming.
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(heard, ['from the phone']);

      final back = <String>[];
      final other = phone.lines!.listen(back.add);
      laptop.channel!.sendLine('from the laptop');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(back, ['from the laptop']);

      await subscription.cancel();
      await other.cancel();
    });

    test('and nothing readable is on the wire', () async {
      // **The point of the whole file**, checked the only way a test can: the plaintext that was
      // sent is not present in the bytes that crossed. A frame carries a clock digest at the start of
      // an exchange, which is a summary of the entire cellar -- so this is what the cafe's wifi
      // listener was previously able to read.
      final (a, b) = _Channel.pair();
      final results = await Future.wait([
        SecureChannel.handshake(a, role: ExchangeRole.initiator, secret: 'ABC123'),
        SecureChannel.handshake(b, role: ExchangeRole.responder, secret: 'ABC123'),
      ]);
      expect(results.every((r) => r.succeeded), isTrue);

      const secretText = 'the cellar holds four bottles of gin';
      results[0].channel!.sendLine(secretText);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final wire = a.sent.join('\n');
      expect(wire, isNot(contains(secretText)));
      expect(wire, isNot(contains('gin')));
      // And it is still decodable by the peer, so the assertion above is about encryption rather
      // than about nothing having been sent.
      final heard = <String>[];
      final sub = results[1].lines!.listen(heard.add);
      await Future<void>.delayed(Duration.zero);
      expect(heard, [secretText]);
      await sub.cancel();
    });
  });

  group('a peer that cannot prove the code is refused', () {
    test('the wrong code fails the handshake on both sides', () async {
      final (phone, laptop, _, _) = await meet(
        initiatorSecret: 'ABC123',
        responderSecret: 'XYZ789',
      );

      expect(phone.succeeded, isFalse);
      expect(laptop.succeeded, isFalse);
      // The message a person reads, and it has to be about the code rather than about a protocol.
      expect(phone.failure, 'the pairing code did not match');
      expect(laptop.failure, 'the pairing code did not match');
    });

    test('a peer speaking the plaintext protocol is refused, not guessed at', () async {
      // What an older build sends: a bare JSON hello with no handshake in front of it.
      //
      // **Started before the line is sent, and awaited after.** The first version awaited the
      // handshake first, which waits for a line that nothing had sent yet -- the test deadlocked
      // itself rather than testing anything, and the only symptom was a thirty-second pause.
      final (older, sealed) = _Channel.pair();
      final pending = SecureChannel.handshake(
        sealed,
        role: ExchangeRole.responder,
        secret: 'ABC123',
      );

      older.sendLine(jsonEncode({'t': 'hello', 'name': 'an older build'}));
      final result = await pending;

      expect(result.succeeded, isFalse);
      expect(result.failure, 'the other end did not open with a sealed handshake');
    });

    test('a peer that says nothing does not hold the connection forever', () async {
      final (silent, waiting) = _Channel.pair();
      // Nothing is ever sent on `silent`.
      final result = await SecureChannel.handshake(
        waiting,
        role: ExchangeRole.responder,
        secret: 'ABC123',
        timeout: const Duration(milliseconds: 50),
      );

      expect(result.succeeded, isFalse);
      expect(silent.sent, isEmpty);
    });
  });

  group('a sealed frame that was interfered with is dropped', () {
    test('a flipped byte in the ciphertext is not delivered', () async {
      final (phone, laptop, phoneWire, laptopWire) = await meet();
      final heard = <String>[];
      final sub = laptop.lines!.listen(heard.add);

      phone.channel!.sendLine('a legitimately sent line');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(heard, hasLength(1));

      // Now the same frame with one bit changed, as an attacker in the middle would do. The tag is
      // the only thing standing between the peer and decoding it, so this is the assertion that says
      // the tag is checked.
      final tampered = _flipFirstPayloadByte(phoneWire.sent.last);
      phoneWire.sendLine(tampered);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(heard, hasLength(1), reason: 'the tampered frame was not delivered');
      await sub.cancel();
    });

    test('a frame repeated out of order is refused', () async {
      // Replay is the other half: the counter is checked rather than tolerated, so the second copy of
      // a frame the peer has already read is not a frame it will read twice.
      final (phone, laptop, phoneWire, laptopWire) = await meet();
      final heard = <String>[];
      final sub = laptop.lines!.listen(heard.add);

      phone.channel!.sendLine('one');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      final first = phoneWire.sent.last;

      phone.channel!.sendLine('two');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(heard, ['one', 'two']);

      // Re-send the FIRST frame: a valid frame under the right key, with a counter already used.
      // Written to the raw channel, because that is what an attacker in the middle can do -- the
      // sealed channel would never produce a counter it has already used.
      phoneWire.sendLine(first);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(heard, ['one', 'two'], reason: 'the replay changed nothing');
      await sub.cancel();
    });
  });

  group('a device that was learned once is recognised without a code', () {
    test('the second connection is authenticated by the key, not by six characters', () async {
      // **What section 10.3 means by "long-term keys are exchanged during pairing".** The first
      // meeting is authenticated by the code; the key each side offers during it is what the other
      // remembers; from then on no human has to stand at two screens.
      final phone = await DeviceIdentity.generate();
      final laptop = await DeviceIdentity.generate();

      // First meeting: the code, and a key learned by each side.
      final (firstPhone, firstLaptop) = await meetWith(
        initiator: phone,
        responder: laptop,
      );
      expect(firstPhone.succeeded, isTrue, reason: firstPhone.failure);
      expect(firstLaptop.succeeded, isTrue, reason: firstLaptop.failure);
      expect(firstPhone.peerIdentity, laptop.publicKey);
      expect(firstLaptop.peerIdentity, phone.publicKey);

      // Second meeting: no code at all, and each side requires the key it learned.
      final (again, back) = await meetWith(
        initiator: phone,
        responder: laptop,
        initiatorSecret: '',
        responderSecret: '',
        initiatorExpected: laptop.publicKey,
        responderExpected: phone.publicKey,
      );
      expect(again.succeeded, isTrue, reason: again.failure);
      expect(back.succeeded, isTrue, reason: back.failure);
      expect(
        again.authenticated,
        isTrue,
        reason: 'a remembered key authenticates the connection as surely as a code does',
      );
    });

    test('a device with the wrong key is refused, and the reason says so', () async {
      final phone = await DeviceIdentity.generate();
      final laptop = await DeviceIdentity.generate();
      // Somebody else entirely, holding a valid key that this device has never learned.
      final stranger = await DeviceIdentity.generate();

      final (fromPhone, fromLaptop) = await meetWith(
        initiator: phone,
        responder: stranger,
        initiatorExpected: laptop.publicKey,
        responderExpected: phone.publicKey,
      );

      expect(fromPhone.succeeded, isFalse);
      expect(fromPhone.failure, 'that is not the device this one remembers');
      expect(fromLaptop.succeeded, isFalse);
    });

    test('a device that claims a remembered key without holding it is refused', () async {
      // The interesting attack: the public key is not a secret, so an attacker can *claim* the key of
      // a device this one remembers. What it cannot produce is the proof, which is a MAC under the
      // static-static secret between the two long-term keys.
      final phone = await DeviceIdentity.generate();
      final laptop = await DeviceIdentity.generate();
      final liar = await DeviceIdentity.generate();

      final (fromLiar, fromHonest) = await meetWith(
        initiator: liar,
        responder: laptop,
        initiatorExpected: laptop.publicKey,
        responderExpected: phone.publicKey,
      );

      expect(fromHonest.succeeded, isFalse, reason: 'the honest side refuses the impostor');
      expect(fromHonest.failure, 'that is not the device this one remembers');
      expect(
        fromLiar.succeeded,
        isFalse,
        reason: 'and the impostor learns it was refused, rather than believing it got in',
      );
    });

    test('the fingerprint is stable, and different for different keys', () async {
      // What two screens can be compared against. Not a secret, and not used for any key derivation.
      final a = await DeviceIdentity.generate();
      final b = await DeviceIdentity.fromSeed(await a.seed());

      expect(b.publicKey, a.publicKey, reason: 'a rebuilt identity is the same device');
      expect(b.fingerprint, a.fingerprint);
      expect((await DeviceIdentity.generate()).fingerprint, isNot(a.fingerprint));
      expect(a.fingerprint, matches(RegExp(r'^[A-Z2-9]{4}(-[A-Z2-9]{4}){3}$')));
    });
  });

  test('a connection with no code is encrypted but its peer is unidentified', () async {
    // A development sync on a trusted network: still confidential, and the result says so rather
    // than letting a caller assume either way.
    final (phone, laptop, _, _) = await meet(initiatorSecret: '', responderSecret: '');

    expect(phone.succeeded, isTrue, reason: phone.failure);
    expect(laptop.succeeded, isTrue, reason: laptop.failure);
    expect(phone.authenticated, isFalse);
    expect(laptop.authenticated, isFalse);
  });
}

/// Flips one bit of a frame's ciphertext, leaving the base64 well-formed and the tag untouched.
String _flipFirstPayloadByte(String frame) {
  final packed = base64.decode(frame);
  // Byte 12 is the first byte after the 12-byte nonce, so it is ciphertext rather than framing.
  packed[12] = packed[12] ^ 0x01;
  return base64.encode(packed);
}
