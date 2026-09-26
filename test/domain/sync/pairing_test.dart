import 'package:hollow_court/domain/events/hlc.dart';
import 'package:hollow_court/domain/sync/pairing.dart';
import 'package:test/test.dart';

Hlc at(int millis, [int counter = 0, String node = 'laptop']) =>
    Hlc(physicalMillis: millis, counter: counter, nodeId: node);

void main() {
  group('a pairing ticket is one string a camera can read', () {
    test('it survives being encoded and decoded', () {
      const ticket = PairingTicket(
        host: '192.168.1.42',
        port: 47821,
        token: 'k7fq2m',
        name: '书架',
      );

      final back = PairingTicket.parse(ticket.encode())!;

      expect(back, ticket);
      expect(back.host, '192.168.1.42');
      expect(back.port, 47821);
      expect(back.token, 'k7fq2m');
      expect(back.name, '书架');
    });

    test('a name with spaces survives the query encoding', () {
      // The name is display copy and a reader will type anything into it. A ticket that
      // round-tripped only for names without spaces would fail on the first real one.
      const ticket = PairingTicket(
        host: '10.0.0.5',
        port: 8080,
        token: 'ab12',
        name: 'the small cellar',
      );

      expect(PairingTicket.parse(ticket.encode())!.name, 'the small cellar');
    });

    test('a ticket with no name is legal, because naming is optional', () {
      const ticket = PairingTicket(host: '10.0.0.5', port: 8080, token: 'ab12');

      final back = PairingTicket.parse(ticket.encode())!;

      expect(back.name, isEmpty);
      expect(back, ticket);
    });

    test('renaming a cellar does not invalidate a code already on a screen', () {
      // The name is not part of the identity: it is what the other cellar calls itself, and
      // a reader who renames it has not changed where it is or what the token is. Comparing
      // the encoded strings would say otherwise.
      const before = PairingTicket(
        host: '10.0.0.5',
        port: 8080,
        token: 'ab12',
        name: 'old name',
      );
      const after = PairingTicket(
        host: '10.0.0.5',
        port: 8080,
        token: 'ab12',
        name: 'new name',
      );

      expect(before.sameTargetAs(after), isTrue);
      expect(before == after, isFalse, reason: 'the values still differ');
    });
  });

  group('what parse refuses, and why it returns null rather than throwing', () {
    test('a code that is not ours is null, because that is the common case', () {
      // A scanned code arrives from whatever the camera was pointed at. `OverlayKey.parse`
      // throws because a key comes from this project's own file; a camera does not.
      for (final raw in [
        '',
        '   ',
        'https://example.com',
        'just some text',
        'hollowcourt:',
        'wifi:S:my-network;T:WPA;P:hunter2;;',
      ]) {
        expect(PairingTicket.parse(raw), isNull, reason: raw);
      }
    });

    test('a ticket with no port is refused rather than given a default', () {
      // Inventing a port would be guessing at a fact the code was supposed to carry, and the
      // guess would be wrong on whichever device mattered.
      expect(PairingTicket.parse('hollowcourt://10.0.0.5/ab12'), isNull);
    });

    test('a ticket with no token is refused, because the token is the point', () {
      // Accepting it would quietly disable the one thing the token does. Section 10.3 puts
      // security at this step and a code with no token has no step.
      expect(PairingTicket.parse('hollowcourt://10.0.0.5:8080/'), isNull);
      expect(PairingTicket.parse('hollowcourt://10.0.0.5:8080'), isNull);
    });

    test('a port outside the range is refused', () {
      expect(PairingTicket.parse('hollowcourt://10.0.0.5:0/ab12'), isNull);
      expect(PairingTicket.parse('hollowcourt://10.0.0.5:99999/ab12'), isNull);
    });
  });

  group('a clock digest decides whether to sync at all', () {
    test('the same readings in a different order give the same digest', () {
      // **The rule that makes this usable.** Two devices hold the same events in whatever
      // order they arrived, so an unsorted hash would differ for a pair that agrees about
      // everything -- and the handshake would send a full clock set every time, which is what
      // the digest exists to avoid.
      final a = ClockDigest.of([at(1), at(2), at(3)]);
      final b = ClockDigest.of([at(3), at(1), at(2)]);

      expect(a.likelyInSyncWith(b), isTrue);
      expect(a, b);
    });

    test('one extra reading is a different digest', () {
      final a = ClockDigest.of([at(1), at(2)]);
      final b = ClockDigest.of([at(1), at(2), at(3)]);

      expect(a.likelyInSyncWith(b), isFalse);
      expect(a.count, 2);
      expect(b.count, 3);
    });

    test('the same count with different readings is not in sync', () {
      // The count alone would say these agree. This is the half a count cannot do, and it is
      // why the digest carries a hash as well.
      final a = ClockDigest.of([at(1), at(2)]);
      final b = ClockDigest.of([at(1), at(9)]);

      expect(a.count, b.count);
      expect(a.likelyInSyncWith(b), isFalse);
    });

    test('the same reading from two nodes is two readings', () {
      // A clock reading includes the node, so two devices that happened to read the same
      // millisecond do not hold the same event.
      final a = ClockDigest.of([at(5, 0, 'laptop')]);
      final b = ClockDigest.of([at(5, 0, 'phone')]);

      expect(a.likelyInSyncWith(b), isFalse);
    });

    test('an empty digest is empty, and two empty ones agree', () {
      final a = ClockDigest.of(const []);
      final b = ClockDigest.of(const []);

      expect(a.isEmpty, isTrue);
      expect(a.likelyInSyncWith(b), isTrue);
      expect(a.count, 0);
    });
  });

  group('the short share code a reader types', () {
    // [decision] The owner, 2026-09-23: a share code of at most eighteen characters whose token half the
    // reader chooses, with the code-less path (discovery, then six digits) left as it is. These tests are
    // the format's own contract: what it carries, how long it may be, and what it refuses.

    test('it carries the address, the port and the token, and nothing else is needed', () {
      const ticket = PairingTicket(
        host: '192.168.31.157',
        port: 48123,
        // `RNDK7M`, not `RINDO7`: the alphabet has no `I`, on purpose, so a token containing one is refused as
        // a character a reader could not have meant. The test that chose `RINDO7` was the test being wrong.
        token: 'RNDK7M',
      );

      final code = ticket.shareCode()!;
      final back = PairingTicket.parse(code)!;

      expect(back.host, '192.168.31.157', reason: 'the address travels inside the code');
      expect(back.port, 48123);
      expect(back.token, 'RNDK7M');
    });

    test('**the whole code is between sixteen and eighteen characters**', () {
      const base = PairingTicket(host: '10.0.0.7', port: 65535, token: '');

      expect(base.shareCodeWith('ABCDEF')!.length, 16, reason: 'ten of address and a six-character token');
      expect(base.shareCodeWith('ABCDEFGH')!.length, 18, reason: 'the ceiling the owner set');
      expect(ShareCode.maxCodeLength, 18);
      expect(ShareCode.addressLength, 10);
    });

    test('a hand-copied code survives being read aloud', () {
      // Separators and case carry no information: somebody who grouped the digits, or typed on a keyboard that
      // was not shouting, has still typed the same code. Every one of these is the same ticket.
      const ticket = PairingTicket(host: '192.168.1.42', port: 47821, token: 'K7FQ2M');
      final code = ticket.shareCode()!;
      final grouped = '${code.substring(0, 5)}-${code.substring(5, 10)} ${code.substring(10)}';

      for (final variant in [code, code.toLowerCase(), grouped, grouped.toLowerCase()]) {
        final back = PairingTicket.parse(variant);
        expect(back, isNotNull, reason: variant);
        expect(back!.token, 'K7FQ2M', reason: variant);
        expect(back.port, 47821, reason: variant);
      }
    });

    test('**the letters that look like numbers are not in the alphabet**', () {
      // The four pairs a person mixes up. `0`/`O` and `1`/`I` are the dangerous ones: a code containing either
      // is a code that can be written down wrongly and still look right.
      for (final banned in ['I', 'O', '0', '1']) {
        expect(ShareCode.alphabet.contains(banned), isFalse, reason: banned);
        expect(PairingTicket.parse('A7K3M9XQ2P${banned}BCDEF'), isNull, reason: banned);
      }
    });

    test('**the first two bits are a format version, and an unknown one is refused**', () {
      // Ten characters are fifty bits and the address needs forty-eight, so the spare two bits are the version.
      // A code whose version is not zero must be refused rather than decoded as if it were this format: the
      // alternative is a future code being read as a plausible address today.
      const ticket = PairingTicket(host: '127.0.0.1', port: 1234, token: 'ABCDEF');
      final code = ticket.shareCode()!;

      // The version is the **high** two bits of the first character: ten characters are fifty bits, the address
      // and port take forty-eight, and the spare two are at the top. (The low two bits belong to the port, and
      // putting the version there made the first version of this refuse almost every real port.)
      final firstIndex = ShareCode.alphabet.indexOf(code[0]);
      expect(firstIndex >> 3, ShareCode.addressVersion, reason: 'version zero, in the top two bits');

      // Setting either bit means a format this build does not know, and it must be refused rather than decoded
      // as if it were the current one: the alternative is a future code read as a plausible address today.
      final forged = '${ShareCode.alphabet[firstIndex | 0x10]}${code.substring(1)}';
      expect(PairingTicket.parse(forged), isNull, reason: 'an unknown version');
    });

    test('a token the reader chose has a floor and a ceiling, with reasons', () {
      expect(ShareCode.problemWithToken('ABCDE'), 'short', reason: 'five is below the floor');
      expect(ShareCode.problemWithToken('ABCDEF'), isNull, reason: 'six is what the generator produces');
      expect(ShareCode.problemWithToken('ABCDEFGH'), isNull);
      expect(ShareCode.problemWithToken('ABCDEFGHI'), 'long', reason: 'nine does not fit under eighteen');
      expect(ShareCode.problemWithToken('ABCDE0'), 'character', reason: 'zero is not in the alphabet');
      expect(ShareCode.problemWithToken(''), 'empty');
    });

    test('a host that is not a dotted IPv4 quad has no short code, and keeps its URI', () {
      // IPv6 does not fit in four bytes. Returning null is the honest answer; truncating would produce a code
      // that connects somewhere else, and the URI form still carries the address.
      const v6 = PairingTicket(host: 'fe80::1', port: 48123, token: 'ABCDEF');
      expect(v6.shareCode(), isNull);
      expect(PairingTicket.parse(v6.encode())!.host, 'fe80::1', reason: 'the URI still works');

      const named = PairingTicket(host: 'laptop.local', port: 48123, token: 'ABCDEF');
      expect(named.shareCode(), isNull);
    });

    test('**the URI still parses, because the short form would lose the repair**', () {
      // `syncEditHostHint` tells a reader they can correct the address inside the code when a host guessed the
      // wrong interface. A short code has no address to correct by hand, so the URI form has to keep working
      // or that route disappears.
      const uri = 'hollowcourt://192.168.31.157:48123/K7FQ2M?name=laptop';
      final parsed = PairingTicket.parse(uri)!;
      expect(parsed.host, '192.168.31.157');
      expect(parsed.token, 'K7FQ2M');
      expect(parsed.name, 'laptop');
    });

    test('a code of the wrong length is refused rather than guessed at', () {
      expect(PairingTicket.parse('A7K3M9XQ2PABCDE'), isNull, reason: 'fifteen characters');
      expect(PairingTicket.parse('A7K3M9XQ2PABCDEFGHI'), isNull, reason: 'nineteen characters');
      expect(PairingTicket.parse(''), isNull);
      expect(PairingTicket.parse('not a code at all'), isNull);
    });
  });
}
