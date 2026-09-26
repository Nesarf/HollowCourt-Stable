import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hollow_court/data/sync/firewall_probe.dart';
import 'package:hollow_court/domain/sync/firewall.dart';
import 'package:hollow_court/ui/sync_section.dart';
import 'package:hollow_court/ui/theme.dart';

/// **§10.3.2 ② as a screen: one button, one sentence, and a command to copy.**
///
/// The probe is substituted rather than run, and that is the point of it being a provider: the verdicts that
/// matter are the ones this repository has actually met -- a rule scoped to another program, and a rule scoped to
/// a category the machine is not on -- and neither can be produced on demand by the machine the test runs on.
/// What the real probe finds on this host is asserted in `test/data/sync/firewall_probe_test.dart`.
final class _FixedProbe implements FirewallProbe {
  _FixedProbe(this.facts);

  final FirewallFacts facts;

  @override
  Future<FirewallFacts?> check({required String listenAddress}) async => facts;
}

void main() {
  const program = r'E:\Hollow Court Win\hollow_court.exe';

  FirewallFacts facts({
    required String listenAddress,
    required List<FirewallRule> rules,
    Set<String> categories = const {'Public'},
  }) => FirewallFacts(
    supported: true,
    program: program,
    listenAddress: listenAddress,
    categories: categories,
    rules: rules,
  );

  Future<void> pump(WidgetTester tester, FirewallFacts given) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [firewallProbeProvider.overrideWithValue(_FixedProbe(given))],
        child: MaterialApp(
          theme: HollowTheme.build(),
          home: const Scaffold(body: SingleChildScrollView(child: HostFirewallRow())),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> check(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(const ValueKey('firewall-check')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('firewall-check')));
    await tester.pumpAndSettle();
  }

  testWidgets('**a machine with no rule is told so, and offered a command to copy**', (tester) async {
    await pump(
      tester,
      facts(listenAddress: '192.168.31.157', rules: const []),
    );

    expect(find.text(Copy.firewallCheck.primary.text), findsOneWidget);
    await check(tester);

    // The one sentence, and it names the actual cause rather than a timeout.
    expect(find.text(Copy.firewallVerdictNoRule.primary.text), findsOneWidget);
    // The facts behind it, because a reader who wants to argue with the answer needs to see what it was made of.
    expect(find.text(program), findsOneWidget);
    expect(find.text('Public'), findsOneWidget);

    // The command: program-scoped, and selectable so it can be copied by hand as well as by button.
    final command = tester
        .widget<SelectableText>(find.byKey(const ValueKey('firewall-command')))
        .data!;
    expect(command, contains('program="$program"'));
    expect(command, contains('profile=any'));

    // And the button copies it.
    final clipboard = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    await tester.ensureVisible(find.byKey(const ValueKey('firewall-copy')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('firewall-copy')));
    await tester.pumpAndSettle();
    expect(clipboard, [command]);
    expect(find.text(Copy.firewallCopied.primary.text), findsOneWidget);
  });

  testWidgets('**a machine that is covered is told that, and is not handed a rule it does not need**',
      (tester) async {
    await pump(
      tester,
      facts(
        listenAddress: '192.168.31.157',
        rules: const [
          FirewallRule(
            name: 'Hollow Court app (inbound TCP)',
            profiles: {'any'},
            enabled: true,
            action: FirewallAction.allow,
          ),
        ],
      ),
    );
    await check(tester);

    expect(find.text(Copy.firewallVerdictOpen.primary.text), findsOneWidget);
    expect(find.text('Hollow Court app (inbound TCP)'), findsOneWidget);
    // **A command under a verdict of "fine" would invite a reader to add a rule they do not need**, which is the
    // one thing this row is allowed not to do: it reports, and offers, and never changes anything itself.
    expect(find.byKey(const ValueKey('firewall-command')), findsNothing);
    expect(find.byKey(const ValueKey('firewall-copy')), findsNothing);
  });

  testWidgets('the `-Profile Private` failure is its own sentence, because its fix is different',
      (tester) async {
    await pump(
      tester,
      facts(
        listenAddress: '192.168.31.157',
        categories: const {'Public'},
        rules: const [
          FirewallRule(
            name: 'Hollow Court sync',
            profiles: {'private'},
            enabled: true,
            action: FirewallAction.allow,
          ),
        ],
      ),
    );
    await check(tester);

    expect(find.text(Copy.firewallVerdictWrongProfile.primary.text), findsOneWidget);
    // The rule is still named, because "a rule exists and does not cover this network" is a statement about *that*
    // rule -- and widening it is the whole fix.
    expect(find.text('Hollow Court sync'), findsOneWidget);
    expect(find.byKey(const ValueKey('firewall-command')), findsOneWidget);
  });

  testWidgets('a listener on loopback is reported before the firewall is even considered', (tester) async {
    await pump(
      tester,
      facts(
        listenAddress: '127.0.0.1',
        rules: const [
          FirewallRule(
            name: 'anything',
            profiles: {'any'},
            enabled: true,
            action: FirewallAction.allow,
          ),
        ],
      ),
    );
    await check(tester);
    expect(find.text(Copy.firewallVerdictLoopback.primary.text), findsOneWidget);
  });
}
