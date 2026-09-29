import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hollow_court/ui/l10n/locale_settings.dart';
import 'package:hollow_court/ui/l10n/locale_providers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hollow_court/domain/sync/device_identity.dart';
import 'package:hollow_court/domain/sync/discovery.dart';
import 'package:hollow_court/ui/discovery_providers.dart';
import 'package:hollow_court/ui/sync_section.dart';
import 'package:hollow_court/ui/theme.dart';

/// **The nearby list: what it says, and what a tap does.**
///
/// The provider is overridden rather than fed by real datagrams, because what is being tested here is the
/// screen's behaviour and not the socket -- the socket has six tests of its own, two of which open real ones.
///
/// **Since §10.3.2 a tap no longer connects.** It opens a box carrying everything the announcement knows -- name,
/// address and port, fingerprint, whether this machine has met the device, and what pressing the button will do
/// -- and the connection happens only if the reader agrees. Most of these tests are about that difference: what
/// the box says, that cancelling connects to nothing, and that a stranger is offered the six digits rather than
/// a code field.
/// The fingerprint as an announcement carries it: the digest in groups of four. The real one comes from
/// `DeviceIdentity.fingerprint`; this mirrors it so a fixture cannot quietly disagree with the wire again.
String _grouped(String digest) => [
  for (var at = 0; at < digest.length; at += 4) digest.substring(at, at + 4),
].join('-');

void main() {
  DiscoveredDevice device({
    required String name,
    required String fingerprint,
    required bool remembered,
  }) => DiscoveredDevice(
    name: name,
    fingerprint: fingerprint,
    address: '192.168.31.240',
    port: 48125,
    lastSeenMillis: 1000,
    remembered: remembered,
    version: '1.0.0',
  );

  Future<void> pumpList(
    WidgetTester tester,
    List<DiscoveredDevice> devices, {
    required List<TrustedDevice> known,
    required List<String> connected,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
       
      overrides: [
        localeSettingsProvider.overrideWith(() => _FixedLocale(
          const LocaleSettings(primaryTag: 'zh-Hans', secondaryTag: 'en', dualCopy: true),
        )),
          discoveredDevicesProvider.overrideWith(
            (ref) => Stream.value(devices),
          ),
        ],
        child: MaterialApp(
          theme: HollowTheme.build(),
          home: Scaffold(
            body: _Harness(known: known, connected: connected),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('**a remembered device is labelled, and its tap asks first**', (tester) async {
    final connected = <String>[];
    // **The announcement carries the GROUPED spelling, not the digest**, and this test used to write the digest on
    // both sides -- which is why it passed while every real device was labelled 新设备. `grouped` is the same
    // transformation `DeviceIdentity.fingerprint` applies, done here so the fixture says what the wire says.
    final fingerprint = _grouped(DeviceIdentity.fingerprintOf('the-key-that-is-trusted'));
    await pumpList(
      tester,
      [device(name: 'phone', fingerprint: fingerprint, remembered: true)],
      known: [TrustedDevice(publicKey: 'the-key-that-is-trusted', name: 'phone')],
      connected: connected,
    );

    expect(find.text('phone'), findsWidgets);
    final row = find.byKey(ValueKey('nearby-$fingerprint'));
    expect(row, findsOneWidget, reason: 'a remembered device is listed');
    await tester.tap(row);
    await tester.pumpAndSettle();

    // **The box, and every field on it comes from the announcement.** Name, address and port, the fingerprint in
    // groups a person can read across a table, and the two rows derived from the store.
    expect(find.text(Copy.syncConnectTitle.primary.text), findsOneWidget);
    expect(find.text('phone'), findsWidgets);
    expect(find.text('192.168.31.240:48125'), findsOneWidget);
    // **Spelled out rather than recomputed through the widget's own helper.** The first version of this assertion
    // called `ConnectBox.grouped`, so it agreed with whatever that method did -- including grouping an
    // already-grouped string into `ABCD -EFG H-IJ KL-M NOP`, which is what a real screen showed.
    final digest = DeviceIdentity.fingerprintKey(fingerprint);
    expect(
      find.text([
        for (var at = 0; at < digest.length; at += 4) digest.substring(at, at + 4),
      ].join(' ')),
      findsOneWidget,
      reason: 'the fingerprint is the one value a device cannot invent about itself',
    );
    expect(find.text(Copy.syncConnectRememberedYes.primary.text), findsOneWidget);
    expect(
      find.text(Copy.syncConnectNextStraight.primary.text),
      findsOneWidget,
      reason: 'a device this machine has met syncs on the key it learned',
    );
    expect(connected, isEmpty, reason: 'nothing has happened yet');

    await tester.tap(find.byKey(const ValueKey('nearby-connect')));
    await tester.pumpAndSettle();
    expect(connected, [fingerprint], reason: 'the tap went to the remembered sync once confirmed');
  });

  testWidgets('**a stranger is marked as new, and the box offers the six digits rather than a code**',
      (tester) async {
    final connected = <String>[];
    await pumpList(
      tester,
      [device(name: 'somebody', fingerprint: 'abcdef123456', remembered: false)],
      known: const [],
      connected: connected,
    );

    expect(find.textContaining(Copy.syncNearbyNew.primary.text), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('nearby-abcdef123456')));
    await tester.pumpAndSettle();

    expect(find.text(Copy.syncConnectRememberedNo.primary.text), findsOneWidget);
    expect(
      find.text(Copy.syncConnectNextCompare.primary.text),
      findsOneWidget,
      reason: 'a stranger has no key to be reached with, so two screens are compared',
    );

    await tester.tap(find.byKey(const ValueKey('nearby-connect')));
    await tester.pumpAndSettle();
    expect(connected, ['abcdef123456']);
  });

  testWidgets('**cancelling the box connects to nothing at all**', (tester) async {
    final connected = <String>[];
    await pumpList(
      tester,
      [device(name: 'somebody', fingerprint: 'abcdef123456', remembered: false)],
      known: const [],
      connected: connected,
    );

    await tester.tap(find.byKey(const ValueKey('nearby-abcdef123456')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('nearby-cancel')));
    await tester.pumpAndSettle();

    expect(find.text(Copy.syncConnectTitle.primary.text), findsNothing);
    expect(connected, isEmpty, reason: 'the reader did not agree, so no request went out');
  });

  testWidgets('a device that announced no fingerprint is shown as unknown rather than as itself',
      (tester) async {
    final connected = <String>[];
    await pumpList(
      tester,
      [device(name: 'nameless', fingerprint: '', remembered: false)],
      known: const [],
      connected: connected,
    );

    // No fingerprint means no identity to compare, and the box says so instead of drawing an empty row. The row
    // is keyed by address when there is no fingerprint, which is `DiscoveredDevice.identityKey`'s rule.
    await tester.tap(find.byKey(const ValueKey('nearby-addr:192.168.31.240:48125')));
    await tester.pumpAndSettle();
    expect(find.text(Copy.firewallNone.primary.text), findsOneWidget);
    expect(find.text(Copy.syncConnectRememberedNo.primary.text), findsOneWidget);
  });

  testWidgets('an empty network draws no heading at all, rather than a promise nobody can keep',
      (tester) async {
    await pumpList(tester, const [], known: const [], connected: []);
    expect(find.text(Copy.syncNearbyTitle.primary.text), findsNothing);
  });
}

/// **The real widget, not a stand-in.** The first version of this test carried a probe that duplicated the
/// recognition rule, which would have kept passing after the screen stopped following it -- so the widget is
/// public and the test drives it directly.
class _Harness extends StatelessWidget {
  const _Harness({required this.known, required this.connected});

  final List<TrustedDevice> known;
  final List<String> connected;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      NearbyDevices(
        known: known,
        onConnect: (device) => connected.add(device.identityKey),
      ),
    ],
  );
}


/// The copy language pinned to Chinese for this file, so that assertions written against the authored
/// sentences do not depend on the platform locale of the machine running the tests.
class _FixedLocale extends LocaleSettingsNotifier {
  _FixedLocale(this._initial);

  final LocaleSettings _initial;

  @override
  LocaleSettings build() => _initial;
}
