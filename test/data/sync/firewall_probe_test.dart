import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hollow_court/data/sync/firewall_probe.dart';
import 'package:hollow_court/domain/sync/firewall.dart';

/// **The real probe, against the real firewall, on the machine running the test.**
///
/// The domain's parsing is tested against captured text and the row is tested against a substituted probe; this is
/// the third thing, and it is the one that cannot be faked: `powershell.exe` runs, Windows answers, and the bytes
/// come back through the same parse the application uses. Its assertions are deliberately loose -- what it
/// establishes is that the query *works here* and that the answer is about this executable, not that this machine
/// happens to be covered or uncovered, which changes with every rule somebody adds.
///
/// **Skipped off Windows**, because the honest answer there is "the question does not apply" rather than a failure:
/// `HostFirewallProbe` returns `supported: false` and the row is not drawn at all.
void main() {
  test('the probe asks this machine about itself and gets a readable answer', () async {
    if (!Platform.isWindows) {
      return;
    }
    final facts = await const HostFirewallProbe().check(listenAddress: '192.168.31.157');

    expect(facts, isNotNull, reason: 'PowerShell ran and printed something this build understands');
    expect(facts!.supported, isTrue);
    // **The program is the one running this test**, which is what makes the answer about *this* build rather than
    // about whatever executable the last round installed.
    expect(facts.program, Platform.resolvedExecutable);
    // A machine on a network has a category; a machine that is not on one has an empty set, which is an answer
    // rather than a failure -- so what is asserted is that the report parsed, not what it says.
    expect(
      facts.categories.length + facts.rules.length,
      greaterThan(0),
      reason: 'either the network category or the rule list has to have come back',
    );
    // The verdict is one of the five, and the one that means "the question could not be asked" is not it: the
    // tooling ran.
    expect(verdictOf(facts), isNot(FirewallVerdict.unknown));

    // Printed rather than only asserted, because the useful part for a person reading a test log is what this
    // machine actually reports -- the same reason the driving script prints a hash instead of saying "unchanged".
    // ignore: avoid_print
    print(
      'firewall probe: program=${facts.program} '
      'categories=${facts.categories.join(",")} '
      'rules=${facts.rules.map((rule) => "${rule.name}[${rule.profiles.join(",")}]").join(" | ")} '
      'verdict=${verdictOf(facts).name}',
    );
  });
}
