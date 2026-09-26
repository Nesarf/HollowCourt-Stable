import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'device_identity.dart';
import 'exchange.dart';
import 'short_code.dart';

/// The sync connection, with the handshake section 10.3 asks for and every frame sealed after it.
///
/// WHY THIS EXISTS AT ALL, STATED AS THE DESIGN'S OWN WORDS.
///
/// Section 10.3 says the LAN must be assumed untrusted -- *"the same Wi-Fi may be a cafe, a dormitory,
/// a company"* -- and promises four things: a QR or PIN confirmation, long-term keys exchanged at
/// pairing with HMAC signatures thereafter, payloads encrypted at the transport layer, and sharing
/// that can be scoped. What the code had was the first one and a plain TCP socket. **A hello frame
/// carries a clock digest, which is a summary of everything in the cellar**, so a passive listener on
/// the cafe's wifi could read how much somebody owns and a man in the middle could rewrite the
/// exchange in flight. This file is the rest.
///
/// THE HANDSHAKE, IN FOUR LINES AND ONE PARAGRAPH.
///
/// Two ephemeral X25519 keys are exchanged in the clear. The shared secret is combined with a hash of
/// the whole handshake transcript through HKDF, which yields two independent AES-GCM keys -- one per
/// direction -- so no nonce is ever reused across directions and a reflection attack has nothing to
/// reflect. When a pairing code exists, both sides additionally prove they know it by HMAC-ing the
/// transcript under a key derived from it: **a peer that does not have the code cannot complete the
/// handshake, and cannot splice two half-handshakes together** because the transcript each side signs
/// is the one it actually saw. That is what makes the six-character code worth having: without this
/// it was a password checked *after* the digest had already been handed over.
///
/// WHY "HMAC SIGNATURES THEREAFTER" IS SATISFIED BY AN AEAD TAG, RATHER THAN BY A SEPARATE MAC.
/// Section 10.3 asks for two properties per message: that it was not modified, and that it came from
/// the peer that holds the key. AES-GCM gives both on every frame, and gives them over the ciphertext
/// -- which is strictly stronger than appending an HMAC to a plaintext frame, where the data is
/// readable to anyone listening and the MAC only says it was not edited. The handshake itself does use
/// a plain HMAC, because the handshake is the part that has to authenticate before there is a key to
/// seal with.
///
/// WHAT THIS DELIBERATELY DOES NOT DO.
///
/// * **No long-term identity key.** The design says "long-term keys are exchanged during pairing"; what
///   is implemented is a per-connection ephemeral pair authenticated by the pairing code. That gives
///   confidentiality and authentication for the connection, and it does **not** give the property a
///   long-term key would: that the device you synced with last week is the device you are syncing with
///   now, without a human re-confirming a code. Recording that as a gap rather than calling the
///   promise kept.
/// * **No forward secrecy across connections beyond the ephemeral keys**, which is what ephemeral keys
///   already give: a key stolen from one connection does not open another.
/// * **No scoping.** Which events travel is decided by `SyncSource`, and nothing here filters them;
///   scoping to a Bar is a filter over events and does not belong inside a transport.
///
/// THE FRAME FORMAT, because it is a wire format and renaming things breaks versions.
///
///     handshake  {"t":"s1","pk":...,"n":...}                     initiator opens
///                {"t":"s2","pk":...,"n":...,"tag":...}           responder answers (tag iff a code)
///                {"t":"s3","tag":...}                           initiator proves it too (iff a code)
///                {"t":"s4"}                                     responder confirms the handshake
///                {"t":"sx","reason":...}                        and either side says why it stops
///     frames     base64( nonce[12] || ciphertext || tag[16] )    one line, as before
///
/// The nonce is the frame's own counter, big-endian, and the counter is **checked rather than
/// tolerated**: a frame out of order, repeated, or missing is refused. TCP already guarantees order,
/// so a gap means a peer that is not running this protocol or an attacker who dropped one -- and both
/// are worth refusing a connection over rather than reassembling a cellar from a lossy stream.
final class SecureChannel implements WireChannel {
  SecureChannel._(this._inner, this._inboundKey, this._outboundKey, this._lines);

  final WireChannel _inner;
  final SecretKey _inboundKey;
  final SecretKey _outboundKey;
  final Stream<String> _lines;

  /// Which direction this side encrypts with. On the wire it decides which of the two derived keys
  /// seals which way, so the two ends cannot accidentally use the same one.
  int _outboundCounter = 0;
  int _inboundCounter = 0;
  bool _closed = false;

  /// A name for the peer, for a screen and for a log. Never part of the identity.
  static const String protocol = 'hc-sync-v1';

  /// The AEAD every frame uses. AES-GCM with 256-bit keys, which is what the platform gives natively.
  static final Cipher _aead = AesGcm.with256bits();
  static final Hmac _hmac = Hmac.sha256();

  @override
  Stream<String> get lines => _lines;

  /// The tail of the send queue: every frame is sealed after the one before it.
  ///
  /// **Sealing is asynchronous and the receiver is strict about order, so the sends have to be
  /// chained.** `sendLine` is synchronous by contract -- `WireChannel` says so -- while AES-GCM
  /// returns a future, and the first version took the counter here and let the encryption race: two
  /// frames written in the same event-loop turn could reach the socket in either order, and the
  /// receiving end refuses a counter it did not expect. That is a real hang under a fast sync, not a
  /// theoretical one, and it would show up as an intermittent refusal between two correct builds.
  Future<void> _sendQueue = Future<void>.value();

  @override
  void sendLine(String line) {
    if (_closed) throw StateError('sent on a closed connection');
    final nonce = _nonceFor(_outboundCounter++);
    _sendQueue = _sendQueue.then((_) => _sealAndSend(line, nonce));
  }

  Future<void> _sealAndSend(String line, Uint8List nonce) async {
    final box = await _aead.encrypt(utf8.encode(line), secretKey: _outboundKey, nonce: nonce);
    // Named lengths first, because a `Mac`'s bytes and a `SecretBox`'s cipher text are both
    // `List<int>` while the sum here is used as a `Uint8List` size -- writing them out makes the
    // arithmetic three ints rather than an inference the reader has to do.
    final nonceLength = nonce.length;
    final cipherLength = box.cipherText.length;
    final tagLength = box.mac.bytes.length;
    final packed = Uint8List(nonceLength + cipherLength + tagLength)
      ..setRange(0, nonceLength, nonce)
      ..setRange(nonceLength, nonceLength + cipherLength, box.cipherText)
      ..setRange(
        nonceLength + cipherLength,
        nonceLength + cipherLength + tagLength,
        box.mac.bytes,
      );
    // **A frame that lost a race with the close is an outcome, not an exception.** The seal is
    // asynchronous, so `close` can land between a caller's `sendLine` and the moment the bytes are
    // ready -- and the last frame of an exchange is exactly that: a `bye` written and then closed
    // after. `sendLine` on a closed channel throws by contract, which is right for a *caller* that
    // sends after the conversation ended; here the send was legitimate when it was made and the peer
    // simply left first. The exchange's own rule is that nothing from the network reaches the caller
    // as an exception, and an unhandled async error did exactly that: the responder's reason came
    // back empty because the throw replaced it.
    try {
      _inner.sendLine(base64.encode(packed));
    } on Object {
      // Nothing to tell anybody: there is no channel to tell it on.
    }
  }

  @override
  Future<void> close() async {
    _closed = true;
    // **The queue is drained before the socket closes**, so a frame written and then closed after --
    // which is what every exchange does with its `bye` -- is actually on the wire. Closing first
    // would drop it, and the peer would see a hang-up instead of a reason.
    try {
      await _sendQueue;
    } on Object {
      // A send that failed on its way out is not a reason to skip closing.
    }
    await _inner.close();
  }

  static Uint8List _nonceFor(int counter) {
    final nonce = Uint8List(12);
    // Big-endian, so the bytes on the wire read in the order the counter counts.
    for (var i = 0; i < 8; i++) {
      nonce[11 - i] = (counter >> (8 * i)) & 0xff;
    }
    return nonce;
  }

  /// Runs the handshake over [inner] and returns a channel that encrypts everything after it.
  ///
  /// [secret] is the pairing code when there is one. An empty one still encrypts -- a development
  /// sync on a trusted network is better off confidential than in the clear -- but then nothing
  /// authenticates the peer, and [authenticated] says so rather than leaving the caller to assume.
  ///
  /// Returns null with a reason when the handshake fails, rather than throwing: a peer that is not
  /// running this protocol, or that does not know the code, is an outcome a screen has to be able to
  /// show, and section 10.3's threat model is exactly "somebody else is on this network".
  static Future<SecureHandshake> handshake(
    WireChannel inner, {
    required ExchangeRole role,
    String secret = '',
    /// This device's long-term key, when it has one. Its presence is what lets the peer recognise
    /// this device next time instead of asking a human for six characters again.
    DeviceIdentity? identity,
    /// The public key this device requires the peer to hold, base64. Empty means "no opinion",
    /// which is the state a first pairing is in -- and, deliberately, also the state of a device
    /// that has chosen to trust anybody on the network.
    String expectedIdentity = '',
    /// **The keys this device will accept *instead of* a pairing code**, which is the host's half of the
    /// second-sync story.
    ///
    /// A joining device knows an address and has learned a key at it, so it can say exactly who it
    /// expects. A **host** cannot: it has just put a code on its own screen, and it does not know which
    /// of the devices it has met will be the one that arrives. So it accepts either proof -- the code it
    /// is showing, or the key of anybody it has remembered -- and this is the set.
    ///
    /// **This gap was found by running two real processes against each other**, not by a test: the
    /// joiner sent its remembered key and no token, and the host refused it in the handshake because it
    /// still demanded the code. The screen test that "proved" the feature was asserting what the
    /// controller passed to a fake service, which is wiring rather than outcome.
    Set<String> acceptedIdentities = const {},
    /// **Whether a peer that proved nothing may still reach the comparison gate.**
    ///
    /// Set by a device that is *reachable rather than hosting* -- the listener a tap in 附近的设备 arrives at
    /// (§10.3.2): it shows no code, so it has no secret to demand and a stranger cannot prove anything yet. The
    /// proof in that case is a person looking at two screens and comparing six digits, which lives one layer up
    /// (`runExchange`'s `confirmComparison`, derived from the transcript this handshake built) -- so the refusal
    /// that would otherwise happen *here*, before the digits exist, would make the stronger of the two ways of
    /// adding a device impossible.
    ///
    /// **Never a default, and never set without that gate.** A caller that turns this on and passes no comparison
    /// is a device that accepts anybody on the network, which is the one thing §10.3 forbids; `runExchange`
    /// derives it from the gate rather than taking it from its own caller, so the two cannot drift apart.
    bool allowUnprovedPeer = false,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final iterator = StreamIterator<String>(inner.lines);
    // **An unproved peer still has to take part in the proof exchange.** `authenticated` decides whether this
    // side reads `s3` and answers `s4`; a responder that skipped those lines while an initiator with an identity
    // sent them would leave the initiator waiting for a confirmation that never comes -- a thirty-second stall
    // that looks like a dead network.
    final authenticated = secret.isNotEmpty ||
        expectedIdentity.isNotEmpty ||
        acceptedIdentities.isNotEmpty ||
        allowUnprovedPeer;

    // Set by the responder's verification below, and read when the result is built: which proof opened
    // the connection decides whether the exchange will still insist on a token.
    var provedCode = false;
    var provedKey = false;

    /// True when the last [readLine] gave up waiting rather than reading something unusable.
    ///
    /// **Two failures that read the same and are not.** A peer that connects and says nothing has
    /// stopped answering; a peer that sends an HTTP request or an older build's hello is speaking a
    /// different protocol. Telling the person at the screen "the handshake did not arrive" when the
    /// truth is "the other device went quiet" sends them looking in the wrong place -- and the
    /// quiet case is the common one, because it is what a sleeping laptop looks like.
    var timedOut = false;

    Future<Map<String, Object?>?> readLine() async {
      // Bounded, because a peer that opens a connection and then says nothing is the cheapest attack
      // there is and must not hold a screen forever.
      timedOut = false;
      final got = await iterator.moveNext().timeout(timeout, onTimeout: () {
        timedOut = true;
        return false;
      });
      if (!got) return null;
      try {
        final decoded = jsonDecode(iterator.current);
        return decoded is Map<String, Object?> ? decoded : null;
      } on FormatException {
        // Not JSON at all: an older build's plaintext hello, or something that is not Hollow Court.
        // Both are the same answer -- this connection is not speaking the sealed protocol.
        return null;
      }
    }

    /// Gives up without waiting for the peer to agree.
    ///
    /// **The close is started, not awaited, and that is the whole point of this method.** A refusal is
    /// aimed exactly at the peer that is not playing fair -- a port scanner, a browser pointed at the
    /// wrong port, somebody who opened a connection and went quiet -- and `SocketChannel.close` awaits
    /// the socket's own close, which a peer that never closes its end can hold open for as long as it
    /// likes. Awaiting it made three tests in `socket_transport_test.dart` sit for thirty seconds
    /// before failing, and in the application it would be a refused sync that leaves the screen
    /// spinning: the cheapest attack there is, costing the attacker nothing and the victim a hang.
    ///
    /// So the socket is told to close and the answer goes back immediately. The `catch` swallows the
    /// error from a close that failed, because there is nobody left to tell.
    Future<SecureHandshake> refuse(String why) async {
      unawaited(inner.close().catchError((Object _) {}));
      unawaited(iterator.cancel().catchError((Object _) => false));
      return SecureHandshake.failed(why);
    }

    final mine = await X25519().newKeyPair();
    final myNonce = base64.encode(_randomBytes(16));
    final myPublic = base64.encode((await mine.extractPublicKey()).bytes);

    // **The thing that gets signed, and why it is built from four fields rather than from the lines.**
    // A tag cannot cover the line it travels in, so "sign the handshake" has to mean something that
    // exists before the last line does. These four values are exactly what an attacker in the middle
    // would have to change, and both ends know all four by the time a tag is checked.
    late String initiatorPublic;
    late String initiatorNonce;
    late String responderPublic;
    late String responderNonce;
    // The two long-term identities are part of the transcript as well, and empty when a device has
    // none. They are not secrets -- they travel in the clear -- but a proof that did not cover them
    // would let an attacker in the middle swap its own key into the exchange and be recognised as
    // the peer next time.
    var initiatorIdentity = '';
    var responderIdentity = '';
    Uint8List transcript() => Uint8List.fromList(
      utf8.encode(
        '$protocol|$initiatorPublic|$initiatorNonce|$responderPublic|$responderNonce'
        '|$initiatorIdentity|$responderIdentity',
      ),
    );

    SimplePublicKey? peerPublic;

    /// The proof that this device holds a long-term key, for the peer that learned its public half.
    ///
    /// **A MAC over the transcript under a key neither side can name alone.** The key is the
    /// static-static X25519 secret between this device's long-term private key and the peer's
    /// long-term public key, so only the two devices named in the transcript can produce it -- and
    /// because the transcript covers both ephemeral keys as well, a proof made for one connection
    /// cannot be replayed into another.
    Future<String?> identityProof(String theirIdentity) async {
      final mine = identity;
      if (mine == null || theirIdentity.isEmpty) return null;
      final peerKey = _decodePublic(theirIdentity);
      if (peerKey == null) return null;
      final staticShared = await X25519().sharedSecretKey(
        keyPair: mine.keyPair,
        remotePublicKey: peerKey,
      );
      final key = await Hkdf(hmac: _hmac, outputLength: 32).deriveKey(
        secretKey: staticShared,
        nonce: utf8.encode(protocol),
        info: utf8.encode('$protocol/identity'),
      );
      final mac = await _hmac.calculateMac(
        Uint8List.fromList([
          ...transcript(),
          ...utf8.encode('|identity'),
        ]),
        secretKey: key,
      );
      return base64.encode(mac.bytes);
    }

    /// True when [proof] is this peer's identity proof, checked against the key we expect.
    Future<bool> identityProves(String proof, String theirIdentity) async {
      if (theirIdentity.isEmpty || expectedIdentity.isEmpty) return false;
      if (theirIdentity != expectedIdentity) return false;
      final expectedProof = await identityProof(theirIdentity);
      return _sameBytes(
        expectedProof == null ? const <int>[] : base64.decode(expectedProof),
        _decodeMac(proof),
      );
    }

    if (role == ExchangeRole.initiator) {
      initiatorPublic = myPublic;
      initiatorNonce = myNonce;
      initiatorIdentity = identity?.publicKey ?? '';
      inner.sendLine(
        jsonEncode({
          't': 's1',
          'pk': myPublic,
          'n': myNonce,
          if (initiatorIdentity.isNotEmpty) 'id': initiatorIdentity,
        }),
      );

      final answer = await readLine();
      if (answer == null || answer['t'] != 's2') {
        return refuse(
          timedOut
              ? 'the other end stopped answering'
              : 'the other end did not answer with a sealed handshake',
        );
      }
      peerPublic = _decodePublic(answer['pk']);
      if (peerPublic == null || _decodeNonce(answer['n']) == null) {
        return refuse('the other end sent a handshake this build cannot read');
      }
      responderPublic = answer['pk']! as String;
      responderNonce = answer['n']! as String;
      responderIdentity = answer['id'] is String ? answer['id']! as String : '';

      // **The code first, then the key.** A pairing code is what a human just arranged; a learned
      // key is what this device remembers. When both are in play the code is checked first because it
      // is the stronger statement about *this* meeting -- and a peer that fails it is refused before
      // its identity is even considered, which keeps the two failures distinguishable.
      if (secret.isNotEmpty) {
        final expected = await _authTag(secret, transcript(), 'responder');
        if (!_sameBytes(expected.bytes, _decodeMac(answer['tag']))) {
          // **The reason goes over the wire before the connection closes**, which is the rule the
          // exchange already follows for its own refusals. Without it the other end waits for a proof
          // that will never come and reports 对方没有证明配对码 -- true about what it saw, and less
          // useful than the cause, which only this side knows.
          inner.sendLine(jsonEncode({'t': 'sx', 'reason': 'the pairing code did not match'}));
          return refuse('the pairing code did not match');
        }
      }

      if (expectedIdentity.isNotEmpty) {
        // A device this one has learned before, reached without a code. The refusal says which of
        // the two things went wrong, because "the code did not match" is not a sentence to show
        // somebody who typed no code.
        if (responderIdentity.isEmpty) {
          return refuse('the other device did not say who it is');
        }
        if (responderIdentity != expectedIdentity) {
          return refuse('that is not the device this one remembers');
        }
        if (!await identityProves(answer['idp'] as String? ?? '', responderIdentity)) {
          return refuse('the other device could not prove it is who it says');
        }
      }

      if (secret.isNotEmpty || identity != null) {
        inner.sendLine(
          jsonEncode({
            't': 's3',
            if (secret.isNotEmpty)
              'tag': base64.encode(
                (await _authTag(secret, transcript(), 'initiator')).bytes,
              ),
            if (await identityProof(responderIdentity) != null)
              'idp': await identityProof(responderIdentity),
          }),
        );

        // The responder's confirmation, and the only thing that turns this side's proof into a
        // completed handshake. See the responder's `s4` for why it exists.
        final confirmation = await readLine();
        if (confirmation == null || confirmation['t'] != 's4') {
          if (confirmation != null && confirmation['t'] == 'sx') {
            final why = confirmation['reason'];
            return refuse(why is String ? why : 'the other end refused the handshake');
          }
          return refuse(
            timedOut
                ? 'the other end stopped answering'
                : 'the other end did not accept the handshake',
          );
        }
      }
    } else {
      final opening = await readLine();
      if (opening == null || opening['t'] != 's1') {
        return refuse(
          timedOut
              ? 'the other end stopped answering'
              : 'the other end did not open with a sealed handshake',
        );
      }
      peerPublic = _decodePublic(opening['pk']);
      if (peerPublic == null || _decodeNonce(opening['n']) == null) {
        return refuse('the other end sent a handshake this build cannot read');
      }
      initiatorPublic = opening['pk']! as String;
      initiatorNonce = opening['n']! as String;
      initiatorIdentity = opening['id'] is String ? opening['id']! as String : '';
      responderPublic = myPublic;
      responderNonce = myNonce;
      responderIdentity = identity?.publicKey ?? '';

      inner.sendLine(
        jsonEncode({
          't': 's2',
          'pk': myPublic,
          'n': myNonce,
          if (secret.isNotEmpty)
            'tag': base64.encode(
              (await _authTag(secret, transcript(), 'responder')).bytes,
            ),
          if (responderIdentity.isNotEmpty) 'id': responderIdentity,
          if (await identityProof(initiatorIdentity) != null)
            'idp': await identityProof(initiatorIdentity),
        }),
      );

      if (authenticated) {
        final proof = await readLine();
        if (proof != null && proof['t'] == 'sx') {
          // The peer's own diagnosis, carried rather than guessed at.
          final why = proof['reason'];
          return refuse(
            why is String ? why : 'the other end refused the handshake',
          );
        }
        if (proof == null || proof['t'] != 's3') {
          return refuse(
            secret.isNotEmpty
                ? 'the other end did not prove the pairing code'
                : 'the other device did not answer at all',
          );
        }
        // **Either proof is enough, and the reason is who is asking.** A joining device presents what it
        // has: the code a human just carried across, or the key it learned the last time. A host is the
        // side that showed the code, so it accepts the code -- and it also accepts any key it has
        // remembered, because the device that is coming back cannot know which of them this is until it
        // says so.
        //
        // A device that requires *one* specific key is the same rule with a list of one, and it is folded
        // in here rather than checked afterwards: the first version refused before reaching it, which a
        // test written earlier caught.
        provedCode = false;
        if (secret.isNotEmpty) {
          final expected = await _authTag(secret, transcript(), 'initiator');
          provedCode = _sameBytes(expected.bytes, _decodeMac(proof['tag']));
        }

        provedKey = false;
        // **A named device is also an acceptable key**, which is what lets a code-less connection work
        // between two devices that each named the other. It stays *additional* as well: see the end of
        // this block, where a device that required one specific peer still requires it after the code.
        final acceptable = <String>{
          ...acceptedIdentities,
          if (expectedIdentity.isNotEmpty) expectedIdentity,
        };
        if (!provedCode && initiatorIdentity.isNotEmpty && acceptable.contains(initiatorIdentity)) {
          // **The proof is symmetric, so this side computes what the peer should have sent** and compares.
          // The first version called `identityProves`, which also insists that the peer's key equals *the*
          // expected one -- and a host has no single expected key, it has a list. That mismatch is why the
          // code-less sync failed with 对方没有接受握手 rather than with a sentence about the key.
          final expectedProof = await identityProof(initiatorIdentity);
          provedKey = expectedProof != null &&
              _sameBytes(base64.decode(expectedProof), _decodeMac(proof['idp']));
        }

        if (!provedCode && !provedKey) {
          // **Except on a device whose listener is waiting to be tapped.** `allowUnprovedPeer` is that case and
          // only that case: the connection is sealed, nothing has been exchanged, and the six digits a person is
          // about to compare are the proof this connection is missing. `provedBy` stays empty, so an outcome can
          // still say plainly that no key and no code was behind this meeting.
          //
          // The refusals below say which door was closed, because the two failures send a person to different
          // places: a mistyped character is the reader's problem, and an unrecognised device is a device that has
          // to pair again.
          if (!allowUnprovedPeer) {
            if (initiatorIdentity.isNotEmpty &&
                acceptedIdentities.isNotEmpty &&
                !acceptedIdentities.contains(initiatorIdentity)) {
              inner.sendLine(jsonEncode({
                't': 'sx',
                'reason': 'that is not a device this one remembers, and no code was given',
              }));
              return refuse('that is not a device this one remembers, and no code was given');
            }
            if (secret.isNotEmpty) return refuse('the pairing code did not match');
            return refuse('the other device did not prove that it may connect');
          }
        }

        // **And a device that requires one specific peer requires it whichever proof passed.** The two
        // parameters mean different things: `acceptedIdentities` is an *alternative* to the code, and
        // `expectedIdentity` is an *additional* requirement on top of it -- "this device, and it must
        // prove itself". Folding them into one set, which the first version of this change did, made a
        // code enough for a host that had asked for a named device, and the impersonation test caught it.
        if (expectedIdentity.isNotEmpty) {
          if (initiatorIdentity.isEmpty) {
            return refuse('the other device did not say who it is');
          }
          if (initiatorIdentity != expectedIdentity) {
            return refuse('that is not the device this one remembers');
          }
          if (!await identityProves(proof['idp'] as String? ?? '', initiatorIdentity)) {
            return refuse('the other device could not prove it is who it says');
          }
        }

        // **The last line of the handshake, and the initiator waits for it.** Without it the initiator
        // declared success the moment it had sent its proof -- so a responder that had *refused* it
        // was something the initiator never learned, and the only sign would be the connection closing
        // under the first frame of the exchange. A sync would still fail rather than leak anything,
        // but it would fail with a transport error instead of the sentence that says why. Both ends
        // now know the handshake completed, or neither does.
        inner.sendLine(jsonEncode({'t': 's4'}));
      }
    }

    final shared = await X25519().sharedSecretKey(
      keyPair: mine,
      remotePublicKey: peerPublic,
    );
    final salt = await Sha256().hash(transcript());
    final hkdf = Hkdf(hmac: _hmac, outputLength: 32);
    final opening = role == ExchangeRole.initiator ? 'i2r' : 'r2i';
    final answering = role == ExchangeRole.initiator ? 'r2i' : 'i2r';
    final outbound = await hkdf.deriveKey(
      secretKey: shared,
      nonce: salt.bytes,
      info: utf8.encode('$protocol/$opening'),
    );
    final inbound = await hkdf.deriveKey(
      secretKey: shared,
      nonce: salt.bytes,
      info: utf8.encode('$protocol/$answering'),
    );

    final channel = SecureChannel._(inner, inbound, outbound, const Stream.empty());
    return SecureHandshake.opened(
      channel: channel,
      authenticated: authenticated,
      peerIdentity: role == ExchangeRole.initiator ? responderIdentity : initiatorIdentity,
      // **The six digits both screens will show**, derived from the transcript this end already signed. The
      // transcript covers both ephemeral keys, both nonces and both identities, so a relay in the middle cannot
      // make the two ends derive the same number -- which is the whole reason the comparison is stronger than
      // the pairing code (see `short_code.dart`).
      shortCode: ShortCode.of(transcript()),
      provedBy: role == ExchangeRole.responder
          ? (provedCode ? 'code' : (provedKey ? 'identity' : ''))
          : (secret.isNotEmpty
              ? 'code'
              : (expectedIdentity.isNotEmpty ? 'identity' : '')),
      // Built from the same iterator the handshake read from, so no line that arrived during the
      // handshake is lost and none is read twice.
      lines: channel._decrypted(iterator),
    );
  }

  /// The remaining lines of the connection, decrypted in order.
  Stream<String> _decrypted(StreamIterator<String> iterator) {
    final controller = StreamController<String>();
    unawaited(() async {
      try {
        while (await iterator.moveNext()) {
          final opened = await _open(iterator.current);
          if (opened == null) {
            await controller.close();
            await _inner.close();
            return;
          }
          controller.add(opened);
        }
        await controller.close();
      } on Object {
        if (!controller.isClosed) await controller.close();
      }
    }());
    return controller.stream;
  }

  /// One frame: base64, nonce, ciphertext, tag -- and the counter has to be the one expected.
  Future<String?> _open(String line) async {
    final List<int> packed;
    try {
      packed = base64.decode(line);
    } on FormatException {
      // A line that is not base64 is either a plaintext peer or something that is not this program.
      return null;
    }
    if (packed.length < 12 + 16) return null;

    final nonce = packed.sublist(0, 12);
    final expected = _nonceFor(_inboundCounter);
    if (!_sameBytes(nonce, expected)) return null;

    final cipherText = packed.sublist(12, packed.length - 16);
    final mac = Mac(packed.sublist(packed.length - 16));
    try {
      final clear = await _aead.decrypt(
        SecretBox(cipherText, nonce: nonce, mac: mac),
        secretKey: _inboundKey,
      );
      _inboundCounter++;
      return utf8.decode(clear);
    } on SecretBoxAuthenticationError {
      // The tag failed: the frame was modified, or it was sealed with another key. Both are refused
      // the same way, and neither is decoded "as far as it could".
      return null;
    }
  }

  // ---- the small pieces, each with one job --------------------------------------------------

  static Uint8List _randomBytes(int count) {
    // `Random.secure()`: these nonces go on the wire beside the keys, and a predictable one would
    // shrink the handshake's security to the strength of the seed.
    final random = Random.secure();
    return Uint8List.fromList([for (var i = 0; i < count; i++) random.nextInt(256)]);
  }

  /// The proof that this side knows the pairing code, over [transcript] and labelled [purpose].
  ///
  /// **The label is what stops a reflection.** Both ends sign the same four fields, so without a
  /// purpose the responder's proof would verify as the initiator's -- a peer could answer its own
  /// challenge. Two different HMAC messages from the same secret cannot be swapped for each other.
  static Future<Mac> _authTag(
    String secret,
    Uint8List transcript,
    String purpose,
  ) async {
    final authKey = await Hkdf(hmac: _hmac, outputLength: 32).deriveKey(
      secretKey: SecretKey(utf8.encode(secret)),
      nonce: utf8.encode(protocol),
      info: utf8.encode('$protocol/auth'),
    );
    return _hmac.calculateMac(
      Uint8List.fromList([...transcript, ...utf8.encode('|$purpose')]),
      secretKey: authKey,
    );
  }

  static SimplePublicKey? _decodePublic(Object? value) {
    if (value is! String) return null;
    try {
      final bytes = base64.decode(value);
      // X25519 public keys are 32 bytes and nothing else is accepted: a shorter or longer one is a
      // peer sending something this build does not understand, and that is a refusal rather than a
      // key to try.
      return bytes.length == 32
          ? SimplePublicKey(bytes, type: KeyPairType.x25519)
          : null;
    } on FormatException {
      return null;
    }
  }

  static Uint8List? _decodeNonce(Object? value) {
    if (value is! String) return null;
    try {
      final bytes = base64.decode(value);
      return bytes.length == 16 ? Uint8List.fromList(bytes) : null;
    } on FormatException {
      return null;
    }
  }

  static Uint8List? _decodeMac(Object? value) {
    if (value is! String) return null;
    try {
      return Uint8List.fromList(base64.decode(value));
    } on FormatException {
      return null;
    }
  }

  /// Length-checked and constant-time-ish comparison.
  ///
  /// **Not `==` on lists**, which compares identity for `Uint8List`, and not an early return on the
  /// first difference, which leaks where the mismatch is. The loop always walks the whole of both.
  static bool _sameBytes(List<int> a, List<int>? b) {
    if (b == null || a.length != b.length) return false;
    var difference = 0;
    for (var i = 0; i < a.length; i++) {
      difference |= a[i] ^ b[i];
    }
    return difference == 0;
  }
}

/// The result of a handshake: a sealed channel, or the reason there is not one.
final class SecureHandshake {
  const SecureHandshake._({
    required this.channel,
    required this.authenticated,
    required this.failure,
    this.lines,
    this.peerIdentity = '',
    this.provedBy = '',
    this.shortCode = '',
  });

  factory SecureHandshake.opened({
    required SecureChannel channel,
    required bool authenticated,
    required Stream<String> lines,
    String peerIdentity = '',
    String provedBy = '',
    String shortCode = '',
  }) => SecureHandshake._(
    channel: channel,
    authenticated: authenticated,
    failure: null,
    lines: lines,
    peerIdentity: peerIdentity,
    provedBy: provedBy,
    shortCode: shortCode,
  );

  factory SecureHandshake.failed(String reason) => SecureHandshake._(
    channel: null,
    authenticated: false,
    failure: reason,
  );

  /// The sealed channel, or null when the handshake failed.
  final SecureChannel? channel;

  /// True when the pairing code was proved, false when this connection is encrypted but its peer is
  /// unidentified. A caller that needs to say which of the two happened must be able to.
  final bool authenticated;

  /// Why there is no channel.
  final String? failure;

  /// The decrypted lines, which the channel hands out once it exists.
  final Stream<String>? lines;

  /// The peer's long-term public key, base64, when it offered one.
  ///
  /// **This is the value a caller remembers.** A device that completed a code-authenticated handshake
  /// with this key on the other end can recognise it next time without asking anybody for a code --
  /// and the fingerprint derived from it is what the two screens can be compared against.
  final String peerIdentity;

  /// Empty when the peer has no long-term key, which is the state before this device has learned one.
  bool get hasPeerIdentity => peerIdentity.isNotEmpty;

  /// **Which proof opened this connection**: `code`, `identity`, or empty for neither.
  ///
  /// The exchange needs it, and the reason is a rule rather than bookkeeping: a hello frame carries the
  /// token as well as a digest, and a peer that authenticated with a remembered key has no token to
  /// carry. Without this the handshake would succeed and the *exchange* would then refuse the connection
  /// with 配对码不对 -- which is what happened, twice, while this was being made to work between two real
  /// processes.
  final String provedBy;

  /// **The six digits to show a person when the reader chose to add the device by comparing screens.**
  ///
  /// Empty when the handshake did not get far enough to have a transcript. It is the same value on both ends
  /// for a handshake nobody interfered with, and a different one when somebody did -- see `short_code.dart` for
  /// why that is what defeats a relay, and why the confirmation must be one-shot.
  final String shortCode;

  bool get provedByKey => provedBy == 'identity';

  bool get succeeded => channel != null;
}
