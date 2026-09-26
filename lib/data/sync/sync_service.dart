import 'dart:async';
import 'dart:collection';
import 'dart:io';

import '../../domain/sync/device_identity.dart';
import '../../domain/sync/exchange.dart';
import '../../domain/sync/pairing.dart';
import 'socket_transport.dart';

/// What a screen needs from a sync, with the socket kept behind it.
///
/// **An interface, and not because there might be another implementation.** A widget test that
/// opened a real socket and waited for a real peer would be a test that is slow, timing-dependent,
/// and unable to produce the interesting failures on demand -- a peer that refuses, a code that is
/// wrong, a device that never answers. The seam exists so those cases can be provoked in
/// milliseconds, and the real implementation still gets its own tests over real loopback
/// connections in `test/data/sync`.
///
/// **One object holds one role at a time.** Hosting and joining are separate methods rather than a
/// mode set by a flag, because a device cannot do both at once: it is showing a code, or it is
/// typing one.
abstract interface class SyncService {
  /// What this device calls itself to a peer. Display copy, and never part of the identity.
  String get localName;

  /// Binds a listener and returns the code to show.
  ///
  /// Returns as soon as the port is bound, so the code can be on screen before anybody is waiting
  /// for it. [awaitPeer] is what waits.
  Future<PairingTicket> host({
    DeviceIdentity? identity,
    String expectedIdentity = '',

    /// The keys this host will accept **in place of** the code it is about to show.
    ///
    /// **A host cannot know which device is coming**, which is why this is a set: it has the code on its
    /// own screen for whoever is holding the other device, and it has the keys of everybody it has met
    /// before -- and the device that is coming back presents one of those rather than a code nobody gave
    /// it. Without this the second sync is refused *after* a successful handshake, with 配对码不对, which
    /// is what two real processes proved before this parameter existed.
    Set<String> acceptedIdentities = const {},

    /// The token to put in the code, when the reader chose one instead of letting the generator pick.
    ///
    /// **[decision] 2026-09-23**, the owner's: a share code at most eighteen characters long whose token half
    /// the reader chooses. Null or empty means the generator's own, because a code with no secret in it is a
    /// first meeting that nothing authenticates.
    String? token,
  });

  /// Waits for the peer that was shown the code, and runs the exchange with it.
  Future<ExchangeOutcome> awaitPeer({
    DeviceIdentity? identity,
    String expectedIdentity = '',
    /// **The reader's confirmation, for the comparison path**, called with the six digits both screens show.
    /// Returning false gives the session up with a reason and moves no events; nothing passed keeps the
    /// code-authenticated behaviour exactly as it was.
    Future<bool> Function(String shortCode)? confirmComparison,
  });

  /// Binds the listener a neighbour's tap arrives at, and answers with the port it holds.
  ///
  /// **Not [host], and the difference is the whole of §10.3.2's first request.** `host` is a device with a
  /// code on its screen: it holds a secret and demands it. This is a device that is only *reachable* -- its
  /// owner is looking at the sync screen, its neighbours can hear it announce itself, and a tap on its name
  /// should connect. It therefore holds no secret to demand, accepts every key it remembers, and lets a
  /// stranger as far as the comparison gate.
  ///
  /// **The port is the port of the listener, and the caller puts it in the announcement.** It used to be a
  /// constant (`defaultDiscoveryPort + 1`) that nothing bound, which is why a tap could not have connected:
  /// the announcement named a port with no socket behind it. Ephemeral is also the safer answer of the two --
  /// a fixed port is a number two applications on one machine collide over.
  Future<int> openForRequests({
    DeviceIdentity? identity,
    Set<String> acceptedIdentities,
  });

  /// Accepts one tap and runs the exchange it asks for, **leaving the listener open for the next one**.
  ///
  /// The same shape as [awaitPeer] with two differences that are the design rather than the plumbing: there
  /// is no token to expect, because no code is on this screen; and a peer that proves nothing is not refused
  /// by the handshake, because the proof here is the person comparing six digits -- [confirmComparison] is
  /// what decides. A caller that passes no gate gets the old behaviour, where an unproved peer is refused.
  Future<ExchangeOutcome> awaitRequest({
    DeviceIdentity? identity,
    Future<bool> Function(String shortCode)? confirmComparison,
  });

  /// Reaches the device the code names and runs the exchange.
  ///
  /// **[expectedIdentity] is how a second sync needs no code.** A ticket carries an address and a
  /// token; the key is what says the device at that address is the one that was there last time, so
  /// a caller that has one passes it here and leaves the token empty.
  Future<ExchangeOutcome> join(
    PairingTicket ticket, {
    DeviceIdentity? identity,
    String expectedIdentity = '',
    /// The same gate as [awaitPeer], and it belongs on both: a joiner that confirmed while the host did not
    /// would be a device whose owner compared two screens against a device that never asked.
    Future<bool> Function(String shortCode)? confirmComparison,
  });

  /// Gives up the role it was in: closes a session's listener, or a connection in flight.
  ///
  /// **And deliberately not the reachable listener**, which is not a session: it belongs to the screen being
  /// looked at, and a code session starting or ending must not take it away -- a device that stopped being
  /// reachable while its owner was typing a code would leave the port in the announcement pointing at nothing.
  /// [closeForRequests] is the one that closes that.
  Future<void> stop();

  /// Closes the listener a neighbour's tap arrives at, if one is open. A no-op otherwise.
  ///
  /// **Called when the screen stops being looked at**, which is the promise being kept: nobody can see this
  /// device and nobody can reach it, in the same movement.
  Future<void> closeForRequests();
}

/// A [SyncService] over a real socket.
final class SocketSyncService implements SyncService {
  SocketSyncService({required this.source, String? name})
    : localName = name ?? _hostName();

  final SyncSource source;

  @override
  final String localName;

  /// **The session's listener** -- the one `host` bound and `awaitPeer` is waiting on.
  ServerSocket? _server;

  /// **The one subscription to the reachable listener, and the sockets it has handed over.**
  ///
  /// **A `ServerSocket` is a single-subscription stream, so a device that stays reachable must own the
  /// subscription and keep it.** The first version called `acceptForSync` again for every request, and the second
  /// call threw `Bad state: Stream was already listened to` -- which the screen reported, correctly and uselessly,
  /// as 没能同步 with that sentence. So the listener is listened to **once**, here, and each accepted socket is
  /// queued for [awaitRequest] to run an exchange over ([runAccepted]).
  StreamSubscription<Socket>? _accepting;
  final Queue<Socket> _accepted = Queue<Socket>();

  /// Set while [awaitRequest] is waiting for a socket; completed by an arrival, or failed when the listener goes
  /// away -- **failed rather than left hanging**, because a loop awaiting a socket that will never come is a
  /// screen that keeps saying "reachable" about a device that is not.
  Completer<void>? _arrival;

  /// Why the listener stopped, for the outcome that says so.
  Object? _acceptFailure;

  /// **The reachable listener**, which is a different socket on a different port.
  ///
  /// Two slots rather than one, because the two roles are open at the same time: a device can be showing a code
  /// and still be *tap-able* by a neighbour, and a single slot would mean the code session's `stop()` silently
  /// taking away the port the announcement is carrying. That was the shape of the original bug in the other
  /// direction -- an announced port with no socket -- and it is not worth re-creating it inside the fix.
  ServerSocket? _requests;

  String _token = '';

  /// The name this machine answers to, for the peer's screen.
  ///
  /// `Platform.localHostname` is the operating system's own answer, which is the honest one to
  /// show: a device that introduced itself as something the reader never chose would be a name
  /// they cannot match against the machine in front of them. It can fail on a machine with no
  /// hostname configured, so there is a fallback rather than an exception.
  static String _hostName() {
    try {
      final name = Platform.localHostname.trim();
      return name.isEmpty ? 'hollow-court' : name;
    } on Object {
      return 'hollow-court';
    }
  }

  @override
  Future<PairingTicket> host({
    DeviceIdentity? identity,
    String expectedIdentity = '',
    Set<String> acceptedIdentities = const {},
    String? token,
  }) async {
    // **The session listener only.** The code goes up on a device that may also be reachable to a neighbour, and
    // taking that listener away here would leave the announcement naming a port nothing holds.
    await _stopHosting();
    // **The token may be the reader's rather than the generator's.** The owner asked for a share code whose
    // token half they choose (2026-09-23), so a caller passes it here; an empty or missing one falls back to
    // the generator rather than producing a code with no secret in it, because a code without a token is a
    // first meeting with nothing authenticating it.
    _token = (token == null || token.isEmpty) ? mintPairingToken() : token;
    _identity = identity;
    _expectedIdentity = expectedIdentity;
    _acceptedIdentities = acceptedIdentities;
    // On the network this device is actually on rather than on every interface it has, with the fallback
    // spelled out in `listenForLanSync`. See that function for why: a proxy cannot touch a raw socket, but
    // a routing-layer tool can, and a socket bound to the LAN address leaves no route to guess at.
    final server = await listenForLanSync(preferred: await lanAddress());
    _server = server;
    return ticketForListener(server, token: _token, name: localName);
  }

  DeviceIdentity? _identity;
  String _expectedIdentity = '';
  Set<String> _acceptedIdentities = const {};

  @override
  Future<ExchangeOutcome> awaitPeer({
    DeviceIdentity? identity,
    String expectedIdentity = '',
    Future<bool> Function(String shortCode)? confirmComparison,
  }) async {
    final server = _server;
    if (server == null) {
      return const ExchangeOutcome(
        merged: 0,
        sent: 0,
        failure: 'no code is being shown',
      );
    }
    try {
      return await acceptForSync(
        server: server,
        source: source,
        localName: localName,
        expectedToken: _token,
        // The identity `host` was given, unless this call brought its own: the two are the same
        // value arriving by two routes, and a caller that set it once at `host` should not have to
        // set it again.
        identity: identity ?? _identity,
        expectedIdentity: expectedIdentity.isEmpty ? _expectedIdentity : expectedIdentity,
        acceptedIdentities: _acceptedIdentities,
        confirmComparison: confirmComparison,
      );
    } finally {
      // The code has been used or given up, so its listener goes -- and the reachable one stays.
      await _stopHosting();
    }
  }

  @override
  Future<ExchangeOutcome> join(
    PairingTicket ticket, {
    DeviceIdentity? identity,
    String expectedIdentity = '',
    Future<bool> Function(String shortCode)? confirmComparison,
  }) async {
    await _stopHosting();
    return syncWithTicket(
      ticket: ticket,
      source: source,
      localName: localName,
      identity: identity,
      expectedIdentity: expectedIdentity,
      confirmComparison: confirmComparison,
    );
  }

  @override
  Future<int> openForRequests({
    DeviceIdentity? identity,
    Set<String> acceptedIdentities = const {},
  }) async {
    await _stopRequests();
    _identity = identity;
    _acceptedIdentities = acceptedIdentities;
    // **No token, and that is the role rather than an omission.** A device that is merely reachable is showing
    // nothing, so there is no secret for a peer to present; what stands in its place is the comparison gate,
    // which the accept loop passes and which refuses nothing by itself.
    _token = '';
    final server = await listenForLanSync(preferred: await lanAddress());
    _requests = server;
    _acceptFailure = null;
    _accepted.clear();
    _accepting = server.listen(
      (socket) {
        _accepted.add(socket);
        _arrival?.complete();
        _arrival = null;
      },
      onError: (Object error) {
        _acceptFailure = error;
        _arrival?.completeError(error);
        _arrival = null;
      },
      onDone: () {
        _acceptFailure ??= StateError('the listener was closed');
        _arrival?.completeError(_acceptFailure!);
        _arrival = null;
      },
      cancelOnError: false,
    );
    return server.port;
  }

  /// The next connection a neighbour made, or an error saying why none is coming.
  Future<Socket> _nextAccepted() async {
    while (true) {
      if (_accepted.isNotEmpty) return _accepted.removeFirst();
      final failure = _acceptFailure;
      if (failure != null) throw failure;
      final waiter = Completer<void>();
      _arrival = waiter;
      await waiter.future;
    }
  }

  @override
  Future<ExchangeOutcome> awaitRequest({
    DeviceIdentity? identity,
    Future<bool> Function(String shortCode)? confirmComparison,
  }) async {
    if (_requests == null) {
      return const ExchangeOutcome(
        merged: 0,
        sent: 0,
        failure: 'this device is not reachable at the moment',
      );
    }
    final Socket socket;
    try {
      socket = await _nextAccepted();
    } on Object catch (error) {
      return ExchangeOutcome(merged: 0, sent: 0, failure: 'stopped listening -- $error');
    }
    // **The listener is left open**, unlike `awaitPeer`: a device waiting to be tapped is not waiting for one
    // particular peer, and a reader who declines the first request has to be able to receive the second.
    return runAccepted(
      socket: socket,
      source: source,
      localName: localName,
      expectedToken: '',
      identity: identity ?? _identity,
      acceptedIdentities: _acceptedIdentities,
      confirmComparison: confirmComparison,
    );
  }

  @override
  Future<void> stop() => _stopHosting();

  @override
  Future<void> closeForRequests() => _stopRequests();

  /// Closes the listener a code session bound, if there is one.
  Future<void> _stopHosting() async {
    final server = _server;
    _server = null;
    if (server != null) await _close(server);
  }

  /// Closes the listener a neighbour's tap arrives at, if there is one.
  Future<void> _stopRequests() async {
    final server = _requests;
    _requests = null;
    final accepting = _accepting;
    _accepting = null;
    // **The waiter is failed before the socket is closed**, so a loop parked in [awaitRequest] learns that this
    // device is not reachable any more instead of waiting for a connection that the next line makes impossible.
    _acceptFailure ??= StateError('this device stopped being reachable');
    _arrival?.completeError(_acceptFailure!);
    _arrival = null;
    _accepted.clear();
    if (accepting != null) {
      try {
        await accepting.cancel();
      } on Object {
        // A subscription that is already gone is cancelled either way.
      }
    }
    if (server != null) await _close(server);
  }

  /// Closing a socket that is already gone is the same as closing one that is not: the caller wanted it closed.
  static Future<void> _close(ServerSocket server) async {
    try {
      await server.close();
    } on Object {
      // A listener that is already gone is closed either way.
    }
  }
}

/// Six characters, from an alphabet chosen for being read aloud.
///
/// **The token is typed by a person, so the alphabet excludes what a person confuses.** `0` and
/// `O`, `1`, `l` and `I` are the pairs that get misheard and misread, and a code that has to be
