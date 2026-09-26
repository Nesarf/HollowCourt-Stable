import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hollow_court/domain/sync/lan_address.dart';
import 'package:hollow_court/ui/sync_section.dart';
import 'package:hollow_court/ui/theme.dart';

/// **The four link modes, on the screen.**
///
/// The modes had eleven domain tests and no reader could see which one they were on -- and the difference
/// matters most exactly where this feature is hardest: a tunnel works across two networks that cannot see each
/// other, a wireless network may have client isolation, and a USB tether is neither.
void main() {
  Future<void> pump(WidgetTester tester, LanCandidate? candidate) async {
    await tester.pumpWidget(
      ProviderScope(
        // **A key per case, because a `ProviderScope` is reused across pumps in one test** and its overrides
        // would not be reapplied: without this, every iteration after the first asserts against the first
        // case's answer -- which is exactly the kind of passing-for-the-wrong-reason a loop hides.
        // **Keyed by the interface name, not by the candidate's `toString()`** -- which does not include
        // it, so four different cases produced one key and the container was reused. That made the loop assert
        // against the first case four times, and it passed three of them by accident.
        key: ValueKey('scope-${candidate?.interfaceName}'),
        overrides: [lanCandidateProvider.overrideWith((ref) async => candidate)],
        child: MaterialApp(
          theme: HollowTheme.build(),
          home: const Scaffold(body: LinkRow()),
        ),
      ),
    );
    // Twice: the candidate arrives from a `Future`, so the first frame is the loading state and the second is
    // the answer. A single pump would assert against "no LAN address" and pass or fail by accident.
    await tester.pump();
    await tester.pump();
  }

  LanCandidate at(String interfaceName) =>
      LanCandidate(interfaceName: interfaceName, address: '192.168.31.157');

  testWidgets('**each mode is named, and the interface is shown beside the address**', (tester) async {
    for (final (name, label) in [
      ('eth0', Copy.syncLinkWired),
      ('wlan0', Copy.syncLinkWireless),
      ('rndis0', Copy.syncLinkUsb),
      ('tun0', Copy.syncLinkTunnel),
    ]) {
      await pump(tester, at(name));
      expect(
        find.textContaining(label.primary.text),
        findsOneWidget,
        reason: '$name should read as ${label.primary.text}',
      );
      expect(find.textContaining('192.168.31.157'), findsOneWidget);
      expect(find.textContaining(name), findsOneWidget, reason: 'the interface is named, not hidden');
    }
  });

  testWidgets('**an interface nobody can classify says so rather than guessing**', (tester) async {
    // A virtual adapter or a driver's own name: `classifyLink` returns null, and the honest line is that
    // nobody knows what this link is -- the sync is still attempted, and a failure has its reason on screen.
    await pump(tester, at('vEthernet (WSL)'));
    expect(find.textContaining(Copy.syncLinkUnknown.primary.text), findsOneWidget);
  });

  testWidgets('a machine with no LAN address says that, instead of showing nothing', (tester) async {
    await pump(tester, null);
    expect(find.text(Copy.syncLinkNone.primary.text), findsOneWidget);
  });
}
