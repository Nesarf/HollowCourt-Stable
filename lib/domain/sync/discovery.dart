import 'dart:convert';

import 'device_identity.dart';
import 'names.dart';

/// Finding the other devices on the local network the way the games of that era did it: a broadcast on a
/// port everybody knows, a list of what answered, and no address typed by a human.
///
/// **What this layer is and is not.** It answers *who is here* and nothing else. Every announcement is a
/// claim by whoever sent it -- a name, a fingerprint and a port, all of which anybody on the network can
/// invent -- so nothing here is trusted, nothing here is authenticated, and nothing here decides anything.
/// The fingerprint in an announcement is used for exactly one thing: **matching a device to one this
/// machine already knows.** The proof that a device is what it claims comes later, from the sealed
/// handshake, and a device that lies in its announcement simply fails there.
///
/// **Discovery is started by hand and stops when the screen does.** The owner asked for exactly that, and
/// the reason is not only politeness about battery: a device that announces itself all day is a device
/// that can be found all day, and "nobody can see me unless I am looking" is a better default for an
/// application whose whole subject is what somebody has in the cupboard.
final class DiscoveryAnnounce {
  const DiscoveryAnnounce({
    required this.deviceName,
    required this.port,
    this.cellarName = '',
    this.shows = NameChoice.device,
    this.fingerprint = '',
    this.version = '',
  });

  /// The protocol's own version, so a future change can be refused rather than misread.
  static const int protocol = 1;

  /// The field that marks a datagram as ours. Short because it is on every packet.
  static const String _marker = 'hollow';

  /// **Both names travel, and the choice is made by the sender.** A receiver that only ever heard one
  /// name could not tell a reader that this is somebody's cellar on somebody's laptop, and the choice
  /// belongs to the device showing itself rather than to the one looking.
  final String deviceName;

  /// The cellar's own name, or empty when the owner has not given one.
  final String cellarName;

  /// Which of the two the sender is presenting.
  final NameChoice shows;

  /// The name to show for this device: what the sender chose, falling back to the device name when the
  /// cellar has none (see [SyncNames.presented]).
  String get displayName => SyncNames(
    deviceName: deviceName,
    cellarName: cellarName,
    shows: shows,
  ).presented;

  /// The device's long-term key fingerprint, or empty when it has no identity yet. Empty is a legitimate
  /// state -- an identity is created when the device first needs one -- and such a device can be seen but
  /// not recognised.
  final String fingerprint;

  /// **The port the device is actually listening on**, which is the point of announcing at all: the
  /// discovery port is fixed so everyone knows where to shout, and the answer has to say where to reply.
  /// Red Alert 2's `PortBase`/`PortPool` pair is the same idea seen from the other side.
  final int port;

  /// The application version, for a screen that wants to say why two devices cannot talk.
  final String version;

  /// A **probe** asks every device that hears it to answer at once. Without one, a device joining a
  /// network waits for the next periodic announcement of everybody else, which is up to one interval of
  /// staring at an empty list. With one, the list fills in a round trip.
  bool get isProbe => port == 0 && deviceName.isEmpty && fingerprint.isEmpty;

  static DiscoveryAnnounce probe() =>
      const DiscoveryAnnounce(deviceName: '', port: 0);

  Map<String, Object?> _toJson() => {
    _marker: protocol,
    if (isProbe) 'probe': true else ...{
      'device': deviceName,
      'port': port,
      if (cellarName.isNotEmpty) 'cellar': cellarName,
      if (shows != NameChoice.device) 'show': shows.wire,
      if (fingerprint.isNotEmpty) 'fp': fingerprint,
      if (version.isNotEmpty) 'v': version,
    },
  };

  String encode() => jsonEncode(_toJson());

  /// Reads a datagram, and **returns null for everything that is not an announcement of ours**.
  ///
  /// A UDP port is shared with whatever else on the machine happens to use it, so a datagram that is not
  /// ours is the normal case rather than an error, and a parser that threw would make ordinary network
  /// noise look like a fault. This is the same rule the event log follows for unreadable lines.
  static DiscoveryAnnounce? parse(String datagram) {
    final Map<String, Object?> decoded;
    try {
      final value = jsonDecode(datagram.trim());
      if (value is! Map<String, Object?>) return null;
      decoded = value;
    } on FormatException {
      return null;
    }

    final marker = decoded[_marker];
    if (marker is! int || marker > protocol) return null;

    if (decoded['probe'] == true) return probe();

    final device = decoded['device'];
    final port = decoded['port'];
    if (device is! String || device.isEmpty) return null;
    if (port is! int || port <= 0 || port > 65535) return null;

    final cellar = decoded['cellar'];
    final show = decoded['show'];
    final fingerprint = decoded['fp'];
    final version = decoded['v'];
    return DiscoveryAnnounce(
      deviceName: device,
      port: port,
      cellarName: cellar is String ? cellar : '',
      // An unrecognised value means the device name, which every device has: a name invented from a
      // field this build does not understand would be worse than the one that is certainly true.
      shows: NameChoice.byName(show is String ? show : null),
      fingerprint: fingerprint is String ? fingerprint : '',
      version: version is String ? version : '',
    );
  }
}

/// A device as the roster currently believes it to be.
final class DiscoveredDevice {
  const DiscoveredDevice({
    required this.name,
    required this.fingerprint,
    required this.address,
    required this.port,
    required this.lastSeenMillis,
    required this.remembered,
    required this.version,
  });

  final String name;

  /// Empty when the device has announced itself without an identity.
  final String fingerprint;

  final String address;
  final int port;
  final int lastSeenMillis;

  /// **Whether this machine has met the device before**, decided by the fingerprint against the store of
  /// paired devices. This is the "identification is automatic" half of what the owner asked for: nobody
  /// presses anything to have a known device recognised, and a device with no fingerprint is shown as new
  /// rather than hidden.
  final bool remembered;

  final String version;

  DiscoveryAnnounce get announce => DiscoveryAnnounce(
    deviceName: name,
    fingerprint: fingerprint,
    port: port,
    version: version,
  );

  /// The key this device is recognised by. The address is deliberately **not** part of it: see
  /// [DeviceRoster.observe].
  String get identityKey => fingerprint.isEmpty ? 'addr:$address:$port' : fingerprint;
}

/// What is on the network right now, as far as this device has been told.
///
/// **The roster is a table with expiry, not an append-only list.** A device that stops announcing is gone
/// -- a phone that walked out of range, an application that was closed -- and a list that never forgot
/// anything would fill with devices that are no longer there, which is worse than an empty list because it
/// makes the reader try. Red Alert 2's slot table has the same shape from the other direction: fixed
/// places, each of which may be empty.
final class DeviceRoster {
  DeviceRoster({this.expiryMillis = 12000});

  /// How long an announcement is believed. Three announcement intervals, so a single lost datagram does
  /// not make a device flicker out of the list.
  final int expiryMillis;

  final Map<String, DiscoveredDevice> _byIdentity = {};

  /// The devices, most interesting first: paired before unpaired, and inside each group the most recently
  /// heard from. A reader is looking for a device they already know far more often than for a stranger.
  List<DiscoveredDevice> get devices {
    final list = _byIdentity.values.toList()
      ..sort((a, b) {
        if (a.remembered != b.remembered) return a.remembered ? -1 : 1;
        return b.lastSeenMillis.compareTo(a.lastSeenMillis);
      });
    return List.unmodifiable(list);
  }

  int get length => _byIdentity.length;

  /// Records what [announce] said, from [address], at [nowMillis].
  ///
  /// **[identityKey] rather than the address decides whether this is a new row or an update.** A device's
  /// address is where it was last seen -- a phone changes network, a listener changes port every time it
  /// starts -- so keying the roster on it would show one device as several and let a reader send a request
  /// into the void. The fingerprint is stable; when there is none, the address is the best available
  /// answer and is used only until the device has an identity.
  DiscoveredDevice observe(
    DiscoveryAnnounce announce, {
    required String address,
    required int nowMillis,
    required Set<String> rememberedFingerprints,
  }) {
    // **Compared in one spelling, because the two sides arrive in two.** The announcement carries the grouped
    // form a person reads; the store keeps the digest. See `DeviceIdentity.fingerprintKey`.
    final alreadyMet = {
      for (final fingerprint in rememberedFingerprints)
        DeviceIdentity.fingerprintKey(fingerprint),
    };
    final candidate = DiscoveredDevice(
      name: announce.displayName,
      fingerprint: announce.fingerprint,
      address: address,
      port: announce.port,
      lastSeenMillis: nowMillis,
      remembered:
          announce.fingerprint.isNotEmpty &&
          alreadyMet.contains(DeviceIdentity.fingerprintKey(announce.fingerprint)),
      version: announce.version,
    );

    // A device that re-announces from a new address is one row that moved, not two rows.
    final stale = _byIdentity.keys
        .where((key) => key.startsWith('addr:$address:') && key != candidate.identityKey)
        .toList();
    for (final key in stale) {
      _byIdentity.remove(key);
    }

    _byIdentity[candidate.identityKey] = candidate;
    return candidate;
  }

  /// Drops everything not heard from within [expiryMillis] of [nowMillis], and answers whether anything
  /// was dropped -- a screen repaints on true and does nothing on false.
  bool expire(int nowMillis) {
    final gone = _byIdentity.entries
        .where((entry) => nowMillis - entry.value.lastSeenMillis > expiryMillis)
        .map((entry) => entry.key)
        .toList();
    for (final key in gone) {
      _byIdentity.remove(key);
    }
    return gone.isNotEmpty;
  }

  void clear() => _byIdentity.clear();
}
