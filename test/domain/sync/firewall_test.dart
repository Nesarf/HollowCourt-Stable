import 'package:flutter_test/flutter_test.dart';
import 'package:hollow_court/domain/sync/firewall.dart';

/// **The host's own answer about its own inbound door, tested on the reports this machine actually produces.**
///
/// The two cases that matter are not hypothetical: this repository's connection test ① was blocked twice before it
/// worked -- once by a rule scoped `-Profile Private` on a wireless Windows classifies **Public**, and once by
/// relying on a rule that was scoped to a *different program*. Both are tests here, because a mistake that cost a
/// real session should not be able to come back as a mistake.
void main() {
  /// The report `data/sync/firewall_probe.dart` prints, with the fields filled in.
  String report({required String categories, required List<String> rules}) =>
      'category=$categories\nrules=${rules.join(';')}\n';

  FirewallFacts factsFrom(
    String output, {
    String listenAddress = '192.168.31.157',
    bool supported = true,
  }) => parseFirewallReport(
    output,
    program: r'E:\Hollow Court Win\hollow_court.exe',
    listenAddress: listenAddress,
    supported: supported,
  )!;

  group('reading what Windows reported', () {
    test('a rule naming this program is read with its profile, state and action', () {
      final facts = factsFrom(
        report(
          categories: 'Public',
          rules: ['Hollow Court app (inbound TCP)|Any|True|Allow'],
        ),
      );

      expect(facts.categories, {'Public'});
      expect(facts.rules.single.name, 'Hollow Court app (inbound TCP)');
      expect(facts.rules.single.profiles, {'any'});
      expect(facts.rules.single.enabled, isTrue);
      expect(facts.rules.single.action, FirewallAction.allow);
      expect(verdictOf(facts), FirewallVerdict.open);
    });

    test('a rule line that cannot be read is dropped and the rest are kept', () {
      // One unreadable rule is not a reason to say nothing about the others -- the same rule the event log
      // follows for a line it cannot parse.
      final facts = factsFrom(
        report(
          categories: 'Public',
          rules: ['nonsense', 'a real rule|Public|True|Allow', '|Public|True|Allow'],
        ),
      );

      expect(facts.rules.map((rule) => rule.name), ['a real rule']);
      expect(verdictOf(facts), FirewallVerdict.open);
    });

    test('output with nothing this build understands is not a report at all', () {
      expect(
        parseFirewallReport(
          'Get-NetFirewallRule : Access is denied.',
          program: 'x',
          listenAddress: '192.168.31.157',
          supported: true,
        ),
        isNull,
      );
    });
  });

  group('the two mistakes that actually happened', () {
    test('**a rule scoped Private does nothing on a Public wireless**', () {
      // Connection test ①, first attempt: `-Profile Private` on a network Windows had classified Public. The rule
      // was there, it was enabled, and it covered nothing.
      final facts = factsFrom(
        report(
          categories: 'Public',
          rules: ['Hollow Court sync|Private|True|Allow'],
        ),
      );

      expect(verdictOf(facts), FirewallVerdict.wrongProfile);
    });

    test('and it is not reported as "no rule", because the fix is different', () {
      // The reader has to widen a rule they already made rather than make one -- so the verdict is its own, which
      // is the whole reason `wrongProfile` is not folded into `noRule`.
      final facts = factsFrom(
        report(categories: 'Public', rules: ['Hollow Court sync|Private|True|Allow']),
      );
      expect(verdictOf(facts), isNot(FirewallVerdict.noRule));
    });

    test('a rule for another program is not a rule for this one', () {
      // The second attempt: the existing "Hollow Court sync probe" rule was scoped to the probe's program, so it
      // never covered `hollow_court.exe`. The probe's rule does not appear here at all -- because the query asks
      // Windows for rules naming *this* executable -- and the verdict is therefore "no rule".
      final facts = factsFrom(report(categories: 'Public', rules: const []));
      expect(verdictOf(facts), FirewallVerdict.noRule);
    });
  });

  group('the other three ways a host cannot be reached', () {
    test('nothing listening on the network is its own sentence', () {
      final facts = factsFrom(
        report(categories: 'Public', rules: ['anything|Any|True|Allow']),
        listenAddress: '',
      );
      expect(verdictOf(facts), FirewallVerdict.noAddress);
    });

    test('a listener on loopback is unreachable however good the rule is', () {
      final facts = factsFrom(
        report(categories: 'Public', rules: ['anything|Any|True|Allow']),
        listenAddress: '127.0.0.1',
      );
      expect(verdictOf(facts), FirewallVerdict.loopbackOnly);
    });

    test('off Windows the answer is "cannot tell", never "fine"', () {
      final facts = factsFrom(
        report(categories: 'Public', rules: ['anything|Any|True|Allow']),
        supported: false,
      );
      expect(verdictOf(facts), FirewallVerdict.unknown);
    });
  });

  group('the command a reader copies', () {
    test('**it is scoped to the program, not to a port, and covers every profile**', () {
      const program = r'E:\Hollow Court Win\hollow_court.exe';
      final command = allowCommandFor(program);

      expect(command, contains('program="$program"'));
      // The port is ephemeral, so a port rule would have to be redone every session; and `profile=any` is what
      // keeps a reader who changes networks from meeting the `-Profile Private` failure a second time.
      expect(command, contains('profile=any'));
      expect(command, isNot(contains('localport')));
      expect(command, startsWith('netsh advfirewall firewall add rule'));
      expect(command, contains('dir=in action=allow'));
    });

    test('the program path is the one the operating system reported, untouched', () {
      // Windows compares these strings as they are, so a helper that tidied the case here would make the check say
      // "covered" about a machine that is not.
      expect(
        programPathFor(r'E:\Hollow Court Win\hollow_court.exe'),
        r'E:\Hollow Court Win\hollow_court.exe',
      );
    });
  });
}
