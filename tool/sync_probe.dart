// ignore_for_file: avoid_print
//
// Every line of this file's output is the point of it: the probe's product is what it prints, and
// `avoid_print` exists to keep debug output out of an application's code. Recorded as an exception with
// its reason rather than by loosening the lint for the repository.
// Drives the production sync code from a command line, so two real processes on two real machines can
// meet without anybody clicking anything.
//
// WHY THIS EXISTS, AND WHAT IT IS NOT.
//
// The two-device acceptance for P3 needs a host on one machine and a joiner on another. The application
// is the only way to be that host and joiner today, and its sync screen needs a person to press a button
// and type a URI -- which a script cannot do. So this is the smallest thing that can stand in for the
// *pressing*: it opens a real `EventLog` on disk, uses the real `SocketChannel`, the real handshake, the
// real exchange and the real identity store, and prints what happened.
//
// **It is a probe and not a product path.** Nothing in the application imports it, it has no UI, and the
// only thing it adds to the library is that the pairing token's minter is now public -- which is where
// the transport can be reached from plain Dart at all.
//
//     dart run tool/sync_probe.dart bottle --dir <cellar> <sku> <millilitres>
//     dart run tool/sync_probe.dart show   --dir <cellar>
//     dart run tool/sync_probe.dart host   --dir <cellar> [--name <label>] [--identity <file>]
//     dart run tool/sync_probe.dart join <code> --dir <cellar> [--name <label>] [--identity <file>]
//     dart run tool/sync_probe.dart beacon --dir <cellar> [--name <label>] [--identity <file>] [--agree] [--hold <s>] [--port <n>]
//
// `beacon` is the **second screen** §10.3.2 needs: it announces itself on the LAN and holds a listener a tap can
// arrive at, so the application can be the side that asks. It answers with the six digits printed on this
// process's own stdout -- the other half of the comparison a person makes across two screens -- and, with
// `--agree`, says yes (after `--hold` seconds, which is what photographing the application's screen needs).
//
// The identity file is the app's own format, so a probe run and an application run can recognise each
// other: the second `join` in a pair needs no code, because the first one learned the host's key.
import 'dart:async';
import 'dart:io';

import 'package:hollow_court/data/event_log.dart';
import 'package:hollow_court/data/sync/discovery_socket.dart';
import 'package:hollow_court/data/sync/identity_store.dart';
import 'package:hollow_court/data/sync/socket_transport.dart';
import 'package:hollow_court/domain/events/stock.dart';
import 'package:hollow_court/domain/sync/device_identity.dart';
import 'package:hollow_court/domain/sync/discovery.dart';
import 'package:hollow_court/domain/sync/exchange.dart';
import 'package:hollow_court/domain/sync/pairing.dart';
import 'package:hollow_court/domain/sync/short_code.dart';
import 'package:hollow_court/domain/units/quantity.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('usage: sync_probe <bottle|show|host|join> ...');
    exit(2);
  }
  final verb = args.first;
  final options = _Options(args.skip(1));

  switch (verb) {
    case 'bottle':
      await _bottle(options);
    case 'show':
      await _show(options);
    case 'host':
      await _host(options);
    case 'join':
      await _join(options);
    case 'beacon':
      await _beacon(options);
    default:
      stderr.writeln('unknown verb: $verb');
      exit(2);
  }
}

Future<EventLog> _open(_Options options) {
  final dir = Directory(options.value('dir') ?? '.')..createSync(recursive: true);
  return EventLog.open(
    file: File('${dir.path}${Platform.pathSeparator}cellar.ndjson'),
    // The node id is what breaks ties between two devices' clocks, so it must differ per side -- which
    // is exactly what a probe on two machines gets for free and a probe on one machine has to be told.
    nodeId: options.value('name') ?? Platform.localHostname,
    nowMillis: () => DateTime.now().millisecondsSinceEpoch,
  );
}

Future<void> _bottle(_Options options) async {
  final rest = options.positional;
  if (rest.length < 2) {
    stderr.writeln('bottle needs <sku> <millilitres>');
    exit(2);
  }
  final log = await _open(options);
  await log.record(
    (hlc) => StockEvents.bottleAdded(
      hlc: hlc,
      bottleId: 'bottle-${rest[0]}-${DateTime.now().microsecondsSinceEpoch}',
      sku: rest[0],
      volume: Volume.fromMillilitres(int.parse(rest[1])),
    ),
  );
  await _printCellar(log, 'after recording');
}

Future<void> _show(_Options options) async {
  await _printCellar(await _open(options), 'cellar');
}

Future<void> _printCellar(EventLog log, String label) async {
  final stock = log.stock;
  print('$label: ${log.events.length} event(s), ${stock.bottleCount} bottle(s), '
      '${stock.remainingTotal.microlitres} ul remaining, '
      '${stock.removedBottleIds.length} retracted');
  for (final bottle in stock.bottles) {
    print('  ${bottle.bottleId}  ${bottle.sku}  ${bottle.remaining.microlitres} ul');
  }
}

Future<StoredSyncIdentity> _identity(_Options options) async {
  // **One identity per cellar directory, not one per machine.** The first version defaulted to a single
  // path under the temporary directory, so both probes on one machine shared an identity -- and the run
  // that "proved" a remembered key proved nothing, because both sides were the same device. Two devices
  // have to be two devices for the key to mean anything.
  final dir = Directory(options.value('dir') ?? '.');
  final path = options.value('identity') ??
      '${dir.path}${Platform.pathSeparator}sync-identity.json';
  final store = SyncIdentityStore(File(path));
  final stored = await store.read();
  if (stored != null) return stored;
  final fresh = StoredSyncIdentity(
    identity: await DeviceIdentity.generate(),
    trusted: const [],
  );
  await store.write(fresh);
  return fresh;
}

Future<void> _host(_Options options) async {
  final log = await _open(options);
  final stored = await _identity(options);
  final name = options.value('name') ?? Platform.localHostname;
  final token = mintPairingToken();

  // A fixed port when one is asked for, so a second run can be found at the address the first one was
  // remembered at -- which is what makes a code-less second sync reproducible.
  final server = await listenForSync(port: int.tryParse(options.value('port') ?? '') ?? 0);
  final ticket = await ticketForListener(server, token: token, name: name);
  print('this device   : $name');
  print('fingerprint   : ${stored.identity.fingerprint}');
  print('cellar        : ${await _describe(log)}');
  print('CODE          : ${ticket.encode()}');
  stdout.writeln('waiting for one peer...');

  // **The host always authenticates with the code**, which is what the application does: it has just put
  // that code on its own screen, so requiring anything else would refuse the device the reader is holding.
  // A first version of this probe let a host that had remembered somebody require *their* key instead,
  // and the run failed with 配对码不对 -- correctly, and for a reason the application does not have.
  //
  // The remembered-key path is the **joiner's**: it is the side that knows an address and has learned a
  // key at it.
  final outcome = await acceptForSync(
    server: server,
    source: log,
    localName: name,
    expectedToken: token,
    identity: stored.identity,
    // **The devices this host has met**, so one of them can come back without a code. The code is still
    // accepted -- it is on this machine's own screen -- but it is no longer the only way in.
    acceptedIdentities: {for (final device in stored.trusted) device.publicKey},
  );
  await _report(
    outcome,
    log,
    stored,
    address: null,
    peerName: 'peer',
    identityDirectory: options.value('dir') ?? '.',
  );
}

/// **The other screen of a six-digit comparison, as a process.**
///
/// What this stands in for: a second device whose owner looks at the digits and says yes. What it does *not*
/// stand in for is a second *phone* -- the protocol is the same code the application runs, but a probe process is
/// not a hand holding a device, and a run that used one is recorded as such.
///
/// It also exercises the two defects 1.0.0.518 fixed, in a real process: the listener accepts **more than one**
/// tap (a `ServerSocket` is a single-subscription stream, so the subscription is taken once here and the arrived
/// sockets are queued), and the peer is remembered **with the address the connection came from**, which is what
/// 再同步一次 would dial.
Future<void> _beacon(_Options options) async {
  final log = await _open(options);
  final stored = await _identity(options);
  final name = options.value('name') ?? 'probe';
  final agree = options.flag('agree');
  final hold = int.tryParse(options.value('hold') ?? '') ?? 0;
  final directory = Directory(options.value('dir') ?? '.');
  final identityPath =
      options.value('identity') ?? '${directory.path}${Platform.pathSeparator}sync-identity.json';

  // The listener first, because the announcement has to carry *its* port -- the defect this whole half of the
  // work was about: an announcement naming a port nothing holds is a tap that cannot arrive.
  // **A fixed port, when one is asked for**, so a run can listen at the address another machine remembered --
  // which is how the remembered path is exercised without relying on discovery, and on one machine discovery
  // *cannot* be relied on: Windows delivers a datagram bound twice on one UDP port to a single socket, so two
  // processes here hear each other only intermittently (see `data/sync/discovery_socket.dart`).
  final server = await listenForLanSync(
    preferred: await lanAddress(),
    port: int.tryParse(options.value('port') ?? '') ?? 0,
  );
  await LanDiscovery.start(
    announce: DiscoveryAnnounce(
      deviceName: name,
      fingerprint: stored.identity.fingerprint,
      port: server.port,
      version: 'probe',
    ),
  );

  print('this device   : $name');
  print('fingerprint   : ${stored.identity.fingerprint}');
  print('listening     : ${server.address.address}:${server.port}');
  print('announcing    : UDP $defaultDiscoveryPort, every few seconds');
  print('cellar        : ${await _describe(log)}');
  stdout.writeln('waiting for taps; Ctrl-C to stop');

  // **One subscription, many taps.** `server.first` would answer once and then throw `Bad state: Stream was
  // already listened to`, which is exactly what the application did before 1.0.0.518.
  final arrived = <Socket>[];
  Completer<void>? wake;
  server.listen((socket) {
    arrived.add(socket);
    wake?.complete();
    wake = null;
  });

  Future<Socket> next() async {
    while (arrived.isEmpty) {
      final waiter = Completer<void>();
      wake = waiter;
      await waiter.future;
    }
    return arrived.removeAt(0);
  }

  var trusted = stored;
  while (true) {
    final socket = await next();
    print('');
    print('tap           : ${socket.remoteAddress.address}');
    final outcome = await runAccepted(
      socket: socket,
      source: log,
      localName: name,
      // **No code, because this device displays none.** It is merely reachable, so the proof of who the peer is
      // is the comparison below -- and a peer that proved a remembered key skips it (`runExchange` decides that,
      // not this file).
      expectedToken: '',
      identity: trusted.identity,
      acceptedIdentities: {for (final device in trusted.trusted) device.publicKey},
      confirmComparison: (shortCode) async {
        print('COMPARE       : ${ShortCode.grouped(shortCode)}');
        print('                the same six digits must be on the other screen');
        if (!agree) {
          stdout.write('agree? [y/N] ');
          final answer = stdin.readLineSync()?.trim().toLowerCase();
          return answer == 'y' || answer == 'yes';
        }
        if (hold > 0) {
          print('waiting $hold s before agreeing, so the other screen can be photographed');
          await Future<void>.delayed(Duration(seconds: hold));
        }
        print('agreed');
        return true;
      },
    );
    print(
      'outcome       : merged=${outcome.merged} sent=${outcome.sent}'
      '${outcome.failure == null ? '' : ' failure=${outcome.failure}'}',
    );
    print('peer          : ${outcome.peerName} at ${outcome.peerAddress}');
    print('peer key      : ${outcome.peerIdentity}');
    print('cellar now    : ${await _describe(log)}');

    // **Remembered, with its address**, exactly as the application does -- so a second tap needs neither digits
    // nor typing, and so this run leaves behind the same evidence the application would.
    if (outcome.peerIdentity.isNotEmpty) {
      final peerAddress = outcome.peerAddress;
      trusted = trusted.remembering(
        TrustedDevice(
          publicKey: outcome.peerIdentity,
          name: outcome.peerName.isEmpty ? 'peer' : outcome.peerName,
          // The peer's own listening port is not in the outcome (the announcement carries it, not the exchange);
          // the address alone is what this can honestly record.
          address: peerAddress.isEmpty ? null : peerAddress,
          lastSeenMillis: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      await SyncIdentityStore(File(identityPath)).write(trusted);
      print('remembered    : ${trusted.trusted.map((device) => device.name).join(', ')}');
    }
  }
}

Future<void> _join(_Options options) async {
  final code = options.positional.isEmpty ? '' : options.positional.first;
  final ticket = PairingTicket.parse(code);
  if (ticket == null) {
    stderr.writeln('that is not a Hollow Court code: "$code"');
    exit(2);
  }
  final log = await _open(options);
  final stored = await _identity(options);
  final name = options.value('name') ?? Platform.localHostname;

  // **The remembered key replaces the token**, which is what section 10.3's long-term keys are for: the
  // first meeting is authenticated by six characters, and every meeting after by the key learned then.
  final known = stored.trusted
      .where((device) => device.address == '${ticket.host}:${ticket.port}')
      .firstOrNull;

  print('this device   : $name');
  print('fingerprint   : ${stored.identity.fingerprint}');
  print('cellar        : ${await _describe(log)}');
  print('reaching      : ${ticket.host}:${ticket.port}');
  print('authentication: ${known == null ? 'the pairing code' : 'the remembered key of ${known.name}'}');

  final outcome = await syncWithTicket(
    ticket: known == null
        ? ticket
        : PairingTicket(
            host: ticket.host,
            port: ticket.port,
            token: '',
            name: ticket.name,
          ),
    source: log,
    localName: name,
    identity: stored.identity,
    expectedIdentity: known?.publicKey ?? '',
  );
  await _report(
    outcome,
    log,
    stored,
    address: '${ticket.host}:${ticket.port}',
    peerName: ticket.name.isEmpty ? 'peer' : ticket.name,
    identityDirectory: options.value('dir') ?? '.',
  );
}

Future<String> _describe(EventLog log) async =>
    '${log.events.length} events, ${log.stock.bottleCount} bottles';

/// Writes down who the peer was, which is what makes a second sync need no code.
Future<void> _report(
  ExchangeOutcome outcome,
  EventLog log,
  StoredSyncIdentity stored, {
  required String? address,
  required String peerName,
  required String identityDirectory,
}) async {
  print('OUTCOME       : ${outcome.succeeded ? 'ok' : 'failed'}'
      '${outcome.failure == null ? '' : ' -- ${outcome.failure}'}');
  print('merged        : ${outcome.merged}');
  print('sent          : ${outcome.sent}');
  print('peer          : ${outcome.peerName}');
  if (outcome.peerIdentity.isNotEmpty) {
    print('peer key      : ${TrustedDevice(publicKey: outcome.peerIdentity, name: peerName).shortKey}...');
  }
  await _printCellar(log, 'after');

  if (outcome.succeeded && outcome.peerIdentity.isNotEmpty) {
    final file = File(
      '${Directory(identityDirectory).path}${Platform.pathSeparator}sync-identity.json',
    );
    await SyncIdentityStore(file).write(
      stored.remembering(
        TrustedDevice(
          publicKey: outcome.peerIdentity,
          name: outcome.peerName.isEmpty ? peerName : outcome.peerName,
          address: address,
          lastSeenMillis: DateTime.now().millisecondsSinceEpoch,
        ),
      ),
    );
    print('remembered    : yes');
  }
}

/// The flags, parsed once.
final class _Options {
  _Options(Iterable<String> args) {
    // **A bare `--flag` does not eat the next word.** The first version read every `--name value` pair the same
    // way, so `--agree --hold 20` swallowed `--hold` as the *value* of agree and the delay never happened.
    final all = args.toList();
    for (var i = 0; i < all.length; i++) {
      final arg = all[i];
      if (!arg.startsWith('--')) {
        positional.add(arg);
        continue;
      }
      final next = i + 1 < all.length ? all[i + 1] : null;
      if (next != null && !next.startsWith('--')) {
        _values[arg.substring(2)] = next;
        i++;
        continue;
      }
      _flags.add(arg.substring(2));
    }
  }

  final Map<String, String> _values = {};
  final Set<String> _flags = {};
  final List<String> positional = [];

  String? value(String name) => _values[name];

  /// Whether a switch was given, with or without a value: `--agree` and `--agree yes` are the same request.
  bool flag(String name) => _flags.contains(name) || _values.containsKey(name);
}
