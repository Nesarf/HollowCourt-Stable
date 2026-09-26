import 'dart:io';

import 'package:test/test.dart';

/// **Nothing on the sync path may go through a proxy.**
///
/// The owner's requirement, in their words: *"记得实现同步工作不被代理影响（即便代理使用全局模式）"*. The two
/// devices are on the same network by definition -- that is the whole point of the feature, and the reason
/// they chose a LAN over Bluetooth is that a hotel's building-wide Wi-Fi lets a device on the fifteenth
/// floor reach one on the first. Traffic between them has no business going out to a proxy and back, and a
/// proxy in global mode would happily try.
///
/// **The guarantee holds by construction, and this file is what keeps it that way.** The sync path opens
/// raw TCP and UDP sockets through `dart:io`; a `Socket` has no concept of a proxy, nothing in it reads
/// `http_proxy` or `https_proxy`, and no HTTP client is involved at any point. An HTTP proxy -- including
/// one in system-wide "global" mode -- cannot intercept a connection it is never asked to make.
///
/// That is a property which is easy to lose by accident: a single convenience call, a helper imported for
/// something unrelated, a `package:http` dependency added for a new feature, and the LAN traffic is quietly
/// going through somebody's proxy server. A comment saying "do not do this" would not survive a year; this
/// test does.
///
/// **What this cannot do, stated plainly so nobody expects it to.** A tool that captures the *routing*
/// rather than the HTTP layer -- a VPN, or a proxy in TUN mode -- operates below the socket API, and no
/// choice in this application prevents it. Two things mitigate it and neither is a guarantee: the sync
/// listener binds to the LAN address rather than to every interface (`listenForLanSync`), so the traffic has
/// a definite route; and the discovery screen says what to check when nothing is found, because "the
/// building's Wi-Fi and a VPN are on at once" is a failure a reader can act on and a silent empty list is
/// not.
void main() {
  /// The files that carry sync traffic, or decide how it is carried.
  const syncPaths = [
    'lib/data/sync/socket_transport.dart',
    'lib/data/sync/sync_service.dart',
    'lib/data/sync/identity_store.dart',
    'lib/domain/sync/exchange.dart',
    'lib/domain/sync/secure_channel.dart',
    'lib/domain/sync/wire.dart',
    'lib/domain/sync/discovery.dart',
    'lib/domain/sync/scope.dart',
    'lib/domain/sync/courtpack.dart',
    'lib/domain/sync/names.dart',
  ];

  test('no file on the sync path mentions a proxy or an HTTP client', () {
    final offenders = <String>[];
    for (final path in syncPaths) {
      final file = File(path);
      expect(file.existsSync(), isTrue, reason: '$path moved or was renamed');
      final text = file.readAsStringSync();
      for (final forbidden in [
        'HttpClient',
        'HttpOverrides',
        'findProxy',
        'http_proxy',
        'https_proxy',
        'HTTP_PROXY',
        'HTTPS_PROXY',
        "package:http/",
      ]) {
        if (text.contains(forbidden)) offenders.add('$path contains $forbidden');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'sync traffic must not be routable through a proxy, even in global mode: $offenders',
    );
  });

  test('**and it never asks a name service, because there may not be one**', () {
    // The owner's framing, and it is sharper than "no proxy": *"这个功能算是传统意义上的VPN了，因为并不和外界
    // 互联网交互，类似医院内网的感觉"*. A hospital intranet, a hotel's guest network behind a captive portal,
    // an air-gapped switch -- all of them can have two 空庭 devices on them and none of them can resolve a
    // name. So the sync path connects to addresses it was given, and a ticket carrying a hostname is
    // refused (`Socket.connect` would otherwise resolve it): the digits are already in the code.
    final offenders = <String>[];
    for (final path in syncPaths) {
      final text = File(path).readAsStringSync();
      for (final forbidden in ['InternetAddress.lookup', 'NetworkInterface.list'].where(
        // `NetworkInterface.list` is fine where it is: enumerating *this* machine's interfaces is a local
        // question with a local answer, and it is how `lanAddress()` knows what to advertise.
        (token) => token != 'NetworkInterface.list',
      )) {
        if (text.contains(forbidden)) offenders.add('$path contains $forbidden');
      }
    }
    expect(offenders, isEmpty, reason: '$offenders');
  });

  test('and the sync path is reachable from a plain Dart program, which is what proves the layer', () {
    // If any of these pulled in Flutter, the probe (`tool/sync_probe.dart`) could not run them, and the
    // two-device round could not have been driven from a command line at all. It is also a second signal
    // for the rule above: the code that talks to the network is the code a plain VM can execute.
    for (final path in syncPaths) {
      expect(
        File(path).readAsStringSync().contains('package:flutter/'),
        isFalse,
        reason: '$path must stay Flutter-free',
      );
    }
  });
}
