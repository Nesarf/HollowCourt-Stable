import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// This device's long-term identity: one key pair that outlives every connection.
///
/// WHY A LONG-TERM KEY AT ALL, GIVEN THE CONNECTION IS ALREADY AUTHENTICATED.
///
/// The pairing code authenticates *one* connection: two devices prove they were both shown the same
/// six characters, and after that they know nothing about each other. The next sync needs the code
/// again, which means a human standing at two screens every time -- and section 10.3 asks for
/// "long-term keys exchanged during pairing" precisely so that a device can be **recognised** rather
/// than re-confirmed. That is the difference this file makes: the first sync is authenticated by the
/// code, and every later one by the key that was learned during it.
///
/// WHAT IT IS NOT. This is not an account and not an identity a server could check: nothing signs it,
/// nobody vouches for it, and it means only "the same device as last time" to the other device that
/// learned it. Section 1.2 has no accounts for exactly this reason, and a key like this is the most a
/// program without a server can honestly offer.
///
/// **A note on what "the same device" is worth.** The private key is a file in this application's
/// support directory. Anyone who can read that file can impersonate this device to a peer that has
/// learned its public key; anyone who can write it can replace this device's identity outright. That
/// is the same trust boundary as the cellar log itself, so it is not a new exposure -- but it is the
/// honest limit of the claim, and it belongs here rather than in a security section that reads as
/// though the key were a hardware secret.
final class DeviceIdentity {
  const DeviceIdentity._(this._keyPair, this.publicKey);

  final SimpleKeyPair _keyPair;

  /// The public half, base64. This is what a peer stores to recognise this device later.
  final String publicKey;

  /// A short, human-checkable fingerprint of [publicKey].
  ///
  /// **For reading aloud, not for security.** Four groups of four characters from a digest, so two
  /// people can compare what their screens say and notice a substitution -- which is the only job a
  /// fingerprint has here. It is not a secret and it is not used in any key derivation.
  String get fingerprint {
    final digest = _fingerprintDigest(publicKey);
    return [
      for (var group = 0; group < 4; group++)
        digest.substring(group * 4, group * 4 + 4),
    ].join('-');
  }

  /// **The same fingerprint, for a public key that came from somewhere else.**
  ///
  /// A discovery announcement carries a fingerprint and a trusted device carries a public key, so deciding
  /// "is this the device I synced with last week?" means deriving one from the other -- and deriving it here
  /// rather than in the screen is what keeps the two from drifting into different digests, which would show
  /// every remembered device as new.
  static String fingerprintOf(String publicKey) => _fingerprintDigest(publicKey);

  /// **The same fingerprint, in the one spelling comparisons are made in.**
  ///
  /// A fingerprint is one value with two spellings: the digest itself (`ABCDEFGHIJKLMNOP`) and the grouped form a
  /// person reads off a screen (`ABCD-EFGH-IJKL-MNOP`, [fingerprint]). The announcement carries the *grouped* one,
  /// because the same string is shown in 附近的设备 and read aloud, while the store keeps the digest -- so comparing
  /// the two directly **never matched**, and the consequences were three:
  ///
  /// * 附近的设备 labelled every device this machine had met as 新设备, two lines above 已记住的设备 listing it;
  /// * tapping a device it had met took the *stranger* path and asked for six digits;
  /// * the confirmation box said 陌生 about a device whose key was in the store.
  ///
  /// Found on a real screen, from the label, and the tests agreed with the code because the fake announcement was
  /// written in the digest form -- the same shape of mistake this project records elsewhere: a test that encodes
  /// the assumption it exists to check.
  static String fingerprintKey(String fingerprint) =>
      fingerprint.replaceAll('-', '').toUpperCase();

  /// Whether two spellings name the same fingerprint.
  static bool sameFingerprint(String a, String b) =>
      a.isNotEmpty && b.isNotEmpty && fingerprintKey(a) == fingerprintKey(b);

  static String _fingerprintDigest(String publicKey) {
    // A deterministic, non-cryptographic digest is enough for a fingerprint people compare by eye;
    // using SHA-256 would suggest a security property that a four-group display cannot carry.
    var hash = 2166136261;
    for (final byte in utf8.encode(publicKey)) {
      hash = (hash ^ byte) * 16777619 & 0xffffffff;
    }
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final buffer = StringBuffer();
    for (var i = 0; i < 16; i++) {
      hash = (hash * 1664525 + 1013904223) & 0xffffffff;
      buffer.write(alphabet[(hash >> 16) % alphabet.length]);
    }
    return buffer.toString();
  }

  /// A brand new identity, from the platform's secure random.
  static Future<DeviceIdentity> generate() async {
    final keyPair = await X25519().newKeyPair();
    return DeviceIdentity._(keyPair, await _publicOf(keyPair));
  }

  /// Rebuilds an identity from the seed it was created with.
  ///
  /// The seed is the private key's bytes, and it is what gets stored: a stored identity that could
  /// not be rebuilt would be a new device on every launch, which is the same as having none.
  static Future<DeviceIdentity> fromSeed(List<int> seed) async {
    final keyPair = await X25519().newKeyPairFromSeed(seed);
    return DeviceIdentity._(keyPair, await _publicOf(keyPair));
  }

  /// The bytes to store. **The private key**, and the only thing in this project that is secret at
  /// rest.
  Future<List<int>> seed() => _keyPair.extractPrivateKeyBytes();

  static Future<String> _publicOf(SimpleKeyPair keyPair) async =>
      base64.encode((await keyPair.extractPublicKey()).bytes);

  /// Kept for the handshake, which needs the key pair itself.
  SimpleKeyPair get keyPair => _keyPair;

  @override
  String toString() => 'DeviceIdentity($fingerprint)';
}

/// A device this one has decided to recognise.
///
/// [publicKey] is what makes the decision checkable; [name] and [address] are what make it usable --
/// a name to show, and somewhere to try, because without mDNS a remembered peer still has to be
/// reachable by an address the two agreed on once.
final class TrustedDevice {
  const TrustedDevice({
    required this.publicKey,
    required this.name,
    this.address,
    this.lastSeenMillis,
  });

  final String publicKey;
  final String name;

  /// `host:port` from the last successful sync, or null when it was never recorded.
  final String? address;

  final int? lastSeenMillis;

  TrustedDevice seenAt(String host, int port, int atMillis) => TrustedDevice(
    publicKey: publicKey,
    name: name,
    address: '$host:$port',
    lastSeenMillis: atMillis,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'publicKey': publicKey,
    'name': name,
    if (address != null) 'address': address,
    if (lastSeenMillis != null) 'lastSeenMillis': lastSeenMillis,
  };

  static TrustedDevice? fromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final publicKey = json['publicKey'];
    final name = json['name'];
    if (publicKey is! String || name is! String) return null;
    if (publicKey.isEmpty) return null;
    return TrustedDevice(
      publicKey: publicKey,
      name: name,
      address: json['address'] as String?,
      lastSeenMillis: json['lastSeenMillis'] as int?,
    );
  }

  /// Eight characters of the public key, so a screen can name a device it does not otherwise know.
  String get shortKey => publicKey.length <= 8 ? publicKey : publicKey.substring(0, 8);
}

/// Random bytes for a seed, when a caller needs one outside [DeviceIdentity.generate].
Uint8List randomSeed([int bytes = 32]) {
  final random = Random.secure();
  return Uint8List.fromList([for (var i = 0; i < bytes; i++) random.nextInt(256)]);
}
