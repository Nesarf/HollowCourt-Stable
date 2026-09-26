// The P3 acceptance criterion, walked through the screens.
//
// Section 14 states P3's acceptance as *phone and computer share one cellar*, and until now the
// phase's state read "built end to end and tested over loopback; **not yet driven from a screen**".
// The screen arrived in `lib/ui/sync_section.dart`; this is the other half of that sentence, and it
// is a different fact from "the pieces exist".
//
// WHAT IS REAL HERE, because a test that replaces something has to say what.
//
//   real   two EventLogs on disk, in two temporary directories, with different node ids
//   real   the screens: the code is read off one device's `SelectableText` and typed into the
//          other's `TextField`, and the result is asserted from what the screens draw
//   real   `PairingTicket.encode` / `.parse`, exercised by carrying the string between them
//   real   `runExchange`, the wire frames, the clock digest, the merge, and the token check
//   real   the two halves' outcomes, computed rather than canned
//
//   not real   the byte pipe. `_MemoryChannel` is two `StreamController`s crossed, so no socket is
//              opened -- and that is deliberate rather than convenient: a widget test runs in a
//              fake-async zone where real socket I/O has to be driven through `runAsync`, and a
//              test that waits on a real peer is the slow, timing-dependent test
//              `sync_service.dart` says the socket layer's own tests exist to avoid. The socket
//              layer is covered over real loopback connections in `test/data/sync`, and this file
//              covers the thing those cannot: a person operating two screens.
//
// The consequence, stated so the two are not confused: this proves **the screens drive a real
// sync**. It does not prove two physical devices on one network have done it.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hollow_court/data/event_log.dart';
import 'package:hollow_court/data/sync/sync_service.dart';
import 'package:hollow_court/domain/events/stock.dart';
import 'package:hollow_court/domain/sync/device_identity.dart';
import 'package:hollow_court/domain/sync/exchange.dart';
import 'package:hollow_court/domain/sync/pairing.dart';
import 'package:hollow_court/domain/units/quantity.dart';
import 'package:hollow_court/ui/library.dart';
import 'package:hollow_court/data/sync/identity_store.dart';
import 'package:hollow_court/domain/sync/discovery.dart';
import 'package:hollow_court/ui/discovery_providers.dart';
import 'package:hollow_court/ui/sync_identity.dart';
import 'package:hollow_court/ui/sync_section.dart';

/// A `WireChannel` that is one end of a pair of crossed stream controllers.
final class _MemoryChannel implements WireChannel {
  _MemoryChannel(this._incoming, this._outgoing);

  final Stream<String> _incoming;
  final StreamController<String> _outgoing;

  @override
  Stream<String> get lines => _incoming;

  @override
  void sendLine(String line) {
    // Mirrors `SocketChannel`, which throws rather than dropping: an exchange that talks after the
    // conversation ended is a bug worth seeing, not one worth swallowing.
    if (_outgoing.isClosed) throw StateError('sent on a closed connection');
    _outgoing.add(line);
  }

  @override
  Future<void> close() async {
    if (!_outgoing.isClosed) await _outgoing.close();
  }
}

/// The host's half of a connection, waiting to be reached.
final class _WaitingHost {
  _WaitingHost({
    required this.forHost,
    required this.forGuest,
    required this.token,
  });

  final WireChannel forHost;
  final WireChannel forGuest;
  final String token;

  /// Completed when somebody uses the code, which is what `acceptForSync` waits for in `server.first`.
  final Completer<void> arrived = Completer<void>();
}

/// The table a port number indexes into, standing in for the operating system's listening sockets.
///
/// **It carries the port, and that is the part worth keeping.** The guest reaches the host *through
/// the code*, by looking up the port the code names -- so a wrong port is a refused connection here
/// exactly as it would be on a network, rather than a test that connects to whatever object it
/// happens to hold.
final class _Switchboard {
  final Map<int, _WaitingHost> _listening = <int, _WaitingHost>{};
  int _nextPort = 47800;

  int open(_WaitingHost host) {
    final port = _nextPort++;
    _listening[port] = host;
    return port;
  }

  _WaitingHost? pickUp(int port) => _listening.remove(port);

  /// **The other role a socket can be in: reachable rather than showing a code** (§10.3.2).
  ///
  /// The difference that matters here is that this one accepts *more than one* connection: a device waiting to be
  /// tapped is not waiting for one particular peer, and the reader who declines the first request has to be able
  /// to receive the second. So a door hands out a fresh pair of channels to each knock instead of being consumed.
  final Map<int, _Door> _doors = <int, _Door>{};

  int openDoor(_Door door) {
    _doors[door.port] = door;
    return door.port;
  }

  void closeDoor(int port) => _doors.remove(port)?.close();

  _Door? door(int port) => _doors[port];
}

/// A listener a neighbour can knock on, and the queue of knocks waiting to be answered.
final class _Door {
  _Door(this.port);

  final int port;

  final List<({WireChannel host, WireChannel guest})> _waiting = [];
  final List<Completer<({WireChannel host, WireChannel guest})>> _knocking = [];
  var _closed = false;

  /// A neighbour's tap: the guest gets its half of a fresh pair, and the host gets the other half.
  WireChannel knock() {
    final pair = _pair();
    if (_knocking.isNotEmpty) {
      _knocking.removeAt(0).complete((host: pair.a, guest: pair.b));
    } else {
      _waiting.add((host: pair.a, guest: pair.b));
    }
    return pair.b;
  }

  /// The host side: the next knock, or a future that waits for one.
  Future<({WireChannel host, WireChannel guest})> next() {
    if (_closed) return Future.error(StateError('this door is closed'));
    if (_waiting.isNotEmpty) return Future.value(_waiting.removeAt(0));
    final completer = Completer<({WireChannel host, WireChannel guest})>();
    _knocking.add(completer);
    return completer.future;
  }

  void close() {
    _closed = true;
    for (final completer in _knocking) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('this door is closed'));
      }
    }
    _knocking.clear();
  }
}

/// Two crossed channels: A writes what B reads, and B writes what A reads.
({WireChannel a, WireChannel b}) _pair() {
  final aToB = StreamController<String>();
  final bToA = StreamController<String>();
  return (
    a: _MemoryChannel(bToA.stream, aToB),
    b: _MemoryChannel(aToB.stream, bToA),
  );
}

/// A [SyncService] whose only substitution is the socket.
///
/// This is not the `_FakeSync` of `sync_section_test.dart`, and the difference is the whole point:
/// that one returns outcomes the test writes, and this one runs the real exchange and reports what
/// it actually did.
final class _LoopbackSync implements SyncService {
  _LoopbackSync({
    required this.board,
    required this.source,
    required this.localName,
    this.doorPort = 47900,
  });

  final _Switchboard board;

  /// The port this device is reachable on while its screen is open.
  ///
  /// Fixed rather than ephemeral, and only in this fake: the test has to be able to *write the announcement* for
  /// the other device, and a port that is only known after the socket binds cannot be put in a widget that was
  /// built before it.
  final int doorPort;
  final SyncSource source;

  @override
  final String localName;

  _WaitingHost? _hosting;

  /// Fixed rather than minted, so a failure is about the exchange and not about a random code.
  static const _token = 'K7FQ2M';

  @override
  Future<PairingTicket> host({
    DeviceIdentity? identity,
    String expectedIdentity = '',
    Set<String> acceptedIdentities = const {},
    // The reader's own token, when they typed one: the interface gained this on 2026-09-23 so that the token
    // half of a share code can be chosen. A fake that does not carry it cannot stand in for the real one.
    String? token,
  }) async {
    await stop();
    final pair = _pair();
    final waiting = _WaitingHost(
      forHost: pair.a,
      forGuest: pair.b,
      token: _token,
    );
    _hosting = waiting;
    final port = board.open(waiting);
    return PairingTicket(
      host: '127.0.0.1',
      port: port,
      token: _token,
      name: localName,
    );
  }

  @override
  Future<ExchangeOutcome> awaitPeer({
    DeviceIdentity? identity,
    String expectedIdentity = '',
    Future<bool> Function(String shortCode)? confirmComparison,
  }) async {
    final waiting = _hosting;
    if (waiting == null) {
      return const ExchangeOutcome(
        merged: 0,
        sent: 0,
        failure: 'no code is being shown',
      );
    }
    await waiting.arrived.future;
    return runExchange(
      confirmComparison: confirmComparison,
      channel: waiting.forHost,
      source: source,
      role: ExchangeRole.responder,
      localName: localName,
      expectedToken: waiting.token,
      timeout: const Duration(seconds: 5),
    );
  }

  @override
  Future<ExchangeOutcome> join(
    PairingTicket ticket, {
    DeviceIdentity? identity,
    String expectedIdentity = '',
    Future<bool> Function(String shortCode)? confirmComparison,
  }) async {
    // **A device that is merely reachable, rather than showing a code.** This is the §10.3.2 tap: no token travels,
    // and what stands behind the connection is the comparison gate both ends were handed.
    final door = board.door(ticket.port);
    if (door != null) {
      final guest = door.knock();
      return runExchange(
        confirmComparison: confirmComparison,
        channel: guest,
        source: source,
        role: ExchangeRole.initiator,
        localName: localName,
        identity: identity,
        token: ticket.token,
        expectedIdentity: expectedIdentity,
        timeout: const Duration(seconds: 5),
      );
    }

    final waiting = board.pickUp(ticket.port);
    if (waiting == null) {
      // The same sentence the socket layer produces, so the screen's failure path is the one a
      // reader would see when the other device is not listening.
      return ExchangeOutcome(
        merged: 0,
        sent: 0,
        failure: 'could not reach ${ticket.host}:${ticket.port} -- Connection refused',
      );
    }
    waiting.arrived.complete();
    return runExchange(
      confirmComparison: confirmComparison,
      channel: waiting.forGuest,
      source: source,
      role: ExchangeRole.initiator,
      localName: localName,
      token: ticket.token,
      timeout: const Duration(seconds: 5),
    );
  }

  /// The door this device is reachable on, while its screen is open.
  _Door? _door;

  @override
  Future<int> openForRequests({
    DeviceIdentity? identity,
    Set<String> acceptedIdentities = const {},
  }) async {
    final door = _Door(doorPort);
    _door = door;
    _reachableAccepting = acceptedIdentities;
    return board.openDoor(door);
  }

  Set<String> _reachableAccepting = const {};

  /// **How many taps this device has answered**, so a test can say the listener is still open afterwards.
  int answeredRequests = 0;

  @override
  Future<ExchangeOutcome> awaitRequest({
    DeviceIdentity? identity,
    Future<bool> Function(String shortCode)? confirmComparison,
  }) async {
    final door = _door;
    if (door == null) {
      return const ExchangeOutcome(
        merged: 0,
        sent: 0,
        failure: 'this device is not reachable at the moment',
      );
    }
    final ({WireChannel host, WireChannel guest}) arrived;
    try {
      arrived = await door.next();
    } on Object catch (error) {
      return ExchangeOutcome(merged: 0, sent: 0, failure: 'stopped listening -- $error');
    }
    answeredRequests++;
    // **No token, because no code is on this screen**, and the same comparison gate the initiator passes: the two
    // ends derive the digits from the handshake itself, and no event moves until both people agree.
    return runExchange(
      confirmComparison: confirmComparison,
      channel: arrived.host,
      source: source,
      role: ExchangeRole.responder,
      localName: localName,
      identity: identity,
      expectedToken: '',
      acceptedIdentities: _reachableAccepting,
      timeout: const Duration(seconds: 5),
    );
  }

  @override
  Future<void> closeForRequests() async {
    final door = _door;
    _door = null;
    if (door != null) board.closeDoor(door.port);
  }

  @override
  Future<void> stop() async {
    final waiting = _hosting;
    _hosting = null;
    if (waiting != null) {
      await waiting.forHost.close();
      await waiting.forGuest.close();
    }
  }
}

class _Seeded extends CellarNotifier {
  _Seeded(this._initial);
  final Cellar _initial;

  @override
  Future<Cellar> build() async => _initial;
}

const _hostKey = ValueKey('device-workstation');
const _guestKey = ValueKey('device-phone');

/// One device: its own cellar, its own sync service, its own key, its own scope.
///
/// **[nearby] is what this device can hear**, injected because the real discovery is a UDP broadcast and a widget
/// test is not a network -- the socket layer has its own tests that open real ones. The list is still the real
/// widget reading the real provider; only the datagrams are substituted.
Widget _device(
  Key key, {
  required Cellar cellar,
  required SyncServiceFactory factory,
  DeviceIdentity? identity,
  List<DiscoveredDevice> nearby = const [],
}) => ProviderScope(
  key: key,
  overrides: [
    cellarProvider.overrideWith(() => _Seeded(cellar)),
    syncServiceFactoryProvider.overrideWithValue(factory),
    if (identity != null) syncIdentityProvider.overrideWith(() => _Keyed(identity)),
    // **Always substituted, never left to the real one.** `discoveredDevicesProvider` opens a UDP socket on the
    // announcement port and runs a periodic sweeper; a widget test that lets it start leaves a real timer pending
    // and fails at teardown with "A Timer is still pending even after the widget tree was disposed" -- a sentence
    // about the test, not about the screen.
    discoveredDevicesProvider.overrideWith((ref) => Stream.value(nearby)),
  ],
  // **`MaterialApp` inside the scope, not outside it.** A dialog is built into the navigator's overlay, which is
  // above whatever is passed as `home` -- so a `ProviderScope` below the `MaterialApp` leaves the confirmation box
  // unable to read a provider at all ("Bad state: No ProviderScope found"). In the application the scope is above
  // everything (`main.dart`), and this is the test's tree saying the same thing.
  child: const MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: SyncSection())),
  ),
);

/// An identity that is already loaded, so a test does not need the file that holds one.
final class _Keyed extends SyncIdentityNotifier {
  _Keyed(this.identity);

  final DeviceIdentity identity;

  @override
  Future<StoredSyncIdentity> build() async =>
      StoredSyncIdentity(identity: identity, trusted: const []);
}

Finder _on(Key key, Finder matching) =>
    find.descendant(of: find.byKey(key), matching: matching);

void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('hollow-court-p3');
  });
  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  testWidgets('a phone and a computer come away with one cellar', (tester) async {
    final board = _Switchboard();

    // Two logs, on disk, with different node ids -- which is what makes the merge a merge.
    final hostLog = (await tester.runAsync(
      () => EventLog.open(
        file: File('${dir.path}${Platform.pathSeparator}host.ndjson'),
        nodeId: 'workstation',
        nowMillis: () => 1000,
      ),
    ))!;
    final guestLog = (await tester.runAsync(
      () => EventLog.open(
        file: File('${dir.path}${Platform.pathSeparator}guest.ndjson'),
        nodeId: 'phone',
        nowMillis: () => 2000,
      ),
    ))!;

    // **A bottle on each side, so the merge has to run in both directions.** One bottle on one
    // device would be satisfied by a one-way push, which is not what "share one cellar" means.
    await tester.runAsync(() async {
      await hostLog.record(
        (hlc) => StockEvents.bottleAdded(
          hlc: hlc,
          bottleId: 'bottle-gin',
          sku: 'gin',
          volume: Volume.fromMillilitres(700),
        ),
      );
      await guestLog.record(
        (hlc) => StockEvents.bottleAdded(
          hlc: hlc,
          bottleId: 'bottle-vermouth',
          sku: 'sweetVermouth',
          volume: Volume.fromMillilitres(700),
        ),
      );
    });
    expect(hostLog.stock.bottleCount, 1);
    expect(guestLog.stock.bottleCount, 1);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              Expanded(
                child: _device(
                  _hostKey,
                  cellar: Cellar.of(hostLog),
                  factory: (_) => _LoopbackSync(
                    board: board,
                    source: hostLog,
                    localName: 'workstation',
                  ),
                ),
              ),
              Expanded(
                child: _device(
                  _guestKey,
                  cellar: Cellar.of(guestLog),
                  factory: (_) => _LoopbackSync(
                    board: board,
                    source: guestLog,
                    localName: 'phone',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    // The cellars arrive from async providers, so a single pump leaves the screens idle-looking but
    // unwired. Safe to settle: the idle state draws no indeterminate animation.
    await tester.pumpAndSettle();

    // ---------------------------------------------------------- the computer shows a code
    await tester.tap(_on(_hostKey, find.text('显示配对码')));
    // `pump` and not `pumpAndSettle`: the waiting state draws an indeterminate progress indicator,
    // whose animation never settles.
    await tester.pump();
    await tester.pump();

    // **The short share code, and the whole acceptance runs on it.** This used to read the first
    // `SelectableText`, which was the URI; the screen now offers the sixteen-to-eighteen character code first
    // and keeps the URI underneath for the cases that need it. Reading the short one means this test proves
    // the compact form end to end -- the host writes it, the guest types it, and the same handshake runs.
    final code = tester
        .widget<SelectableText>(_on(_hostKey, find.byKey(const ValueKey('host-share-code'))))
        .data!;
    expect(code.length, inInclusiveRange(16, 18));
    expect(code, endsWith('K7FQ2M'), reason: 'the ticket token is the tail of the code');
    expect(RegExp(r'^[A-Z2-9]+$').hasMatch(code), isTrue,
        reason: 'nothing outside the alphabet a person can read aloud');
    expect(_on(_hostKey, find.text('正在等待对方输入这串码…')), findsOneWidget);

    // --------------------------------------------------------------- the phone is told it
    await tester.enterText(_on(_guestKey, find.byKey(const ValueKey('sync-code'))), code);
    await tester.tap(_on(_guestKey, find.text('连接并同步')));

    // The exchange is real work rather than one frame's worth of state change, so pump until both
    // screens have said so -- with a bound, because a loop that cannot end is a hang instead of a
    // failure.
    var pumps = 0;
    while (pumps < 400 && find.text('同步完成').evaluate().length < 2) {
      // **A real turn of the event loop, then a frame, and both are needed.** The merge writes
      // into `EventLog`, which is a file -- so this exchange does real disk I/O, and a widget
      // test's fake-async zone never yields to the event loop. Pumping alone therefore hung with
      // every frame on the wire and neither side finishing: the write's completion could not be
      // delivered. `runAsync` gives the loop its turn; the frame after it runs the continuation.
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump(const Duration(milliseconds: 10));
      pumps++;
    }

    // ------------------------------------------------------------------------- both say so
    expect(_on(_hostKey, find.text('同步完成')), findsOneWidget,
        reason: 'after $pumps pumps the hosting screen had not reported');
    expect(_on(_guestKey, find.text('同步完成')), findsOneWidget,
        reason: 'after $pumps pumps the joining screen had not reported');
    // One event each way, and the screen shows the arithmetic rather than a tick.
    expect(_on(_hostKey, find.text('1 / 1')), findsOneWidget);
    expect(_on(_guestKey, find.text('1 / 1')), findsOneWidget);
    // The peer named itself, and it is the other device's name.
    expect(_on(_guestKey, find.text('workstation')), findsOneWidget);
    expect(_on(_hostKey, find.text('phone')), findsOneWidget);

    // -------------------------------------------------- and the cellars really are one cellar
    expect(hostLog.stock.bottles.map((b) => b.sku), contains('sweetVermouth'));
    expect(guestLog.stock.bottles.map((b) => b.sku), contains('gin'));
    expect(hostLog.stock.bottleCount, 2);
    expect(guestLog.stock.bottleCount, 2);

    // Both directions were recorded, not just merged in memory: the state above survives a re-read.
    final rereadHost = await tester.runAsync(
      () => EventLog.open(
        file: File('${dir.path}${Platform.pathSeparator}host.ndjson'),
        nodeId: 'workstation',
        nowMillis: () => 3000,
      ),
    );
    expect(rereadHost!.stock.bottles.map((b) => b.sku), contains('sweetVermouth'));
  });

  testWidgets('a device that is not listening is a sentence, not a stack trace',
      (tester) async {
    // The same screen, told a code for a port nobody opened -- which is the ordinary case on a
    // network and the one the socket layer turns into an outcome instead of an exception.
    final board = _Switchboard();
    final log = (await tester.runAsync(
      () => EventLog.open(
        file: File('${dir.path}${Platform.pathSeparator}solo.ndjson'),
        nodeId: 'phone',
        nowMillis: () => 1000,
      ),
    ))!;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: _device(
            _guestKey,
            cellar: Cellar.of(log),
            factory: (_) => _LoopbackSync(
              board: board,
              source: log,
              localName: 'phone',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      _on(_guestKey, find.byKey(const ValueKey('sync-code'))),
      'hollowcourt://127.0.0.1:47000/AB23CD',
    );
    await tester.tap(_on(_guestKey, find.text('连接并同步')));
    var pumps = 0;
    while (pumps < 100 && find.text('没能同步').evaluate().isEmpty) {
      await tester.pump();
      pumps++;
    }

    expect(_on(_guestKey, find.text('没能同步')), findsOneWidget);
    expect(_on(_guestKey, find.textContaining('Connection refused')), findsOneWidget);
    expect(log.stock.bottleCount, 0);
  });

  // ---------------------------------------------------------------------------------------------
  // §10.3.2 ①: the tap in 附近的设备.
  //
  // **Two new facts are what this test is for**, and neither is "a screen draws a box": the connection does not
  // go out until the reader confirms, and a *stranger* is authenticated by the six digits rather than by a code
  // nobody typed. The rest of it -- the sealed handshake, the merge, the arithmetic on the screen -- is the same
  // `runExchange` the test above walks through.
  testWidgets('**a tap in the nearby list connects only after the box, and a stranger compares six digits**',
      (tester) async {
    final board = _Switchboard();
    final hostLog = (await tester.runAsync(
      () => EventLog.open(
        file: File('${dir.path}${Platform.pathSeparator}tap-host.ndjson'),
        nodeId: 'workstation',
        nowMillis: () => 1000,
      ),
    ))!;
    final guestLog = (await tester.runAsync(
      () => EventLog.open(
        file: File('${dir.path}${Platform.pathSeparator}tap-guest.ndjson'),
        nodeId: 'phone',
        nowMillis: () => 2000,
      ),
    ))!;
    final hostIdentity = (await tester.runAsync(DeviceIdentity.generate))!;
    final guestIdentity = (await tester.runAsync(DeviceIdentity.generate))!;
    await tester.runAsync(() async {
      await hostLog.record(
        (hlc) => StockEvents.bottleAdded(
          hlc: hlc,
          bottleId: 'bottle-gin',
          sku: 'gin',
          volume: Volume.fromMillilitres(700),
        ),
      );
      await guestLog.record(
        (hlc) => StockEvents.bottleAdded(
          hlc: hlc,
          bottleId: 'bottle-vermouth',
          sku: 'sweetVermouth',
          volume: Volume.fromMillilitres(700),
        ),
      );
    });

    const doorPort = 47900;
    // **What the laptop can hear**: the phone, announcing itself with the port it is listening on. This is the
    // datagram the real `LanDiscovery` would have delivered -- and the port in it is the one the phone's listener
    // actually holds, which is the bug this half of the work fixed.
    final heard = [
      DiscoveredDevice(
        name: 'phone',
        fingerprint: guestIdentity.fingerprint,
        address: '127.0.0.1',
        port: doorPort,
        lastSeenMillis: 1,
        // A stranger: this machine has never met it.
        remembered: false,
        version: '1.0.0',
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              Expanded(
                child: _device(
                  _hostKey,
                  cellar: Cellar.of(hostLog),
                  identity: hostIdentity,
                  nearby: heard,
                  factory: (_) => _LoopbackSync(
                    board: board,
                    source: hostLog,
                    localName: 'workstation',
                  ),
                ),
              ),
              Expanded(
                child: _device(
                  _guestKey,
                  cellar: Cellar.of(guestLog),
                  identity: guestIdentity,
                  factory: (_) => _LoopbackSync(
                    board: board,
                    source: guestLog,
                    localName: 'phone',
                    doorPort: doorPort,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The phone is reachable: its screen is open, so its listener is bound and the announcement carries the port.
    expect(board.door(doorPort), isNotNull, reason: 'the phone holds a listener while its screen is open');

    // ---------------------------------------------------------------- the tap, and the box
    final row = _on(_hostKey, find.byKey(ValueKey('nearby-${guestIdentity.fingerprint}')));
    expect(row, findsOneWidget);
    // **Scrolled to first.** The nearby list sits below the code field and the scope chooser, and a tap on a widget
    // outside the viewport lands nowhere -- which reads as "the box never opened" rather than as a missed tap.
    await tester.ensureVisible(row);
    await tester.pump();
    await tester.tap(row);
    await tester.pumpAndSettle();

    expect(_on(_hostKey, find.text('连这台设备？')), findsOneWidget);
    expect(_on(_hostKey, find.text('127.0.0.1:$doorPort')), findsOneWidget);
    expect(_on(_hostKey, find.text('陌生——这台机器没见过它')), findsOneWidget);
    expect(
      _on(_hostKey, find.text('两台设备各显示六位数字，对上了才开始同步。')),
      findsOneWidget,
      reason: 'a stranger has no key, so the digits are what will authenticate this',
    );
    // Nothing has moved: no event, and no connection either.
    expect(hostLog.stock.bottleCount, 1);
    expect(guestLog.stock.bottleCount, 1);

    await tester.ensureVisible(find.byKey(const ValueKey('nearby-connect')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('nearby-connect')));
    var pumps = 0;
    // **Both screens show the six digits and both wait.** Nothing is exchanged until each person has pressed, which
    // is the whole reason the digits are worth anything.
    while (pumps < 400 && find.text('对一下两边的数字').evaluate().length < 2) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump(const Duration(milliseconds: 10));
      pumps++;
    }
    expect(
      find.text('对一下两边的数字'),
      findsNWidgets(2),
      reason: 'the asking screen and the answering one both stop on the comparison',
    );
    // The same digits on both, because both derived them from the same transcript. Read off the two `compare-code`
    // widgets rather than off every `Text` on the screen: the value is drawn by a `SelectableText`, and a finder
    // that looked for `Text` found nothing at all while the case it was checking was working.
    final shown = {
      for (final found in find.byKey(const ValueKey('compare-code')).evaluate())
        (found.widget as SelectableText).data!,
    };
    expect(shown.length, 1, reason: 'one transcript, one number, whichever screen it is drawn on');
    expect(shown.single, matches(RegExp(r'^\d{3} \d{3}$')));

    // **Both people agree, one screen each.** Tapping "the first 一致 on screen" twice would have pressed the same
    // button twice and never the other device's -- which reads as an exchange that hangs, and is really a test that
    // only ever answered one side. The digits are worth nothing unless both sides look.
    for (final key in const [_hostKey, _guestKey]) {
      final agree = _on(key, find.byKey(const ValueKey('compare-agree')));
      await tester.ensureVisible(agree);
      await tester.pump();
      await tester.tap(agree);
      await tester.pump();
      // **[the defect this asserts against] The screen it was pressed on stops asking.** Agreeing does not finish
      // the exchange -- the other device's person has not answered yet -- so a screen that kept drawing the same
      // six digits and the same two buttons was a button that appeared to do nothing. Reported in exactly those
      // words from a phone, in front of a comparison that was working.
      expect(
        _on(key, find.byKey(const ValueKey('compare-code'))),
        findsNothing,
        reason: 'the device that answered has left the question behind',
      );
      // And the other screen is still asking, which is what "one screen each" means.
      final other = key == _hostKey ? _guestKey : _hostKey;
      if (key == _hostKey) {
        expect(_on(other, find.byKey(const ValueKey('compare-code'))), findsOneWidget);
        // **One person agreeing does not establish the connection, and this is the assertion that says so.**
        // The gate on the other side is ahead of its first frame, so after this answer there is a device that has
        // agreed, a device that has not, and two cellars that are still exactly as they were -- which is the whole
        // reason the digits are worth comparing. A version that let one answer through would pass every
        // screenshot check and fail here.
        expect(hostLog.stock.bottleCount, 1, reason: 'nothing has moved yet');
        expect(guestLog.stock.bottleCount, 1, reason: 'nothing has moved on the other side either');
      }
    }

    pumps = 0;
    while (pumps < 400 && find.text('同步完成').evaluate().length < 2) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump(const Duration(milliseconds: 10));
      pumps++;
    }

    expect(_on(_hostKey, find.text('同步完成')), findsOneWidget);
    expect(_on(_guestKey, find.text('同步完成')), findsOneWidget);
    expect(hostLog.stock.bottles.map((b) => b.sku), contains('sweetVermouth'));
    expect(guestLog.stock.bottles.map((b) => b.sku), contains('gin'));
  });
}
