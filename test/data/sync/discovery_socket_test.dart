import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:hollow_court/data/sync/discovery_socket.dart';
import 'package:hollow_court/domain/sync/discovery.dart';
import 'package:test/test.dart';

/// **The socket layer, tested with two real sockets rather than a mock.**
///
/// The domain's roster logic had thirteen tests and nothing was sending anything, which is the shape of work
/// that passes and does not work. These open actual UDP sockets on the loopback interface, inject the
/// destination so the traffic stays on this machine, and check that one device hears the other.
void main() {
  /// A port nobody is using: bind to zero, read what the system gave us, let it go.
  Future<int> freePort() async {
    final socket = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    socket.close();
    return port;
  }

  DiscoveryAnnounce device(String name, String fingerprint) => DiscoveryAnnounce(
    deviceName: name,
    fingerprint: fingerprint,
    port: 48123,
    version: '1.0.0',
  );

  test('**two devices on one machine hear each other**', () async {
    // **Two ports, because one machine is not two devices.** Windows delivers a UDP port bound twice to one
    // socket only, so each side listens on its own port and aims at the other's -- production has both on
    // `defaultDiscoveryPort`, and the difference lives in this line rather than in a hidden special case.
    final laptopPort = await freePort();
    final phonePort = await freePort();
    final laptop = await LanDiscovery.start(
      announce: device('laptop', 'aaaa'),
      port: laptopPort,
      sendPort: phonePort,
      destination: InternetAddress.loopbackIPv4,
      bindAddress: '127.0.0.1',
    );
    final phone = await LanDiscovery.start(
      announce: device('phone', 'bbbb'),
      port: phonePort,
      sendPort: laptopPort,
      destination: InternetAddress.loopbackIPv4,
      bindAddress: '127.0.0.1',
    );
    addTearDown(() async {
      await laptop.stop();
      await phone.stop();
    });

    // Each side hears the other, and the address comes from the datagram rather than the payload.
    final heardByLaptop = await laptop.announces
        .firstWhere((a) => a.announce.fingerprint == 'bbbb')
        .timeout(const Duration(seconds: 5));
    expect(heardByLaptop.announce.deviceName, 'phone');
    expect(heardByLaptop.address, '127.0.0.1');

    final heardByPhone = await phone.announces
        .firstWhere((a) => a.announce.fingerprint == 'aaaa')
        .timeout(const Duration(seconds: 5));
    expect(heardByPhone.announce.deviceName, 'laptop');
    expect(heardByPhone.announce.port, 48123);
  });

  test('**a device does not hear itself**, because a roster showing this machine as a peer is worse than an empty one',
      () async {
    final port = await freePort();
    final one = await LanDiscovery.start(
      announce: device('laptop', 'aaaa'),
      port: port,
      // Aimed at itself: a device whose own announcement comes back -- over a loopback, or because two copies
      // on one machine share a fingerprint -- must not report a peer.
      sendPort: port,
      destination: InternetAddress.loopbackIPv4,
      bindAddress: '127.0.0.1',
    );
    addTearDown(one.stop);

    final heard = <String>[];
    final subscription = one.announces.listen((a) => heard.add(a.announce.deviceName));
    await Future<void>.delayed(const Duration(milliseconds: 600));
    await subscription.cancel();
    expect(heard, isEmpty);
  });

  test('**junk on the port is ignored rather than fatal**', () async {
    final port = await freePort();
    final discovery = await LanDiscovery.start(
      announce: device('laptop', 'aaaa'),
      port: port,
      destination: InternetAddress.loopbackIPv4,
      bindAddress: '127.0.0.1',
    );
    addTearDown(discovery.stop);

    final vandal = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(vandal.close);
    // Not JSON, then JSON of the wrong shape, then a truncated line -- three ways a radio or a stranger can
    // produce something the parser must survive.
    for (final junk in ['hello', '{"a":1}', '{"hollow":1,"name":']) {
      vandal.send(utf8.encode(junk), InternetAddress.loopbackIPv4, port);
    }

    final heard = <String>[];
    final subscription = discovery.announces.listen((a) => heard.add(a.announce.deviceName));
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await subscription.cancel();
    expect(heard, isEmpty, reason: 'nothing usable was sent, so nothing is reported');

    // And the socket is still alive: a real announcement after the junk is heard.
    vandal.send(utf8.encode(device('phone', 'bbbb').encode()), InternetAddress.loopbackIPv4, port);
    final real = await discovery.announces.first.timeout(const Duration(seconds: 5));
    expect(real.announce.deviceName, 'phone');
  });

  test('a probe is heard and carries no identity, which is what makes a device new rather than hidden', () async {
    final port = await freePort();
    final listener = await LanDiscovery.start(
      announce: device('laptop', 'aaaa'),
      port: port,
      destination: InternetAddress.loopbackIPv4,
      bindAddress: '127.0.0.1',
    );
    addTearDown(listener.stop);

    final stranger = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(stranger.close);
    stranger.send(
      utf8.encode(DiscoveryAnnounce.probe().encode()),
      InternetAddress.loopbackIPv4,
      port,
    );

    final heard = await listener.announces.first.timeout(const Duration(seconds: 5));
    expect(heard.announce.isProbe, isTrue);
    expect(heard.announce.fingerprint, isEmpty);
    // And the roster still shows it, marked as not remembered.
    final roster = DeviceRoster();
    final device_ = roster.observe(
      heard.announce,
      address: heard.address,
      nowMillis: 1000,
      rememberedFingerprints: const {},
    );
    expect(device_.remembered, isFalse);
  });

  test('stopping closes the socket, which is what makes discovery belong to the screen', () async {
    final port = await freePort();
    final listener = await LanDiscovery.start(
      announce: device('laptop', 'aaaa'),
      port: port,
      destination: InternetAddress.loopbackIPv4,
      bindAddress: '127.0.0.1',
    );
    await listener.stop();

    final sender = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(sender.close);
    sender.send(utf8.encode(device('phone', 'bbbb').encode()), InternetAddress.loopbackIPv4, port);

    final heard = <String>[];
    final subscription = listener.announces.listen((a) => heard.add(a.announce.deviceName));
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await subscription.cancel();
    expect(heard, isEmpty);
  });

  test('there is no HTTP anywhere on this path, so there is nothing for a proxy to be configured around', () {
    // The same stance the sync transport is held to, and checked the same way: the announcement is a UDP
    // datagram built here, not a request made through a client stack that could consult a proxy setting.
    final source = File('lib/data/sync/discovery_socket.dart').readAsStringSync();
    for (final forbidden in ['HttpClient', 'http://', 'https://', 'Proxy', 'findProxy']) {
      expect(source.contains(forbidden), isFalse, reason: 'discovery mentions $forbidden');
    }
    expect(defaultDiscoveryPort, isNot(48123), reason: 'the announcement channel is not the sync port');
  });
}
