/// The two devices, talking.
///
/// **The algorithm is here and the socket is somewhere else, on purpose.** Everything that can be
/// wrong about a sync -- who speaks first, when the clock set is worth sending, what happens when
/// the two disagree about the token, what a peer that hangs up mid-sentence means -- is decided in
/// this file, over a [WireChannel] that is only "lines in, lines out". The socket implementation
/// then has nothing left to get wrong but bytes, and this logic can be tested by handing it a pair
/// of in-memory channels instead of hoping a loopback connection reproduces a race.
///
/// **Both sides send their clock set, and that is the whole trick.** The obvious design has the
/// initiator ask and the responder answer, which costs a round trip and makes the two sides
/// different programs. Here, once the digests have disagreed, each side sends its own readings and
/// then sends whatever the other turns out to be missing -- so it is one exchange either way, and
/// the code for "the other side" does not exist.
///
/// **The peer's events are merged as they arrive, not collected and merged at the end.** A first
/// sync is the whole cellar, and waiting for the last frame before writing any of it would mean
/// holding all of it in memory and losing the whole transfer to a dropped connection. Merging per
/// frame also means the log is the only place the events live, which is the property the store was
/// built for.
///
/// **Nothing is sent before the token is checked.** A responder that answered first and compared
/// afterwards would hand its clock set -- a summary of everything this cellar holds, including how
/// much of it -- to whatever connected. The initiator sends its own hello first because it is the
/// one holding the ticket; that asymmetry is the only place the two roles differ.
library;

import 'dart:async';
import 'dart:collection';

import '../events/event.dart';
import '../events/hlc.dart';
import 'device_identity.dart';
import 'pairing.dart';
import 'secure_channel.dart';
import 'wire.dart';

/// What a sync needs from a cellar. `EventLog` already satisfies it, member for member.
///
/// **Three members and no more**, because these three are the entire surface the exchange has any
/// business touching. It reads the clock set, asks what a peer is missing, and merges. It does not
/// fold, does not render and does not know what an event means -- and an interface that said
/// anything about the cellar beyond that would be the exchange developing an opinion about the
/// domain, which is how a transport ends up needing a test per event type.
abstract interface class SyncSource {
  /// Every clock reading this cellar holds.
  Set<Hlc> get clocks;

  /// The events a peer holding [theirClocks] does not have.
  List<Event> missingFrom(Set<Hlc> theirClocks);

  /// Adds [incoming], and reports what was actually new.
  Future<List<Event>> merge(Iterable<Event> incoming);
}

/// A connection, reduced to what the exchange needs: lines arrive, lines leave, and it can close.
///
/// **Lines rather than frames, so that parsing stays on this side of the boundary.** A channel
/// that handed back parsed frames would have to decide what to do about an unreadable one, and the
/// answer -- close the connection and say why -- is a decision about the conversation, not about
/// the socket. Keeping the parse here also means the in-memory test channel is nine lines long.
abstract interface class WireChannel {
  /// Lines received, in order, as a single-subscription stream.
  Stream<String> get lines;

  /// Sends one line. Must not be called after [close].
  void sendLine(String line);

  /// Ends the connection. Idempotent.
  Future<void> close();
}

/// Which end of the handshake this is.
///
/// **Not a direction of data** -- both sides send and both sides receive. It decides two things
/// only: who speaks first, and who checks the token. Collapsing it into "client" and "server"
/// would suggest the roles differ in more ways than they do.
enum ExchangeRole {
  /// The side that holds the pairing ticket: sends first, presents the token.
  initiator,

  /// The side that was connected to: waits, checks the token, answers.
  responder,
}

/// The most readings a peer may claim to hold.
///
/// A ledger of a million pouring events is a real cellar; a claim of more is a peer describing
/// itself as something this program will not allocate for on request. The limit is a statement
/// about what is plausible, so that an implausible number is refused instead of served.
const int maxClockEntries = 1 << 20;

/// What happened, in enough detail for a screen to say something true about it.
final class ExchangeOutcome {
  const ExchangeOutcome({
    required this.merged,
    required this.sent,
    this.peerName = '',
    this.peerReason = '',
    this.peerIdentity = '',
    this.peerAddress = '',
    this.failure,
  });

  /// The peer's long-term public key, base64, when the handshake learned one.
  ///
  /// **This is what a caller remembers so the next sync needs no code.** It is on the outcome rather
  /// than in a field of the service because it belongs to *one exchange*: two syncs in flight would
  /// overwrite a shared field, and the value arrives before a single event moves, which is what lets
  /// a device be refused for having the wrong key rather than noticed afterwards.
  ///
  /// Empty when the peer offered none, and empty on a failure -- a refusal names no peer.
  final String peerIdentity;

  /// **Where the peer was reached, so the next sync needs no code *and* no typing.**
  ///
  /// The key alone is half of it: `TrustedDevice.address` is what 再同步一次 dials, and a device that learned a
  /// key from a connection *it accepted* has no idea where the other end lives unless the socket is asked. That
  /// was a real defect -- a tap answered, the peer remembered, and 再同步一次 did nothing because the address was
  /// missing -- and the fix belongs here rather than in the screen, because the socket that accepted the
  /// connection is the only thing that knows.
  ///
  /// Empty on the paths that never had a socket (a test's canned outcome) and on failures.
  final String peerAddress;

  /// How many of the peer's events were new to this cellar.
  final int merged;

  /// How many events this cellar handed over.
  final int sent;

  /// What the peer called itself, for showing the reader which device this was.
  final String peerName;

  /// The peer's closing reason, which is display copy.
  final String peerReason;

  /// The same outcome, with the address the connection came from or went to.
  ExchangeOutcome atPeer(String address) => ExchangeOutcome(
    merged: merged,
    sent: sent,
    peerName: peerName,
    peerReason: peerReason,
    peerIdentity: peerIdentity,
    peerAddress: address,
    failure: failure,
  );

  /// Why this exchange did not complete, or null when it did.
  ///
  /// **A string rather than an exception, and a completed exchange with a failure is still an
  /// outcome.** "The token was wrong" and "the other end vanished" are both things that happen to
  /// a person holding a phone, and both leave a log that may already have been added to. Throwing
  /// would make the caller distinguish "nothing happened" from "half of it happened" using a stack
  /// trace, and the second case is the one that needs saying out loud.
  final String? failure;

  bool get succeeded => failure == null;
}


/// Runs one exchange to completion, or to the first thing that stops it.
///
/// [token] is what this side presents, so it is meaningful for [ExchangeRole.initiator].
/// [expectedToken] is what this side requires; a responder with an empty one accepts any hello,
/// which is a decision a caller should make deliberately and never inherit from a default.
///
/// [timeout] bounds **each wait for the next frame**, not the exchange: a cellar with sixty
/// thousand events is a slow but healthy sync, while a peer that has stopped sending is a stuck
/// connection, and only the second is what a deadline should catch.
Future<ExchangeOutcome> runExchange({
  required WireChannel channel,
  required SyncSource source,
  required ExchangeRole role,
  required String localName,
  String token = '',
  String expectedToken = '',
  Duration timeout = const Duration(seconds: 30),
  /// **The reader's confirmation, when the device is being added by comparing screens.**
  ///
  /// Called with the six digits derived from this handshake (`short_code.dart`) **after** the channel is
  /// sealed and **before** a single event moves. Returning false ends the session with a reason and merges
  /// nothing -- and **there is no retry**, which is not a preference: twenty bits is enough exactly once. A
  /// caller that passes nothing gets the code-authenticated behaviour unchanged, which is what keeps the two
  /// ways of adding a device from interfering with each other.
  ///
  /// The host passes it too, and that is the half that is easy to forget: a responder that confirmed while the
  /// initiator did not would be a device that asked its owner to compare two screens and then served the
  /// cellar to whoever was there.
  Future<bool> Function(String shortCode)? confirmComparison,

  /// Whether the connection is sealed before anything is said on it.
  ///
  /// **On by default, and the default is the point.** Section 10.3 assumes the network is hostile,
  /// and the first frame of an exchange carries a clock digest -- a summary of everything in the
  /// cellar. Leaving this opt-in would mean the safe path is the one a caller has to remember, and
  /// the one they get by forgetting is the one that leaks. A caller that has a reason to talk
  /// plainly (a test of the frame protocol itself, or a socket somebody has already secured) says so
  /// by name.
  bool seal = true,
  /// This device's long-term key, when it has one, and the key it expects the peer to hold.
  ///
  /// **[expectedIdentity] is what replaces the code on every sync after the first.** The first
  /// meeting is authenticated by six characters a human arranged; each side learns the other's key
  /// during it; from then on a connection can be authenticated by the key alone. An empty
  /// expectation means "no opinion", which is the state a first pairing is in.
  DeviceIdentity? identity,
  String expectedIdentity = '',

  /// The keys this side will accept **in place of** a pairing code.
  ///
  /// The host's half of the second-sync story: a joiner knows exactly which device it expects, and a host
  /// knows only which devices it has met -- so it accepts the code it is showing, or any key on this list.
  Set<String> acceptedIdentities = const {},
}) async {
  WireChannel connection = channel;

  /// Who the peer turned out to be. **Declared before the handshake, not after it**, because the
  /// handshake is what fills it and the sealed channel is built from the same block.
  var peerIdentity = '';

  /// True when the handshake authenticated the peer with a remembered key rather than the pairing code.
  var handshakeProvedByKey = false;

  if (seal) {
    // **The code is the secret, and each side knows its own half of it.** The initiator presents the
    // code it was shown; the responder holds the one it minted. An empty expected code means this
    // device is not requiring pairing at all -- a deliberate choice a caller makes, per the
    // parameter's own note -- and then the connection is encrypted without anybody being identified.
    final secret = role == ExchangeRole.initiator ? token : expectedToken;
    final handshake = await SecureChannel.handshake(
      channel,
      role: role,
      secret: secret,
      identity: identity,
      expectedIdentity: expectedIdentity,
      acceptedIdentities: acceptedIdentities,
      // **A gate a person operates is what makes an unproved peer acceptable** (§10.3.2). A listener that is
      // waiting to be tapped holds no code, so it has nothing to demand and a stranger has nothing to show --
      // and the proof in that meeting is the comparison below, which is derived from this very handshake. The
      // flag is derived here rather than passed in by the caller, so "reachable by anybody" and "a person
      // decides" cannot drift apart at a call site that passes one without the other.
      allowUnprovedPeer: confirmComparison != null,
      timeout: timeout,
    );
    if (!handshake.succeeded) {
      // Nothing was merged and nothing was sent: the refusal happened before the hello, which is the
      // whole reason the handshake comes first.
      return ExchangeOutcome(
        merged: 0,
        sent: 0,
        failure: handshake.failure,
      );
    }

    connection = handshake.channel!;
    peerIdentity = handshake.peerIdentity;
    handshakeProvedByKey = handshake.provedByKey;
    // The lines the handshake already read are the sealed stream's own, so the exchange continues on
    // exactly the byte stream the handshake finished with.
    connection = _SealedLines(connection, handshake.lines!);

    // **The comparison gate, and it is here because this is the only place both roles pass through.** The
    // channel is sealed, both ends have derived the same six digits, and nothing has been exchanged yet --
    // which is exactly the moment a person can still decide. A refusal says why and closes, so the other
    // screen can say the same thing rather than waiting.
    //
    // **And a device that proved a remembered key is not asked.** The rule `startHosting` states for the
    // code path is the same one: a key this machine learned during an earlier meeting is the authentication,
    // and asking somebody to compare digits for a device they synced with last week is ceremony. What this
    // costs is stated rather than hidden -- a reader who chose the comparison still gets it for every peer
    // that is *new*, which is the case the comparison exists for.
    final confirm = confirmComparison;
    if (confirm != null && !handshakeProvedByKey) {
      final agreed = await confirm(handshake.shortCode);
      if (!agreed) {
        const reason = 'the two screens showed different numbers, so this session was given up';
        try {
          connection.sendLine(ByeFrame(reason: reason).encode());
        } on Object {
          // The other end is already gone; the reason then only exists on this screen.
        }
        return ExchangeOutcome(merged: 0, sent: 0, failure: reason);
      }
    }
  }

  final inbox = _Inbox(connection.lines);
  var sent = 0;
  var merged = 0;
  var peerName = '';
  var peerReason = '';

  Future<ExchangeOutcome> fail(String why) async {
    // Say why before closing, when the channel still works. A dropped connection with no reason
    // leaves the other end guessing, and the other end is a person's screen.
    try {
      connection.sendLine(ByeFrame(reason: why).encode());
    } on Object {
      // The channel is already gone; the reason then only exists locally.
    }
    await connection.close();
    await inbox.finish();
    return ExchangeOutcome(
      peerIdentity: peerIdentity,
      merged: merged,
       sent: sent,
      peerName: peerName,
      peerReason: peerReason,
      failure: why,
    );
  }

  try {
    final mine = ClockDigest.of(source.clocks);

    if (role == ExchangeRole.initiator) {
      connection.sendLine(
        HelloFrame(name: localName, digest: mine, token: token).encode(),
      );
    }

    // The peer's hello, or the bye that means it will not be sending one.
    final greeting = await inbox.next(timeout);
    if (greeting is ByeFrame) {
      peerReason = greeting.reason;
      await connection.close();
      await inbox.finish();
      return ExchangeOutcome(
        peerIdentity: peerIdentity,
        merged: merged,
         sent: sent,
        peerReason: peerReason,
        failure: 'the other end refused: ${greeting.reason}',
      );
    }
    if (greeting is! HelloFrame) {
      return await fail('the other end did not start with a hello');
    }
    peerName = greeting.name;

    if (role == ExchangeRole.responder) {
      // Checked before anything of ours is sent. Answering first and judging afterwards would
      // give a stranger a summary of this cellar before finding out it was not welcome.
      //
      // An EMPTY expectation means this device is not requiring pairing at all, which is a choice
      // a caller makes on purpose and never inherits -- so it accepts any hello, including one
      // carrying no token. The alternative reading of an empty string, "require a token and
      // compare it against nothing", would make every connection fail in a way that looks like a
      // bug in the pairing code rather than a decision.
      // **A connection that authenticated with a remembered key has no token to send**, and requiring one
      // would undo the whole feature at the last step: the handshake would pass and this check would refuse
      // the peer with 配对码不对. Found by running two real processes against each other.
      final provedByKey = seal && handshakeProvedByKey;
      if (!provedByKey && expectedToken.isNotEmpty && greeting.token != expectedToken) {
        return await fail('the pairing code did not match');
      }
      connection.sendLine(HelloFrame(name: localName, digest: mine).encode());
    }

    if (mine.likelyInSyncWith(greeting.digest)) {
      // The case ClockDigest exists for: two devices that already agree, one frame each.
      connection.sendLine(const ByeFrame(reason: 'already in sync').encode());
      await connection.close();
      await inbox.finish();
      // **[defect, reported from a real phone as "the device was not remembered"] The peer's identity belongs on
      // *every* successful outcome, and this path was the one that dropped it.** Two devices that are already in
      // sync end here -- no events to move, a `ByeFrame`, a clean success -- and the caller that remembers peers
      // keys off `peerIdentity`, so a sync that succeeded perfectly remembered nobody. The reader's second
      // connection was the one that failed to stick, which is also the one most likely to be noticed.
      return ExchangeOutcome(
        merged: 0,
        sent: 0,
        peerIdentity: peerIdentity,
        peerName: peerName,
        peerReason: 'already in sync',
      );
    }

    // Both sides send their readings; see the class comment for why not ask-then-answer.
    //
    // **Chunked like the events are, and that is not symmetry for its own sake.** A clock set has
    // one entry per event, so a cellar with more than maxItemsPerFrame events made a readings
    // frame the peer refused as unreadable -- and then the whole sync failed on the very cellars
    // most worth syncing. Caught by the test that pushes past the cap.
    for (final chunk in _chunks(source.clocks.toList())) {
      connection.sendLine(ClocksFrame(chunk).encode());
    }

    // **How many readings to expect is already on the wire**, so nothing has to be guessed and no
    // frame past the end has to be read: the hello announced `digest.count`, and a peer sends
    // exactly that many readings before it sends anything else. Reading until "the next frame is
    // not a readings frame" would deadlock -- the peer is doing the same and will not send its
    // events until its own loop ends -- which is what the first version of this did.
    //
    // A count that does not match what actually arrives is a peer contradicting itself: too few
    // and this waits until the deadline, too many and the extra readings frame lands in the middle
    // of the sync and is refused. Both are reported, and neither is guessed at.
    final announced = greeting.digest.count;
    if (announced > maxClockEntries) {
      // A count is a claim, and this one would have us allocate on demand from the far end of a
      // socket. Refusing an absurd claim is cheaper than discovering it while holding the memory.
      return await fail('the other end claims $announced events, which is beyond the limit');
    }

    final theirClocks = <Hlc>[];
    while (theirClocks.length < announced) {
      final frame = await inbox.next(timeout);
      if (frame is! ClocksFrame) {
        return await fail('the other end did not send all of its readings');
      }
      theirClocks.addAll(frame.clocks);
    }

    // Everything to send is decided now, from the peer's readings, and the sending happens with
    // the inbox already draining -- so a large transfer in both directions at once cannot deadlock
    // on two peers who are each waiting for the other to finish writing.
    final owed = source.missingFrom(theirClocks.toSet());
    final drain = inbox.drainEvents(
      timeout: timeout,
      onMerged: (count) => merged += count,
      merge: source.merge,
    );

    for (final chunk in _chunks(owed)) {
      connection.sendLine(EventsFrame(chunk).encode());
      sent += chunk.length;
    }

    // Our own bye goes out here, BEFORE anything is awaited, and that placement is the whole
    // difference between a sync and a hang. `bye` means "I have nothing more to send", which
    // became true the moment the last event frame left -- so conditioning it on the peer's bye
    // would leave two peers each waiting for the other to finish before either would say it had.
    // This file had exactly that deadlock, and the in-memory test found it, which is why the
    // algorithm is testable without a socket.
    connection.sendLine(const ByeFrame(reason: 'done').encode());

    // The peer's bye comes back from the drain rather than from another `next`. The drain is what
    // reads that frame, so asking the inbox for it afterwards would wait for something already
    // consumed and time out on a sync that had in fact succeeded.
    final closing = await drain;
    peerReason = closing.reason;

    await connection.close();
    await inbox.finish();
    return ExchangeOutcome(
      peerIdentity: peerIdentity,
      merged: merged,
       sent: sent,
      peerName: peerName,
      peerReason: peerReason,
    );
  } on Object catch (error) {
    // Nothing that arrives over a network is allowed to reach the caller as an exception: the
    // caller is a UI action, and every failure here has a sentence a reader can act on.
    //
    // The channel is closed here as well as in `fail`, because the paths that reach this catch --
    // an unreadable frame, a timeout, a peer that vanished -- are exactly the ones that left a
    // socket open, and a leaked socket is a port still bound with nothing using it.
    try {
      await connection.close();
    } on Object {
      // Already gone, which is one of the ways to get here.
    }
    await inbox.finish();
    return ExchangeOutcome(
      peerIdentity: peerIdentity,
      merged: merged,
       sent: sent,
      peerName: peerName,
      peerReason: peerReason,
      failure: '$error',
    );
  }
}

/// Splits a list into frames no larger than [maxItemsPerFrame].
///
/// Generic because both a readings frame and an events frame are capped, and the reason is the
/// same for both: the receiver allocates per frame, so an uncapped frame is an allocation decided
/// by the other end of a socket.
Iterable<List<T>> _chunks<T>(List<T> items) sync* {
  for (var at = 0; at < items.length; at += maxItemsPerFrame) {
    final end = at + maxItemsPerFrame;
    yield items.sublist(at, end > items.length ? items.length : end);
  }
}

/// Frames that arrived before anyone asked for them, and the one waiter there can be.
///
/// **One subscription for the whole exchange.** A `channel.lines` stream is single-subscription,
/// so listening in one phase and again in the next would either throw or silently drop whatever
/// arrived in between -- and what arrives in between is exactly the interesting part, since both
/// sides send their clock sets without waiting. So the subscription is taken once, at the start,
/// and frames are either handed to whoever is waiting or held in order until somebody is.
final class _Inbox {
  _Inbox(Stream<String> lines) {
    _subscription = lines.listen(
      _receive,
      onError: (Object error) => _end('the connection failed: $error'),
      onDone: () => _end('the other end closed the connection'),
    );
  }

  late final StreamSubscription<String> _subscription;
  final Queue<WireFrame> _arrived = Queue<WireFrame>();
  Completer<WireFrame>? _waiter;
  String? _stopped;
  bool _finished = false;

  void _receive(String line) {
    if (_finished || _stopped != null) return;
    final frame = WireFrame.parse(line);
    if (frame == null) {
      _end('the other end sent something unreadable');
      return;
    }
    final waiter = _waiter;
    if (waiter != null) {
      _waiter = null;
      waiter.complete(frame);
    } else {
      _arrived.add(frame);
    }
  }

  void _end(String why) {
    if (_stopped != null) return;
    _stopped = why;
    final waiter = _waiter;
    _waiter = null;
    // A waiter that will never be satisfied is told so, rather than left pending forever behind a
    // connection that is already gone.
    waiter?.completeError(StateError(why));
  }

  /// The next frame, waiting for it if it has not arrived.
  Future<WireFrame> next(Duration timeout) async {    final queued = _arrived.isNotEmpty ? _arrived.removeFirst() : null;
    if (queued != null) return queued;
    final stopped = _stopped;
    if (stopped != null) throw StateError(stopped);

    final waiter = Completer<WireFrame>();
    _waiter = waiter;
    return waiter.future.timeout(
      timeout,
      onTimeout: () {
        _waiter = null;
        throw TimeoutException('the other end stopped answering', timeout);
      },
    );
  }

  /// Consumes events frames, merging each as it lands, and returns the bye that ends them.
  ///
  /// Completes when the peer's `bye` has been seen **and** every merge started before it has
  /// finished, so a caller that awaits it knows the log is settled. Merges are chained rather than
  /// run concurrently: the stream delivers in order, and two merges racing would let the second
  /// fold before the first had written.
  ///
  /// **It hands back the bye rather than swallowing it**, because the bye is the frame the caller
  /// needs next and a drain that consumed it would leave the caller waiting for one that had
  /// already arrived.
  Future<ByeFrame> drainEvents({
    required Duration timeout,
    required void Function(int) onMerged,
    required Future<List<Event>> Function(Iterable<Event>) merge,
  }) async {
    while (true) {
      final frame = await next(timeout);
      if (frame is EventsFrame) {
        final fresh = await merge(frame.events);
        onMerged(fresh.length);
        continue;
      }
      if (frame is ByeFrame) return frame;
      // Anything else mid-batch is a peer that is not following its own protocol. Stopping is
      // safer than guessing which frame it meant to send.
      throw StateError('the other end sent a ${frame.kind.wire} in the middle of a sync');
    }
  }

  Future<void> finish() async {
    _finished = true;
    await _subscription.cancel();
  }
}

/// The sealed channel with the line stream the handshake itself produced.
///
/// **A `WireChannel` is two halves, and they cannot come from the same place after a handshake.** The
/// handshake reads the first lines off the socket to agree on keys, so the *decrypting* stream has to
/// continue from the iterator the handshake was reading -- while writing still goes to the socket,
/// through the sealing `sendLine`. This puts the two halves back together.
final class _SealedLines implements WireChannel {
  const _SealedLines(this._channel, this._lines);

  final WireChannel _channel;
  final Stream<String> _lines;

  @override
  Stream<String> get lines => _lines;

  @override
  void sendLine(String line) => _channel.sendLine(line);

  @override
  Future<void> close() => _channel.close();
}
