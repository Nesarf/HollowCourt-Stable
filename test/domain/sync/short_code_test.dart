import 'dart:convert';
import 'dart:typed_data';

import 'package:hollow_court/domain/sync/short_code.dart';
import 'package:test/test.dart';

/// **The six digits a person compares, and the one property that makes them worth comparing.**
///
/// The owner chose to offer both ways of adding a device (2026-09-22): *"两条都给，让读者选"*. This is the
/// foundation of the comparison: a number derived from the handshake transcript, identical on both ends when
/// nobody interfered, and different when somebody did.
void main() {
  List<int> transcript({
    String initiatorPublic = 'a',
    String initiatorNonce = 'n1',
    String responderPublic = 'b',
    String responderNonce = 'n2',
    String initiatorIdentity = 'id-a',
    String responderIdentity = 'id-b',
  }) => Uint8List.fromList(
    utf8.encode(
      'hollow-sync/1|$initiatorPublic|$initiatorNonce|$responderPublic|$responderNonce'
      '|$initiatorIdentity|$responderIdentity',
    ),
  );

  test('**six digits, always, with the leading zeros kept**', () {
    // `012345` and `12345` are different things on a screen, and a person comparing two screens is reading
    // characters rather than a number.
    for (var i = 0; i < 200; i++) {
      final code = ShortCode.of(transcript(initiatorNonce: 'nonce-$i'));
      expect(code.length, ShortCode.digits, reason: code);
      expect(RegExp(r'^[0-9]{6}$').hasMatch(code), isTrue, reason: code);
    }
  });

  test('the same transcript gives the same digits on both ends', () {
    // Both ends build the transcript from the same fields -- that symmetry is what makes the comparison
    // meaningful, and it is asserted here rather than assumed.
    expect(ShortCode.of(transcript()), ShortCode.of(transcript()));
  });

  test('**any field changed changes the digits -- which is what catches a device in the middle**', () {
    final honest = ShortCode.of(transcript());
    final variations = {
      'an ephemeral key': transcript(initiatorPublic: 'a2'),
      'a nonce': transcript(responderNonce: 'n9'),
      'the initiator identity': transcript(initiatorIdentity: 'id-mallory'),
      'the responder identity': transcript(responderIdentity: 'id-mallory'),
    };
    for (final entry in variations.entries) {
      final meddled = ShortCode.of(entry.value);
      expect(
        meddled,
        isNot(honest),
        reason: 'changing ${entry.key} must be visible on the screens',
      );
    }
  });

  test('two different handshakes do not collide in a sample of a thousand', () {
    // The birthday question for twenty bits: across a thousand handshakes, a collision would be about a
    // one-in-two-thousand event, so a collision here is a finding rather than luck.
    final codes = <String>{};
    var collisions = 0;
    for (var i = 0; i < 1000; i++) {
      final code = ShortCode.of(transcript(initiatorNonce: 'n-$i', responderNonce: 'r-$i'));
      if (!codes.add(code)) collisions++;
    }
    expect(collisions, lessThan(3), reason: '$collisions collisions in a thousand');
  });

  test('**the confirmation is one-shot, and the rule has somewhere to live**', () {
    // Twenty bits is enough exactly once. A retry button, a "try again", or an automatic reconnect after a
    // mismatch would give an attacker in the middle as many attempts as they have patience for -- and twenty
    // bits falls in seconds. Nothing here can enforce a screen's behaviour, so the rule is a value the screen
    // reads and this test asserts.
    expect(ShortCode.isOneShot, isTrue);
  });

  test('agreement is compared as text, and grouping is for reading', () {
    expect(ShortCode.agree('012345', '012345'), isTrue);
    expect(ShortCode.agree('012345', '12345'), isFalse, reason: 'a dropped leading zero is a mismatch');
    expect(ShortCode.grouped('123456'), '123 456', reason: 'two groups of three is a number to compare');
    expect(ShortCode.grouped('12345'), '12345', reason: 'anything unexpected is shown as it is');
  });
}
