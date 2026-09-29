import 'dart:io';

import '../../domain/sync/firewall.dart';

/// **The two questions only the operating system can answer, asked once each** (§10.3.2 ②).
///
/// Everything decidable without a process is decided in `domain/sync/firewall.dart`; this is the part that has to
/// talk to Windows. It is deliberately two reads and no writes: **the check never changes the firewall**, it
/// reports and offers a command for a person to run. A program that silently widened a firewall rule on startup
/// would be a worse neighbour than the timeout this replaces.
///
/// **One PowerShell invocation rather than three.** Each one costs about a second and a half on this machine
/// (measured: `Get-NetFirewallApplicationFilter` over the active store), and three would be five seconds of a
/// screen that looks frozen; the script prints two lines the parser reads.
///
/// **Nothing is written to disk.** No temporary script file, no output file -- the whole thing travels as an
/// argument, which also means there is nothing to leave behind on a machine whose disk policy is somebody
/// else's.
abstract interface class FirewallProbe {
  /// The rule report, or null when the tooling could not be run at all.
  ///
  /// [listenAddress] is what the caller already knows about its own listener -- the check does not try to
  /// discover it, because the process that bound the socket is the one that knows where it bound it.
  Future<FirewallFacts?> check({required String listenAddress});
}

/// The real one, over `powershell.exe`.
///
/// **An interface with one implementation, and not for symmetry.** The row's interesting behaviour is which
/// sentence a verdict produces and when the command appears, and the two verdicts worth testing are the ones this
/// repository has actually met -- a rule scoped to another program, and a rule scoped to a category the machine is
/// not on. Neither can be produced on demand on the machine running the test, so the seam is what makes them
/// assertable; the real query is covered by `test/data/sync/firewall_probe_test.dart`, which runs it for real.
final class HostFirewallProbe implements FirewallProbe {
  const HostFirewallProbe();

  @override
  Future<FirewallFacts?> check({required String listenAddress}) async {
    if (!Platform.isWindows) {
      return FirewallFacts(
        supported: false,
        program: programPathFor(Platform.resolvedExecutable),
        listenAddress: listenAddress,
        categories: const {},
        rules: const [],
      );
    }

    final program = programPathFor(Platform.resolvedExecutable);
    final output = await _run(_script(program));
    if (output == null) {
      return FirewallFacts(
        supported: false,
        program: program,
        listenAddress: listenAddress,
        categories: const {},
        rules: const [],
      );
    }
    return parseFirewallReport(
      output,
      program: program,
      listenAddress: listenAddress,
      supported: true,
    );
  }

  /// The script, as a single argument.
  ///
  /// **`-PolicyStore ActiveStore` and not the default.** The default store is the persistent one, which is what a
  /// rule is written to and also what shows rules from a Group Policy that the machine is not obeying; the active
  /// store is what is actually in force, which is the question being asked.
  ///
  /// **`Get-NetFirewallApplicationFilter` first and then the rule**, rather than every rule and then its filter:
  /// the reverse order asks Windows for the filter of several hundred rules one at a time, which is the
  /// difference between 1.6 s and half a minute.
  String _script(String program) {
    final escaped = program.replaceAll("'", "''");
    return '''
\$ErrorActionPreference = 'Stop';
\$program = '$escaped';
\$categories = (Get-NetConnectionProfile | Select-Object -ExpandProperty NetworkCategory | Sort-Object -Unique) -join ',';
'category=' + \$categories;
\$rules = Get-NetFirewallApplicationFilter -PolicyStore ActiveStore |
  Where-Object { \$_.Program -eq \$program } |
  ForEach-Object {
    \$rule = \$_ | Get-NetFirewallRule;
    '{0}|{1}|{2}|{3}' -f \$rule.DisplayName, \$rule.Profile, \$rule.Enabled, \$rule.Action
  };
'rules=' + (\$rules -join ';')
''';
  }

  /// Runs PowerShell and answers with its stdout, or null when it could not be run or said nothing.
  ///
  /// **Bounded, because a screen is waiting.** A firewall query has no business taking longer than a few seconds,
  /// and a hung one that left a spinner on the screen forever would be a worse failure than the one this check
  /// exists to explain.
  Future<String?> _run(String script) async {
    try {
      final result = await Process.run(
        'powershell.exe',
        ['-NoProfile', '-NonInteractive', '-Command', script],
        stdoutEncoding: const SystemEncoding(),
      ).timeout(const Duration(seconds: 20));
      if (result.exitCode != 0) return null;
      final text = result.stdout is String ? result.stdout as String : '';
      return text.trim().isEmpty ? null : text;
    } on Object {
      // Not installed, not runnable, or too slow: all three are "this machine cannot answer that question",
      // which the verdict already has a sentence for.
      return null;
    }
  }
}
