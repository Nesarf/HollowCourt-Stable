import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../../domain/sync/device_identity.dart';
import '../../domain/sync/exchange.dart';
import '../../domain/sync/lan_address.dart';
import '../../domain/sync/pairing.dart';
import '../../domain/sync/wire.dart';

/// The socket half of a sync, and the only file in the project that knows a connection is TCP.
///
/// **Everything decidable without a socket was decided without one.** Who speaks first, when the
/// readings are worth sending, what a peer that hangs up means -- all of that is in
/// `domain/sync/exchange.dart` over a channel that is only lines in and lines out, and it is tested
/// there against an in-memory pair. What is left here is bytes: turning a socket into those lines,
/// enforcing the size limit while reading rather than after, and turning a refused connection into
/// an outcome instead of an exception.
///
/// **A line is a frame, and the limit is enforced on the bytes as they arrive.** The obvious
/// implementation -- `socket.transform(utf8.decoder).transform(const LineSplitter())` -- cannot
/// enforce [maxFrameBytes] at all, because it hands back a line only once the whole line has
/// already been buffered and decoded. A peer that opens a connection and sends without ever sending
/// a newline would then cost this process as much memory as it cared to send. So the bytes are
/// framed here, one newline at a time, and the pending buffer is checked as it grows.
final class SocketChannel implements WireChannel {
  SocketChannel._(this._socket) {
    // Our frames are already batched and a sync is a short sequence of small messages, so Nagle's
    // algorithm would add a delay to each one that has nothing to coalesce with. On a loopback
    // that is invisible; on Wi-Fi it is a stall per round trip, and a sync has several.
    _socket.setOption(SocketOption.tcpNoDelay, true);
    _subscription = _socket.listen(
      _onBytes,
      onError: _onError,
      onDone: _onDone,
      cancelOnError: false,
    );
  }

  /// Wraps an accepted or connected socket.
  factory SocketChannel.of(Socket socket) => SocketChannel._(socket);

  final Socket _socket;
  final StreamController<String> _lines = StreamController<String>();
  late final StreamSubscription<List<int>> _subscription;

  /// Bytes received that do not yet make a whole line.
  final List<int> _pending = <int>[];

  bool _closed = false;

  @override
  Stream<String> get lines => _lines.stream;

  void _onBytes(List<int> chunk) {
    if (_closed) return;
    var at = 0;
    while (at < chunk.length) {
      final newline = chunk.indexOf(0x0A, at);
      if (newline < 0) {
        _pending.addAll(chunk.sublist(at));
        if (_pending.length > maxFrameBytes) {
          // Checked here, before a line is ever assembled, because the point is not to judge a
          // large frame but to never hold one.
          _fail(StateError('the other end sent more than $maxFrameBytes bytes without a frame end'));
        }
        return;
      }
      _pending.addAll(chunk.sublist(at, newline));
      final line = _takeLine();
      at = newline + 1;
      if (_closed) return;
      _lines.add(line);
    }
  }

  String _takeLine() {
    var end = _pending.length;
    // A peer that terminates with CRLF is not wrong, and a trailing return would end up inside the
    // JSON as a stray character. The parser trims, so this is belt and braces rather than load
    // bearing -- but a line is a frame and a frame should not carry its terminator.
    if (end > 0 && _pending[end - 1] == 0x0D) end--;
    final line = utf8.decode(_pending.sublist(0, end), allowMalformed: true);
    _pending.clear();
    return line;
  }

  void _fail(Object error) {
    if (_closed) return;
    _closed = true;
    if (!_lines.isClosed) {
      _lines.addError(error);
      unawaited(_lines.close());
    }
    _socket.destroy();
  }

  void _onError(Object error) => _fail(error);

  void _onDone() {
    if (_closed) return;
    _closed = true;
    if (!_lines.isClosed) unawaited(_lines.close());
  }

  @override
  void sendLine(String line) {
    if (_closed) throw StateError('sent on a closed connection');
    // One frame, one line, always: `WireFrame.encode` is `jsonEncode`, which escapes any newline
    // inside a value. The terminator added here is the only one on the wire.
    _socket.add(utf8.encode('$line\n'));
  }

  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    try {
      await _socket.flush();
      await _socket.close();
    } on Object {
      // A connection the peer already dropped is closed either way, which is what was asked for.
    }
    await _subscription.cancel();
    if (!_lines.isClosed) await _lines.close();
  }
}

/// Binds a listener for a sync, on an ephemeral port unless one is named.
///
/// [port] of 0 is the useful default rather than a fixed number: two cellars on one machine, or a
/// phone that already has something on a well-known port, both work when the operating system
/// picks, and the port that was picked is read back off the listener and put in the ticket. A fixed
/// port would be a number that has to be right before it is known.
Future<ServerSocket> listenForSync({
  InternetAddress? address,
  int port = 0,
}) => ServerSocket.bind(address ?? InternetAddress.anyIPv4, port, backlog: 1);

/// Binds the sync listener on the network this device is actually on, and falls back to every interface.
///
/// **Two reasons, and the second one is the owner's requirement**: *"记得实现同步工作不被代理影响（即便代理使用
/// 全局模式）"*.
///
/// 1. **A socket bound to one address is a socket only that network can reach.** Binding to `anyIPv4`
///    listens on every interface the machine has -- the Wi-Fi, the WSL bridge, a VPN's adapter -- and the
///    ticket then advertises one address while the socket accepts connections on all of them. A phone on
///    the Wi-Fi has no business reaching this process through a container bridge.
/// 2. **And it is what makes the route unambiguous.** An HTTP proxy cannot touch this: the sync path opens
///    raw TCP and UDP sockets and never consults a proxy setting, which `test/data/sync/no_proxy_test.dart`
///    holds in place. What *can* interfere is a tool that captures the routing table itself -- a VPN or a
///    TUN-mode proxy. Sending from a socket bound to the LAN address pins the traffic to that interface,
///    which is the difference between a route the operating system chooses and a route that is known.
///
/// The fallback matters as much as the binding: on a machine whose interfaces cannot be enumerated, or
/// whose advertised address has gone stale between the ticket and the connection, refusing to host at all
/// would be worse than listening everywhere. Discovery already ranked the candidates (`chooseLanAddress`),
/// and this is the same choice applied to a socket.
Future<ServerSocket> listenForLanSync({int port = 0, String? preferred}) async {
  if (preferred != null && preferred.isNotEmpty) {
    try {
      return await listenForSync(address: InternetAddress(preferred), port: port);
    } on Object {
      // Then the address this device thought it had is not one it can bind -- a stale answer, or an
      // interface that went away. Every interface is the honest fallback rather than a failed host.
    }
  }
  return listenForSync(port: port);
}

/// The address a peer on the same network can actually reach.
///
/// **A listener bound to `anyIPv4` has no useful address of its own**, so a ticket built from it would
/// say `0.0.0.0` and nobody could connect. This asks the interfaces instead.
///
/// **And then it ranks them rather than taking the first**, which is the fix for a failure that is
/// invisible from this side: `NetworkInterface.list` returns whatever order the operating system keeps,
/// and on a machine with WSL, Hyper-V or a VPN one of those arrives first, answers perfectly, and is
/// reachable by nobody else. The ranking lives in `domain/sync/lan_address.dart` so it can be tested
/// without this machine's adapters. Null when there is nothing to offer.
Future<String?> lanAddress() async {
  try {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
      includeLinkLocal: false,
    );
    return chooseLanAddress([
      for (final interface in interfaces)
        for (final address in interface.addresses)
          LanCandidate(
            interfaceName: interface.name,
            address: address.address,
          ),
    ]);
  } on Object {
    // A machine that will not enumerate its interfaces is a machine with no address to offer.
  }
  return null;
}

/// **The interface this device would be reached on, name and address together.**
///
/// `lanAddress()` answers with the address, which is enough to listen on and not enough to say *what kind of
/// link* it is: the classification reads the interface's name (`link_mode.dart`), so a screen that wants to
/// tell a reader "you are on Wi-Fi" needs the name as well. Returning the candidate rather than a second
/// lookup keeps the address and the name from being chosen twice and disagreeing.
Future<LanCandidate?> lanCandidate() async {
  try {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
      includeLinkLocal: false,
    );
    final ranked = rankedLanCandidates([
      for (final interface in interfaces)
        for (final address in interface.addresses)
          LanCandidate(interfaceName: interface.name, address: address.address),
    ]);
    return ranked.isEmpty ? null : ranked.first;
  } on Object {
    // A machine that will not enumerate its interfaces is a machine with no address to offer.
  }
  return null;
}

/// The ticket to show for a listener, using [host] when given and the interfaces otherwise.
Future<PairingTicket> ticketForListener(
  ServerSocket server, {
  required String token,
  required String name,
  String? host,
}) async {
  final chosen = host ?? await lanAddress() ?? server.address.address;
  return PairingTicket(host: chosen, port: server.port, token: token, name: name);
}

/// The connecting side: reach the ticket's address and run one exchange.
///
/// **A refused connection is an outcome and not an exception.** Nothing is more ordinary on a
/// network than the other device being asleep, on a different network, or simply gone -- and the
/// person holding the phone needs a sentence, not a stack trace. Only the connect is handling here;
/// the exchange catches its own failures.
Future<ExchangeOutcome> syncWithTicket({
  required PairingTicket ticket,
  required SyncSource source,
  required String localName,
  /// This device's long-term key, and the key it requires the host to hold.
  ///
  /// **[expectedIdentity] is what makes a second sync need no code**: the first meeting learned the
  /// host's key, and passing it here means the connection is authenticated by the key instead of by
  /// six characters somebody read off a screen.
  DeviceIdentity? identity,
  String expectedIdentity = '',
  Set<String> acceptedIdentities = const {},
  Future<bool> Function(String shortCode)? confirmComparison,
  Duration connectTimeout = const Duration(seconds: 8),
  Duration timeout = const Duration(seconds: 30),
}) async {
  // **An address, never a name.** `Socket.connect` takes a `String` and resolves it if it is a hostname,
  // which means a pairing code carrying a name would send this process to a name service -- and a name
  // service is the outside world. The owner's framing is exact: this feature is a *closed* network, the
  // kind of thing a hospital runs inside its own walls, and it has to work on a network with no route out
  // at all. Two devices that are on the same network by definition do not need to ask anybody where the
  // other one is: the ticket already says so, in digits.
  //
  // So the name is refused before a socket exists, with a sentence that says why rather than a resolution
  // failure that does not.
  final address = InternetAddress.tryParse(ticket.host);
  if (address == null) {
    return ExchangeOutcome(
      merged: 0,
      sent: 0,
      failure: 'the address in that code is not an IP address, and this connects by address: '
          'the network it is for has no name service to ask',
    );
  }

  final Socket socket;
  try {
    socket = await Socket.connect(address, ticket.port, timeout: connectTimeout);
  } on Object catch (error) {
    return ExchangeOutcome(
      merged: 0,
      sent: 0,
      failure: 'could not reach ${ticket.host}:${ticket.port} -- $error',
    );
  }
  return runExchange(
    channel: SocketChannel.of(socket),
    source: source,
    role: ExchangeRole.initiator,
    localName: localName,
    token: ticket.token,
    identity: identity,
    expectedIdentity: expectedIdentity,
    confirmComparison: confirmComparison,
    timeout: timeout,
  );
}

/// The listening side: accept one connection and run one exchange with it.
///
/// **One connection, because a sync is a conversation between two cellars.** Accepting in a loop
/// would mean a device that anybody on the network can keep busy, and the second connection has
/// nothing to add that the first did not: the listener is meant to be open while a code is on the
/// screen and closed afterwards.
Future<ExchangeOutcome> acceptForSync({
  required ServerSocket server,
  required SyncSource source,
  required String localName,
  required String expectedToken,
  /// This device's long-term key, and the key it requires the joining device to hold.
  DeviceIdentity? identity,
  String expectedIdentity = '',
  Set<String> acceptedIdentities = const {},
  Future<bool> Function(String shortCode)? confirmComparison,
  Duration timeout = const Duration(seconds: 30),
}) async {
  final Socket socket;
  try {
    // **`server.first` is a one-shot listen, and that is the point of the distinction.** It is right for a code
    // on a screen -- one peer was told the code, and the listener closes afterwards -- and it is *wrong* for a
    // listener that stays open to be tapped again: a `ServerSocket` is a single-subscription stream, so the
    // second `first` throws `Bad state: Stream was already listened to` instead of waiting for the next peer.
    // That is what a reachable device did after answering once: it reported 没能同步 with exactly that sentence
    // and stopped accepting anybody. [runAccepted] is the half that a caller which already holds a socket uses.
    socket = await server.first;
  } on Object catch (error) {
    return ExchangeOutcome(merged: 0, sent: 0, failure: 'stopped listening -- $error');
  }
  return runAccepted(
    socket: socket,
    source: source,
    localName: localName,
    expectedToken: expectedToken,
    identity: identity,
    expectedIdentity: expectedIdentity,
    acceptedIdentities: acceptedIdentities,
    confirmComparison: confirmComparison,
    timeout: timeout,
  );
}

/// Runs one exchange over a connection somebody else accepted.
///
/// **Split out because `ServerSocket` can be listened to once.** A device waiting to be tapped holds one
/// listener across many requests, so *it* owns the subscription (see `SocketSyncService`) and hands each arrived
/// socket here; the code path keeps calling [acceptForSync], which is this plus the single accept that a screen
/// with a code on it wants.
Future<ExchangeOutcome> runAccepted({
  required Socket socket,
  required SyncSource source,
  required String localName,
  required String expectedToken,
  DeviceIdentity? identity,
  String expectedIdentity = '',
  Set<String> acceptedIdentities = const {},
  Future<bool> Function(String shortCode)? confirmComparison,
  Duration timeout = const Duration(seconds: 30),
}) async {
  // **Read before the exchange, because the exchange closes the socket.** `Socket.remoteAddress` on a closed
  // socket throws `SocketException: Socket has been closed` -- which turned two existing tests into errors the
  // first time this was written, and would have turned a *successful* sync into a thrown exception on a device.
  String address = '';
  try {
    address = socket.remoteAddress.address;
  } on Object {
    // A socket that is already gone has no address to offer, and the exchange below will say why.
  }
  final outcome = await runExchange(
    channel: SocketChannel.of(socket),
    source: source,
    role: ExchangeRole.responder,
    localName: localName,
    expectedToken: expectedToken,
    identity: identity,
    expectedIdentity: expectedIdentity,
    acceptedIdentities: acceptedIdentities,
    confirmComparison: confirmComparison,
    timeout: timeout,
  );
  // **The address comes from the socket, and only the socket knows it.** This is what a device that accepted a
  // tap remembers, and without it the peer is remembered with a key and nowhere to use it (see
  // `ExchangeOutcome.peerAddress`).
  return outcome.atPeer(address);
}

/// retyped because two of its characters are the same shape is a code that failed at the one job
/// section 10 gives it -- being the fallback for when the camera will not cooperate. The remaining
/// thirty-one characters are unambiguous in both cases when spoken.
///
/// **`Random.secure()`, not the default.** The token's whole purpose is that a stranger on the
/// same network does not have it, and a predictable sequence would hand it to anyone who had seen
/// one code before. Thirty-one to the sixth is about nine hundred million, which is small against
/// a determined attacker and entirely adequate against the threat section 10.3 names: somebody
/// else on the café's wifi.
String mintPairingToken() {
  const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  final random = Random.secure();
  return String.fromCharCodes([
    for (var i = 0; i < 6; i++) alphabet.codeUnitAt(random.nextInt(alphabet.length)),
  ]);
}
