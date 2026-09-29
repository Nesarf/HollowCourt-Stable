import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../domain/sync/discovery.dart';

/// **The datagrams that make "see a name, tap it, sync" possible.**
///
/// `domain/sync/discovery.dart` holds what an announcement means and what the roster of them looks like; this
/// is the socket underneath, and it exists because the domain was finished and nothing was sending anything.
///
/// ## What travels, and what it is worth
///
/// One line of JSON, periodically, to the subnet's broadcast address on a fixed port. **An announcement is a
/// claim and never an identity** -- anybody can send any name -- so nothing here is trusted: the receiver
/// learns an address from the datagram's source (the payload never carries the sender's address, because a
/// payload can lie about it and a source cannot), and the fingerprint is only ever used to look a device up in
/// the store of ones this machine has already met. Missing a fingerprint makes a device *new*, not invisible.
///
/// ## Why UDP broadcast rather than mDNS, again, in the code
///
/// Android needs a `MulticastLock` for multicast and drops it when the screen sleeps; broadcast generally
/// does not need one, and it does not require reasoning about a plugin's lifecycle on three platforms. The
/// cost is that **broadcast does not cross a router's client isolation**, which is why the pairing code stays:
/// discovery is the pleasant path and the code is the one that always works.
///
/// ## And it is raw UDP, which is a property rather than an implementation detail
///
/// There is no HTTP here, so there is no proxy in the path -- not "a proxy is disabled", but nothing that a
/// proxy could be configured around. That is the same stance as `socket_transport.dart`, and it is tested the
/// same way.
final class LanDiscovery {
  LanDiscovery._(this._socket, this.announce, this._destination, this._sendPort);

  final RawDatagramSocket _socket;

  /// What this device says about itself. Sent unchanged every time.
  final DiscoveryAnnounce announce;


  final InternetAddress _destination;
  final int _sendPort;

  final _received = StreamController<({DiscoveryAnnounce announce, String address})>.broadcast();
  Timer? _timer;

  /// The announcements this device has heard, each with the address it actually came from.
  Stream<({DiscoveryAnnounce announce, String address})> get announces => _received.stream;

  /// **Opens the socket and starts announcing.** Returns a running instance; the caller stops it.
  ///
  /// [destination] and [port] are parameters rather than constants so a test can put two real sockets on the
  /// loopback interface and watch one hear the other. In production the destination is the subnet's broadcast
  /// address, and it is derived here rather than passed in so that no caller has to know how.
  static Future<LanDiscovery> start({
    required DiscoveryAnnounce announce,
    Duration interval = const Duration(seconds: 3),
    int port = defaultDiscoveryPort,
    InternetAddress? destination,
    String? bindAddress,
    int? sendPort,
  }) async {
    final socket = await RawDatagramSocket.bind(
      bindAddress == null ? InternetAddress.anyIPv4 : InternetAddress(bindAddress),
      // **The same port on both sides.** Every device listens where every device sends, which is what makes
      // this work without a rendezvous: there is no server to ask, so there cannot be a different port.
      port,
      reuseAddress: true,
      reusePort: false,
    );
    socket.broadcastEnabled = true;

    final target = destination ?? await _broadcastAddress(bindAddress);
    // **Where the announcement goes, which in production is the port it listens on.** There is no server to
    // ask, so both sides have to agree on one number, and that number is `defaultDiscoveryPort`.
    //
    // `sendPort` exists because of a platform fact worth writing down rather than rediscovering: **on Windows a
    // UDP port bound twice with `reuseAddress` delivers each datagram to one socket only.** Two copies of this
    // application on one machine therefore cannot both listen on the fixed port -- which matters for the tests,
    // where two instances share a machine, and not for real devices, which do not. Production passes nothing
    // here and gets the same port on both sides.
    final discovery = LanDiscovery._(socket, announce, target, sendPort ?? port);
    discovery._listen();
    discovery._sendNow();
    discovery._timer = Timer.periodic(interval, (_) => discovery._sendNow());
    return discovery;
  }

  /// The address an announcement goes to when nobody says otherwise.
  ///
  /// **The interface's own broadcast address, not 255.255.255.255.** The limited broadcast reaches one
  /// subnet -- the one this device is on -- and a subnet-directed broadcast derived from the interface is the
  /// same reach in practice while being the form that routers are least unhappy about. Both reach exactly one
  /// subnet, which is the honest limit of this whole mechanism and is written down in 10.2.0.1.
  static Future<InternetAddress> _broadcastAddress(String? bindAddress) async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    for (final interface in interfaces) {
      for (final address in interface.addresses) {
        if (bindAddress != null && address.address != bindAddress) continue;
        if (address.isLoopback) continue;
        final parts = address.address.split('.');
        if (parts.length != 4) continue;
        // A /24 assumption, and it is stated rather than hidden: the mask is not available from this API, and
        // a wrong guess costs a redundant datagram to an address nobody is on -- which the network drops.
        parts[3] = '255';
        final candidate = InternetAddress.tryParse(parts.join('.'));
        if (candidate != null) return candidate;
      }
    }
    // Nothing usable: the limited broadcast, which is the one address that always means "this subnet".
    return InternetAddress('255.255.255.255');
  }

  void _listen() {
    _socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      final datagram = _socket.receive();
      if (datagram == null) return;
      final text = utf8.decode(datagram.data, allowMalformed: true).trim();
      final parsed = DiscoveryAnnounce.parse(text);
      if (parsed == null) return;
      // **A probe from this very device is not a device.** Two copies of the application on one machine are a
      // legitimate pair to sync, but an announcement we sent ourselves coming back on the loopback is not, and
      // a roster showing this machine as a peer is worse than an empty one.
      if (parsed.fingerprint.isNotEmpty && parsed.fingerprint == announce.fingerprint) return;
      _received.add((announce: parsed, address: datagram.address.address));
    }, onError: (Object _) {
      // A socket error is not worth killing discovery for: the announce that arrives next is the recovery.
    });
  }

  void _sendNow() {
    try {
      _socket.send(utf8.encode(announce.encode()), _destination, _sendPort);
    } on Object {
      // Sending can fail when an interface goes away mid-flight. The next tick tries again; a discovery that
      // threw here would take the screen down for a network event that fixes itself.
    }
  }

  /// Sends once, immediately, outside the interval -- for a screen that has just opened and does not want to
  /// wait three seconds to be seen.
  void announceNow() => _sendNow();

  /// **Stops announcing and closes the socket.** Discovery belongs to the sync screen, so this is called when
  /// that screen closes: an application that announced itself from the moment it launched would be a device
  /// that is discoverable while nobody is looking, and on Android it would also want a foreground service to
  /// stay alive, which is a permission this feature does not need to ask for.
  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    await _received.close();
    _socket.close();
  }
}

/// **The port discovery uses, beside the sync port rather than equal to it.**
///
/// Fixed, and it has to be: there is no server to ask, so both sides have to know where to look. The sync
/// probes use 48123 and this is the announcement channel, so a device can be heard before anything is
/// connected -- and a firewall rule for one is not a rule for the other.
const int defaultDiscoveryPort = 48124;
