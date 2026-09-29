import 'package:hollow_court/domain/sync/lan_address.dart';
import 'package:hollow_court/domain/sync/link_mode.dart';
import 'package:test/test.dart';

/// Two modes that cannot be used at once, and the classification that makes that true.
///
/// The owner's design: *"把有线和无线分成两种模式（不可同时选择），有线模式下无法使用无线网络进行同步，反之亦然"*.
/// A mode is a stronger promise than a preference, so this file is mostly about the ways a promise like
/// that can be quietly broken -- by a fallback, by a guess, by an interface nobody classified.
void main() {
  LanCandidate c(String name, String address) =>
      LanCandidate(interfaceName: name, address: address);

  group('an interface name is classified, or honestly not', () {
    test('the four platforms, by the names they actually use', () {
      // Windows
      expect(classifyLink('Ethernet'), SyncLink.wired);
      expect(classifyLink('以太网'), SyncLink.wired);
      expect(classifyLink('Wi-Fi'), SyncLink.wireless);
      expect(classifyLink('WLAN'), SyncLink.wireless);
      // Linux
      expect(classifyLink('enp3s0'), SyncLink.wired);
      expect(classifyLink('eth0'), SyncLink.wired);
      expect(classifyLink('wlp2s0'), SyncLink.wireless);
      // Android
      expect(classifyLink('wlan0'), SyncLink.wireless);
      // **And USB is its own mode**, which the owner asked for once they remembered Android: a tethered
      // phone presents `rndis0`/`usb0`, and folding that into 有线 would make choosing 有线 on a phone
      // silently mean "tethering".
      expect(classifyLink('rndis0'), SyncLink.usb);
      expect(classifyLink('usb0'), SyncLink.usb);
    });

    test('**a tunnel is its own mode**, as the owner decided', () {
      // A routed tunnel is not a cable, not a radio and not a USB link, so it was put to them and they
      // chose a fourth mode. These names carry a route rather than a link, and a device reached over one may
      // not be on this network at all -- which is the point of the mode.
      expect(classifyLink('Tailscale'), SyncLink.tunnel);
      expect(classifyLink('tun0'), SyncLink.tunnel);
      expect(classifyLink('wg0'), SyncLink.tunnel);
      expect(classifyLink('WireGuard Tunnel'), SyncLink.tunnel);
      expect(classifyLink('OpenVPN TAP-Windows6'), SyncLink.tunnel);
    });

    test('**and everything else is neither, rather than guessed into a mode**', () {
      // A container bridge, a virtual switch, a Bluetooth PAN, a loopback alias, a name from a platform
      // nobody has taught this function yet. A coin toss presented as a classification is worse than an
      // honest null, because the mode it guessed into would then promise something it cannot keep.
      expect(classifyLink('vEthernet (WSL)'), isNull);
      expect(classifyLink('docker0'), isNull);
      expect(classifyLink('lo'), isNull);
      expect(classifyLink('en0'), isNull,
          reason: 'en0 is Wi-Fi on almost every Mac and Ethernet on some -- a documented unknown');
    });
  });

  group('the modes exclude each other completely', () {
    final machine = [
      c('Wi-Fi', '192.168.31.157'),
      c('Ethernet', '169.254.10.20'),
      c('vEthernet (WSL)', '172.30.96.1'),
      c('Tailscale', '100.101.102.103'),
    ];

    test('wired mode sees the cable and nothing else', () {
      final wired = candidatesFor(SyncLink.wired, machine);
      expect(wired.map((c) => c.interfaceName), ['Ethernet']);
      expect(wired.map((c) => c.address), isNot(contains('192.168.31.157')));
    });

    test('wireless mode sees the radio and nothing else', () {
      final wireless = candidatesFor(SyncLink.wireless, machine);
      expect(wireless.map((c) => c.interfaceName), ['Wi-Fi']);
      expect(wireless.map((c) => c.address), isNot(contains('169.254.10.20')));
    });

    test('**and no mode adopts the interfaces that are none of them**', () {
      // The quiet fallback a mode exists to prevent: a container bridge or a VPN overlay used under a
      // setting that promised "only this kind of link". Checked across every mode, so a fourth one added
      // later inherits the property rather than needing to remember it.
      for (final mode in SyncLink.values) {
        final addresses = candidatesFor(mode, machine).map((c) => c.address);
        expect(addresses, isNot(contains('172.30.96.1')), reason: '$mode');
        // The database of a tunnel belongs to the tunnel mode and to nothing else.
        if (mode != SyncLink.tunnel) {
          expect(addresses, isNot(contains('100.101.102.103')), reason: '$mode');
        }
      }
    });

    test('tunnel mode sees the overlay and nothing else', () {
      final tunnelled = [
        c('Wi-Fi', '192.168.31.157'),
        c('Tailscale', '100.101.102.103'),
        c('vEthernet (WSL)', '172.30.96.1'),
      ];
      expect(candidatesFor(SyncLink.tunnel, tunnelled).map((c) => c.interfaceName), ['Tailscale']);
      expect(
        candidatesFor(SyncLink.tunnel, tunnelled).map((c) => c.interfaceName),
        isNot(contains('vEthernet (WSL)')),
        reason: 'a container bridge is not a tunnel, whatever it looks like',
      );
    });

    test('usb mode sees the tether and nothing else', () {
      // A phone that is tethered *and* on Wi-Fi is the case this mode is for: the reader wants the cable,
      // and the radio must not be what answers.
      final tethered = [
        c('Wi-Fi', '192.168.31.157'),
        c('rndis0', '192.168.42.129'),
        c('Ethernet', '169.254.10.20'),
      ];
      expect(candidatesFor(SyncLink.usb, tethered).map((c) => c.interfaceName), ['rndis0']);
      expect(candidatesFor(SyncLink.wired, tethered).map((c) => c.interfaceName), ['Ethernet']);
      expect(candidatesFor(SyncLink.wireless, tethered).map((c) => c.interfaceName), ['Wi-Fi']);
    });

    test('a mode with nothing in it returns nothing, which a screen has to say out loud', () {
      // A laptop with no cable in 有线 mode, or a desktop with no radio in 无线 mode. An empty list is the
      // correct answer and it must not be filled in from the other mode.
      final noCable = [c('Wi-Fi', '192.168.31.157')];
      expect(candidatesFor(SyncLink.wired, noCable), isEmpty);
      expect(candidatesFor(SyncLink.wireless, noCable), hasLength(1));

      final noRadio = [c('Ethernet', '192.168.1.5')];
      expect(candidatesFor(SyncLink.wireless, noRadio), isEmpty);
      expect(candidatesFor(SyncLink.wired, noRadio), hasLength(1));
    });

    test('and the order inside a mode is still the ranking, not the enumeration', () {
      // Two cables, one link-local and one routed: the routed one is what the network at large can use.
      final twoCables = [
        c('Ethernet 2', '169.254.10.20'),
        c('Ethernet', '10.0.0.5'),
      ];
      expect(candidatesFor(SyncLink.wired, twoCables).first.address, '10.0.0.5');
    });
  });

  group('the mode round-trips as a stored setting', () {
    test('by name, which is what a stored value is', () {
      expect(SyncLink.byName('wired'), SyncLink.wired);
      expect(SyncLink.byName('wireless'), SyncLink.wireless);
      expect(SyncLink.byName('usb'), SyncLink.usb);
      expect(SyncLink.byName('tunnel'), SyncLink.tunnel);
      // Anything else -- including a value from a build that has a third mode -- is "no opinion", which the
      // caller resolves rather than having a mode invented for it.
      expect(SyncLink.byName('satellite'), isNull,
          reason: 'a mode from a build that has one more than this does is "no opinion", not a guess');
      expect(SyncLink.byName(null), isNull);
    });
  });
}
