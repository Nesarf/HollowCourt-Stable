import 'dart:convert';

import '../events/hlc.dart';

/// What a QR code carries, and everything a second device needs to reach this one.
///
/// **One string, and it is a URI rather than a JSON blob or three separate codes.** A
/// pairing flow that asked a reader to scan a host and then a port has already failed the
/// reason section 10 gives for having QR codes at all -- a great many routers and guest
/// networks enable client isolation, so discovery does not work and the code is the only
/// path left. One scan, one string, and the string is short enough to read aloud when a
/// camera will not cooperate, which is the fallback nobody plans for and everybody needs.
///
/// **The token is not a password and the type says so by not pretending to be one.** Section
/// 10.3 puts security at the pairing step: what the token does is make the first connection
/// need something a stranger on the same network does not have. It travels in a QR code shown
/// on a screen, so it is visible to anyone who can see the screen -- which is exactly the
/// threat model, and a name like `token` rather than `secret` is the honest label for it.
///
/// The scheme is `hollowcourt:` and the format is
///
///     hollowcourt://<host>:<port>/<token>?name=<cellar>
///
/// where the name is the *other* cellar's own label, shown to the reader so they can tell two
/// devices apart before merging anything.
final class PairingTicket {
  const PairingTicket({
    required this.host,
    required this.port,
    required this.token,
    this.name = '',
  });

  static const String scheme = 'hollowcourt';

  final String host;
  final int port;

  /// The one-time value that makes the first connection need something.
  final String token;

  /// What the other cellar calls itself, for a reader choosing between two devices.
  final String name;

  String encode() {
    final query = name.isEmpty ? '' : '?name=${Uri.encodeQueryComponent(name)}';
    // **An IPv6 host needs brackets, and without them the URI form is simply broken for one.** A bare
    // `hollowcourt://fe80::1:48123/ABC` parses as a host of `fe80::1:48123` or not at all, so a ticket for an
    // IPv6 listener could be shown and never read back. Found by a test written for the short share code, which
    // is the form that has no IPv6 answer -- and the URI is supposed to be the one that does.
    final authority = host.contains(':') ? '[$host]' : host;
    return '$scheme://$authority:$port/$token$query';
  }

  /// Reads a scanned code, or returns null when it is not one of ours.
  ///
  /// **Null rather than an exception, and that is the difference between this and
  /// `OverlayKey.parse`.** A key arrives from this project's own file; a scanned code arrives
  /// from whatever the camera was pointed at, which is very often not ours at all. A parser
  /// that threw would turn "the reader scanned the wrong thing" into a crash, and the wrong
  /// thing is the common case.
  static PairingTicket? parse(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;

    // **The short share code first, because it is what the field now asks for.** The URI still parses: a QR
    // code carries one, and it is the form a reader can repair by hand when a host guessed the wrong address
    // (see `syncEditHostHint`). Reading both is the difference between a friendlier field and a lost route.
    final share = ShareCode.parse(text);
    if (share != null) return share;

    final Uri uri;
    try {
      uri = Uri.parse(text);
    } on FormatException {
      return null;
    }
    if (uri.scheme != scheme) return null;

    // A host and a port are both required: a ticket without either cannot be connected to,
    // and inventing a default port would be guessing at a fact the code was supposed to
    // carry.
    final host = uri.host;
    if (host.isEmpty) return null;
    if (!uri.hasPort) return null;
    final port = uri.port;
    if (port <= 0 || port > 65535) return null;

    // The token is the first path segment. A ticket with no token is refused rather than
    // accepted as an unauthenticated pairing, because accepting it would quietly disable the
    // one thing the token does.
    final token = uri.pathSegments.isEmpty ? '' : uri.pathSegments.first;
    if (token.isEmpty) return null;

    return PairingTicket(
      host: host,
      port: port,
      token: token,
      name: uri.queryParameters['name'] ?? '',
    );
  }

  /// Whether [other] is the same ticket, ignoring the name.
  ///
  /// **The name is not part of the identity.** It is what the other cellar calls itself, it
  /// is display copy, and a reader renaming their cellar must not invalidate a code that is
  /// already on a screen. Comparing the two encoded strings would do exactly that.
  bool sameTargetAs(PairingTicket other) =>
      other.host == host && other.port == port && other.token == token;

  /// The short form a reader types: **ten characters of address and port, then the chosen token.**
  ///
  /// **[decision] The owner asked for this on 2026-09-23**: *「把手动输入的东西改成可自定义的分享码，最长为 18
  /// 位，但是不需要手动输入码的连接方式所需要的依赖条件不变」* -- a share code of at most eighteen
  /// characters whose **token half the reader chooses**, with the code-less path (discovery, then comparing
  /// six digits) left exactly as it was.
  ///
  ///     A7K3M9XQ2P RINDO7            ten characters of address, then the chosen token
  ///     └────┬────┘ └──┬───┘
  ///      50 bits     6..8 chars
  ///
  /// Each part is a decision:
  ///
  /// * **The address survives inside the code**, and that is what keeps every case for which the pairing
  ///   code was the only route: a network where broadcast does not cross, a hotel access point that isolates
  ///   its clients, and the USB/`adb forward` link whose address is `127.0.0.1`. A code carrying only a
  ///   secret would have moved those cases onto discovery, which is the opposite of what was asked.
  /// * **Ten characters is fifty bits**, laid out as two bits of format version, four bytes of IPv4 address
  ///   and two bytes of port. Fifty is two more than the forty-eight the address needs, so the version has
  ///   somewhere to live instead of being an assumption -- and the first field of a written-down code is the
  ///   one thing that cannot change later without invalidating codes already on paper.
  /// * **Sixteen to eighteen characters in total**: ten of address plus a token of six to eight. Eight is
  ///   the most that fits under the owner's ceiling **and is stronger than the six this project has been
  ///   generating**, so the shorter code is not the weaker one.
  /// * **The alphabet is the tokens' own** (`ABCDEFGHJKLMNPQRSTUVWXYZ23456789`): thirty-two symbols with no
  ///   `I`, `O`, `0` or `1`, so a code read aloud or copied by hand cannot turn into a different code. And
  ///   thirty-two divides into five bits exactly, which is why ten characters hold fifty bits.
  ///
  /// **Null when the host is not a dotted IPv4 quad.** IPv6 does not fit, and inventing a truncation would
  /// produce a code that quietly connects somewhere else; [encode] still carries those as the URI it always
  /// has.
  String? shareCode() {
    final octets = _ipv4(host);
    if (octets == null) return null;
    var address = 0;
    for (final octet in octets) {
      address = (address << 8) | octet;
    }
    // **The version goes in the HIGH two bits, and the tests caught it in the low ones.** Ten characters are
    // fifty bits and the address and port take forty-eight, so the spare two are the *top* of the first
    // character -- whereas the low two belong to the port, which is why the first version of this refused
    // almost every real port as an unknown format version.
    final packed = (ShareCode.addressVersion << 48) | ((address & 0xffffffff) << 16) | (port & 0xffff);
    return '${_base32(packed, 10)}${ShareCode.normaliseToken(token)}';
  }

  /// The same address and port with **a token the reader chose** in place of this ticket's own.
  ///
  /// This is what the host side calls: it holds a ticket for the listener it just opened, and the reader picks
  /// a token to put in the code they read out. The token is normalised here rather than by the caller so that
  /// the string a reader typed and the string inside the code are the same string.
  String? shareCodeWith(String token) => PairingTicket(
        host: host,
        port: port,
        token: ShareCode.normaliseToken(token),
      ).shareCode();

  static List<int>? _ipv4(String host) {
    final parts = host.split('.');
    if (parts.length != 4) return null;
    final octets = <int>[];
    for (final part in parts) {
      final value = int.tryParse(part);
      if (value == null || value < 0 || value > 255) return null;
      octets.add(value);
    }
    return octets;
  }

  static String _base32(int value, int length) {
    final buffer = StringBuffer();
    for (var i = length - 1; i >= 0; i--) {
      buffer.write(ShareCode.alphabet[(value >> (i * 5)) & 0x1f]);
    }
    return buffer.toString();
  }

  /// Reads a share code, or returns null when it is not one of ours.
  ///
  /// **Both forms are read, and the short one is tried first.** The URI is what a QR code carries and what
  /// a reader can correct by hand when a host guessed the wrong address, so it stays; the short form is what
  /// somebody says across a table. A parser that dropped the URI would take away the repair.
  static PairingTicket? parseShareCode(String raw) => parse(raw);

  @override
  String toString() => encode();

  @override
  bool operator ==(Object other) =>
      other is PairingTicket &&
      other.host == host &&
      other.port == port &&
      other.token == token &&
      other.name == name;

  @override
  int get hashCode => Object.hash(host, port, token, name);
}

/// The rules of the short share code: its alphabet, its length, and which tokens are allowed.
///
/// **The token is the reader's to choose** (the owner's decision, recorded on [PairingTicket.shareCode]), and
/// a chosen secret has a property a generated one does not: it can be *weak*. So the rules live here rather
/// than in the widget, one place can be tested, and the minimum is a rule rather than a hint.
///
/// **Six is the floor because that is what this project was already generating.** `mintPairingToken` picks six
/// characters from this alphabet -- thirty-one to the sixth, about nine hundred million, which its own comment
/// calls "small against a determined attacker and entirely adequate against the threat section 10.3 names:
/// somebody else on the café's wifi". A reader who chooses their own token may choose a *better* one; the rule
/// is only that they may not choose a worse one than the generator's default.
///
/// **Eight is the ceiling because eighteen minus ten is eight.** The owner bounded the whole code at eighteen
/// characters, ten of them carry the address, and the rest is the token.
final class ShareCode {
  const ShareCode._();

  /// Thirty-two symbols: every capital except `I` and `O`, and the digits `2` to `9`.
  ///
  /// No `0` or `1` either, so the four pairs a person mixes up -- `0`/`O`, `1`/`I`/`l`, `5`/`S`, `2`/`Z` --
  /// are either absent or separated by case. `l` is not in the set at all, and input is upper-cased before it
  /// is checked, so a hand-copied code has nowhere to go wrong quietly.
  static const String alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  /// The format version this build writes, in the **high two bits** of the ten-character address half.
  ///
  /// Zero, and it exists so that a later layout can be told apart from this one instead of being decoded as if
  /// it were. The first field of a code somebody has written down is the one thing that cannot change later.
  static const int addressVersion = 0;

  /// The characters of address and port that come first.
  static const int addressLength = 10;

  static const int minTokenLength = 6;
  static const int maxTokenLength = 8;

  /// The longest code the owner allows, and the sum of the two parts rather than a separate number.
  static const int maxCodeLength = addressLength + maxTokenLength;

  /// Upper case, and stripped of the separators a person adds when reading a code aloud.
  ///
  /// Spaces, hyphens, underscores and the full-width space are removed rather than refused: they carry no
  /// information, and a reader who grouped `A7K3M9XQ2P` as `A7K3M-9XQ2P` has not made a mistake worth a
  /// message. Case is folded for the same reason -- the alphabet is upper case, and `a7k3...` is the same
  /// code typed by somebody whose keyboard was not shouting.
  static String normalise(String raw) {
    final buffer = StringBuffer();
    for (final rune in raw.toUpperCase().runes) {
      final character = String.fromCharCode(rune);
      if (character == ' ' || character == '-' || character == '_' || character == '　') continue;
      buffer.write(character);
    }
    return buffer.toString();
  }

  /// The same normalising, for a token on its own.
  static String normaliseToken(String token) => normalise(token);

  /// Why this token cannot be used, or null when it can.
  ///
  /// **A reason rather than a boolean**, because the reader has to be told which of three things is wrong --
  /// too short, too long, or a character that will not survive being read aloud -- and the settings rows in
  /// this application state the cost of a choice rather than only forbidding it.
  static String? problemWithToken(String token) {
    final clean = normalise(token);
    if (clean.isEmpty) return 'empty';
    if (clean.length < minTokenLength) return 'short';
    if (clean.length > maxTokenLength) return 'long';
    for (final rune in clean.runes) {
      if (!alphabet.contains(String.fromCharCode(rune))) return 'character';
    }
    return null;
  }

  /// Reads the ten-character address part plus whatever token follows.
  ///
  /// **The split is positional, not marked.** A separator would spend one of the eighteen characters the owner
  /// allowed on punctuation, and the address part is a fixed ten, so there is nothing for a separator to
  /// disambiguate.
  static PairingTicket? parse(String raw) {
    final clean = normalise(raw);
    if (clean.length < addressLength + minTokenLength) return null;
    if (clean.length > maxCodeLength) return null;
    for (final rune in clean.runes) {
      if (!alphabet.contains(String.fromCharCode(rune))) return null;
    }

    var packed = 0;
    for (var i = 0; i < addressLength; i++) {
      packed = (packed << 5) | alphabet.indexOf(clean[i]);
    }
    // Two bits of format version at the top of the fifty. `00` is the only one that exists, and a code saying
    // anything else is refused rather than read as if it were this format.
    if ((packed >> 48) != addressVersion) return null;
    final port = packed & 0xffff;
    final address = (packed >> 16) & 0xffffffff;
    final host = '${(address >> 24) & 0xff}.${(address >> 16) & 0xff}.'
        '${(address >> 8) & 0xff}.${address & 0xff}';
    if (port == 0) return null;

    final token = clean.substring(addressLength);
    if (problemWithToken(token) != null) return null;

    return PairingTicket(host: host, port: port, token: token);
  }
}

/// A compact summary of what a device holds, for deciding whether to sync at all.
///
/// **The first message of a handshake, and it is small on purpose.** Two devices on a LAN
/// exchange this before either sends an event: equal digests mean there is nothing to do, and
/// on a phone that is the difference between a sync that costs nothing and one that uploads a
/// clock set per event. The full clock set is what [EventLog.missingFrom] needs; this is only
/// the question of whether to ask for it.
///
/// **A digest is a hint and never a proof.** Two different sets can collide by count and
/// hash, so an equal digest means "probably nothing to send" and a caller that needs certainty
/// compares the sets themselves. The name says `digest` rather than `state` for that reason --
/// this is not the cellar, it is a summary of it, and the fold over the real events remains
/// the only thing that decides what a cellar contains.
final class ClockDigest {
  const ClockDigest._(this.count, this.digest);

  factory ClockDigest.of(Iterable<Hlc> clocks) {
    final packed = [
      for (final clock in clocks) clock.toString(),
    ]..sort();

    // A polynomial rolling hash over the sorted readings. Sorted first, because two devices
    // hold the same events in whatever order they arrived and an unsorted hash would differ
    // for a pair that agrees about everything.
    var hash = 0;
    for (final item in packed) {
      for (final unit in utf8.encode(item)) {
        hash = (hash * 31 + unit) & 0x7fffffff;
      }
    }
    return ClockDigest._(packed.length, hash);
  }

  /// A digest **as reported by a peer**, which is why this constructor is not `of`.
  ///
  /// [ClockDigest.of] derives a summary from readings this device holds, so a value it returns is
  /// true of the cellar by construction. This one takes a count and a hash off the wire, where
  /// nothing about them is derived: they are the other end's claim about itself, and a claim is
  /// all [likelyInSyncWith] was ever entitled to act on. Naming the difference at the only place
  /// it can be named -- the constructor -- is cheaper than remembering it at every call site.
  const ClockDigest.fromSummary({required this.count, required this.digest});

  /// How many readings this device holds.
  final int count;

  /// A hash of them, in order.
  final int digest;

  bool get isEmpty => count == 0;

  /// Whether [other] probably holds the same events.
  bool likelyInSyncWith(ClockDigest other) =>
      count == other.count && digest == other.digest;

  @override
  String toString() => 'ClockDigest($count, $digest)';

  @override
  bool operator ==(Object other) =>
      other is ClockDigest && other.count == count && other.digest == digest;

  @override
  int get hashCode => Object.hash(count, digest);
}
