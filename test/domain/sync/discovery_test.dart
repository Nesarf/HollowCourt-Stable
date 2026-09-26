import 'package:hollow_court/domain/sync/device_identity.dart';
import 'package:hollow_court/domain/sync/discovery.dart';
import 'package:hollow_court/domain/sync/names.dart';
import 'package:test/test.dart';

/// Finding devices on the network, and the two rules that make it usable: **the address is not the
/// identity**, and **a device that stops talking is gone**.
///
/// The layer is deliberately the least interesting one in the sync feature: it says who is here and
/// decides nothing. These tests are therefore mostly about the two ways a discovery list becomes a
/// nuisance -- a device that appears twice, and a device that stays in the list after it has left.
void main() {
  // **A fingerprint has two spellings and the roster must not care which arrives.** The announcement carries the
  // grouped form (what a person reads off a screen); the store keeps the digest. Comparing them directly labelled
  // every device this machine had met as 新设备 -- found on a real screen, from the label.
  test('a device is recognised when the two spellings differ', () {
    final roster = DeviceRoster();
    final digest = 'ABCDEFGHIJKLMNOP';
    final grouped = 'ABCD-EFGH-IJKL-MNOP';

    final device = roster.observe(
      const DiscoveryAnnounce(deviceName: 'phone', port: 48123, fingerprint: 'ABCD-EFGH-IJKL-MNOP'),
      address: '192.168.31.240',
      nowMillis: 1000,
      rememberedFingerprints: {digest},
    );

    expect(device.remembered, isTrue, reason: '$grouped and $digest are one fingerprint');
    expect(DeviceIdentity.sameFingerprint(grouped, digest), isTrue);
    expect(DeviceIdentity.sameFingerprint(grouped, 'WXYZ-WXYZ-WXYZ-WXYZ'), isFalse);
    // An empty one is not a match, whatever it is compared against: a device that announced no identity is new.
    expect(DeviceIdentity.sameFingerprint('', digest), isFalse);
  });

  DiscoveryAnnounce announce(String name, String fingerprint, [int port = 48123]) =>
      DiscoveryAnnounce(deviceName: name, fingerprint: fingerprint, port: port);

  group('an announcement is a small line of JSON, and anything else is ignored', () {
    test('a round trip keeps every field', () {
      final original = DiscoveryAnnounce(
        deviceName: 'NesarfDX',
        cellarName: '试验酒窖',
        shows: NameChoice.cellar,
        fingerprint: 'CEEA-J38S-G96C-TCSQ',
        port: 48123,
        version: '1.0.0',
      );
      final read = DiscoveryAnnounce.parse(original.encode())!;

      expect(read.deviceName, 'NesarfDX');
      expect(read.cellarName, '试验酒窖');
      expect(read.shows, NameChoice.cellar);
      expect(read.fingerprint, 'CEEA-J38S-G96C-TCSQ');
      expect(read.port, 48123);
      expect(read.version, '1.0.0');
      expect(read.isProbe, isFalse);
    });

    test('a probe is recognised as one, and carries nothing else', () {
      final probe = DiscoveryAnnounce.parse(DiscoveryAnnounce.probe().encode())!;
      expect(probe.isProbe, isTrue);
      expect(probe.encode().length, lessThan(40), reason: 'it is on every probe');
    });

    test('**noise returns null rather than throwing**', () {
      // A UDP port is shared with whatever else on the machine uses it, so a datagram that is not ours is
      // the ordinary case. A parser that threw would turn network noise into a fault.
      for (final junk in [
        '',
        '   ',
        'hello?',
        '{"hello":1}',
        '[1,2,3]',
        '{"hollow":"1","name":"x","port":1}',
        '{"hollow":1,"device":"","port":1}',
        '{"hollow":1,"device":"x","port":0}',
        '{"hollow":1,"device":"x","port":70000}',
      ]) {
        expect(DiscoveryAnnounce.parse(junk), isNull, reason: junk);
      }
    });

    test('a protocol from the future is ignored rather than half-read', () {
      expect(
        DiscoveryAnnounce.parse('{"hollow":${DiscoveryAnnounce.protocol + 1},"device":"x","port":1}'),
        isNull,
      );
    });

    test('a device with no identity yet can still be seen', () {
      // An identity is created when a device first needs one, so "here, but not recognisable" is a real
      // state and not a broken packet.
      final read = DiscoveryAnnounce.parse(
        const DiscoveryAnnounce(deviceName: 'phone', port: 49000).encode(),
      )!;
      expect(read.deviceName, 'phone');
      expect(read.fingerprint, isEmpty);
    });
  });

  group('the roster is keyed on identity and expires', () {
    test('a device that moves to a new address is one row, not two', () {
      // **The rule that keeps the list usable.** A phone changes network; a listener gets a new port every
      // time it starts. Keying the roster on the address would show one device as several -- and a reader
      // who taps the stale row sends a request into the void.
      final roster = DeviceRoster();
      roster.observe(
        announce('Nesarf\'s World', 'AAAA-BBBB-CCCC-DDDD', 49000),
        address: '192.168.31.240',
        nowMillis: 1000,
        rememberedFingerprints: const {'AAAA-BBBB-CCCC-DDDD'},
      );
      roster.observe(
        announce('Nesarf\'s World', 'AAAA-BBBB-CCCC-DDDD', 49001),
        address: '192.168.31.241',
        nowMillis: 2000,
        rememberedFingerprints: const {'AAAA-BBBB-CCCC-DDDD'},
      );

      expect(roster.length, 1);
      expect(roster.devices.single.address, '192.168.31.241');
      expect(roster.devices.single.port, 49001);
    });

    test('a device with no fingerprint is keyed on where it was heard from', () {
      // Until a device has an identity, the address is the only thing that can tell two of them apart.
      final roster = DeviceRoster();
      roster.observe(
        announce('anonymous', '', 49000),
        address: '192.168.31.50',
        nowMillis: 1000,
        rememberedFingerprints: const {},
      );
      roster.observe(
        announce('anonymous', '', 49000),
        address: '192.168.31.51',
        nowMillis: 1000,
        rememberedFingerprints: const {},
      );
      expect(roster.length, 2);
    });

    test('once it has one, the address-keyed row it used to be is gone', () {
      final roster = DeviceRoster();
      roster.observe(
        announce('phone', '', 49000),
        address: '192.168.31.240',
        nowMillis: 1000,
        rememberedFingerprints: const {},
      );
      roster.observe(
        announce('phone', 'AAAA-BBBB-CCCC-DDDD', 49000),
        address: '192.168.31.240',
        nowMillis: 2000,
        rememberedFingerprints: const {},
      );
      expect(roster.length, 1);
      expect(roster.devices.single.fingerprint, 'AAAA-BBBB-CCCC-DDDD');
    });

    test('a device that stops announcing leaves the list', () {
      final roster = DeviceRoster(expiryMillis: 5000);
      roster.observe(
        announce('laptop', 'AAAA', 49000),
        address: '10.0.0.5',
        nowMillis: 1000,
        rememberedFingerprints: const {},
      );
      expect(roster.expire(3000), isFalse, reason: 'still inside the window');
      expect(roster.length, 1);
      expect(roster.expire(6001), isTrue, reason: 'and it says so, so a screen knows to repaint');
      expect(roster.length, 0);
    });

    test('and one that comes back does not flicker out first', () {
      // The window is three announcement intervals, so a single lost datagram must not remove a device.
      final roster = DeviceRoster(expiryMillis: 12000);
      roster.observe(
        announce('laptop', 'AAAA', 49000),
        address: '10.0.0.5',
        nowMillis: 1000,
        rememberedFingerprints: const {},
      );
      roster.observe(
        announce('laptop', 'AAAA', 49000),
        address: '10.0.0.5',
        nowMillis: 6000,
        rememberedFingerprints: const {},
      );
      expect(roster.expire(7000), isFalse);
      expect(roster.length, 1);
    });
  });

  group('identification is automatic', () {
    test('a device this machine has met is marked as remembered with nobody pressing anything', () {
      final roster = DeviceRoster();
      final known = roster.observe(
        announce('NesarfDX', 'CEEA-J38S-G96C-TCSQ', 49000),
        address: '192.168.31.157',
        nowMillis: 1000,
        rememberedFingerprints: const {'CEEA-J38S-G96C-TCSQ'},
      );
      final stranger = roster.observe(
        announce('Device C', 'ZZZZ-YYYY-XXXX-WWWW', 49000),
        address: '192.168.31.99',
        nowMillis: 1000,
        rememberedFingerprints: const {'CEEA-J38S-G96C-TCSQ'},
      );

      expect(known.remembered, isTrue);
      expect(stranger.remembered, isFalse);
    });

    test('the list puts the devices a reader already knows first', () {
      final roster = DeviceRoster();
      roster.observe(
        announce('stranger', 'ZZZZ', 49000),
        address: '10.0.0.9',
        nowMillis: 9000,
        rememberedFingerprints: const {},
      );
      roster.observe(
        announce('known', 'AAAA', 49000),
        address: '10.0.0.5',
        nowMillis: 1000,
        rememberedFingerprints: const {'AAAA'},
      );

      expect(roster.devices.first.name, 'known',
          reason: 'most recently heard is the tiebreak inside a group, not across them');
      expect(roster.devices.last.name, 'stranger');
    });

    test('clearing forgets everything, which is what closing the search does', () {
      final roster = DeviceRoster();
      roster.observe(
        announce('laptop', 'AAAA', 49000),
        address: '10.0.0.5',
        nowMillis: 1000,
        rememberedFingerprints: const {},
      );
      roster.clear();
      expect(roster.length, 0);
    });
  });
}
