import 'package:hollow_court/domain/sync/discovery.dart';
import 'package:hollow_court/domain/sync/names.dart';
import 'package:test/test.dart';

/// Two names, one presentation, and the rules that keep them from producing a blank row in somebody
/// else's list.
///
/// The owner's words: *"在设置一栏里，里面可以给自己的空庭命名，然后对外同步的时候可以选择'同步时使用的名义'，
/// 即设备名称和空庭名称二选一。"* What these tests are mostly about is the case nobody thinks about until
/// it happens -- **the cellar name is a setting a person may not have filled in yet**.
void main() {
  group('a device always has a name, even when the machine will not say one', () {
    test('the operating system\'s name is used when it is a real one', () {
      expect(SyncNames.defaultsFor('NesarfDX', isAndroid: false).deviceName, 'NesarfDX');
      expect(SyncNames.defaultsFor('  NesarfDX  ', isAndroid: false).deviceName, 'NesarfDX');
    });

    test('**and Android\'s `localhost` is not a name**', () {
      // `Platform.localHostname` answers `localhost` on Android, which would put every phone in the world
      // into a peer's list under the same name. A name that identifies nobody is worse than a generic one,
      // because it looks like an answer.
      expect(SyncNames.defaultsFor('localhost', isAndroid: true).deviceName, 'Android 设备');
      expect(SyncNames.defaultsFor('', isAndroid: true).deviceName, 'Android 设备');
      expect(SyncNames.defaultsFor('LOCALHOST', isAndroid: false).deviceName, '这台设备');
      expect(SyncNames.defaultsFor('   ', isAndroid: false).deviceName, '这台设备');
    });
  });

  group('which name is presented', () {
    test('the device name by default, and the cellar name when asked for', () {
      const names = SyncNames(deviceName: 'NesarfDX', cellarName: '试验酒窖');
      expect(names.presented, 'NesarfDX');
      expect(names.withChoice(NameChoice.cellar).presented, '试验酒窖');
      expect(names.withChoice(NameChoice.device).presented, 'NesarfDX');
    });

    test('**a name that does not exist cannot be presented**', () {
      // Choosing the cellar name before naming the cellar is the ordinary case -- the setting is a
      // two-option control and the name is a text field somebody may not have filled in. Falling back to
      // the device name keeps the announcement usable; sending an empty name would put a blank row in
      // another device's list, which a reader cannot act on.
      const unnamed = SyncNames(deviceName: 'NesarfDX', shows: NameChoice.cellar);
      expect(unnamed.presented, 'NesarfDX');
      expect(unnamed.wantsAnUnnamedCellar, isTrue,
          reason: 'and a settings screen has to say so rather than silently ignoring the choice');

      const named = SyncNames(deviceName: 'NesarfDX', cellarName: '试验酒窖', shows: NameChoice.cellar);
      expect(named.wantsAnUnnamedCellar, isFalse);
    });

    test('a cellar name of nothing but spaces counts as unnamed', () {
      const spaces = SyncNames(deviceName: 'NesarfDX', cellarName: '   ', shows: NameChoice.cellar);
      expect(spaces.presented, 'NesarfDX');
      expect(spaces.wantsAnUnnamedCellar, isTrue);
    });

    test('the choice is a presentation, not an identity', () {
      // Switching names must not make one device look like another: the fingerprint is what recognises a
      // device, and it travels beside whichever name is shown.
      const before = SyncNames(deviceName: 'NesarfDX', cellarName: '试验酒窖');
      const after = SyncNames(
        deviceName: 'NesarfDX',
        cellarName: '试验酒窖',
        shows: NameChoice.cellar,
      );
      expect(before.presented, isNot(after.presented));

      final roster = DeviceRoster();
      roster.observe(
        const DiscoveryAnnounce(deviceName: 'NesarfDX', port: 49000, fingerprint: 'AAAA'),
        address: '10.0.0.5',
        nowMillis: 1000,
        rememberedFingerprints: const {'AAAA'},
      );
      roster.observe(
        const DiscoveryAnnounce(
          deviceName: 'NesarfDX',
          cellarName: '试验酒窖',
          shows: NameChoice.cellar,
          port: 49000,
          fingerprint: 'AAAA',
        ),
        address: '10.0.0.5',
        nowMillis: 2000,
        rememberedFingerprints: const {'AAAA'},
      );
      expect(roster.length, 1, reason: 'the same device, renamed as far as the list is concerned');
      expect(roster.devices.single.name, '试验酒窖');
      expect(roster.devices.single.remembered, isTrue, reason: 'and still recognised');
    });
  });

  group('what travels on the wire', () {
    test('both names and the choice, so a peer can say whose cellar this is on whose machine', () {
      const original = DiscoveryAnnounce(
        deviceName: 'NesarfDX',
        cellarName: '试验酒窖',
        shows: NameChoice.cellar,
        port: 49000,
        fingerprint: 'AAAA',
      );
      final read = DiscoveryAnnounce.parse(original.encode())!;
      expect(read.deviceName, 'NesarfDX');
      expect(read.cellarName, '试验酒窖');
      expect(read.displayName, '试验酒窖');
    });

    test('and a peer that only gets a device name still shows a usable one', () {
      const plain = DiscoveryAnnounce(deviceName: 'Nesarf\'s World', port: 49000);
      final read = DiscoveryAnnounce.parse(plain.encode())!;
      expect(read.displayName, 'Nesarf\'s World');
      expect(read.cellarName, isEmpty);
    });

    test('a packet is small enough to be one datagram', () {
      // UDP, on every announce, from every device, once every few seconds. A packet that fragments is a
      // packet that gets lost on a busy network -- and two names is the most this will ever carry.
      const worst = DiscoveryAnnounce(
        deviceName: 'Nesarf\'s World (Pixel 10 Pro XL, borrowed for the weekend)',
        cellarName: '试验酒窖 · 主酒窖 · 只放威士忌的那一间',
        shows: NameChoice.cellar,
        port: 65535,
        fingerprint: 'CEEA-J38S-G96C-TCSQ',
        version: '1.0.0',
      );
      expect(worst.encode().length, lessThan(400));
    });

    test('an unrecognised choice falls back to the name every device has', () {
      // A value written by a later version. Inventing a name from a field this build does not understand
      // would be worse than the one that is certainly true.
      final read = DiscoveryAnnounce.parse(
        '{"hollow":1,"device":"NesarfDX","cellar":"试验酒窖","show":"something-new","port":49000}',
      )!;
      expect(read.shows, NameChoice.device);
      expect(read.displayName, 'NesarfDX');
    });
  });

  group('stored names survive being read back by a build that knows less', () {
    test('a full round trip', () {
      const names = SyncNames(
        deviceName: 'NesarfDX',
        cellarName: '试验酒窖',
        shows: NameChoice.cellar,
      );
      final read = SyncNames.fromJson(names.toJson(), fallbackDeviceName: 'fallback');
      expect(read.deviceName, 'NesarfDX');
      expect(read.cellarName, '试验酒窖');
      expect(read.shows, NameChoice.cellar);
    });

    test('a missing field is defaulted, and the rest of the file is kept', () {
      // Refusing the whole file would throw away a name the owner chose because of a field they never set.
      final read = SyncNames.fromJson(
        const {'cellarName': '试验酒窖'},
        fallbackDeviceName: 'NesarfDX',
      );
      expect(read.deviceName, 'NesarfDX');
      expect(read.cellarName, '试验酒窖');
      expect(read.shows, NameChoice.device);
    });

    test('an empty stored device name falls back rather than becoming blank', () {
      final read = SyncNames.fromJson(
        const {'deviceName': '   ', 'cellarName': 'x'},
        fallbackDeviceName: 'NesarfDX',
      );
      expect(read.deviceName, 'NesarfDX');
    });
  });
}
