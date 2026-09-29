import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/dart.dart';

/// **The six digits two screens show, so a person can decide whether the devices found each other.**
///
/// This is the second way to add a device, beside the pairing code, and the owner chose to offer both
/// (2026-09-22): *"两条都给，让读者选"*. The two answer the same question -- **"is the device I am talking to the
/// device you are looking at?"** -- and they answer it under different conditions:
///
/// | | code | these six digits |
/// | --- | --- | --- |
/// | what somebody does | reads one screen and types into the other | looks at both and presses one button |
/// | needs | only one screen visible | **both screens visible at once** |
/// | protects by | a shared secret the peer must know | a value bound to *this* handshake |
///
/// **Neither is encryption.** The channel is already sealed (X25519, HKDF, AES-GCM) and this adds nothing to
/// it. What it protects against is a device in the middle of the *first* meeting, and it does it differently
/// from the code: a relay cannot produce two identical transcripts, so the two ends derive different digits and
/// the person in front of the screens sees it. The code cannot catch that, because a relay that knows the code
/// passes it along -- which is why the comparison is the stronger of the two and why it is the one offered
/// first.
///
/// ## Six digits, and why not more
///
/// Six decimal digits is about **twenty bits**. That is not a lot, and it is enough **exactly once**: an
/// attacker in the middle gets one attempt per handshake, and a wrong guess is visible on both screens. The
/// rule that follows is not a preference -- **the confirmation must be one-shot**. A retry loop, a "try again",
/// or an automatic reconnect after a mismatch would hand the attacker as many attempts as they have patience
/// for, and twenty bits falls in seconds. `ShortCode.isOneShot` exists so the rule has somewhere to live.
///
/// More digits would be stronger and worse: this is a number a person compares by eye across a table, and the
/// value of the comparison is that it actually happens. Bluetooth settled on six for the same reason.
///
/// ## What it is derived from
///
/// The handshake transcript: both ephemeral public keys, both nonces and both long-term identities, in the
/// order both ends agree on. Not from the shared secret -- a value derived from the secret alone would be
/// identical on two connections that a relay had spliced, while a transcript covers *which* keys were used and
/// *who* claimed to be taking part. The transcript is already built for the authentication tag
/// (`secure_channel.dart`), so this adds a display of something that already exists rather than a second
/// mechanism that could drift from it.
final class ShortCode {
  const ShortCode._();

  /// How many digits a person is asked to compare.
  static const int digits = 6;

  /// [decision] **The confirmation is one-shot, and this is where that is written down.**
  ///
  /// Twenty bits is not a margin that survives repetition. Nothing in this file can enforce a UI rule, so the
  /// rule is stated here as a value the screen can read and a test can assert, rather than as a comment on a
  /// button somebody edits later.
  static const bool isOneShot = true;

  /// The digits for a transcript, as a six-character string with leading zeros kept.
  ///
  /// **Deterministic and symmetric**: both ends hash the same bytes, so both show the same digits, and a
  /// transcript that differs in any field produces digits that agree only by a one-in-a-million coincidence.
  static String of(List<int> transcript) {
    final digest = const DartSha256()
        .hashSync(Uint8List.fromList([...transcript, ...utf8.encode('/short-code')]))
        .bytes;
    // The first four bytes as an unsigned 32-bit number, reduced. Big-endian, and the domain separation above
    // is what keeps this from being the same value as any other digest of the transcript -- the point is a
    // number derived from *this* handshake, not a prefix of a hash somebody else may also be displaying.
    final value = (digest[0] << 24) | (digest[1] << 16) | (digest[2] << 8) | digest[3];
    final digits = (value % 1000000).toString().padLeft(ShortCode.digits, '0');
    return digits;
  }

  /// Whether two showcases agree, which is what the person is asked and what a mismatch means.
  ///
  /// Compared as text rather than as numbers: the reader is looking at six characters, and `012345` and
  /// `12345` are different things on a screen even though they would be one number.
  static bool agree(String shown, String seen) => shown == seen;

  /// The digits formatted for a screen: `123456` reads as `123 456`, because six digits in a row is a number
  /// to read and two groups of three is a number to **compare**.
  static String grouped(String code) =>
      code.length == digits ? '${code.substring(0, 3)} ${code.substring(3)}' : code;
}
