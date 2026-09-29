/// **What a host can find out about its own inbound door, and the one sentence it owes the other end.**
///
/// §10.3.2's second request exists because of what a failure looked like from the outside: the machine that
/// could not be reached said nothing at all, and the phone said `Connection timed out`. Everything a person
/// needed was knowable on the host -- is the listener on an address the network can reach, which category does
/// Windows think this network is, and is this program covered by an inbound rule -- and none of it was being
/// asked.
///
/// **The parsing lives here and the process does not.** Everything in this file takes text and returns values,
/// so the interesting cases -- a WLAN classified `Public`, a rule scoped to another program, a rule that exists
/// but covers only `Private` -- are testable without a firewall, and the two of those this repository has
/// actually been bitten by are tests rather than anecdotes (`test/domain/sync/firewall_test.dart`).
///
/// **Why a program rule rather than a port rule.** The listener's port is ephemeral (10838 on the day this was
/// written, and a different number next time), so a port rule has to be redone every session and is wrong in
/// between. A program rule covers every port that binary will ever open, which is both narrower in what it can
/// let through and permanent.
library;

/// Whether a rule lets traffic in or keeps it out.
enum FirewallAction { allow, block }

/// One rule that names this program, as Windows reports it.
final class FirewallRule {
  const FirewallRule({
    required this.name,
    required this.profiles,
    required this.enabled,
    required this.action,
  });

  const FirewallRule.disabled(String name)
    : this(name: name, profiles: const {}, enabled: false, action: FirewallAction.block);

  final String name;

  /// The categories the rule applies to, lower case. `any` is the whole set rather than an empty one, because
  /// the two are different things and only one of them lets traffic through.
  final Set<String> profiles;

  final bool enabled;
  final FirewallAction action;

  /// Whether this rule would let a peer in when the machine is on [category].
  bool covers(String category) {
    if (!enabled || action != FirewallAction.allow) return false;
    if (profiles.contains('any')) return true;
    return profiles.contains(category.toLowerCase().trim());
  }
}

/// What the host found out about itself.
final class FirewallFacts {
  const FirewallFacts({
    required this.supported,
    required this.program,
    required this.listenAddress,
    required this.categories,
    required this.rules,
  });

  /// False off Windows, or when the tooling is missing: the answer is then "cannot tell", not "fine".
  final bool supported;

  /// The executable a rule has to name, as the operating system reports it.
  final String program;

  /// The address the listener is bound to, or empty when nothing is listening.
  final String listenAddress;

  /// The network categories this machine is currently on -- usually one, and two when a laptop is on a cable
  /// and a wireless at the same time.
  final Set<String> categories;

  final List<FirewallRule> rules;

  /// **Whether the listener is somewhere a peer on the network can get to.**
  ///
  /// Two ways to fail, kept apart because they send a reader to different places: no address at all means this
  /// machine is not on a network (the row above the check already says so in `syncLinkNone`), while an address
  /// that is loopback or the wildcard means the socket is bound where nobody outside can reach it -- and that
  /// one otherwise looks like nothing at all, because such a listener accepts every connection from this machine.
  bool get listeningOnTheNetwork {
    if (listenAddress.isEmpty) return false;
    if (listenAddress.startsWith('127.')) return false;
    if (listenAddress == '0.0.0.0') return false;
    return true;
  }

  /// Whether there is an address at all, which is a different question from whether it is reachable.
  bool get hasAddress => listenAddress.isNotEmpty;

  /// The rules that would actually let a peer in on the network this machine is on.
  List<FirewallRule> get covering => [
    for (final rule in rules)
      if (categories.any(rule.covers)) rule,
  ];

  /// The rules that name this program and let something through, whether or not they cover this network.
  List<FirewallRule> get allowing => [
    for (final rule in rules)
      if (rule.enabled && rule.action == FirewallAction.allow) rule,
  ];
}

/// What the host should say, in one sentence, about its own door.
enum FirewallVerdict {
  /// Nothing in the way: listening on the network and covered by a rule.
  open,

  /// The listener is not on an address the network can reach.
  loopbackOnly,

  /// This machine has no network address at all, so there is nothing for a peer to connect to.
  noAddress,

  /// No inbound rule names this program at all.
  noRule,

  /// A rule names this program, but not for the category this network is in.
  wrongProfile,

  /// The question could not be asked -- not Windows, or the tooling is missing.
  unknown,
}

/// The verdict, from the facts and nothing else.
FirewallVerdict verdictOf(FirewallFacts facts) {
  if (!facts.supported) return FirewallVerdict.unknown;
  if (!facts.hasAddress) return FirewallVerdict.noAddress;
  if (!facts.listeningOnTheNetwork) return FirewallVerdict.loopbackOnly;
  if (facts.covering.isNotEmpty) return FirewallVerdict.open;
  // **A rule that exists and does not cover this network is its own answer**, because the fix is different: the
  // reader has to widen a rule they already made, not make one. This is the `-Profile Private` lesson, kept as a
  // verdict rather than as a paragraph in a README.
  if (facts.allowing.isNotEmpty) return FirewallVerdict.wrongProfile;
  return FirewallVerdict.noRule;
}

/// The command that would let this program through, ready to copy.
///
/// **`profile=any`, and the reason is the mistake this repository already made once.** A rule scoped to the
/// category in use at the time -- `Private`, on the day the wireless was classified `Public` -- does nothing at
/// all while looking like it should, and every network the reader joins afterwards is a fresh chance to get it
/// wrong. The command is **program-scoped rather than port-scoped** for the reason in this file's header.
///
/// The name is fixed rather than timestamped so that running it twice updates one rule instead of leaving two.
String allowCommandFor(String program) =>
    'netsh advfirewall firewall add rule '
    'name="Hollow Court LAN sync" dir=in action=allow '
    'program="$program" enable=yes profile=any protocol=TCP';

/// The program path as a rule has to spell it, which is **exactly what the operating system reports**.
///
/// Nothing is normalised -- no case folding, no short path, no trailing separator. Windows compares these strings
/// as they are, so a rule naming `E:\a\hollow_court.exe` does not cover `E:\a\Hollow_Court.exe`; a helper that
/// tidied the path here would make the check say "covered" about a machine that is not.
String programPathFor(String resolvedExecutable) => resolvedExecutable;

/// Reads what the probe printed, or null when it printed nothing usable.
///
/// The format is fixed by `data/sync/firewall_probe.dart` and stated there; it is a pair of `key=value` lines
/// rather than JSON because the thing on the other side of it is PowerShell, where a one-line format string is
/// readable and a JSON serialiser is three more things that can fail.
///
///     category=Public
///     rules=Hollow Court app (inbound TCP)|any|True|Allow;another|Private|True|Allow
///
/// A rule line whose fields do not parse is **dropped, and the rest are kept**: one unreadable rule is not a
/// reason to tell a reader nothing about the others, which is the same rule the event log follows for a line it
/// cannot read.
FirewallFacts? parseFirewallReport(
  String output, {
  required String program,
  required String listenAddress,
  required bool supported,
}) {
  var sawSomething = false;
  final categories = <String>{};
  final rules = <FirewallRule>[];

  for (final rawLine in output.split(RegExp(r'\r?\n'))) {
    final line = rawLine.trim();
    if (line.isEmpty) continue;
    if (line.startsWith('category=')) {
      sawSomething = true;
      for (final value in line.substring('category='.length).split(',')) {
        final category = value.trim();
        if (category.isNotEmpty) categories.add(category);
      }
      continue;
    }
    if (line.startsWith('rules=')) {
      sawSomething = true;
      for (final value in line.substring('rules='.length).split(';')) {
        final fields = value.trim().split('|');
        if (fields.length < 4) continue;
        final name = fields[0].trim();
        if (name.isEmpty) continue;
        rules.add(
          FirewallRule(
            name: name,
            profiles: {
              for (final profile in fields[1].split(','))
                if (profile.trim().isNotEmpty) profile.trim().toLowerCase(),
            },
            enabled: fields[2].trim().toLowerCase() == 'true',
            action: fields[3].trim().toLowerCase() == 'allow'
                ? FirewallAction.allow
                : FirewallAction.block,
          ),
        );
      }
    }
  }

  if (!sawSomething) return null;
  return FirewallFacts(
    supported: supported,
    program: program,
    listenAddress: listenAddress,
    categories: categories,
    rules: rules,
  );
}
